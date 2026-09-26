#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
SUSFS_BIN="$TEST_ROOT/ksu_susfs"
SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log"
export SUSFS_BIN SUSAF_FAKE_SUSFS_LOG

cat > "$SUSFS_BIN" <<'EOF'
#!/bin/sh
case "$1" in
	show)
		case "$2" in
			version) printf '%s\n' "${SUSAF_FAKE_VERSION:-}" ;;
			variant) printf '%s\n' "${SUSAF_FAKE_VARIANT:-}" ;;
			enabled_features) printf '%s\n' "${SUSAF_FAKE_FEATURES:-}" ;;
			*) exit 2 ;;
		esac
		;;
	--help)
		printf '%s\n' "${SUSAF_FAKE_HELP:-}"
		;;
	*)
		printf '%s\n' "$*" >> "$SUSAF_FAKE_SUSFS_LOG"
		exit "${SUSAF_FAKE_COMMAND_STATUS:-0}"
		;;
esac
EOF
chmod 755 "$SUSFS_BIN"

cat > "$TEST_ROOT/ksud" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$TEST_ROOT/ksud"

version_ge() {
	ver1="${1#v}"
	ver2="${2#v}"
	major1=$(echo "$ver1" | cut -d. -f1); major1=${major1:-0}
	minor1=$(echo "$ver1" | cut -d. -f2); minor1=${minor1:-0}
	patch1=$(echo "$ver1" | cut -d. -f3); patch1=${patch1:-0}
	major2=$(echo "$ver2" | cut -d. -f1); major2=${major2:-0}
	minor2=$(echo "$ver2" | cut -d. -f2); minor2=${minor2:-0}
	patch2=$(echo "$ver2" | cut -d. -f3); patch2=${patch2:-0}
	[ "$major1" -gt "$major2" ] && return 0
	[ "$major1" -lt "$major2" ] && return 1
	[ "$minor1" -gt "$minor2" ] && return 0
	[ "$minor1" -lt "$minor2" ] && return 1
	[ "$patch1" -ge "$patch2" ]
}

resolve_ksud_bin() {
	printf '%s\n' "$TEST_ROOT/ksud"
}

kernel_umount_check_feature() {
	printf '%s\n' "${SUSAF_FAKE_KSU_CHECK:-unsupported}"
}

. "$MODULE_DIR/lib/susfs-capabilities.sh"

reset_capability_cache() {
	SUSFS_FEATURES_READY=0
	SUSFS_HELP_READY=0
	SUSFS_VERSION_READY=0
	SUSFS_VARIANT_READY=0
	SUSFS_FEATURES_CACHE=
	SUSFS_HELP_CACHE=
	SUSFS_VERSION_CACHE=
	SUSFS_VARIANT_CACHE=
}

# Modern SUSFS: feature list deliberately uses commas/semicolons to verify the
# parser is not coupled to one helper output format.
# The help output intentionally omits the legacy SUS_PATH root setters, matching
# the v2.3 helper observed on-device. They must remain unavailable on v2.1+.
SUSAF_FAKE_VERSION=v2.3.0
SUSAF_FAKE_VARIANT=ReSukiSU
SUSAF_FAKE_KSU_CHECK=supported
SUSAF_FAKE_FEATURES='CONFIG_KSU_SUSFS_SUS_PATH,CONFIG_KSU_SUSFS_SUS_MAP;CONFIG_KSU_SUSFS_SUS_KSTAT CONFIG_KSU_SUSFS_OPEN_REDIRECT CONFIG_KSU_SUSFS_SPOOF_UNAME CONFIG_KSU_SUSFS_ENABLE_LOG CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT CONFIG_KSU_SUSFS_SUS_OVERLAYFS CONFIG_KSU_SUSFS_FUTURE_TEST'
SUSAF_FAKE_HELP='add_sus_path add_sus_path_loop add_sus_map add_sus_kstat add_sus_kstat_statically update_sus_kstat add_open_redirect set_uname set_cmdline_or_bootconfig hide_sus_mnts_for_all_procs hide_sus_mnts_for_non_su_procs enable_log enable_avc_log_spoofing'
export SUSAF_FAKE_VERSION SUSAF_FAKE_VARIANT SUSAF_FAKE_KSU_CHECK SUSAF_FAKE_FEATURES SUSAF_FAKE_HELP
reset_capability_cache

