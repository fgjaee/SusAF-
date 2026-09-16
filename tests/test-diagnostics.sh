#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
PERSISTENT_DIR="$TEST_ROOT/persistent"
STATE_DIR="$PERSISTENT_DIR/state"
BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$STATE_DIR/migrations" "$BIN_DIR"

cat > "$PERSISTENT_DIR/config.txt" <<'EOF'
KERNEL_UMOUNT_MODE=enabled
AUTO_KERNEL_UMOUNT=1
ALLOW_BROAD_KERNEL_UMOUNT=0
ADB_MODE=unchanged
EOF
cat > "$PERSISTENT_DIR/sus_paths.txt" <<'EOF'
/system/valid
relative-is-invalid
EOF
cat > "$PERSISTENT_DIR/sus_paths_loop.txt" <<'EOF'
/dev/pts/7
EOF
cat > "$PERSISTENT_DIR/sus_maps.txt" <<'EOF'
/system/lib64/target.so
EOF
cat > "$PERSISTENT_DIR/kstat_paths.txt" <<'EOF'
/system/framework/framework.jar
EOF
cat > "$PERSISTENT_DIR/open_redirect.txt" <<'EOF'
/source /target 0
bad redirect
EOF
cat > "$PERSISTENT_DIR/kernel_umount.txt" <<'EOF'
/system/bin/tool
EOF
cat > "$STATE_DIR/kernel_umount.feature.txt" <<'EOF'
mode=enabled
check=supported
current=enabled
result=ok
EOF
cat > "$STATE_DIR/kernel_umount.report.txt" <<'EOF'
mode=enabled
auto=1
add=/system/bin/tool|source:KSU|ok
skip=/system/bin/tool|explicit|duplicate
reject=/missing|explicit|not-mounted
added=1
existing=2
inactive=1
broad_skipped=1
rejected=1
failed=0
notify=ok
result=ok
EOF
cat > "$STATE_DIR/adb_mode.report.txt" <<'EOF'
mode=unchanged
result=unchanged
EOF
cat > "$STATE_DIR/updater.report.txt" <<'EOF'
source_repository=sidex15/susfs4ksu-binaries
source_commit=26958b7c3dca487c17227b62a6dd7cf11645b49a
expected_sha256=8a626ce3bae27a7bcaa2e7f5f7b91e786ecc57f8e57d19c7856719a89b54b6fa
actual_sha256=8a626ce3bae27a7bcaa2e7f5f7b91e786ecc57f8e57d19c7856719a89b54b6fa
installed_sha256=8a626ce3bae27a7bcaa2e7f5f7b91e786ecc57f8e57d19c7856719a89b54b6fa
candidate_version=v2.3.0
candidate_variant=GKI
verification=verified
backup=created
rollback=not-needed
result=installed
EOF
cat > "$STATE_DIR/cmdline_or_bootconfig.generated.txt" <<'EOF'
androidboot.verifiedbootstate = "green"
androidboot.vbmeta.device_state = "locked"
EOF
cat > "$STATE_DIR/mount_hiding.generated.txt" <<'EOF'
/system/bin/tool
EOF
cat > "$STATE_DIR/stage.post-fs-data.properties" <<'EOF'
schema=1
status=finished
started_at=2026-09-12T00:00:00Z
finished_at=2026-09-12T00:00:02Z
duration_seconds=2
exit_status=0
EOF
cat > "$STATE_DIR/stage.boot-completed.properties" <<'EOF'
schema=1
status=finished
started_at=2026-09-12T00:01:00Z
finished_at=2026-09-12T00:01:03Z
duration_seconds=3
exit_status=0
EOF
: > "$STATE_DIR/migrations/v1-resusfs.done"

cat > "$TEST_ROOT/mountinfo" <<'EOF'
100 1 0:1 / / rw,relatime - ext4 /dev/root rw
200 100 0:2 / /system/bin/tool ro,relatime - overlay KSU ro
EOF
cat > "$TEST_ROOT/bootconfig" <<'EOF'
androidboot.verifiedbooterror = "verification failed"
androidboot.verifyerrorpart = "vbmeta"
EOF
printf 'Linux version diagnostic-fixture\n' > "$TEST_ROOT/proc-version"

