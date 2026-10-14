#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
FAKE="$TEST_ROOT/ksud"
MOUNTINFO="$TEST_ROOT/mountinfo"
KSU_LOG="$TEST_ROOT/ksud.log"
: > "$KSU_LOG"

cat > "$FAKE" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SUSAF_TEST_KSUD_LOG"
case "$1 $2 $3" in
    "feature check kernel_umount") printf '%s\n' "${SUSAF_TEST_UMOUNT_SUPPORT:-supported}" ;;
    "feature check selinux_hide") printf 'supported\n' ;;
    "feature get kernel_umount") printf 'Feature: kernel_umount (1)\nStatus: enabled\n' ;;
    "feature get selinux_hide") printf 'Feature: selinux_hide (1)\nStatus: disabled\n' ;;
    *) echo "unexpected/mutating invocation: $*" >&2; exit 1 ;;
esac
EOF
chmod 700 "$FAKE"

cat > "$MOUNTINFO" <<'EOF'
10 1 8:1 / / ro,relatime - erofs /dev/root ro
20 10 8:2 /adb/modules/zygisk_vector/bin/dex2oat32 /apex/com.android.art/bin/dex2oat32 ro,relatime - f2fs /dev/block/dm-69 ro
21 10 8:2 /adb/modules/zygisk_vector/bin/dex2oat64 /apex/com.android.art/bin/dex2oat64 ro,relatime - f2fs /dev/block/dm-69 ro
22 10 8:2 /adb/modules/Re-Malwack/system/etc/hosts /system/etc/hosts ro,relatime - f2fs /dev/block/dm-69 ro
30 10 8:3 / /vendor/lib ro,relatime - overlay overlay ro,lowerdir=/mnt/vendor/my_region
EOF

SUSAF_KSUD_BIN="$FAKE"
SUSAF_MOUNTINFO="$MOUNTINFO"
SUSAF_TEST_KSUD_LOG="$KSU_LOG"
export SUSAF_KSUD_BIN SUSAF_MOUNTINFO SUSAF_TEST_KSUD_LOG

. "$MODULE_DIR/lib/ksud.sh"
. "$MODULE_DIR/lib/ksu-readonly.sh"

result=$(susaf_ksu_readonly_audit)
printf '%s\n' "$result" | grep -Fqx 'status=available'
printf '%s\n' "$result" | grep -Fqx 'kernel_umount.support=supported'
printf '%s\n' "$result" | grep -Fqx 'selinux_hide.current=disabled'
printf '%s\n' "$result" | grep -Fqx '  /apex/com.android.art/bin/dex2oat32'
printf '%s\n' "$result" | grep -Fqx '  /apex/com.android.art/bin/dex2oat64'
printf '%s\n' "$result" | grep -Fqx '  /system/etc/hosts'
if printf '%s\n' "$result" | grep -Eq 'lowerdir=|/dev/block'; then exit 1; fi

# The audit must never mutate kernel settings or registered mounts.
if grep -Ev '^feature (check|get) (kernel_umount|selinux_hide)$' "$KSU_LOG"; then
    echo "audit invoked unexpected daemon command" >&2
    exit 1
fi

SUSAF_TEST_UMOUNT_SUPPORT=unsupported
export SUSAF_TEST_UMOUNT_SUPPORT
if susaf_ksu_readonly_audit > "$TEST_ROOT/unsupported.output"; then
    echo "unsupported umount returned success" >&2
    exit 1
fi
grep -Fqx 'status=kernel-umount-unavailable' "$TEST_ROOT/unsupported.output"
grep -Fqx 'kernel_umount.support=unsupported' "$TEST_ROOT/unsupported.output"

SUSAF_KSUD_BIN="$TEST_ROOT/nonexistent"
export SUSAF_KSUD_BIN
if susaf_ksu_readonly_audit > "$TEST_ROOT/missing.output"; then exit 1; fi
grep -Fqx 'status=daemon-unavailable' "$TEST_ROOT/missing.output"

echo 'KSU-only read-only audit tests passed'
