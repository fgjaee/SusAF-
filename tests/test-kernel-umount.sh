#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
PERSISTENT_DIR="$TEST_ROOT/persistent"
MODULE_ID=susaf
mkdir -p "$TEST_ROOT/bin" "$PERSISTENT_DIR"

get_conf() {
	key="$1"
	fallback="$2"
	file="$3"
	value=$(grep "^$key=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2-) || value=""
	[ -n "$value" ] || value="$fallback"
	printf '%s\n' "$value"
}

. "$MODULE_DIR/lib/kernel-umount.sh"

cat > "$TEST_ROOT/mountinfo" <<'EOF'
100 1 0:1 / / rw,relatime - ext4 /dev/root rw
200 100 0:2 / /system/bin/tool ro,relatime - overlay KSU ro
201 100 0:3 /adb/modules/example/system/etc /system/etc ro,relatime - ext4 /dev/block/dm-10 ro
202 100 0:4 / /vendor/lib ro,relatime - overlay overlay ro,lowerdir=/data/adb/modules/example/system/vendor/lib
203 100 0:5 / /product/app ro,relatime - ext4 /data/adb/modules/example/product/app ro
999999999 100 0:6 / /legitimate rw,relatime shared:2 - tmpfs tmpfs rw
205 100 0:7 / /space\040target ro,relatime - overlay KSU ro
206 100 0:8 / /manual ro,relatime - ext4 /dev/block/dm-20 ro
207 100 0:9 / /system_ext ro,relatime - ext4 /dev/block/dm-21 ro
EOF

cat > "$TEST_ROOT/config" <<'EOF'
KERNEL_UMOUNT_MODE=enabled
AUTO_KERNEL_UMOUNT=1
EOF

cat > "$TEST_ROOT/kernel_umount.txt" <<'EOF'
# Explicit entries must be validated against mountinfo.
/manual
/system_ext
/system/bin/tool # duplicate of an automatic target
/missing
relative
/
/space target
EOF

cat > "$TEST_ROOT/bin/ksud" <<'EOF'
#!/bin/sh
case "$1 $2 $3" in
	"feature check kernel_umount")
		printf '%s\n' "${SUSAF_FAKE_FEATURE_CHECK:-supported}"
		;;
	"feature get kernel_umount")
		printf 'Feature: kernel_umount (1)\nStatus: %s\n' "${SUSAF_FAKE_FEATURE_STATUS:-enabled}"
		;;
	"feature set kernel_umount")
		printf '%s\n' "$*" >> "$SUSAF_FAKE_KSUD_LOG"
		[ "${SUSAF_FAKE_SET_FAIL:-0}" = 0 ]
		;;
	"kernel umount add")
		printf '%s\n' "$*" >> "$SUSAF_FAKE_KSUD_LOG"
		[ "${SUSAF_FAKE_ADD_FAIL:-}" != "$4" ]
		;;
	"kernel umount list")
		printf '%s\n' "${SUSAF_FAKE_UMOUNT_LIST_JSON:-[]}"
		;;
	"kernel notify-module-mounted ")
		printf '%s\n' "$*" >> "$SUSAF_FAKE_KSUD_LOG"
		;;
	*)
		exit 1
		;;
esac
EOF
chmod 755 "$TEST_ROOT/bin/ksud"

# ReSukiSU packages ksud as an executable native library inside its app data.
MANAGER_KSUD="$TEST_ROOT/data-app/~~install/com.resukisu.resukisu-current/lib/arm64/libksud.so"
mkdir -p "$(dirname "$MANAGER_KSUD")"
cp "$TEST_ROOT/bin/ksud" "$MANAGER_KSUD"
chmod 755 "$MANAGER_KSUD"
SUSAF_DATA_APP_ROOT="$TEST_ROOT/data-app"
export SUSAF_DATA_APP_ROOT
[ "$(resolve_ksud_bin)" = "$MANAGER_KSUD" ]

# KernelSU-Next uses com.rifsxd.ksunext and packages ksud as libksud.so.
rm -f "$MANAGER_KSUD"
KSUNEXT_KSUD="$TEST_ROOT/data-app/~~install/com.rifsxd.ksunext-current/lib/arm64/libksud.so"
mkdir -p "$(dirname "$KSUNEXT_KSUD")"
cp "$TEST_ROOT/bin/ksud" "$KSUNEXT_KSUD"
chmod 755 "$KSUNEXT_KSUD"
[ "$(resolve_ksud_bin)" = "$KSUNEXT_KSUD" ]

KSUD_LOG="$TEST_ROOT/ksud.log"
: > "$KSUD_LOG"
SUSAF_KSUD_BIN="$TEST_ROOT/bin/ksud"
SUSAF_FAKE_KSUD_LOG="$KSUD_LOG"
SUSAF_FAKE_UMOUNT_LIST_JSON='[{"path":"/system/etc","flags":2}]'
SUSAF_KERNEL_UMOUNT_FEATURE_REPORT="$TEST_ROOT/feature.report"
export SUSAF_KSUD_BIN SUSAF_FAKE_KSUD_LOG SUSAF_FAKE_UMOUNT_LIST_JSON SUSAF_KERNEL_UMOUNT_FEATURE_REPORT
apply_kernel_umount_feature "$TEST_ROOT/config"

