#!/bin/sh

# Runtime SUSFS adapter.
#
# The kernel is the source of truth.  Do not infer support from the Sus'AF
# module version: ask the installed ksu_susfs helper and enabled kernel
# features, then expose a stable interface to the rest of Sus'AF.

SUSFS_FEATURES_READY=0
SUSFS_HELP_READY=0
SUSFS_VERSION_READY=0
SUSFS_VARIANT_READY=0
SUSFS_FEATURES_CACHE=
SUSFS_HELP_CACHE=
SUSFS_VERSION_CACHE=
SUSFS_VARIANT_CACHE=

susfs_features() {
	if [ "$SUSFS_FEATURES_READY" != "1" ]; then
		SUSFS_FEATURES_CACHE=$("$SUSFS_BIN" show enabled_features 2>/dev/null || true)
		SUSFS_FEATURES_READY=1
	fi
	printf '%s\n' "$SUSFS_FEATURES_CACHE"
}

susfs_help() {
	if [ "$SUSFS_HELP_READY" != "1" ]; then
		SUSFS_HELP_CACHE=$("$SUSFS_BIN" --help 2>/dev/null || true)
		SUSFS_HELP_READY=1
	fi
	printf '%s\n' "$SUSFS_HELP_CACHE"
}

susfs_version_value() {
	if [ "$SUSFS_VERSION_READY" != "1" ]; then
		SUSFS_VERSION_CACHE=$("$SUSFS_BIN" show version 2>/dev/null | head -n1 || true)
		SUSFS_VERSION_READY=1
	fi
	printf '%s\n' "$SUSFS_VERSION_CACHE"
}

susfs_variant_value() {
	if [ "$SUSFS_VARIANT_READY" != "1" ]; then
		SUSFS_VARIANT_CACHE=$("$SUSFS_BIN" show variant 2>/dev/null | head -n1 || true)
		SUSFS_VARIANT_READY=1
	fi
	printf '%s\n' "$SUSFS_VARIANT_CACHE"
}

susfs_has_feature() {
	feature="$1"
	[ -n "$feature" ] || return 1
	susfs_features | tr ',;' '  ' | awk -v wanted="$feature" '{
		for (i = 1; i <= NF; i++) {
			token = $i
			gsub(/^[,;[:space:]]+|[,;[:space:]]+$/, "", token)
			if (token == wanted) found = 1
		}
	} END { exit(found ? 0 : 1) }'
}

susfs_has_command() {
	command_name="$1"
	[ -n "$command_name" ] || return 1

	# Sidex's universal helper exposes only commands supported by the detected
	# kernel in --help.  When that contract is available, it is authoritative.
	help_text=$(susfs_help)
	if [ -n "$help_text" ]; then
		if printf '%s\n' "$help_text" | grep -Eq "(^|[^[:alnum:]_])${command_name}([^[:alnum:]_]|$)"; then
			return 0
		fi

		# The external-root setters existed only in the transitional SUSFS ABI:
		# v1.5.8 through v2.0.x.  They were removed from v2.1.0+, where SUS_PATH
		# no longer needs this userspace initialization.
		case "$command_name" in
			set_sdcard_root_path|set_android_data_root_path)
				version=$(susfs_version_value)
				susfs_has_feature CONFIG_KSU_SUSFS_SUS_PATH &&
					version_ge "$version" "v1.5.8" &&
					! version_ge "$version" "v2.1.0"
				return $?
				;;
			*) return 1 ;;
		esac
	fi

	# Older helpers may not provide useful --help output.  Use the runtime
	# feature list/version when available, but treat totally unknown capability
	# state as pass-through rather than falsely marking a command unsupported.
	features=$(susfs_features)
	version=$(susfs_version_value)
	case "$command_name" in
		add_sus_path)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_SUS_PATH
			;;
		add_sus_map)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_SUS_MAP
			;;
		add_sus_kstat|add_sus_kstat_statically|update_sus_kstat)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_SUS_KSTAT
			;;
		add_open_redirect)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_OPEN_REDIRECT
			;;
		set_uname)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_SPOOF_UNAME
			;;
		set_cmdline_or_bootconfig)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
			;;
		enable_log)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_ENABLE_LOG
			;;
		add_try_umount)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_TRY_UMOUNT
			;;
		add_sus_mount)
			[ -z "$features" ] && [ -z "$version" ] && return 0
			susfs_has_feature CONFIG_KSU_SUSFS_SUS_MOUNT
			;;
		add_sus_path_loop)
			[ -z "$version" ] && return 0
			version_ge "$version" "v1.5.9"
			;;
		hide_sus_mnts_for_non_su_procs)
			[ -z "$version" ] && return 0
			version_ge "$version" "v1.5.7"
			;;
		hide_sus_mnts_for_all_procs)
			[ -z "$version" ] && return 0
			version_ge "$version" "v2.0.0"
			;;
		set_sdcard_root_path|set_android_data_root_path)
			[ -z "$version" ] && return 0
			version_ge "$version" "v1.5.8" && ! version_ge "$version" "v2.1.0"
			;;
		enable_avc_log_spoofing)
			[ -z "$version" ] && return 0
			version_ge "$version" "v1.5.9"
			;;
		*) return 1 ;;
	esac
}