cat > "$BIN_DIR/ksu_susfs" <<'EOF'
#!/bin/sh
case "$1 $2" in
    'show version') printf 'v2.3.0\n' ;;
    'show variant') printf 'GKI\n' ;;
    'show enabled_features') printf 'SUS_PATH\nSUS_MAP\n' ;;
    *) exit 1 ;;
esac
EOF
cat > "$BIN_DIR/ksud" <<'EOF'
#!/bin/sh
case "$1 $2 $3" in
    'feature check kernel_umount') printf 'supported\n' ;;
    'feature get kernel_umount') printf 'Feature: kernel_umount (1)\nStatus: enabled\n' ;;
    'feature check selinux_hide') printf 'supported\n' ;;
    'feature get selinux_hide') printf 'Feature: selinux_hide (4)\nStatus: enabled\n' ;;
    '--version  ') printf 'ksud 1.0-test\n' ;;
    *) exit 1 ;;
esac
EOF
cat > "$BIN_DIR/settings" <<'EOF'
#!/bin/sh
case "$3" in
    development_settings_enabled|adb_enabled) printf '1\n' ;;
    adb_wifi_enabled) printf '0\n' ;;
    *) exit 1 ;;
esac
EOF
cat > "$BIN_DIR/getprop" <<'EOF'
#!/bin/sh
case "$1" in
    init.svc.adbd) printf 'running\n' ;;
    sys.usb.config|sys.usb.state|persist.sys.usb.config) printf 'mtp,adb\n' ;;
    *) exit 1 ;;
