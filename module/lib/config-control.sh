#!/bin/sh

# Centralized persistent configuration writes for Sus'AF.
# WebUI and shell callers use the same validation and atomic replacement path.

susaf_config_validate() {
	key="$1"
	value="$2"

	case "$key" in
		HIDE_SUS_MNTS_NON_SU|HIDE_SUS_MNTS_LATE|ENABLE_LOG|ENABLE_AVC_LOG_SPOOFING|\
		AUTO_KERNEL_UMOUNT|ALLOW_BROAD_KERNEL_UMOUNT|AUTOPILOT_SCAN_ON_BOOT|AUTOPILOT_APPLY_SAFE)
			case "$value" in 0|1) return 0 ;; *) return 1 ;; esac
			;;
		KERNEL_UMOUNT_MODE|SELINUX_HIDE_MODE)
			case "$value" in unchanged|enabled|disabled) return 0 ;; *) return 1 ;; esac
			;;
		ADB_MODE)
			case "$value" in unchanged|spoof-off|actually-disable) return 0 ;; *) return 1 ;; esac
			;;
		*)
			return 1
			;;
	esac
}

susaf_config_show() {
	file="${1:-$PERSISTENT_DIR/config.txt}"
	[ -f "$file" ] || return 0

	for key in \
		HIDE_SUS_MNTS_NON_SU HIDE_SUS_MNTS_LATE ENABLE_LOG ENABLE_AVC_LOG_SPOOFING \
		KERNEL_UMOUNT_MODE AUTO_KERNEL_UMOUNT ALLOW_BROAD_KERNEL_UMOUNT \
		ADB_MODE AUTOPILOT_SCAN_ON_BOOT AUTOPILOT_APPLY_SAFE SELINUX_HIDE_MODE
	do
		value=$(grep "^$key=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2-) || value=
		if [ -n "$value" ]; then
			printf '%s=%s\n' "$key" "$value"
		fi
	done
	return 0
}

susaf_config_set() {
	file="$1"
	shift

	[ "$#" -gt 0 ] || {
		echo "[x] no config values supplied"
		return 1
	}

	# Validate the complete batch before touching the persistent file.
	for pair in "$@"; do
		case "$pair" in
			*=*) ;;
			*)
				echo "[x] invalid config assignment: $pair"
				return 1
				;;
		esac
		key=${pair%%=*}
		value=${pair#*=}
		if ! susaf_config_validate "$key" "$value"; then
			echo "[x] rejected config value: $key=$value"
			return 1
		fi
	done

	mkdir -p "$(dirname "$file")" || return 1
	umask 077
	tmp="${file}.susaf.$$"
	trap 'rm -f "$tmp"' EXIT HUP INT TERM

	if [ -f "$file" ]; then
		cp "$file" "$tmp" || return 1
	else
		: > "$tmp"
	fi

	for pair in "$@"; do
		key=${pair%%=*}
		value=${pair#*=}
		if grep -q "^$key=" "$tmp" 2>/dev/null; then
			next="${tmp}.next"
			awk -F= -v wanted="$key" -v replacement="$value" '
				BEGIN { replaced=0 }
				$1 == wanted && !replaced {
					print wanted "=" replacement
					replaced=1
					next
				}
				$1 == wanted { next }
				{ print }
			' "$tmp" > "$next" || return 1
			mv "$next" "$tmp" || return 1
		else
			printf '%s=%s\n' "$key" "$value" >> "$tmp" || return 1
		fi
	done

	chmod 600 "$tmp" || return 1
	mv "$tmp" "$file" || return 1
	trap - EXIT HUP INT TERM

	for pair in "$@"; do
		printf '[+] config saved: %s\n' "$pair"
	done
}
