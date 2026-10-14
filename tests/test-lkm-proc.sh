#!/bin/sh
set -eu
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
SUSAF_LKM_PROC_ROOT="$TEST_ROOT/proc"
export SUSAF_LKM_PROC_ROOT
mkdir -p "$SUSAF_LKM_PROC_ROOT"
. "$MODULE_DIR/lib/lkm-proc.sh"

if susaf_lkm_proc_probe; then exit 1; fi
[ "$SUSAF_LKM_PROC_STATUS" = unavailable ]
[ "$SUSAF_LKM_PROC_COUNT" = 0 ]

: > "$SUSAF_LKM_PROC_ROOT/susfs_hide_mounts"
if susaf_lkm_proc_probe; then exit 1; fi
[ "$SUSAF_LKM_PROC_STATUS" = partial ]
[ "$SUSAF_LKM_PROC_COUNT" = 1 ]

for name in susfs_hide_modules susfs_path susfs_kstat susfs_open_redirect             susfs_avc_spoof susfs_enable_log; do
    : > "$SUSAF_LKM_PROC_ROOT/$name"
done
susaf_lkm_proc_probe
[ "$SUSAF_LKM_PROC_STATUS" = present ]
[ "$SUSAF_LKM_PROC_COUNT" = 7 ]
susaf_lkm_proc_report > "$TEST_ROOT/report"
grep -Fqx 'mode=lkm-proc-readonly' "$TEST_ROOT/report"
grep -Fqx 'status=present' "$TEST_ROOT/report"
grep -Fqx 'readable_nodes=7/7' "$TEST_ROOT/report"
grep -Fqx 'result=read-only; no LKM loaded, altered, or unloaded' "$TEST_ROOT/report"

rm -f "$SUSAF_LKM_PROC_ROOT/susfs_kstat"
ln -s /proc/version "$SUSAF_LKM_PROC_ROOT/susfs_kstat"
if susaf_lkm_proc_probe; then exit 1; fi
[ "$SUSAF_LKM_PROC_STATUS" = partial ]
[ "$SUSAF_LKM_PROC_COUNT" = 6 ]

echo "LKM proc interface tests passed"