susfs_managed_command() {
	case "$1" in
		add_sus_path|add_sus_path_loop|add_sus_map|add_sus_mount|add_try_umount|\
		add_sus_kstat|add_sus_kstat_statically|update_sus_kstat|add_open_redirect|\
		set_uname|set_cmdline_or_bootconfig|set_sdcard_root_path|set_android_data_root_path|\
		hide_sus_mnts_for_non_su_procs|hide_sus_mnts_for_all_procs|\
		enable_log|enable_avc_log_spoofing)
			return 0
			;;
		*) return 1 ;;
	esac
}

susfs() {
	cmd="$1"
	case "$cmd" in
		show|--help) "$SUSFS_BIN" "$@"; return $? ;;
	esac

	if susfs_managed_command "$cmd" && ! susfs_has_command "$cmd"; then
		echo "[*] skip unsupported SUSFS command: $cmd"
		return 0
	fi

	# Unknown/new commands pass through.  Typos and changed upstream syntax
	# should surface the helper's real error rather than become fake success.
	"$SUSFS_BIN" "$@"
}

susfs_mount_filter_backend() {
	version=$(susfs_version_value)

	if version_ge "$version" "v2.0.0" && susfs_has_command hide_sus_mnts_for_all_procs; then
		printf 'hide_sus_mnts_for_all_procs\n'
		return 0
	fi
	if susfs_has_command hide_sus_mnts_for_non_su_procs; then
		printf 'hide_sus_mnts_for_non_su_procs\n'
		return 0
	fi
	if susfs_has_command hide_sus_mnts_for_all_procs; then
		printf 'hide_sus_mnts_for_all_procs\n'
		return 0
	fi
	printf 'unavailable\n'
}

susfs_set_mount_filter() {
	value="$1"
	backend=$(susfs_mount_filter_backend)
	case "$backend" in
		hide_sus_mnts_for_all_procs|hide_sus_mnts_for_non_su_procs)
			echo "[>] $backend $value"
			susfs "$backend" "$value"
			;;
		*)
			echo "[*] mount filtering is not supported by this SUSFS kernel/helper"
			return 0
			;;
	esac
}

susfs_prepare_path_roots() {
	result=0
	sdcard_root="${SUSAF_SDCARD_ROOT:-/sdcard}"
	android_data_root="${SUSAF_ANDROID_DATA_ROOT:-$sdcard_root/Android/data}"

	if ! susfs_has_command add_sus_path && ! susfs_has_command add_sus_path_loop; then
		return 0
	fi

	if susfs_has_command set_sdcard_root_path; then
		if [ -d "$sdcard_root" ]; then
			echo "[>] set_sdcard_root_path $sdcard_root"
			susfs set_sdcard_root_path "$sdcard_root" || result=1
		else
			echo "[!] $sdcard_root is unavailable; skipped SUS_PATH sdcard root setup"
		fi
	fi

	if susfs_has_command set_android_data_root_path; then
		wait_seconds="${SUSAF_ANDROID_DATA_WAIT_SECONDS:-30}"
		case "$wait_seconds" in
			''|*[!0-9]*) wait_seconds=30 ;;
		esac
		elapsed=0
		while [ ! -d "$android_data_root" ] && [ "$elapsed" -lt "$wait_seconds" ]; do
			sleep 1
			elapsed=$((elapsed + 1))
		done
		if [ -d "$android_data_root" ]; then
			echo "[>] set_android_data_root_path $android_data_root"
			susfs set_android_data_root_path "$android_data_root" || result=1
		else
			echo "[!] $android_data_root unavailable after ${wait_seconds}s; skipped Android data root setup"
		fi
	fi

	return "$result"
}

