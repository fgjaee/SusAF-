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
	susfs_features | awk -v wanted="$feature" '{
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

	# Sidex's universal helper intentionally exposes only commands supported by
	# the detected kernel in --help.  Prefer that live contract when present.
	help_text=$(susfs_help)
	if [ -n "$help_text" ] && printf '%s\n' "$help_text" | grep -Eq "(^|[^[:alnum:]_])${command_name}([^[:alnum:]_]|$)"; then
		return 0
	fi

	# Feature/version fallbacks keep Sus'AF usable with older helpers whose
	# --help output is incomplete.
	case "$command_name" in
		add_sus_path) susfs_has_feature CONFIG_KSU_SUSFS_SUS_PATH ;;
		add_sus_map) susfs_has_feature CONFIG_KSU_SUSFS_SUS_MAP ;;
		add_sus_kstat|add_sus_kstat_statically|update_sus_kstat) susfs_has_feature CONFIG_KSU_SUSFS_SUS_KSTAT ;;
		add_open_redirect) susfs_has_feature CONFIG_KSU_SUSFS_OPEN_REDIRECT ;;
		set_uname) susfs_has_feature CONFIG_KSU_SUSFS_SPOOF_UNAME ;;
		set_cmdline_or_bootconfig) susfs_has_feature CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG ;;
		enable_log) susfs_has_feature CONFIG_KSU_SUSFS_ENABLE_LOG ;;
		add_try_umount) susfs_has_feature CONFIG_KSU_SUSFS_TRY_UMOUNT ;;
		add_sus_mount) susfs_has_feature CONFIG_KSU_SUSFS_SUS_MOUNT ;;
		add_sus_path_loop) version_ge "$(susfs_version_value)" "v1.5.9" ;;
		hide_sus_mnts_for_non_su_procs) version_ge "$(susfs_version_value)" "v1.5.7" ;;
		enable_avc_log_spoofing) version_ge "$(susfs_version_value)" "v1.5.9" ;;
		*) return 1 ;;
	esac
}

susfs_managed_command() {
	case "$1" in
		add_sus_path|add_sus_path_loop|add_sus_map|add_sus_mount|add_try_umount|\
		add_sus_kstat|add_sus_kstat_statically|update_sus_kstat|add_open_redirect|\
		set_uname|set_cmdline_or_bootconfig|hide_sus_mnts_for_non_su_procs|\
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

show_capabilities() {
	if [ ! -x "$SUSFS_BIN" ]; then
		printf 'SUSFS_AVAILABLE=0\n'
		printf 'SUSFS_BINARY=%s\n' "$SUSFS_BIN"
		printf 'UMOUNT_BACKEND=unavailable\n'
		return 0
	fi

	version=$(susfs_version_value)
	variant=$(susfs_variant_value)
	features=$(susfs_features)

	[ -n "$version" ] && available=1 || available=0
	printf 'SUSFS_AVAILABLE=%s\n' "$available"
	printf 'SUSFS_BINARY=%s\n' "$SUSFS_BIN"
	printf 'SUSFS_VERSION=%s\n' "$version"
	printf 'SUSFS_VARIANT=%s\n' "$variant"

	printf '%s\n' "$features" | awk '{
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
		set_uname set_cmdline_or_bootconfig hide_sus_mnts_for_non_su_procs \
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
}