esac
EOF
cat > "$BIN_DIR/pidof" <<'EOF'
#!/bin/sh
[ "$1" = adbd ] && printf '123\n'
EOF
chmod 755 "$BIN_DIR"/*

module_prop_before=$(sha256sum "$MODULE_DIR/module.prop")
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_LEGACY_RESUSFS_DIR="$TEST_ROOT/no-resusfs" \
SUSAF_LEGACY_SUSFS4KSU_DIR="$TEST_ROOT/no-susfs4ksu" \
SUSAF_SUSFS_BIN="$BIN_DIR/ksu_susfs" \
SUSAF_KSUD_BIN="$BIN_DIR/ksud" \
SUSAF_SETTINGS_BIN="$BIN_DIR/settings" \
SUSAF_GETPROP_BIN="$BIN_DIR/getprop" \
SUSAF_PIDOF_BIN="$BIN_DIR/pidof" \
SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo" \
SUSAF_BOOTCONFIG_SOURCE="$TEST_ROOT/bootconfig" \
SUSAF_PROC_VERSION="$TEST_ROOT/proc-version" \
sh "$MODULE_DIR/SusAF.sh" --diagnostics > "$TEST_ROOT/stdout"
module_prop_after=$(sha256sum "$MODULE_DIR/module.prop")

[ "$module_prop_before" = "$module_prop_after" ]
REPORT="$STATE_DIR/diagnostics.properties"
cmp "$REPORT" "$TEST_ROOT/stdout"
[ "$(stat -c '%a' "$REPORT")" = 600 ]
grep -Fqx 'schema=1' "$REPORT"
grep -Fqx 'overall.status=healthy' "$REPORT"
grep -Fqx 'module.id=susaf' "$REPORT"
grep -Fqx 'susfs.status=active' "$REPORT"
grep -Fqx 'susfs.version=v2.3.0' "$REPORT"
grep -Fqx 'susfs.feature_count=2' "$REPORT"
grep -Fqx "kernelsu.binary=$BIN_DIR/ksud" "$REPORT"
grep -Fqx 'kernel_umount.support=supported' "$REPORT"
grep -Fqx 'kernel_umount.current=enabled' "$REPORT"
grep -Fqx 'kernel_umount.allow_broad=0' "$REPORT"
grep -Fqx 'mount_filter.early=0' "$REPORT"
grep -Fqx 'mount_filter.late=0' "$REPORT"

cp "$PERSISTENT_DIR/config.txt" "$PERSISTENT_DIR/config.saved"
printf 'HIDE_SUS_MNTS_LATE=1\n' >> "$PERSISTENT_DIR/config.txt"
SUSAF_DIAGNOSTICS_FILE="$TEST_ROOT/late-filter.stdout" \
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_LEGACY_RESUSFS_DIR="$TEST_ROOT/no-resusfs" \
SUSAF_LEGACY_SUSFS4KSU_DIR="$TEST_ROOT/no-susfs4ksu" \
SUSAF_SUSFS_BIN="$BIN_DIR/ksu_susfs" \
SUSAF_KSUD_BIN="$BIN_DIR/ksud" \
SUSAF_SETTINGS_BIN="$BIN_DIR/settings" \
SUSAF_GETPROP_BIN="$BIN_DIR/getprop" \
SUSAF_PIDOF_BIN="$BIN_DIR/pidof" \
SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo" \
SUSAF_BOOTCONFIG_SOURCE="$TEST_ROOT/bootconfig" \
SUSAF_CMDLINE_SOURCE="$TEST_ROOT/cmdline" \
SUSAF_PROC_VERSION="$TEST_ROOT/proc-version" \
sh "$MODULE_DIR/SusAF.sh" --diagnostics >/dev/null
grep -Fqx 'mount_filter.late=1' "$TEST_ROOT/late-filter.stdout"
grep -Fqx 'overall.status=degraded' "$TEST_ROOT/late-filter.stdout"
mv "$PERSISTENT_DIR/config.saved" "$PERSISTENT_DIR/config.txt"

cp "$PERSISTENT_DIR/config.txt" "$PERSISTENT_DIR/config.saved"
sed -i 's/^ALLOW_BROAD_KERNEL_UMOUNT=.*/ALLOW_BROAD_KERNEL_UMOUNT=1/' "$PERSISTENT_DIR/config.txt"
SUSAF_DIAGNOSTICS_FILE="$TEST_ROOT/broad-target.stdout" \
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_LEGACY_RESUSFS_DIR="$TEST_ROOT/no-resusfs" \
SUSAF_LEGACY_SUSFS4KSU_DIR="$TEST_ROOT/no-susfs4ksu" \
SUSAF_SUSFS_BIN="$BIN_DIR/ksu_susfs" \
SUSAF_KSUD_BIN="$BIN_DIR/ksud" \
SUSAF_SETTINGS_BIN="$BIN_DIR/settings" \
SUSAF_GETPROP_BIN="$BIN_DIR/getprop" \
SUSAF_PIDOF_BIN="$BIN_DIR/pidof" \
SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo" \
SUSAF_BOOTCONFIG_SOURCE="$TEST_ROOT/bootconfig" \
SUSAF_CMDLINE_SOURCE="$TEST_ROOT/cmdline" \
SUSAF_PROC_VERSION="$TEST_ROOT/proc-version" \
sh "$MODULE_DIR/SusAF.sh" --diagnostics >/dev/null
grep -Fqx 'kernel_umount.allow_broad=1' "$TEST_ROOT/broad-target.stdout"
grep -Fqx 'overall.status=degraded' "$TEST_ROOT/broad-target.stdout"
mv "$PERSISTENT_DIR/config.saved" "$PERSISTENT_DIR/config.txt"
grep -Fqx 'selinux_hide.support=supported' "$REPORT"
grep -Fqx 'selinux_hide.current=enabled' "$REPORT"
grep -Fqx 'kernel_umount.candidates=1' "$REPORT"
grep -Fqx 'kernel_umount.added=1' "$REPORT"
grep -Fqx 'kernel_umount.existing=2' "$REPORT"
grep -Fqx 'kernel_umount.inactive=1' "$REPORT"
grep -Fqx 'kernel_umount.broad_skipped=1' "$REPORT"
grep -Fqx 'kernel_umount.skipped=1' "$REPORT"
grep -Fqx 'kernel_umount.rejected=1' "$REPORT"
grep -Fqx 'kernel_umount.failures=0' "$REPORT"
grep -Fqx 'targets.sus_paths=2' "$REPORT"
grep -Fqx 'targets.sus_paths_malformed=1' "$REPORT"
grep -Fqx 'targets.open_redirect_malformed=1' "$REPORT"
grep -Fqx 'targets.pty=1' "$REPORT"
grep -Fqx 'boot.live_error_keys=2' "$REPORT"
grep -Fqx 'boot.generated_error_keys=0' "$REPORT"
grep -Fqx 'adb.configured=unchanged' "$REPORT"
grep -Fqx 'adb.service=running' "$REPORT"
grep -Fqx 'stage.postfs.duration=2' "$REPORT"
grep -Fqx 'stage.boot.duration=3' "$REPORT"
grep -Fqx 'migration.resusfs=complete' "$REPORT"
grep -Fqx 'migration.susfs4ksu=not-needed' "$REPORT"
grep -Fqx 'updater.verification=verified' "$REPORT"
grep -Fqx 'updater.backup=created' "$REPORT"
grep -Fqx 'updater.rollback=not-needed' "$REPORT"
grep -Fqx 'updater.last_result=installed' "$REPORT"
! grep -Fq '/system/valid' "$REPORT"
! grep -Fq 'relative-is-invalid' "$REPORT"