susfs_add_open_redirect() {
	target="$1"
	redirect="$2"
	scheme="${3:-2}"
	version=$(susfs_version_value)

	case "$scheme" in
		0|1|2|3|4) ;;
		*)
			echo "[x] invalid Open Redirect uid scheme: $scheme"
			return 1
			;;
	esac

	if version_ge "$version" "v2.1.0"; then
		echo "[>] add_open_redirect $target -> $redirect (scheme $scheme)"
		susfs add_open_redirect "$target" "$redirect" "$scheme"
	else
		echo "[>] add_open_redirect $target -> $redirect (legacy two-argument interface)"
		susfs add_open_redirect "$target" "$redirect"
	fi
}

emit_susfs_command_capability() {
	command_name="$1"
	key=$(printf '%s' "$command_name" | tr '[:lower:]' '[:upper:]')
	if susfs_has_command "$command_name"; then
		printf 'CMD_%s=1\n' "$key"
	else
		printf 'CMD_%s=0\n' "$key"
	fi
}

susfs_preferred_umount_backend() {
	version=$(susfs_version_value)
	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=

	# Current upstream SUSFS 2.x deprecates its old try-umount route in favor
	# of KernelSU's official kernel_umount facility.  Prefer the official
	# KernelSU interface whenever both the generation and daemon support it.
	if version_ge "$version" "v2.0.0" && [ -n "$ksu_bin" ]; then
		case "$(kernel_umount_check_feature "$ksu_bin")" in
			supported|managed)
				printf 'kernel_umount\n'
				return 0
				;;
		esac
	fi

	if susfs_has_command add_try_umount; then
		printf 'susfs_try_umount\n'
	else
		printf 'unavailable\n'
	fi
}

emit_registry_entry() {
	id="$1"
	mode="$2"
	available="$3"
	source="$4"
	replacement="$5"
	printf 'REGISTRY=%s|%s|%s|%s|%s\n' "$id" "$mode" "$available" "$source" "$replacement"
}

emit_registry_command() {
	id="$1"
	command_name="$2"
	if susfs_has_command "$command_name"; then
		available=1
	else
		available=0
	fi
	emit_registry_entry "$id" control "$available" "command:$command_name" none
}

emit_registry_feature() {
	id="$1"
	feature="$2"
	if susfs_has_feature "$feature"; then
		available=1
	else
		available=0
	fi
	emit_registry_entry "$id" status "$available" "feature:$feature" none
}

susfs_feature_is_mapped() {
	case "$1" in
		CONFIG_KSU_SUSFS|\
		CONFIG_KSU_SUSFS_SUS_PATH|\
		CONFIG_KSU_SUSFS_SUS_MAP|\
		CONFIG_KSU_SUSFS_SUS_MOUNT|\
		CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT|\
		CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT|\
		CONFIG_KSU_SUSFS_SUS_KSTAT|\
		CONFIG_KSU_SUSFS_TRY_UMOUNT|\
		CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT|\
		CONFIG_KSU_SUSFS_SPOOF_UNAME|\
		CONFIG_KSU_SUSFS_ENABLE_LOG|\
		CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS|\
		CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG|\
		CONFIG_KSU_SUSFS_OPEN_REDIRECT|\
		CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT|\
		CONFIG_KSU_SUSFS_SUS_OVERLAYFS|\
		CONFIG_KSU_SUSFS_SUS_SU)
			return 0
			;;
		*) return 1 ;;
	esac
}

