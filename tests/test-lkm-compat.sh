#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
FAKE="$TEST_ROOT/ksu_susfs"
MODULES="$TEST_ROOT/modules"
printf 'susfs 16384 0 - Live 0x00000000\n' > "$MODULES"

cat > "$FAKE" <<'EOF'
#!/bin/sh
case "$*" in
    "show version") printf '%s\n' "${SUSAF_TEST_VERSION:-v2.3.0-r18.1}" ;;
    "show variant") printf 'GKI\n' ;;
    "show enabled_features")
        [ "${SUSAF_TEST_FEATURE_ERROR:-0}" = 0 ] || exit 1
        printf 'SUS_MOUNT\n'
        ;;
    *) exit 1 ;;
esac
EOF
chmod 700 "$FAKE"

SUSAF_COMPAT_ARCH=aarch64
SUSAF_COMPAT_KERNEL=5.15.167-android13
SUSAF_COMPAT_PROC_MODULES="$MODULES"
SUSAF_SUSFS_BIN="$FAKE"
SUSFS_MIN_VERSION=v2.2.0
export SUSAF_COMPAT_ARCH SUSAF_COMPAT_KERNEL SUSAF_COMPAT_PROC_MODULES SUSAF_SUSFS_BIN SUSFS_MIN_VERSION

. "$MODULE_DIR/lib/lkm-compat.sh"

susaf_compat_probe
[ "$SUSAF_COMPAT_RESULT" = ready ]
[ "$SUSAF_COMPAT_BACKEND" = loaded-lkm ]
[ "$SUSAF_COMPAT_VERSION" = v2.3.0-r18.1 ]
susaf_compat_require

# Built-in support does not need a module-list entry: use the kernel ioctl.
: > "$MODULES"
susaf_compat_probe
[ "$SUSAF_COMPAT_RESULT" = ready ]
[ "$SUSAF_COMPAT_BACKEND" = not-listed ]

# Reject older or unrecognized kernel interfaces.
SUSAF_TEST_VERSION=v1.5.5
export SUSAF_TEST_VERSION
if susaf_compat_probe; then exit 1; fi
[ "$SUSAF_COMPAT_REASON" = unsupported-susfs-version ]
SUSAF_TEST_VERSION="v2.3.0-r18.1"
export SUSAF_TEST_VERSION

# An unavailable feature query is not evidence of a compatible LKM.
SUSAF_TEST_FEATURE_ERROR=1
export SUSAF_TEST_FEATURE_ERROR
if susaf_compat_probe; then exit 1; fi
[ "$SUSAF_COMPAT_REASON" = feature-query-failed ]
SUSAF_TEST_FEATURE_ERROR=0
export SUSAF_TEST_FEATURE_ERROR

# Missing manager binary must block automatic kernel rule application.
SUSAF_SUSFS_BIN="$TEST_ROOT/missing"
export SUSAF_SUSFS_BIN
if susaf_compat_probe; then exit 1; fi
[ "$SUSAF_COMPAT_REASON" = userspace-tool-unavailable ]
if susaf_compat_require 2>/dev/null; then exit 1; fi

# Verify the public startup entry point stops before stage_early.
PERSISTENT_DIR="$TEST_ROOT/persistent"
mkdir -p "$PERSISTENT_DIR"
export SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" SUSAF_MODULE_DIR="$MODULE_DIR"
if NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --stage-early >"$TEST_ROOT/stage.log" 2>&1; then
    echo "ERROR: startup ran without SUSFS backend" >&2; exit 1
fi
if grep -Fq 'stage: early' "$TEST_ROOT/stage.log"; then
    echo "ERROR: stage began before the compatibility gate" >&2; exit 1
fi
grep -Fq 'runtime apply blocked' "$TEST_ROOT/stage.log"

echo "LKM backend compatibility tests passed"
