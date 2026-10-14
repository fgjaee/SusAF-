#!/bin/sh
# Read-only SUSFS LKM /proc surface discovery. No proc writes or live module load.
# The inforcqb guard LKM exposes these nodes only when loaded with expose_proc=1.

susaf_lkm_proc_probe() {
    local root="${SUSAF_LKM_PROC_ROOT:-/proc}"
    local node found=0
    SUSAF_LKM_PROC_STATUS=unavailable
    SUSAF_LKM_PROC_COUNT=0
    for node in susfs_hide_mounts susfs_hide_modules susfs_path                 susfs_kstat susfs_open_redirect susfs_avc_spoof                 susfs_enable_log; do
        if [ -f "$root/$node" ] && [ -r "$root/$node" ] && [ ! -L "$root/$node" ]; then
            found=$((found + 1))
        fi
    done
    SUSAF_LKM_PROC_COUNT=$found
    if [ "$found" -eq 0 ]; then
        SUSAF_LKM_PROC_STATUS=unavailable
        return 1
    fi
    if [ "$found" -ne 7 ]; then
        SUSAF_LKM_PROC_STATUS=partial
        return 1
    fi
    SUSAF_LKM_PROC_STATUS=present
    return 0
}

susaf_lkm_proc_report() {
    local root="${SUSAF_LKM_PROC_ROOT:-/proc}"
    local name first
    susaf_lkm_proc_probe
    local result=$?
    printf 'mode=lkm-proc-readonly\n'
    printf 'status=%s\n' "$SUSAF_LKM_PROC_STATUS"
    printf 'readable_nodes=%s/7\n' "$SUSAF_LKM_PROC_COUNT"
    for name in susfs_hide_mounts susfs_hide_modules susfs_path                 susfs_kstat susfs_open_redirect susfs_avc_spoof                 susfs_enable_log; do
        if [ -f "$root/$name" ] && [ -r "$root/$name" ] && [ ! -L "$root/$name" ]; then
            printf '%s=readable\n' "$name"
        else
            printf '%s=unavailable\n' "$name"
        fi
    done
    printf 'note=proc observation is not proof of safe writes or compatibility with every feature\n'
    printf 'result=read-only; no LKM loaded, altered, or unloaded\n'
    return "$result"
}