emit_feature_registry() {
	version=$(susfs_version_value)
	umount_backend=$(susfs_preferred_umount_backend)

	emit_registry_command sus_path add_sus_path
	emit_registry_command sus_path_loop add_sus_path_loop
	emit_registry_command sus_map add_sus_map
	emit_registry_command sus_kstat add_sus_kstat
	emit_registry_command open_redirect add_open_redirect
	emit_registry_command uname set_uname
	emit_registry_command cmdline_bootconfig set_cmdline_or_bootconfig
	mount_filter_backend=$(susfs_mount_filter_backend)
	[ "$mount_filter_backend" = unavailable ] && mount_filter_available=0 || mount_filter_available=1
	emit_registry_entry mount_filter control "$mount_filter_available" "adapter:$mount_filter_backend" none
	emit_registry_command sdcard_root set_sdcard_root_path
	emit_registry_command android_data_root set_android_data_root_path
	emit_registry_command kernel_log enable_log
	emit_registry_command avc_log_spoofing enable_avc_log_spoofing

	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=
	kernel_umount_available=0
	if [ -n "$ksu_bin" ]; then
		case "$(kernel_umount_check_feature "$ksu_bin")" in
			supported|managed) kernel_umount_available=1 ;;
		esac
	fi
	emit_registry_entry kernel_umount control "$kernel_umount_available" "kernelsu:kernel_umount" none

	if version_ge "$version" "v2.0.0"; then
		sus_mount_available=0
		susfs_has_command add_sus_mount && sus_mount_available=1
		emit_registry_entry sus_mount legacy "$sus_mount_available" "command:add_sus_mount" kernel_managed_mounts

		try_umount_available=0
		susfs_has_command add_try_umount && try_umount_available=1
		if [ "$umount_backend" = "kernel_umount" ]; then
			emit_registry_entry try_umount legacy "$try_umount_available" "command:add_try_umount" kernel_umount
		else
			emit_registry_entry try_umount control "$try_umount_available" "command:add_try_umount" none
		fi

		sus_su_available=0
		susfs_has_feature CONFIG_KSU_SUSFS_SUS_SU && sus_su_available=1
		emit_registry_entry sus_su legacy "$sus_su_available" "feature:CONFIG_KSU_SUSFS_SUS_SU" removed_in_susfs_v2
	else
		emit_registry_command sus_mount add_sus_mount
		emit_registry_command try_umount add_try_umount
		emit_registry_feature sus_su CONFIG_KSU_SUSFS_SUS_SU
	fi

	emit_registry_feature auto_default_mount CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT
	emit_registry_feature auto_bind_mount CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT
	emit_registry_feature auto_try_umount_bind CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT
	emit_registry_feature hide_symbols CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
	emit_registry_feature magic_mount CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT
	emit_registry_feature overlayfs CONFIG_KSU_SUSFS_SUS_OVERLAYFS

	susfs_features | tr ',;' '  ' | awk '{
		for (i = 1; i <= NF; i++) {
			token = $i
			gsub(/^[,;[:space:]]+|[,;[:space:]]+$/, "", token)
			if (token ~ /^CONFIG_KSU_SUSFS_[A-Z0-9_]+$/ && !seen[token]++) print token
		}
	}' | while IFS= read -r feature; do
		[ -n "$feature" ] || continue
		if ! susfs_feature_is_mapped "$feature"; then
			printf 'UNMAPPED_FEATURE=%s\n' "$feature"
		fi
	done
}

show_capabilities() {
	if [ ! -x "$SUSFS_BIN" ]; then
		printf 'SUSFS_AVAILABLE=0\n'
		printf 'SUSFS_BINARY=%s\n' "$SUSFS_BIN"
		printf 'SUSFS_SOURCE=%s\n' "${SUSFS_BIN_SOURCE:-unknown}"
		printf 'UMOUNT_BACKEND=unavailable\n'
		return 0
	fi

	version=$(susfs_version_value)
	variant=$(susfs_variant_value)
	features=$(susfs_features)

	[ -n "$version" ] && available=1 || available=0
	printf 'SUSFS_AVAILABLE=%s\n' "$available"
	printf 'SUSFS_BINARY=%s\n' "$SUSFS_BIN"
	printf 'SUSFS_SOURCE=%s\n' "${SUSFS_BIN_SOURCE:-unknown}"
	printf 'SUSFS_VERSION=%s\n' "$version"
	printf 'SUSFS_VARIANT=%s\n' "$variant"

	printf '%s\n' "$features" | tr ',;' '  ' | awk '{
		for (i = 1; i <= NF; i++) {
			token = $i
			gsub(/^[,;[:space:]]+|[,;[:space:]]+$/, "", token)
			if (token ~ /^CONFIG_KSU_SUSFS_[A-Z0-9_]+$/ && !seen[token]++) print token
		}
	}' | sort -u | while IFS= read -r feature; do
		[ -n "$feature" ] && printf 'FEATURE=%s\n' "$feature"
	done

	for command_name in \
		add_sus_path add_sus_path_loop add_sus_map add_sus_mount add_try_umount \
		add_sus_kstat add_sus_kstat_statically update_sus_kstat add_open_redirect \
		set_uname set_cmdline_or_bootconfig set_sdcard_root_path set_android_data_root_path \
		hide_sus_mnts_for_non_su_procs hide_sus_mnts_for_all_procs \
		enable_log enable_avc_log_spoofing
	do
		emit_susfs_command_capability "$command_name"
	done

	kernel_umount=0
	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=
	if [ -n "$ksu_bin" ]; then
		case "$(kernel_umount_check_feature "$ksu_bin")" in
			supported|managed) kernel_umount=1 ;;
		esac
	fi
	printf 'KERNEL_UMOUNT=%s\n' "$kernel_umount"
	printf 'UMOUNT_BACKEND=%s\n' "$(susfs_preferred_umount_backend)"
	printf 'MOUNT_FILTER_BACKEND=%s\n' "$(susfs_mount_filter_backend)"
	emit_feature_registry
}
