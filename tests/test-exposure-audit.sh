#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
PERSISTENT_DIR="$TEST_ROOT/state"
mkdir -p "$PERSISTENT_DIR" "$TEST_ROOT/tmp" "$TEST_ROOT/apex/bin"
export PERSISTENT_DIR

printf 'alive\n' > "$TEST_ROOT/tmp/ksud"
printf 'ordinary\n' > "$TEST_ROOT/tmp/readme.txt"
printf 'hidden\n' > "$TEST_ROOT/tmp/.su_marker"
printf 'apex\n' > "$TEST_ROOT/apex/bin/su"
ln -s /missing/target "$TEST_ROOT/tmp/ghostlock_su"
python3 - "$TEST_ROOT/tmp/temp_su.sock" <<'PY'
import socket
import sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(sys.argv[1])
sock.close()
PY

printf '%s\n' "$TEST_ROOT/tmp/ksud" > "$PERSISTENT_DIR/sus_paths_loop.txt"
: > "$PERSISTENT_DIR/sus_paths.txt"

SUSAF_EXPOSURE_TMP_ROOT="$TEST_ROOT/tmp"
SUSAF_EXPOSURE_APEX_SU="$TEST_ROOT/apex/bin/su"
SUSAF_EXPOSURE_MAX_ITEMS=64
export SUSAF_EXPOSURE_TMP_ROOT SUSAF_EXPOSURE_APEX_SU SUSAF_EXPOSURE_MAX_ITEMS

. "$ROOT/module/lib/coverage.sh"
. "$ROOT/module/lib/exposure-audit.sh"

susfs_has_command() { [ "$1" = add_sus_path_loop ]; }
evidence="$TEST_ROOT/evidence.tsv"
exposure_scan "$evidence"
output=$(exposure_emit_report "$evidence")

printf '%s\n' "$output" | grep -Fqx 'exposure.schema=1'
printf '%s\n' "$output" | grep -Fqx 'exposure.count=5'
printf '%s\n' "$output" | grep -Fqx 'exposure.result=observed-unverified'
printf '%s\n' "$output" | grep -Fqx 'exposure.app_visibility=not-tested'
printf '%s\n' "$output" | grep -Fqx 'exposure.policy_action=none'
printf '%s\n' "$output" | grep -Fqx 'exposure.truncated=0'
printf '%s\n' "$output" | grep -Fqx 'exposure.tmp_check=checked'
printf '%s\n' "$output" | grep -Fqx 'exposure.apex_check=checked'
printf '%s\n' "$output" | grep -Fq "$TEST_ROOT/tmp/ksud"
printf '%s\n' "$output" | grep -Fq "$TEST_ROOT/tmp/temp_su.sock"
printf '%s\n' "$output" | grep -Fq "$TEST_ROOT/apex/bin/su"
printf '%s\n' "$output" | grep -Fq 'backend_supported=loop'
printf '%s\n' "$output" | grep -Fq 'configured=listed-loop'
printf '%s\n' "$output" | grep -Fq 'type=socket'
printf '%s\n' "$output" | grep -Fq 'type=symlink'
if printf '%s\n' "$output" | grep -Fq "$TEST_ROOT/tmp/readme.txt"; then
    echo 'benign file incorrectly flagged as root signal' >&2
    exit 1
fi

# Non-mutating: the discovery phase must leave all fixtures untouched.
[ -e "$TEST_ROOT/tmp/ksud" ]
[ -S "$TEST_ROOT/tmp/temp_su.sock" ]
[ -L "$TEST_ROOT/tmp/ghostlock_su" ]

# A live LKM with only static procfs path support must not claim loop support.
susfs_has_command() { [ "$1" = add_sus_path ]; }
[ "$(exposure_backend)" = static-only ]
susfs_has_command() { return 1; }
[ "$(exposure_backend)" = unsupported ]

# Truncation must be visible rather than silently calling the audit complete.
SUSAF_EXPOSURE_MAX_ITEMS=1
exposure_scan "$evidence"
limited=$(exposure_emit_report "$evidence")
printf '%s\n' "$limited" | grep -Fqx 'exposure.count=1'
printf '%s\n' "$limited" | grep -Fqx 'exposure.truncated=1'
printf '%s\n' "$limited" | grep -Fqx 'exposure.result=incomplete'

# Missing directory is unavailable, not a verified clean filesystem.
SUSAF_EXPOSURE_TMP_ROOT="$TEST_ROOT/missing"
SUSAF_EXPOSURE_APEX_SU="$TEST_ROOT/missing/bin/su"
exposure_scan "$evidence"
missing=$(exposure_emit_report "$evidence")
printf '%s\n' "$missing" | grep -Fqx 'exposure.result=incomplete'
printf '%s\n' "$missing" | grep -Fqx 'exposure.tmp_check=unavailable'

# Empty, fully checked scope is still not app-side verification.
mkdir -p "$TEST_ROOT/empty"
SUSAF_EXPOSURE_TMP_ROOT="$TEST_ROOT/empty"
SUSAF_EXPOSURE_APEX_SU="$TEST_ROOT/apex/bin/missing"
SUSAF_EXPOSURE_MAX_ITEMS=64
exposure_scan "$evidence"
empty=$(exposure_emit_report "$evidence")
printf '%s\n' "$empty" | grep -Fqx 'exposure.count=0'
printf '%s\n' "$empty" | grep -Fqx 'exposure.result=no-observations-unverified'

echo 'read-only exposure audit tests passed'