# The boot service must be event-based, not a perpetual metadata writer.
! grep -Fq 'while true' "$MODULE_DIR/service.sh"
! grep -Eq 'sed .*module\.prop' "$MODULE_DIR/SusAF.sh"

# Enabling kernel_umount without a reachable daemon must not look healthy.
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_LEGACY_RESUSFS_DIR="$TEST_ROOT/no-resusfs" \
SUSAF_LEGACY_SUSFS4KSU_DIR="$TEST_ROOT/no-susfs4ksu" \
SUSAF_SUSFS_BIN="$BIN_DIR/ksu_susfs" \
SUSAF_KSUD_BIN="$BIN_DIR/missing-ksud" \
SUSAF_SETTINGS_BIN="$BIN_DIR/settings" \
SUSAF_GETPROP_BIN="$BIN_DIR/getprop" \
SUSAF_PIDOF_BIN="$BIN_DIR/pidof" \
SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo" \
SUSAF_BOOTCONFIG_SOURCE="$TEST_ROOT/bootconfig" \
SUSAF_PROC_VERSION="$TEST_ROOT/proc-version" \
sh "$MODULE_DIR/SusAF.sh" --diagnostics > "$TEST_ROOT/degraded.stdout"
grep -Fqx 'overall.status=degraded' "$TEST_ROOT/degraded.stdout"
grep -Fqx 'kernelsu.binary=unavailable' "$TEST_ROOT/degraded.stdout"

# True registration failures must degrade the otherwise healthy snapshot.
cp "$STATE_DIR/kernel_umount.report.txt" "$STATE_DIR/kernel_umount.report.saved"
cat > "$STATE_DIR/kernel_umount.report.txt" <<'EOF'
mode=enabled
auto=1
add=/system/bin/tool|source:KSU|failed|ioctl error
added=0
existing=0
rejected=0
failed=1
notify=ok
result=partial
EOF
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_LEGACY_RESUSFS_DIR="$TEST_ROOT/no-resusfs" \
SUSAF_LEGACY_SUSFS4KSU_DIR="$TEST_ROOT/no-susfs4ksu" \
SUSAF_SUSFS_BIN="$BIN_DIR/ksu_susfs" \
SUSAF_KSUD_BIN="$BIN_DIR/ksud" \
SUSAF_SETTINGS_BIN="$BIN_DIR/settings" \
SUSAF_GETPROP_BIN="$BIN_DIR/getprop" \
SUSAF_PIDOF_BIN="$BIN_DIR/pidof" \
SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo" \
SUSAF_BOOTCONFIG_SOURCE="$TEST_ROOT/bootconfig" \
SUSAF_PROC_VERSION="$TEST_ROOT/proc-version" \
sh "$MODULE_DIR/SusAF.sh" --diagnostics > "$TEST_ROOT/partial.stdout"
grep -Fqx 'overall.status=degraded' "$TEST_ROOT/partial.stdout"
grep -Fqx 'kernel_umount.mount_result=partial' "$TEST_ROOT/partial.stdout"
grep -Fqx 'kernel_umount.failures=1' "$TEST_ROOT/partial.stdout"
mv "$STATE_DIR/kernel_umount.report.saved" "$STATE_DIR/kernel_umount.report.txt"

. "$MODULE_DIR/lib/stage-state.sh"
stage_state_begin test-stage
stage_state_finish test-stage 7
grep -Fqx 'status=finished' "$STATE_DIR/stage.test-stage.properties"
grep -Fqx 'exit_status=7' "$STATE_DIR/stage.test-stage.properties"
[ "$(stat -c '%a' "$STATE_DIR/stage.test-stage.properties")" = 600 ]

echo "diagnostics tests passed"
