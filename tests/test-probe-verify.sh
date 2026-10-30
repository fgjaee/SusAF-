#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
PERSISTENT_DIR="$TEST_ROOT/SusAF"
mkdir -p "$PERSISTENT_DIR" "$TEST_ROOT/bin"
printf '# empty\n' > "$PERSISTENT_DIR/sus_paths.txt"
printf '# empty\n' > "$PERSISTENT_DIR/sus_paths_loop.txt"
export PERSISTENT_DIR
export SUSAF_PROBE_RETRY_DELAY=0
export SUSAF_FAKE_PROBE_STATE="$TEST_ROOT/probe-retry-state"

cat > "$TEST_ROOT/bin/pm" <<'EOF'
#!/bin/sh
[ "$1" = path ] || exit 1
[ "$2" = com.fgjaee.susaf.probe ] || exit 1
printf 'package:/data/app/susafprobe/base.apk\n'
EOF
chmod 755 "$TEST_ROOT/bin/pm"

cat > "$TEST_ROOT/bin/content" <<'EOF'
#!/bin/sh
if [ "${SUSAF_FAKE_PROBE_FAIL_ONCE:-0}" = 1 ] && [ ! -e "${SUSAF_FAKE_PROBE_STATE:-/nonexistent}" ]; then
    : > "$SUSAF_FAKE_PROBE_STATE"
    echo 'transient provider failure' >&2
    exit 1
fi
payload=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --arg) shift; payload="$1" ;;
    esac
    shift
done
[ -n "$payload" ] || exit 1
count=$(printf '%s\n' "$payload" | awk 'END {print NR}')
status=$(printf '%s\n' "$payload" | awk '
    {
        if (NR>1) printf ","
        if ($0 ~ /\/ksud$/) printf "VISIBLE"
        else if ($0 ~ /\/temp_su.sock$/) printf "MISSING"
        else if ($0 ~ /\/apex\//) printf "DENIED"
        else printf "ERROR"
    }')
uid="${SUSAF_FAKE_PROBE_UID:-10142}"
printf 'Result: Bundle[{result=SUSAFPROBEV1__%s__%s__%s}]\n' "$uid" "$count" "$status"
EOF
chmod 755 "$TEST_ROOT/bin/content"

export SUSAF_PROBE_CONTENT_BIN="$TEST_ROOT/bin/content"
export SUSAF_PROBE_PM_BIN="$TEST_ROOT/bin/pm"
. "$ROOT/module/lib/coverage.sh"
. "$ROOT/module/lib/exposure-audit.sh"
. "$ROOT/module/lib/probe-verify.sh"

f="$TEST_ROOT/test.tsv"
{
    printf '/data/local/tmp/ksud\tfile\ttemp-root\tnot-listed\tloop\n'
    printf '/data/local/tmp/temp_su.sock\tsocket\ttemp-root\tnot-listed\tloop\n'
    printf '/apex/com.android.virt/bin/su\tfile\tapex-su\tnot-listed\tloop\n'
} > "$f"

probe_verify_file "$f"
[ "$PROBE_STATUS" = ready ]
[ "$PROBE_UID" = 10142 ]
[ "$(awk -F '\t' '$6=="VISIBLE" {n++} END {print n+0}' "$f")" = 1 ]
[ "$(awk -F '\t' '$6=="MISSING" {n++} END {print n+0}' "$f")" = 1 ]
[ "$(awk -F '\t' '$6=="DENIED" {n++} END {print n+0}' "$f")" = 1 ]
[ "$(awk -F '\t' '$7=="10142" {n++} END {print n+0}' "$f")" = 3 ]

# Transient provider failure should recover on retry.
rm -f "$SUSAF_FAKE_PROBE_STATE"
SUSAF_FAKE_PROBE_FAIL_ONCE=1; export SUSAF_FAKE_PROBE_FAIL_ONCE
{
    printf '/data/local/tmp/ksud\tfile\ttemp-root\tnot-listed\tloop\n'
    printf '/data/local/tmp/temp_su.sock\tsocket\ttemp-root\tnot-listed\tloop\n'
} > "$f"
probe_verify_file "$f"
[ "$PROBE_STATUS" = ready ]
[ -e "$SUSAF_FAKE_PROBE_STATE" ]
unset SUSAF_FAKE_PROBE_FAIL_ONCE

EXPOSURE_TMP_CHECK=checked
EXPOSURE_APEX_CHECK=checked
EXPOSURE_TRUNCATED=0
out=$(exposure_emit_report "$f")
printf '%s\n' "$out" | grep -Fqx 'exposure.app_visibility=checked'
printf '%s\n' "$out" | grep -Fqx 'exposure.result=observed-app-visible'
printf '%s\n' "$out" | grep -Fqx 'exposure.visible_count=1'
printf '%s\n' "$out" | grep -Fqx 'exposure.denied_count=1'
printf '%s\n' "$out" | grep -Fqx 'exposure.missing_count=1'
printf '%s\n' "$out" | grep -Fqx 'exposure.1.probe_uid=10142'
printf '%s\n' "$out" | grep -Fqx 'exposure.2.app_visibility=not-found'

# No installed app must leave observations unverified, not falsely clean.
cat > "$TEST_ROOT/bin/pm" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 755 "$TEST_ROOT/bin/pm"
cp "$f" "$TEST_ROOT/previous"
probe_verify_file "$f"
[ "$PROBE_STATUS" = not-installed ]
cmp "$f" "$TEST_ROOT/previous"

# Reject responses that come from a root process rather than an app UID.
cat > "$TEST_ROOT/bin/pm" <<'EOF'
#!/bin/sh
printf 'package:/data/app/susafprobe/base.apk\n'
EOF
chmod 755 "$TEST_ROOT/bin/pm"
SUSAF_FAKE_PROBE_UID=0; export SUSAF_FAKE_PROBE_UID
printf '/data/local/tmp/ksud\tfile\ttemp-root\tnot-listed\tloop\n' > "$f"
probe_verify_file "$f"
[ "$PROBE_STATUS" = call-failed ]
grep -Fq "$(printf '\t')NOT_TESTED$(printf '\t')0" "$f"

# An inconclusive syscall is NOT proof the app cannot see an artifact.
unset SUSAF_FAKE_PROBE_UID
printf '/data/local/tmp/unknown_root\tfile\ttemp-root\tnot-listed\tloop\n' > "$f"
probe_verify_file "$f"
[ "$PROBE_STATUS" = ready ]
out=$(exposure_emit_report "$f")
printf '%s\n' "$out" | grep -Fqx 'exposure.app_visibility=partial'
printf '%s\n' "$out" | grep -Fqx 'exposure.result=observed-unverified'
printf '%s\n' "$out" | grep -Fqx 'exposure.1.app_visibility=error'

echo 'app-process visibility verifier tests passed'

parsed=$(probe_parse_reply 'Result: Bundle[{result=SUSAFPROBEV1__10739__6__MISSING,MISSING,DENIED,VISIBLE,ERROR,INVALID}]')
[ "$parsed" = '10739|6|MISSING,MISSING,DENIED,VISIBLE,ERROR,INVALID' ] || {
    echo "Bundle parser failed: $parsed" >&2
    exit 1
}