show_capabilities > "$TEST_ROOT/v2.out"

grep -Fqx 'SUSFS_AVAILABLE=1' "$TEST_ROOT/v2.out"
grep -Fqx 'SUSFS_VERSION=v2.3.0' "$TEST_ROOT/v2.out"
grep -Fqx 'SUSFS_VARIANT=ReSukiSU' "$TEST_ROOT/v2.out"
grep -Fqx 'UMOUNT_BACKEND=kernel_umount' "$TEST_ROOT/v2.out"
grep -Fqx 'CMD_ADD_SUS_PATH=1' "$TEST_ROOT/v2.out"
grep -Fqx 'CMD_ADD_TRY_UMOUNT=0' "$TEST_ROOT/v2.out"
grep -Fqx 'KERNEL_UMOUNT=1' "$TEST_ROOT/v2.out"
grep -Fqx 'MOUNT_FILTER_BACKEND=hide_sus_mnts_for_non_su_procs' "$TEST_ROOT/v2.out"
grep -Fqx 'CMD_SET_SDCARD_ROOT_PATH=0' "$TEST_ROOT/v2.out"
grep -Fqx 'CMD_SET_ANDROID_DATA_ROOT_PATH=0' "$TEST_ROOT/v2.out"
grep -Fqx 'REGISTRY=kernel_umount|control|1|kernelsu:kernel_umount|none' "$TEST_ROOT/v2.out"
grep -Fqx 'REGISTRY=try_umount|legacy|0|command:add_try_umount|kernel_umount' "$TEST_ROOT/v2.out"
grep -Fqx 'REGISTRY=sus_mount|legacy|0|command:add_sus_mount|kernel_managed_mounts' "$TEST_ROOT/v2.out"
grep -Fqx 'REGISTRY=auto_bind_mount|status|1|feature:CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT|none' "$TEST_ROOT/v2.out"
grep -Fqx 'UNMAPPED_FEATURE=CONFIG_KSU_SUSFS_FUTURE_TEST' "$TEST_ROOT/v2.out"

mkdir -p "$TEST_ROOT/sdcard/Android/data"
SUSAF_SDCARD_ROOT="$TEST_ROOT/sdcard"
SUSAF_ANDROID_DATA_ROOT="$TEST_ROOT/sdcard/Android/data"
SUSAF_ANDROID_DATA_WAIT_SECONDS=0
export SUSAF_SDCARD_ROOT SUSAF_ANDROID_DATA_ROOT SUSAF_ANDROID_DATA_WAIT_SECONDS
: > "$SUSAF_FAKE_SUSFS_LOG"
susfs_prepare_path_roots >/dev/null
[ ! -s "$SUSAF_FAKE_SUSFS_LOG" ]

: > "$SUSAF_FAKE_SUSFS_LOG"
susfs_set_mount_filter 1 >/dev/null
grep -Fqx 'hide_sus_mnts_for_non_su_procs 1' "$SUSAF_FAKE_SUSFS_LOG"

: > "$SUSAF_FAKE_SUSFS_LOG"
susfs_add_open_redirect /original /redirected 4 >/dev/null
grep -Fqx 'add_open_redirect /original /redirected 4' "$SUSAF_FAKE_SUSFS_LOG"

# Transitional SUSFS v2.0 still requires the two SUS_PATH root setters.
SUSAF_FAKE_VERSION=v2.0.0
SUSAF_FAKE_VARIANT=GKI
SUSAF_FAKE_KSU_CHECK=unsupported
SUSAF_FAKE_FEATURES='CONFIG_KSU_SUSFS_SUS_PATH'
SUSAF_FAKE_HELP='add_sus_path add_sus_path_loop hide_sus_mnts_for_non_su_procs'
export SUSAF_FAKE_VERSION SUSAF_FAKE_VARIANT SUSAF_FAKE_KSU_CHECK SUSAF_FAKE_FEATURES SUSAF_FAKE_HELP
reset_capability_cache

