#!/bin/sh
PATH=/data/adb/ksu/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"
. "$MODULE_DIR/lib/stage-state.sh"

stage_result=0
stage_state_begin post-fs-data || stage_result=1

# This runs even without an interactive app: do not execute independent
# KernelSU feature writers or migrated user scripts when SUSFS is unavailable.
if ! sh "$MODULE_DIR/SusAF.sh" --compat-check >/dev/null 2>&1; then
    echo "[SusAF] skipping boot-stage policy: SUSFS backend unavailable"
    stage_state_finish post-fs-data 2 || true
    exit 0
fi

# apply early-stage susfs config now that mounts have settled
sh "$MODULE_DIR/SusAF.sh" --stage-early || stage_result=1

sh "$MODULE_DIR/SusAF.sh" --run-postfs-scripts || stage_result=1

# Re-assert Sus'AF's explicit policy after migrated/custom scripts have run.
sh "$MODULE_DIR/SusAF.sh" --apply-kernel-umount-feature || stage_result=1

stage_state_finish post-fs-data "$stage_result" || true

# EOF
