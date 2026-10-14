#!/bin/sh
# Read-only capability discovery for KernelSU's native umount interface.
# Supports a useful diagnostic mode when SUSFS is absent. This file never sets
# features, registers unmounts, writes a module setting, or insmods an LKM.

susaf_ksu_readonly_probe() {
    SUSAF_KSU_STATUS=unavailable
    SUSAF_KSU_BINARY=unavailable
    SUSAF_KSU_KERNEL_UMOUNT=unknown
    SUSAF_KSU_SELINUX_HIDE=unknown
    SUSAF_KSU_KERNEL_UMOUNT_CURRENT=unknown
    SUSAF_KSU_SELINUX_HIDE_CURRENT=unknown
    local binary check value feature

    if ! command -v resolve_ksud_bin >/dev/null 2>&1; then
        SUSAF_KSU_STATUS=resolver-missing
        return 1
    fi
    binary=$(resolve_ksud_bin 2>/dev/null) || binary=""
    if [ -z "$binary" ] || [ ! -f "$binary" ] || [ ! -x "$binary" ]; then
        SUSAF_KSU_STATUS=daemon-unavailable
        return 1
    fi
    SUSAF_KSU_BINARY="$binary"

    for feature in kernel_umount selinux_hide; do
        check=$("$binary" feature check "$feature" 2>/dev/null) || check=unavailable
        case "$check" in supported|managed|unsupported) ;; *) check=unavailable ;; esac
        value=$("$binary" feature get "$feature" 2>/dev/null |
            awk -F': ' '$1 == "Status" { print $2; exit }') || value=unknown
        [ -n "$value" ] || value=unknown
        case "$feature" in
        kernel_umount)
            SUSAF_KSU_KERNEL_UMOUNT="$check"
            SUSAF_KSU_KERNEL_UMOUNT_CURRENT="$value"
            ;;
        selinux_hide)
            SUSAF_KSU_SELINUX_HIDE="$check"
            SUSAF_KSU_SELINUX_HIDE_CURRENT="$value"
            ;;
        esac
    done

    case "$SUSAF_KSU_KERNEL_UMOUNT" in
        supported|managed) SUSAF_KSU_STATUS=available; return 0 ;;
        *) SUSAF_KSU_STATUS=kernel-umount-unavailable; return 1 ;;
    esac
}

susaf_ksu_readonly_audit() {
    local mountinfo="${SUSAF_MOUNTINFO:-/proc/1/mountinfo}"
    local result
    susaf_ksu_readonly_probe
    result=$?
    printf 'mode=kernel-only-readonly\n'
    printf 'status=%s\n' "$SUSAF_KSU_STATUS"
    printf 'daemon=%s\n' "$SUSAF_KSU_BINARY"
    printf 'kernel_umount.support=%s\n' "$SUSAF_KSU_KERNEL_UMOUNT"
    printf 'kernel_umount.current=%s\n' "$SUSAF_KSU_KERNEL_UMOUNT_CURRENT"
    printf 'selinux_hide.support=%s\n' "$SUSAF_KSU_SELINUX_HIDE"
    printf 'selinux_hide.current=%s\n' "$SUSAF_KSU_SELINUX_HIDE_CURRENT"
    printf 'susfs=not-required-for-readonly-audit\n'
    if [ ! -r "$mountinfo" ]; then
        printf 'mountinfo=unavailable\n'
        return 1
    fi
    printf 'mountinfo=readable\n'
    printf 'module_backed_mounts:\n'
    # Show only the mountpoint and a curated module source classification.
    # No binary keys, device IDs, app private data, or full mountinfo lines.
    awk '
      function module_path(value) {
        return value ~ /(^|\/)data\/adb\/modules(_update)?\// ||
               value ~ /(^|\/)adb\/modules(_update)?\//
      }
      {
        sep=0
        for (i=7; i<=NF; i++) if ($i == "-") { sep=i; break }
        if (!sep || sep + 2 > NF) next
        root=$4; target=$5; fs=$(sep+1); source=$(sep+2)
        opts=(sep+3<=NF ? $(sep+3) : "")
        if (source == "KSU" || module_path(root) ||
            module_path(source) || (fs == "overlay" && module_path(opts))) {
            if (!seen[target]++) print "  " target
        }
      }
    ' "$mountinfo"
    printf 'result=read-only; no features or unmounts applied\n'
    return "$result"
}
