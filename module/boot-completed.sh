#!/bin/sh
PATH=/data/adb/ksu/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"
. "$MODULE_DIR/lib/stage-state.sh"

stage_result=0
stage_state_begin boot-completed || stage_result=1

# A CLI-level stage gate alone is insufficient: this boot script also invokes
# the independent KernelSU feature writer. Check once before *any* script.
if ! sh "$MODULE_DIR/SusAF.sh" --compat-check >/dev/null 2>&1; then
    echo "[SusAF] skipping boot-stage policy: SUSFS backend unavailable"
    stage_state_finish boot-completed 2 || true
    exit 0
fi

# apply late-stage susfs config now that mounts have settled
sh "$MODULE_DIR/SusAF.sh" --stage-late || stage_result=1

sh "$MODULE_DIR/SusAF.sh" --run-bootcompleted-scripts || stage_result=1

# Migrated scripts may contain ReSuSFS's old numeric disable command.
sh "$MODULE_DIR/SusAF.sh" --apply-kernel-umount-feature || stage_result=1

stage_state_finish boot-completed "$stage_result" || true
sh "$MODULE_DIR/SusAF.sh" --status-report > /dev/null 2>&1 || true

# EOF
