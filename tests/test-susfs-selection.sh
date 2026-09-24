#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
export SUSAF_MODULE_DIR="$MODULE_DIR"
export SUSAF_PERSISTENT_DIR="$TEST_ROOT/persistent"
export SUSAF_BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$SUSAF_PERSISTENT_DIR" "$SUSAF_BIN_DIR"

. "$MODULE_DIR/common.sh"
MODDIR="$MODULE_DIR"
. "$MODULE_DIR/utils.sh"

make_helper() {
	path="$1"
	version="$2"
	variant="$3"
	cat > "$path" <<EOF
#!/bin/sh
case "\$1 \$2" in
	'show version') printf '%s\n' '$version' ;;
	'show variant') printf '%s\n' '$variant' ;;
	*) exit 0 ;;
esac
EOF
	chmod 755 "$path"
}

make_helper "$TEST_ROOT/external" v2.3.0 ReSukiSU
ln -s "$TEST_ROOT/external" "$DEST_BIN_DIR/ksu_susfs"
make_helper "$TEST_ROOT/bundled" v2.3.0 Bundled
SUSFS_BUNDLED_BIN="$TEST_ROOT/bundled"
export SUSFS_BUNDLED_BIN

select_susfs_binary v2.2.0
[ "$SUSFS_BIN" = "$DEST_BIN_DIR/ksu_susfs" ]
[ "$SUSFS_BIN_SOURCE" = external ]

rm -f "$DEST_BIN_DIR/ksu_susfs"
make_helper "$TEST_ROOT/external-old" v1.5.12 Legacy
ln -s "$TEST_ROOT/external-old" "$DEST_BIN_DIR/ksu_susfs"

select_susfs_binary v2.2.0
[ "$SUSFS_BIN" = "$TEST_ROOT/bundled" ]
[ "$SUSFS_BIN_SOURCE" = bundled ]

SUSAF_SUSFS_BIN="$TEST_ROOT/external-old"
export SUSAF_SUSFS_BIN
select_susfs_binary v2.2.0
[ "$SUSFS_BIN" = "$TEST_ROOT/external-old" ]
[ "$SUSFS_BIN_SOURCE" = override ]
unset SUSAF_SUSFS_BIN

rm -f "$DEST_BIN_DIR/ksu_susfs" "$TEST_ROOT/bundled"
set +e
select_susfs_binary v2.2.0
status=$?
set -e
[ "$status" -ne 0 ]
[ "$SUSFS_BIN_SOURCE" = unavailable ]

printf 'test-susfs-selection: ok\n'