grep -Fqx 'feature set kernel_umount 1' "$KSUD_LOG"
grep -Fqx 'mode=enabled' "$TEST_ROOT/feature.report"
grep -Fqx "binary=$TEST_ROOT/bin/ksud" "$TEST_ROOT/feature.report"
grep -Fqx 'check=supported' "$TEST_ROOT/feature.report"
grep -Fqx 'current=enabled' "$TEST_ROOT/feature.report"
grep -Fqx 'result=ok' "$TEST_ROOT/feature.report"

: > "$KSUD_LOG"
SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo"
SUSAF_KERNEL_UMOUNT_REPORT="$TEST_ROOT/mounts.report"
export SUSAF_MOUNTINFO SUSAF_KERNEL_UMOUNT_REPORT
apply_kernel_umount_mounts "$TEST_ROOT/config" "$TEST_ROOT/kernel_umount.txt"

for target in /system/bin/tool /vendor/lib /product/app /manual; do
	grep -Fqx "kernel umount add $target --flags 2" "$KSUD_LOG"
done
[ "$(grep -c '^kernel umount add ' "$KSUD_LOG")" -eq 4 ]
[ "$(grep -c '^kernel umount add /system/bin/tool ' "$KSUD_LOG")" -eq 1 ]
! grep -Fq 'kernel umount wipe' "$KSUD_LOG"
[ "$(tail -n1 "$KSUD_LOG")" = 'kernel notify-module-mounted' ]
grep -Fqx 'add=/system/bin/tool|source:KSU|ok' "$TEST_ROOT/mounts.report"
grep -Fqx "binary=$TEST_ROOT/bin/ksud" "$TEST_ROOT/mounts.report"
grep -Fqx 'skip=/system/etc|module-backed|already-present' "$TEST_ROOT/mounts.report"
grep -Fqx 'add=/vendor/lib|module-overlay|ok' "$TEST_ROOT/mounts.report"
grep -Fqx 'skip=/system/bin/tool|explicit|duplicate' "$TEST_ROOT/mounts.report"
grep -Fqx 'skip=/missing|explicit|not-mounted' "$TEST_ROOT/mounts.report"
grep -Fqx 'skip=/system_ext|explicit|broad-target' "$TEST_ROOT/mounts.report"
grep -Fqx 'reject=relative|explicit|unsafe-path' "$TEST_ROOT/mounts.report"
grep -Fqx 'reject=/|explicit|unsafe-path' "$TEST_ROOT/mounts.report"
grep -Fqx 'added=4' "$TEST_ROOT/mounts.report"
grep -Fqx 'existing=1' "$TEST_ROOT/mounts.report"
grep -Fqx 'inactive=1' "$TEST_ROOT/mounts.report"
grep -Fqx 'broad_skipped=1' "$TEST_ROOT/mounts.report"
grep -Fqx 'rejected=4' "$TEST_ROOT/mounts.report"
grep -Fqx 'failed=0' "$TEST_ROOT/mounts.report"
grep -Fqx 'notify=ok' "$TEST_ROOT/mounts.report"
grep -Fqx 'result=ok' "$TEST_ROOT/mounts.report"

# A real add failure is separate from invalid and already-registered targets.
: > "$KSUD_LOG"
SUSAF_FAKE_ADD_FAIL=/manual
SUSAF_FAKE_UMOUNT_LIST_JSON='[]'
SUSAF_KERNEL_UMOUNT_REPORT="$TEST_ROOT/partial.report"
export SUSAF_FAKE_ADD_FAIL SUSAF_FAKE_UMOUNT_LIST_JSON SUSAF_KERNEL_UMOUNT_REPORT
apply_kernel_umount_mounts "$TEST_ROOT/config" "$TEST_ROOT/kernel_umount.txt"
grep -Fq 'add=/manual|explicit|failed|' "$TEST_ROOT/partial.report"
grep -Fqx 'failed=1' "$TEST_ROOT/partial.report"
grep -Fqx 'inactive=1' "$TEST_ROOT/partial.report"
grep -Fqx 'rejected=4' "$TEST_ROOT/partial.report"
grep -Fqx 'result=partial' "$TEST_ROOT/partial.report"
unset SUSAF_FAKE_ADD_FAIL
SUSAF_FAKE_UMOUNT_LIST_JSON='[{"path":"/system/etc","flags":2}]'
export SUSAF_FAKE_UMOUNT_LIST_JSON

