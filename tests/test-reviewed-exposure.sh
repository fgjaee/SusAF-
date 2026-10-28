#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
PERSISTENT_DIR="$TEST_ROOT/SusAF"
export PERSISTENT_DIR
mkdir -p "$PERSISTENT_DIR/state" "$PERSISTENT_DIR/checkpoints" "$TEST_ROOT/live"
RUNTIME="$TEST_ROOT/live/ksud"
printf 'live runtime fixture\n' > "$RUNTIME"

cat > "$PERSISTENT_DIR/config.txt" <<'EOF'
KERNEL_UMOUNT_MODE=unchanged
SELINUX_HIDE_MODE=unchanged
EOF
: > "$PERSISTENT_DIR/sus_maps.txt"
: > "$PERSISTENT_DIR/sus_paths.txt"
: > "$PERSISTENT_DIR/sus_paths_loop.txt"
: > "$PERSISTENT_DIR/kernel_umount.txt"

. "$ROOT/module/lib/coverage.sh"
coverage_runtime_path_is_reviewable() { [ "$1" = "$RUNTIME" ]; }
apply_sus_maps() { return 0; }
apply_sus_paths() { return 0; }
apply_sus_paths_loop() { return 0; }
apply_kernel_umount_feature() { return 0; }
apply_kernel_umount_mounts() { return 0; }
apply_toggles() { return 0; }

report="$PERSISTENT_DIR/state/coverage.report.txt"
make_report() {
    kind="$1" backend="$2" action="$3"
    cat > "$report" <<EOF
schema=2
candidate.count=1
candidate.1.kind=$kind
candidate.1.target=$RUNTIME
candidate.1.reason=app_visible_root_artifact
candidate.1.risk=high
candidate.1.action=$action
exposure.count=1
exposure.1.path=$RUNTIME
exposure.1.app_visibility=visible
exposure.1.backend_supported=$backend
EOF
}

# High-risk path remains a recommendation until explicitly accepted.
make_report sus_path static-only hide_path_static
safe=$(coverage_apply_safe)
printf '%s\n' "$safe" | grep -Fqx 'result=no-safe-changes'
[ ! -s "$PERSISTENT_DIR/sus_paths.txt" ]

# Reviewed static-LKM path has a checkpoint, a runtime apply, and rollback.
apply=$(coverage_apply_ids 1)
printf '%s\n' "$apply" | grep -Fqx 'result=applied'
printf '%s\n' "$apply" | grep -Fqx 'added.sus_paths=1'
grep -Fqx "$RUNTIME" "$PERSISTENT_DIR/sus_paths.txt"
checkpoint=$(printf '%s\n' "$apply" | sed -n 's/^checkpoint=//p')
[ -e "$checkpoint/sus_paths.txt" ]
undo=$(coverage_rollback)
printf '%s\n' "$undo" | grep -Fqx 'result=restored'
[ ! -s "$PERSISTENT_DIR/sus_paths.txt" ]

# A report that no longer proves visibility cannot stage a kernel rule.
make_report sus_path static-only hide_path_static
sed -i 's/exposure.1.app_visibility=visible/exposure.1.app_visibility=not-tested/' "$report"
if coverage_apply_ids 1 >/dev/null 2>&1; then
    echo 'unverified candidate accepted' >&2
    exit 1
fi
[ ! -s "$PERSISTENT_DIR/sus_paths.txt" ]

# Backend mismatch must fail even if an unprivileged app observed the path.
make_report sus_path loop hide_path_static
if coverage_apply_ids 1 >/dev/null 2>&1; then
    echo 'static candidate accepted on loop-only backend' >&2
    exit 1
fi

# Loop-capable backend uses its separate persistent policy and checkpoint.
make_report sus_path_loop loop hide_path
apply=$(coverage_apply_ids 1)
grep -Fqx "$RUNTIME" "$PERSISTENT_DIR/sus_paths_loop.txt"
printf '%s\n' "$apply" | grep -Fqx 'added.sus_paths_loop=1'
coverage_rollback >/dev/null
[ ! -s "$PERSISTENT_DIR/sus_paths_loop.txt" ]

# Root-side observation alone can never authorize a reviewed correction.
make_report sus_path_loop loop hide_path
sed -i 's/exposure.1.app_visibility=visible/exposure.1.app_visibility=not-tested/' "$report"
if coverage_apply_ids 1 >/dev/null 2>&1; then
    echo 'root-only candidate accepted' >&2
    exit 1
fi

echo 'reviewed artifact checkpoint and rollback tests passed'
