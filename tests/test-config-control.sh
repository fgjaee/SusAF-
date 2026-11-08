#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
PERSISTENT_DIR="$TEST_ROOT/persistent"
mkdir -p "$PERSISTENT_DIR"

. "$MODULE_DIR/lib/config-control.sh"

cat > "$PERSISTENT_DIR/config.txt" <<'EOF'
# preserved comment
HIDE_SUS_MNTS_NON_SU=1
ENABLE_LOG=0
ENABLE_LOG=1
UNKNOWN_SETTING=keep-me
KERNEL_UMOUNT_MODE=enabled
EOF

susaf_config_set "$PERSISTENT_DIR/config.txt" \
	HIDE_SUS_MNTS_NON_SU=0 \
	ENABLE_LOG=0 \
	ALLOW_BROAD_KERNEL_UMOUNT=1

grep -Fqx '# preserved comment' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'HIDE_SUS_MNTS_NON_SU=0' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'ENABLE_LOG=0' "$PERSISTENT_DIR/config.txt"
[ "$(grep -c '^ENABLE_LOG=' "$PERSISTENT_DIR/config.txt")" -eq 1 ]
grep -Fqx 'ALLOW_BROAD_KERNEL_UMOUNT=1' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'UNKNOWN_SETTING=keep-me' "$PERSISTENT_DIR/config.txt"
[ "$(stat -c '%a' "$PERSISTENT_DIR/config.txt")" = 600 ]

susaf_config_show "$PERSISTENT_DIR/config.txt" > "$TEST_ROOT/show.out"
grep -Fqx 'HIDE_SUS_MNTS_NON_SU=0' "$TEST_ROOT/show.out"
grep -Fqx 'ENABLE_LOG=0' "$TEST_ROOT/show.out"
grep -Fqx 'KERNEL_UMOUNT_MODE=enabled' "$TEST_ROOT/show.out"
grep -Fqx 'ALLOW_BROAD_KERNEL_UMOUNT=1' "$TEST_ROOT/show.out"
! grep -Fq 'UNKNOWN_SETTING' "$TEST_ROOT/show.out"

cp "$PERSISTENT_DIR/config.txt" "$TEST_ROOT/before-invalid"
set +e
susaf_config_set "$PERSISTENT_DIR/config.txt" ENABLE_LOG=1 HIDE_SUS_MNTS_LATE=maybe
status=$?
set -e
[ "$status" -ne 0 ]
cmp -s "$TEST_ROOT/before-invalid" "$PERSISTENT_DIR/config.txt"

set +e
susaf_config_set "$PERSISTENT_DIR/config.txt" NOT_A_SUSAF_KEY=1
status=$?
set -e
[ "$status" -ne 0 ]

set +e
susaf_config_set "$PERSISTENT_DIR/config.txt" KERNEL_UMOUNT_MODE=banana
status=$?
set -e
[ "$status" -ne 0 ]

susaf_config_set "$PERSISTENT_DIR/config.txt" KERNEL_UMOUNT_MODE=unchanged ADB_MODE=spoof-off
grep -Fqx 'KERNEL_UMOUNT_MODE=unchanged' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'ADB_MODE=spoof-off' "$PERSISTENT_DIR/config.txt"

printf 'test-config-control: ok\n'
