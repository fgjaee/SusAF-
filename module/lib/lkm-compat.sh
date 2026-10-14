#!/bin/sh
# Read-only compatibility check for built-in and separately loaded SUSFS backends.
# Never insmod, patch a boot image, apply rules, or replace manager-owned binaries.

susaf_compat_version_at_least() {
    local observed="${1#v}" minimum="${2#v}" part
    observed="${observed%% *}"; observed="${observed%%-*}"
    minimum="${minimum%% *}"; minimum="${minimum%%-*}"
    case "$observed:$minimum" in
        *[!0-9.:]*|'':*|*:'') return 1 ;;
    esac
    # Require exactly major.minor.patch, then compare numerically.
    printf '%s\n' "$observed" "$minimum" |
      awk -F. 'NF != 3 { bad=1 } {
        for (i=1; i<=3; i++) if ($i !~ /^[0-9]+$/) bad=1
        for (i=1; i<=3; i++) v[NR,i]=$i+0
      } END {
        if (NR != 2 || bad) exit 1
        for (i=1; i<=3; i++) {
          if (v[1,i] > v[2,i]) exit 0
          if (v[1,i] < v[2,i]) exit 1
        }
        exit 0
      }'
}

susaf_compat_probe() {
    local binary="${SUSAF_SUSFS_BIN:-${SUSFS_BIN:-}}"
    local modules="${SUSAF_COMPAT_PROC_MODULES:-/proc/modules}"
    local minimum="${SUSFS_MIN_VERSION:-v2.2.0}"
    local version variant features
    SUSAF_COMPAT_RESULT=blocked
    SUSAF_COMPAT_REASON=unknown
    SUSAF_COMPAT_VERSION=unavailable
    SUSAF_COMPAT_VARIANT=unavailable
    SUSAF_COMPAT_BACKEND=not-listed
    SUSAF_COMPAT_KERNEL="${SUSAF_COMPAT_KERNEL:-$(cat /proc/sys/kernel/osrelease 2>/dev/null || uname -r)}"
    SUSAF_COMPAT_ARCH="${SUSAF_COMPAT_ARCH:-$(uname -m)}"
    SUSAF_COMPAT_BINARY="${binary:-unavailable}"

    if [ -r "$modules" ] && grep -Eq '^(susfs|susfs_lkm|susfs4ksu|susfs4ksu_lkm)[[:space:]]' "$modules"; then
        SUSAF_COMPAT_BACKEND=loaded-lkm
    fi
    case "$SUSAF_COMPAT_ARCH" in
      aarch64|arm64) ;;
      *) SUSAF_COMPAT_REASON=unsupported-architecture; return 1 ;;
    esac
    if [ -z "$binary" ] || [ ! -f "$binary" ] || [ ! -x "$binary" ] || [ -L "$binary" ]; then
        SUSAF_COMPAT_REASON=userspace-tool-unavailable
        return 1
    fi
    version=$("$binary" show version 2>/dev/null) || {
        SUSAF_COMPAT_REASON=kernel-interface-unavailable
        return 1
    }
    SUSAF_COMPAT_VERSION="$(printf '%s\n' "$version" | sed -n '1p')"
    if ! susaf_compat_version_at_least "$SUSAF_COMPAT_VERSION" "$minimum"; then
        SUSAF_COMPAT_REASON=unsupported-susfs-version
        return 1
    fi
    variant=$("$binary" show variant 2>/dev/null) || {
        SUSAF_COMPAT_REASON=variant-query-failed
        return 1
    }
    SUSAF_COMPAT_VARIANT="$(printf '%s\n' "$variant" | sed -n '1p')"
    [ -n "$SUSAF_COMPAT_VARIANT" ] || {
        SUSAF_COMPAT_REASON=variant-unavailable
        return 1
    }
    features=$("$binary" show enabled_features 2>/dev/null) || {
        SUSAF_COMPAT_REASON=feature-query-failed
        return 1
    }
    # A successful feature query proves the query is wired up, not that every
    # command is supported. Feature-specific validation still occurs at apply.
    SUSAF_COMPAT_RESULT=ready
    SUSAF_COMPAT_REASON=kernel-queries-accepted
    return 0
}

susaf_compat_report() {
    susaf_compat_probe
    local result=$?
    printf 'status=%s\n' "$SUSAF_COMPAT_RESULT"
    printf 'reason=%s\n' "$SUSAF_COMPAT_REASON"
    printf 'kernel=%s\n' "$SUSAF_COMPAT_KERNEL"
    printf 'architecture=%s\n' "$SUSAF_COMPAT_ARCH"
    printf 'backend=%s\n' "$SUSAF_COMPAT_BACKEND"
    printf 'userspace.binary=%s\n' "$SUSAF_COMPAT_BINARY"
    printf 'susfs.version=%s\n' "$SUSAF_COMPAT_VERSION"
    printf 'susfs.variant=%s\n' "$SUSAF_COMPAT_VARIANT"
    printf 'note=loaded-lkm is advisory; a healthy SUSFS kernel query is required for runtime actions\n'
    return "$result"
}

susaf_compat_require() {
    susaf_compat_probe && return 0
    printf '[SusAF] runtime apply blocked: %s (%s)\n' "$SUSAF_COMPAT_REASON" "$SUSAF_COMPAT_BINARY" >&2
    printf '[SusAF] run --compat-check; no kernel rule has been applied\n' >&2
    return 1
}
