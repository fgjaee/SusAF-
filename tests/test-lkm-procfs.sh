#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
SUSFS_BIN="$TEST_ROOT/nonexistent-helper"
export SUSFS_BIN
. "$MODULE_DIR/lib/susfs-capabilities.sh"

# The test shadows kernel discovery so no real /proc node is ever modified.
susfs_lkm_active() { return 0; }
susfs_lkm_node() {
    case "$1" in
        add_sus_path|add_sus_path_loop) printf '%s/path\n' "$TEST_ROOT" ;;
        add_sus_kstat|add_sus_kstat_statically|update_sus_kstat) printf '%s/kstat\n' "$TEST_ROOT" ;;
        add_open_redirect) printf '%s/redirect\n' "$TEST_ROOT" ;;
        enable_log) printf '%s/log\n' "$TEST_ROOT" ;;
        enable_avc_log_spoofing) printf '%s/avc\n' "$TEST_ROOT" ;;
        *) return 1 ;;
    esac
}
for name in path kstat redirect log avc; do
    : > "$TEST_ROOT/$name"
done

susfs_has_command add_sus_path
susfs_has_command add_sus_path_loop
susfs_has_command add_open_redirect
if susfs_has_command add_sus_map; then
    echo "unsupported LKM command falsely reported" >&2
    exit 1
fi

susfs add_sus_path /data/local/tmp/susaf_test
grep -Fqx 'add /data/local/tmp/susaf_test' "$TEST_ROOT/path"
susfs add_sus_path_loop /data/local/tmp/susaf_loop_test
grep -Fqx 'add /data/local/tmp/susaf_loop_test' "$TEST_ROOT/path"

susfs add_sus_kstat /data/local/tmp/susaf_test
grep -Fqx 'add_sus_kstat /data/local/tmp/susaf_test' "$TEST_ROOT/kstat"

susfs add_open_redirect /tmp/source /tmp/target 2
grep -Fqx 'add_open_redirect /tmp/source /tmp/target 2' "$TEST_ROOT/redirect"

susfs enable_log 1
grep -Fqx '1' "$TEST_ROOT/log"

if susfs enable_log 7 2>/dev/null; then
    echo "invalid log toggle accepted" >&2
    exit 1
fi
if susfs add_open_redirect /tmp/source /tmp/target 8 2>/dev/null; then
    echo "invalid redirection scheme accepted" >&2
    exit 1
fi
if susfs add_sus_map /tmp/source >/dev/null 2>&1; then
    echo "unsupported LKM operation reported success" >&2
    exit 1
fi

echo "LKM procfs transport tests passed"
