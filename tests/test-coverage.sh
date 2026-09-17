#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

PERSISTENT_DIR="$TEST_ROOT/SusAF"
STATE_DIR="$PERSISTENT_DIR/state"
PROC_ROOT="$TEST_ROOT/proc"
MAP_ROOT="$TEST_ROOT/data/adb/modules"
mkdir -p "$PERSISTENT_DIR" "$STATE_DIR" "$PROC_ROOT/4321" \
	"$MAP_ROOT/target/lib64" "$MAP_ROOT/unrelated/lib64" "$TEST_ROOT/bin"

printf '# exact map targets\n%s\n' "$MAP_ROOT/target/lib64/already.so" > "$PERSISTENT_DIR/sus_maps.txt"
printf '# paths\n' > "$PERSISTENT_DIR/sus_paths.txt"
printf '# loop paths\n' > "$PERSISTENT_DIR/sus_paths_loop.txt"
printf '# umount paths\n' > "$PERSISTENT_DIR/kernel_umount.txt"
printf 'SusAF_apply-sus-maps.sh\nSusAF_apply-sus-paths.sh\nSusAF_apply-sus-paths-loop.sh\n' \
	> "$PERSISTENT_DIR/scripts_postfs.txt"

printf 'mapped\n' > "$MAP_ROOT/target/lib64/already.so"
printf 'candidate\n' > "$MAP_ROOT/target/lib64/exact-candidate.so"
printf 'unrelated\n' > "$MAP_ROOT/unrelated/lib64/not-mapped.so"

cat > "$PROC_ROOT/4321/maps" <<EOF
70000000-70001000 r--p 00000000 103:06 100 $MAP_ROOT/target/lib64/already.so
70001000-70002000 r-xp 00000000 103:06 101 $MAP_ROOT/target/lib64/exact-candidate.so
70002000-70003000 r-xp 00000000 00:00 0 /memfd:jit-cache (deleted)
EOF

cat > "$TEST_ROOT/bin/pidof" <<'EOF'
#!/bin/sh
[ "$1" = com.example.detector ] && printf '4321\n'
EOF
chmod 755 "$TEST_ROOT/bin/pidof"

cat > "$TEST_ROOT/mountinfo" <<EOF
31 25 0:26 / / rw,relatime - rootfs rootfs rw
40 31 0:50 /data/adb/modules/hosts/system/etc/hosts /system/etc/hosts ro - tmpfs KSU rw
EOF

export PERSISTENT_DIR
export LEGACY_RESUSFS_DIR="$TEST_ROOT/legacy-resusfs"
export LEGACY_SUSFS4KSU_DIR="$TEST_ROOT/legacy-susfs4ksu"
export SUSAF_PIDOF_BIN="$TEST_ROOT/bin/pidof"
export SUSAF_PROC_ROOT="$PROC_ROOT"
export SUSAF_COVERAGE_MAP_ROOTS="$MAP_ROOT"
export SUSAF_COVERAGE_REQUIRE_EXISTS=1
export SUSAF_MOUNTINFO="$TEST_ROOT/mountinfo"

. "$ROOT/module/lib/kernel-umount.sh"
. "$ROOT/module/lib/coverage.sh"

output=$(coverage_scan com.example.detector)
report="$STATE_DIR/coverage.report.txt"
[ -f "$report" ]
grep -Fqx 'schema=1' "$report"
grep -Fqx 'mode=app' "$report"
grep -Fqx 'package=com.example.detector' "$report"
grep -Fqx 'process.count=1' "$report"
grep -Fqx 'candidate.count=1' "$report"
grep -Fqx 'candidate.sus_maps=1' "$report"
grep -Fqx "candidate.1.path=$MAP_ROOT/target/lib64/exact-candidate.so" "$report"
grep -Fqx 'candidate.1.kind=sus_map' "$report"
grep -Fqx 'candidate.1.reason=mapped_module_file' "$report"
printf '%s\n' "$output" | grep -Fqx 'result=ok'
! grep -Fq 'not-mapped.so' "$report"

# A hostile package string must be rejected before pidof is called.
if coverage_scan 'com.example;touch.bad' >/dev/null 2>&1; then
	echo 'unsafe package accepted' >&2
	exit 1
fi

# A comment marker would change the meaning of a persisted list entry.
if coverage_path_is_safe "$MAP_ROOT/target/lib64/name#hidden.so"; then
	echo 'comment-bearing path accepted' >&2
	exit 1
fi

apply_output=$(coverage_apply_ids 1)
grep -Fqx "$MAP_ROOT/target/lib64/exact-candidate.so" "$PERSISTENT_DIR/sus_maps.txt"
printf '%s\n' "$apply_output" | grep -Fqx 'result=saved'
printf '%s\n' "$apply_output" | grep -Fqx 'added.sus_maps=1'
checkpoint=$(printf '%s\n' "$apply_output" | sed -n 's/^checkpoint=//p')
[ -d "$checkpoint" ]
grep -Fqx "$MAP_ROOT/target/lib64/already.so" "$checkpoint/sus_maps.txt"

# Applying the same report again is idempotent.
second_output=$(coverage_apply_ids 1)
printf '%s\n' "$second_output" | grep -Fqx 'result=no-changes'
[ "$(grep -Fxc "$MAP_ROOT/target/lib64/exact-candidate.so" "$PERSISTENT_DIR/sus_maps.txt")" -eq 1 ]

# A tampered report cannot turn the assistant into an arbitrary-file hider.
cat > "$report" <<EOF
schema=1
package=com.example.detector
candidate.1.kind=sus_map
candidate.1.path=/etc/passwd
candidate.1.reason=mapped_module_file
EOF
if coverage_apply_ids 1 >/dev/null 2>&1; then
	echo 'out-of-scope map accepted' >&2
	exit 1
fi

echo 'coverage assistant tests passed'
