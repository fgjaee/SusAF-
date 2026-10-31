#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
PERSISTENT_DIR="$TEST_ROOT/SusAF"
mkdir -p "$PERSISTENT_DIR" "$TEST_ROOT/bin"

cat > "$TEST_ROOT/bin/ksu_susfs" <<'EOF'
#!/bin/sh
case "$1" in
	show)
		case "$2" in
			version) echo v2.3.0 ;;
			variant) echo ReSukiSU ;;
			enabled_features) echo 'CONFIG_KSU_SUSFS_SUS_PATH CONFIG_KSU_SUSFS_SUS_KSTAT CONFIG_KSU_SUSFS_ENABLE_LOG' ;;
			*) exit 2 ;;
		esac
		;;
	--help)
		echo 'add_sus_path add_sus_path_loop add_sus_kstat add_sus_kstat_statically update_sus_kstat add_open_redirect set_cmdline_or_bootconfig hide_sus_mnts_for_non_su_procs enable_log enable_avc_log_spoofing'
		;;
	*)
		printf '%s\n' "$*" >> "$SUSAF_FAKE_SUSFS_LOG"
		if [ -n "${SUSAF_FAKE_FAIL_ARG:-}" ] && [ "${2:-}" = "$SUSAF_FAKE_FAIL_ARG" ]; then
			exit 9
		fi
		exit 0
		;;
esac
EOF
chmod 755 "$TEST_ROOT/bin/ksu_susfs"
: > "$TEST_ROOT/susfs.log"

printf '# optional; no entries\n' > "$PERSISTENT_DIR/open_redirect.txt"
open_output=$(SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-open-redirect)
printf '%s\n' "$open_output" | grep -Fqx '[*] Open Redirect has no configured entries'
printf '%s\n' "$open_output" | grep -Fqx '[*] this optional feature is off; nothing applied'
[ ! -s "$TEST_ROOT/susfs.log" ]

printf '# generated automatically\n' > "$PERSISTENT_DIR/cmdline_or_bootconfig.txt"
boot_output=$(SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-cmdline-bootconfig)
printf '%s\n' "$boot_output" | grep -Fqx '[*] no custom cmdline/bootconfig entries configured'
[ ! -s "$TEST_ROOT/susfs.log" ]

printf '/definitely/missing default default default default default default default default default default default default\n' > "$PERSISTENT_DIR/kstat_paths.txt"
kstat_output=$(SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-kstat-add)
printf '%s\n' "$kstat_output" | grep -Fqx '[!] skip missing path: /definitely/missing'
[ ! -s "$TEST_ROOT/susfs.log" ]

printf '%s default default default default default default default default default default default default\n' "$TEST_ROOT" > "$TEST_ROOT/kstat.generated.txt"
SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-kstat-add-direct "$TEST_ROOT/kstat.generated.txt" >/dev/null
grep -Fqx "add_sus_kstat_statically $TEST_ROOT default default default default default default default default default default default default" "$TEST_ROOT/susfs.log"

: > "$TEST_ROOT/susfs.log"
printf '%s\n' "$TEST_ROOT" > "$PERSISTENT_DIR/kstat_paths.txt"
SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-kstat-add >/dev/null
grep -Fqx "add_sus_kstat $TEST_ROOT" "$TEST_ROOT/susfs.log"

: > "$TEST_ROOT/susfs.log"
cat > "$PERSISTENT_DIR/config.txt" <<'EOF'
HIDE_SUS_MNTS_NON_SU=1
HIDE_SUS_MNTS_LATE=0
ENABLE_LOG=0
ENABLE_AVC_LOG_SPOOFING=1
EOF
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-toggles early >/dev/null
grep -Fqx 'hide_sus_mnts_for_non_su_procs 1' "$TEST_ROOT/susfs.log"

: > "$TEST_ROOT/susfs.log"
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-toggles late >/dev/null
grep -Fqx 'hide_sus_mnts_for_non_su_procs 0' "$TEST_ROOT/susfs.log"
! grep -Fq 'enable_log' "$TEST_ROOT/susfs.log"

: > "$TEST_ROOT/susfs.log"
sed -i '/^HIDE_SUS_MNTS_LATE=/d' "$PERSISTENT_DIR/config.txt"
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-toggles current >/dev/null
grep -Fqx 'hide_sus_mnts_for_non_su_procs 1' "$TEST_ROOT/susfs.log"
grep -Fqx 'enable_log 0' "$TEST_ROOT/susfs.log"
grep -Fqx 'enable_avc_log_spoofing 1' "$TEST_ROOT/susfs.log"

: > "$TEST_ROOT/susfs.log"
mkdir -p "$TEST_ROOT/path-ok-1" "$TEST_ROOT/path-fail" "$TEST_ROOT/path-ok-2"
printf '%s\n%s\n%s\n' \
	"$TEST_ROOT/path-ok-1" "$TEST_ROOT/path-fail" "$TEST_ROOT/path-ok-2" \
	> "$PERSISTENT_DIR/sus_paths.txt"
set +e
SUSAF_MODULE_DIR="$MODULE_DIR" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
SUSAF_FAKE_FAIL_ARG="$TEST_ROOT/path-fail" \
NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-sus-paths >"$TEST_ROOT/apply-paths.out" 2>&1
apply_status=$?
set -e
[ "$apply_status" -ne 0 ]
grep -Fqx "add_sus_path $TEST_ROOT/path-ok-1" "$TEST_ROOT/susfs.log"
grep -Fqx "add_sus_path $TEST_ROOT/path-fail" "$TEST_ROOT/susfs.log"
grep -Fqx "add_sus_path $TEST_ROOT/path-ok-2" "$TEST_ROOT/susfs.log"
grep -Fqx "[x] add_sus_path failed for: $TEST_ROOT/path-fail" "$TEST_ROOT/apply-paths.out"

echo "config-action tests passed"
