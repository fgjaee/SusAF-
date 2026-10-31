#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$SDK" ] || { echo "ANDROID_HOME/ANDROID_SDK_ROOT is required" >&2; exit 1; }
TOOLS="$SDK/build-tools/35.0.0"
PLATFORM="$SDK/platforms/android-35/android.jar"
for cmd in "$TOOLS/aapt2" "$TOOLS/d8" "$TOOLS/zipalign" "$TOOLS/apksigner"; do
  [ -x "$cmd" ] || { echo "Missing Android build tool: $cmd" >&2; exit 1; }
done
[ -r "$PLATFORM" ] || { echo "Missing Android 35 platform" >&2; exit 1; }
command -v javac >/dev/null
command -v keytool >/dev/null
command -v zip >/dev/null

OUT="${1:-$ROOT/dist}"
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/susaf-probe-build-$$"
mkdir -p "$OUT" "$WORK/classes" "$WORK/dex"
trap 'rm -rf "$WORK"' EXIT

javac -source 8 -target 8 -Xlint:-options -encoding UTF-8 \
  -cp "$PLATFORM" -d "$WORK/classes" \
  "$ROOT/probe-app/src/com/fgjaee/susaf/probe/ProbeProvider.java"

"$TOOLS/d8" --min-api 26 --lib "$PLATFORM" --output "$WORK/dex" \
  "$WORK/classes/com/fgjaee/susaf/probe/ProbeProvider.class"

"$TOOLS/aapt2" link \
  -o "$WORK/unsigned.apk" -I "$PLATFORM" \
  --manifest "$ROOT/probe-app/AndroidManifest.xml" \
  --min-sdk-version 26 --target-sdk-version 35 \
  --version-code 1 --version-name "1.0"

(
  cd "$WORK/dex"
  zip -q -j "$WORK/unsigned.apk" classes.dex
)
"$TOOLS/zipalign" -f -p 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"

# This generated certificate is TEST-ONLY. Release builds should use a
# stable private signing secret. Test APK upgrades may require uninstalling.
if [ -n "${SUSAF_PROBE_KEYSTORE_BASE64:-}" ]; then
  printf '%s' "$SUSAF_PROBE_KEYSTORE_BASE64" | base64 -d > "$WORK/signing.jks"
  : "${SUSAF_PROBE_STORE_PASS:?set store pass for real keystore}"
  : "${SUSAF_PROBE_KEY_PASS:?set key pass for real keystore}"
  "$TOOLS/apksigner" sign --ks "$WORK/signing.jks" \
    --ks-key-alias "${SUSAF_PROBE_KEY_ALIAS:-susafprobe}" \
    --ks-pass "pass:$SUSAF_PROBE_STORE_PASS" \
    --key-pass "pass:$SUSAF_PROBE_KEY_PASS" \
    --out "$OUT/SusAF-Visibility-Probe.apk" "$WORK/aligned.apk"
else
  keytool -genkeypair -noprompt -keystore "$WORK/signing.jks" \
    -storepass android -keypass android -alias susafprobe \
    -dname "CN=SusAF temporary CI test key" -keyalg RSA -keysize 2048 \
    -validity 3650 >/dev/null 2>&1
  "$TOOLS/apksigner" sign --ks "$WORK/signing.jks" \
    --ks-key-alias susafprobe --ks-pass pass:android \
    --key-pass pass:android \
    --out "$OUT/SusAF-Visibility-Probe.apk" "$WORK/aligned.apk"
fi
"$TOOLS/apksigner" verify --verbose "$OUT/SusAF-Visibility-Probe.apk"
unzip -t "$OUT/SusAF-Visibility-Probe.apk" >/dev/null
echo "Built: $OUT/SusAF-Visibility-Probe.apk"
