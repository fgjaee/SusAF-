#!/bin/sh
set -eu
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
export SUSFS_BIN="$TEST_ROOT/nonexistent-helper"
export SUSAF_SUSFS_LKM_LOADER="$TEST_ROOT/loader"
export SUSAF_GUARD_TEST_ACTIVE="$TEST_ROOT/active"
export SUSAF_GUARD_TEST_COUNT="$TEST_ROOT/load-count"
mkdir -p "$SUSAF_SUSFS_LKM_LOADER/bin"
cat > "$SUSAF_SUSFS_LKM_LOADER/bin/susfs_probe" <<'PROBE'
#!/bin/sh
[ -f "$SUSAF_GUARD_TEST_ACTIVE" ] && exit 0
exit 10
PROBE
cat > "$SUSAF_SUSFS_LKM_LOADER/post-fs-data.sh" <<'LOAD'
#!/bin/sh
printf 'load\n' >> "$SUSAF_GUARD_TEST_COUNT"
: > "$SUSAF_GUARD_TEST_ACTIVE"
exit 0
LOAD
chmod 755 "$SUSAF_SUSFS_LKM_LOADER/bin/susfs_probe" "$SUSAF_SUSFS_LKM_LOADER/post-fs-data.sh"
. "$MODULE_DIR/lib/susfs-capabilities.sh"
susfs_lkm_active() { [ -f "$SUSAF_GUARD_TEST_ACTIVE" ]; }
susfs_ensure_backend
[ "$(wc -l < "$SUSAF_GUARD_TEST_COUNT" | tr -d '[:space:]')" = 1 ]
susfs_ensure_backend
[ "$(wc -l < "$SUSAF_GUARD_TEST_COUNT" | tr -d '[:space:]')" = 1 ]
rm -f "$SUSAF_GUARD_TEST_ACTIVE"
cat > "$SUSAF_SUSFS_LKM_LOADER/bin/susfs_probe" <<'PROBE'
#!/bin/sh
exit 5
PROBE
chmod 755 "$SUSAF_SUSFS_LKM_LOADER/bin/susfs_probe"
if susfs_ensure_backend >/dev/null 2>&1; then
    echo "inconclusive probe incorrectly allowed a guard load" >&2
    exit 1
fi
[ "$(wc -l < "$SUSAF_GUARD_TEST_COUNT" | tr -d '[:space:]')" = 1 ]
echo "SUSFS guard loader tests passed"