show_capabilities > "$TEST_ROOT/v20.out"
grep -Fqx 'CMD_SET_SDCARD_ROOT_PATH=1' "$TEST_ROOT/v20.out"
grep -Fqx 'CMD_SET_ANDROID_DATA_ROOT_PATH=1' "$TEST_ROOT/v20.out"
grep -Fqx 'MOUNT_FILTER_BACKEND=hide_sus_mnts_for_non_su_procs' "$TEST_ROOT/v20.out"

: > "$SUSAF_FAKE_SUSFS_LOG"
susfs_prepare_path_roots >/dev/null
grep -Fqx "set_sdcard_root_path $TEST_ROOT/sdcard" "$SUSAF_FAKE_SUSFS_LOG"
grep -Fqx "set_android_data_root_path $TEST_ROOT/sdcard/Android/data" "$SUSAF_FAKE_SUSFS_LOG"

# Older generation: custom try_umount and sus_mount remain controllable when
# the helper/kernel expose them and KernelSU's official backend is unavailable.
SUSAF_FAKE_VERSION=v1.5.12
SUSAF_FAKE_VARIANT=KernelSU
SUSAF_FAKE_KSU_CHECK=unsupported
SUSAF_FAKE_FEATURES='CONFIG_KSU_SUSFS_SUS_PATH CONFIG_KSU_SUSFS_SUS_MOUNT CONFIG_KSU_SUSFS_TRY_UMOUNT CONFIG_KSU_SUSFS_SUS_SU CONFIG_KSU_SUSFS_OPEN_REDIRECT'
SUSAF_FAKE_HELP='add_sus_path add_sus_path_loop add_sus_mount add_try_umount add_open_redirect hide_sus_mnts_for_all_procs enable_avc_log_spoofing'
export SUSAF_FAKE_VERSION SUSAF_FAKE_VARIANT SUSAF_FAKE_KSU_CHECK SUSAF_FAKE_FEATURES SUSAF_FAKE_HELP
reset_capability_cache

show_capabilities > "$TEST_ROOT/v1.out"
grep -Fqx 'UMOUNT_BACKEND=susfs_try_umount' "$TEST_ROOT/v1.out"
grep -Fqx 'KERNEL_UMOUNT=0' "$TEST_ROOT/v1.out"
grep -Fqx 'MOUNT_FILTER_BACKEND=hide_sus_mnts_for_all_procs' "$TEST_ROOT/v1.out"
grep -Fqx 'REGISTRY=sus_mount|control|1|command:add_sus_mount|none' "$TEST_ROOT/v1.out"
grep -Fqx 'REGISTRY=try_umount|control|1|command:add_try_umount|none' "$TEST_ROOT/v1.out"
grep -Fqx 'REGISTRY=sus_su|status|1|feature:CONFIG_KSU_SUSFS_SUS_SU|none' "$TEST_ROOT/v1.out"

: > "$SUSAF_FAKE_SUSFS_LOG"
susfs_set_mount_filter 1 >/dev/null
grep -Fqx 'hide_sus_mnts_for_all_procs 1' "$SUSAF_FAKE_SUSFS_LOG"

: > "$SUSAF_FAKE_SUSFS_LOG"
susfs_add_open_redirect /original /redirected 4 >/dev/null
grep -Fqx 'add_open_redirect /original /redirected' "$SUSAF_FAKE_SUSFS_LOG"
! grep -Fq 'add_open_redirect /original /redirected 4' "$SUSAF_FAKE_SUSFS_LOG"

# Unknown/new commands are passed through so helper errors stay visible.
: > "$SUSAF_FAKE_SUSFS_LOG"
SUSAF_FAKE_COMMAND_STATUS=7
export SUSAF_FAKE_COMMAND_STATUS
set +e
susfs future_command test-arg
status=$?
set -e
[ "$status" -eq 7 ]
grep -Fqx 'future_command test-arg' "$SUSAF_FAKE_SUSFS_LOG"

printf 'test-susfs-capabilities: ok\n'
