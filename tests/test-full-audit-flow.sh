#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
PERSISTENT_DIR="$TEST_ROOT/SusAF"
RUNTIME="$TEST_ROOT/tmp/ksud"
mkdir -p "$PERSISTENT_DIR/state" "$PERSISTENT_DIR/checkpoints" "$TEST_ROOT/tmp" "$TEST_ROOT/apex/bin" "$TEST_ROOT/bin"
export PERSISTENT_DIR
printf 'root runtime\n' > "$RUNTIME"
: > "$PERSISTENT_DIR/sus_maps.txt"
: > "$PERSISTENT_DIR/sus_paths.txt"
: > "$PERSISTENT_DIR/sus_paths_loop.txt"
: > "$PERSISTENT_DIR/kernel_umount.txt"
: > "$PERSISTENT_DIR/scripts_postfs.txt"
cat > "$PERSISTENT_DIR/config.txt" <<'EOF'
KERNEL_UMOUNT_MODE=unchanged
SELINUX_HIDE_MODE=unchanged
EOF
cat > "$PERSISTENT_DIR/state/kernel_umount.feature.txt" <<'EOF'
result=ok
EOF
cat > "$PERSISTENT_DIR/state/kernel_umount.report.txt" <<'EOF'
failed=0
result=ok
EOF

cat > "$TEST_ROOT/bin/pm" <<'EOF'
#!/bin/sh
printf 'package:/data/app/com.fgjaee.susaf.probe/base.apk\n'
EOF
cat > "$TEST_ROOT/bin/content" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = --arg ]; then shift; arg="$1"; break; fi
    shift
done
if grep -Fqx "$arg" "$PERSISTENT_DIR/sus_paths_loop.txt"; then
    visible=MISSING
else
    visible=VISIBLE
fi
printf 'Result: Bundle[{result=SUSAFPROBEV1__10156__1__%s}]\n' "$visible"
EOF
chmod 755 "$TEST_ROOT/bin/content" "$TEST_ROOT/bin/pm"
export SUSAF_PROBE_CONTENT_BIN="$TEST_ROOT/bin/content"
export SUSAF_PROBE_PM_BIN="$TEST_ROOT/bin/pm"
export SUSAF_EXPOSURE_TMP_ROOT="$TEST_ROOT/tmp"
export SUSAF_EXPOSURE_APEX_SU="$TEST_ROOT/apex/bin/su"
export SUSAF_COVERAGE_REPORT="$PERSISTENT_DIR/state/coverage.report.txt"

. "$ROOT/module/lib/coverage.sh"
. "$ROOT/module/lib/exposure-audit.sh"
. "$ROOT/module/lib/probe-verify.sh"
susfs_has_command() { [ "$1" = add_sus_path_loop ]; }
coverage_runtime_path_is_reviewable() { [ "$1" = "$RUNTIME" ]; }
coverage_collect_curated_paths() { :; }
coverage_collect_process_maps() { COVERAGE_PROCESS_COUNT=0; COVERAGE_PROCESS_IDS=none; }
coverage_collect_mount_namespaces() { COVERAGE_MOUNT_NAMESPACE_COUNT=1; COVERAGE_HIGH_ID_COUNT=0; }
coverage_collect_controls() { :; }
apply_sus_maps() { :; }
apply_sus_paths() { :; }
apply_sus_paths_loop() { :; }
apply_kernel_umount_feature() { :; }
apply_kernel_umount_mounts() { :; }
apply_toggles() { :; }
coverage_schedule_status() { printf 'not-scheduled\n'; }

scan=$(coverage_scan)
printf '%s\n' "$scan" | grep -Fqx 'exposure.1.app_visibility=visible'
printf '%s\n' "$scan" | grep -Fqx 'exposure.probe_uid=10156'
printf '%s\n' "$scan" | grep -Fqx 'candidate.count=1'
printf '%s\n' "$scan" | grep -Fqx 'candidate.safe=0'
printf '%s\n' "$scan" | grep -Fqx 'candidate.risky=1'
printf '%s\n' "$scan" | grep -Fqx 'candidate.1.reason=app_visible_root_artifact'

safe=$(coverage_apply_safe)
printf '%s\n' "$safe" | grep -Fqx 'result=no-safe-changes'
[ ! -s "$PERSISTENT_DIR/sus_paths_loop.txt" ]

apply=$(coverage_apply_ids 1)
printf '%s\n' "$apply" | grep -Fqx 'result=applied'
grep -Fqx "$RUNTIME" "$PERSISTENT_DIR/sus_paths_loop.txt"

# The fixture imitates the app observing that the now-configured path is
# unavailable. This checks orchestration, not a real kernel implementation.
verified=$(coverage_verify)
printf '%s\n' "$verified" | grep -Fqx 'result=clean'
printf '%s\n' "$verified" | grep -Fqx 'app_visibility=checked'
printf '%s\n' "$verified" | grep -Fqx 'observations.visible=0'
grep -Fqx 'exposure.1.app_visibility=not-found' "$SUSAF_COVERAGE_REPORT"

coverage_rollback >/dev/null
[ ! -s "$PERSISTENT_DIR/sus_paths_loop.txt" ]
echo 'full audit to reviewed correction to re-verification flow passed'