# Whole-partition targets require an explicit compatibility override.
cat > "$TEST_ROOT/config.allow-broad" <<'EOF'
KERNEL_UMOUNT_MODE=enabled
AUTO_KERNEL_UMOUNT=0
ALLOW_BROAD_KERNEL_UMOUNT=1
EOF
: > "$KSUD_LOG"
SUSAF_FAKE_UMOUNT_LIST_JSON='[]'
SUSAF_KERNEL_UMOUNT_REPORT="$TEST_ROOT/allow-broad.report"
export SUSAF_FAKE_UMOUNT_LIST_JSON SUSAF_KERNEL_UMOUNT_REPORT
apply_kernel_umount_mounts "$TEST_ROOT/config.allow-broad" "$TEST_ROOT/kernel_umount.txt"
grep -Fqx 'kernel umount add /system_ext --flags 2' "$KSUD_LOG"
grep -Fqx 'allow_broad=1' "$TEST_ROOT/allow-broad.report"
grep -Fqx 'broad_skipped=0' "$TEST_ROOT/allow-broad.report"

SUSAF_FAKE_UMOUNT_LIST_JSON='[{"path":"/system/etc","flags":2}]'
export SUSAF_FAKE_UMOUNT_LIST_JSON

cat > "$TEST_ROOT/config.disabled" <<'EOF'
KERNEL_UMOUNT_MODE=disabled
AUTO_KERNEL_UMOUNT=1
EOF
: > "$KSUD_LOG"
SUSAF_KERNEL_UMOUNT_FEATURE_REPORT="$TEST_ROOT/disabled.feature.report"
export SUSAF_KERNEL_UMOUNT_FEATURE_REPORT
apply_kernel_umount_feature "$TEST_ROOT/config.disabled"
grep -Fqx 'feature set kernel_umount 0' "$KSUD_LOG"

: > "$KSUD_LOG"
SUSAF_KERNEL_UMOUNT_REPORT="$TEST_ROOT/disabled.mounts.report"
export SUSAF_KERNEL_UMOUNT_REPORT
apply_kernel_umount_mounts "$TEST_ROOT/config.disabled" "$TEST_ROOT/kernel_umount.txt"
[ ! -s "$KSUD_LOG" ]
grep -Fqx 'result=disabled' "$TEST_ROOT/disabled.mounts.report"

cat > "$TEST_ROOT/config.unchanged" <<'EOF'
KERNEL_UMOUNT_MODE=unchanged
AUTO_KERNEL_UMOUNT=0
EOF
: > "$KSUD_LOG"
SUSAF_KERNEL_UMOUNT_FEATURE_REPORT="$TEST_ROOT/unchanged.feature.report"
export SUSAF_KERNEL_UMOUNT_FEATURE_REPORT
apply_kernel_umount_feature "$TEST_ROOT/config.unchanged"
[ ! -s "$KSUD_LOG" ]
grep -Fqx 'set=unchanged' "$TEST_ROOT/unchanged.feature.report"

set +e
SUSAF_FAKE_FEATURE_CHECK=unsupported
SUSAF_KERNEL_UMOUNT_FEATURE_REPORT="$TEST_ROOT/unsupported.feature.report"
export SUSAF_FAKE_FEATURE_CHECK SUSAF_KERNEL_UMOUNT_FEATURE_REPORT
apply_kernel_umount_feature "$TEST_ROOT/config"
unsupported_status=$?
set -e
unset SUSAF_FAKE_FEATURE_CHECK
[ "$unsupported_status" -eq 0 ]
grep -Fqx 'result=not-supported' "$TEST_ROOT/unsupported.feature.report"

unset SUSAF_KSUD_BIN
mkdir -p "$TEST_ROOT/empty-data-app"
SUSAF_DATA_APP_ROOT="$TEST_ROOT/empty-data-app"
SUSAF_KERNEL_UMOUNT_FEATURE_REPORT="$TEST_ROOT/unavailable.feature.report"
export SUSAF_DATA_APP_ROOT SUSAF_KERNEL_UMOUNT_FEATURE_REPORT
apply_kernel_umount_feature "$TEST_ROOT/config"
grep -Fqx 'binary=unavailable' "$TEST_ROOT/unavailable.feature.report"
grep -Fqx 'check=unavailable' "$TEST_ROOT/unavailable.feature.report"
grep -Fqx 'result=daemon-unavailable' "$TEST_ROOT/unavailable.feature.report"

cat > "$TEST_ROOT/bin/SusAF" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" > "$SUSAF_FAKE_CLI_ARGS"
cp "$2" "$SUSAF_FAKE_CLI_FILE"
EOF
chmod 755 "$TEST_ROOT/bin/SusAF"
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo" \
SUSAF_FAKE_CLI_ARGS="$TEST_ROOT/mount-hide.args" \
SUSAF_FAKE_CLI_FILE="$TEST_ROOT/mount-hide.captured" \
PATH="$TEST_ROOT/bin:$PATH" \
sh "$MODULE_DIR/configs/scripts/SusAF_apply-mount-hiding.sh"

grep -Fqx -- '--apply-sus-paths-loop-direct' "$TEST_ROOT/mount-hide.args"
cat > "$TEST_ROOT/mount-hide.expected" <<'EOF'
/product/app
/system/bin/tool
/system/etc
/vendor/lib
EOF
cmp "$TEST_ROOT/mount-hide.expected" "$TEST_ROOT/mount-hide.captured"
cmp "$TEST_ROOT/mount-hide.expected" "$PERSISTENT_DIR/state/mount_hiding.generated.txt"

echo "kernel_umount tests passed"
