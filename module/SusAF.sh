#!/bin/sh
PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"
MODDIR="$MODULE_DIR"
USER_SCRIPTS_DIR="$PERSISTENT_DIR/scripts"
POSTFS_SCRIPTS_FILE="$PERSISTENT_DIR/scripts_postfs.txt"
BOOTCOMPLETED_SCRIPTS_FILE="$PERSISTENT_DIR/scripts_bootcompleted.txt"
SUSFS_BIN="${SUSAF_SUSFS_BIN:-$DEST_BIN_DIR/ksu_susfs}"
[ -n "${SUSAF_SUSFS_BIN:-}" ] || [ -x "$SUSFS_BIN" ] || \
	[ ! -x "$SUSFS_BUNDLED_BIN" ] || SUSFS_BIN="$SUSFS_BUNDLED_BIN"
SUSFS_MIN_VERSION="v2.2.0"

. "$MODDIR/utils.sh"
. "$MODDIR/lib/kernel-umount.sh"
. "$MODDIR/lib/diagnostics.sh"
. "$MODDIR/lib/backup-restore.sh"
. "$MODDIR/lib/coverage.sh"

versionCode=$(grep versionCode $MODDIR/module.prop | sed 's/versionCode=//g' )

[ -n "$WEBUI_QUIET" ] && [ "${NO_BANNER:-0}" = "0" ] && banner

susfs() { "$SUSFS_BIN" "$@"; }

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

[ ! -d "$PERSISTENT_DIR" ] && mkdir -p "$PERSISTENT_DIR"

get_conf() {
	file="${3:-$PERSISTENT_DIR/config.txt}"
	val=$(grep "^$1=" "$file" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
	[ -z "$val" ] && val="$2"
	echo "$val"
}

read_list() {
	[ -f "$1" ] || return
	sed 's/#.*//' "$1" | grep -v '^[[:space:]]*$'
}

[ ! -d "$USER_SCRIPTS_DIR" ] && mkdir -p "$USER_SCRIPTS_DIR"
[ ! -f "$POSTFS_SCRIPTS_FILE" ] && : > "$POSTFS_SCRIPTS_FILE"
[ ! -f "$BOOTCOMPLETED_SCRIPTS_FILE" ] && : > "$BOOTCOMPLETED_SCRIPTS_FILE"

CRON_SCRIPTS_FILE="$PERSISTENT_DIR/scripts_cron.txt"
[ ! -f "$CRON_SCRIPTS_FILE" ] && : > "$CRON_SCRIPTS_FILE"
CROND_DIR="$PERSISTENT_DIR/crontabs"

run_stage_scripts() {
	stage_file="$1"
	[ -f "$stage_file" ] || return
	list=$(read_list "$stage_file") || return
	[ -z "$list" ] && return
	echo "$list" | while IFS= read -r name; do
		case "$name" in
			"!"*) continue ;;
		esac
		script="$USER_SCRIPTS_DIR/$name"
		if [ -f "$script" ]; then
			echo "[>] running $script"
			sh "$script"
		else
			echo "[!] script not found, skipping: $name"
		fi
	done
}

sync_cron_scripts() {
	[ ! -d "$CROND_DIR" ] && mkdir -p "$CROND_DIR"

	pkill -f "busybox crond -bc $CROND_DIR" 2>/dev/null
	sleep 1

	busybox crond -bc "$CROND_DIR" -L /dev/null

	tmp="${CROND_DIR}/root.tmp.$$"
	: > "$tmp"

	list=$(read_list "$CRON_SCRIPTS_FILE") || { rm -f "$tmp"; return; }
	echo "$list" | while IFS= read -r line; do
		schedule=$(echo "$line" | cut -d' ' -f1-5)
		name=$(echo "$line" | cut -d' ' -f6-)
		[ -z "$name" ] && continue
		[ -f "$USER_SCRIPTS_DIR/$name" ] || { echo "[!] cron script not found, skipping: $name"; continue; }
		echo "$schedule sh $MODULE_DIR/SusAF.sh --run-script $USER_SCRIPTS_DIR/$name >> $PERSISTENT_DIR/cron.log 2>&1" >> "$tmp"
	done

	busybox crontab -c "$CROND_DIR" "$tmp" 2>/dev/null
	rm -f "$tmp"

	echo "[+] cron schedule synced"
}

run_script() {
	script="$1"
	[ -z "$script" ] && { echo "[x] no script specified"; echo "[!] syntax: --run-script <path>"; exit 1; }
	case "$script" in
		*.sh) : ;;
		*) echo "[x] only .sh files allowed: $script"; exit 1 ;;
	esac
	[ -f "$script" ] || { echo "[x] script not found: $script"; exit 1; }
	[ -r "$script" ] || { echo "[x] script not readable: $script"; exit 1; }
	echo "[>] running $script"
	sh "$script"
	echo "[+] exit code: $?"
}

apply_list() {
	default="$1"; cmd="$2"; mode="$3"; file="${4:-$default}"

	if [ -f "$file" ]; then
		tmp="${file}.tmp.$$"
		busybox awk '
			/^[[:space:]]*#/ { print; next }
			/^[[:space:]]*$/ { next }
			!seen[$0]++
		' "$file" > "$tmp" && cat "$tmp" > "$file"
		rm -f "$tmp"
	fi

	list=$(read_list "$file" 2>/dev/null) || list=
	[ -z "$list" ] && return
	echo "$list" | while IFS= read -r p; do
		if [ "$mode" = "1" ] && [ ! -e "$p" ]; then echo "[!] skip missing path: $p"; continue; fi
		if [ "$mode" = "2" ] && [ ! -e "$p" ]; then continue; fi
		echo "[>] $cmd $p"
		susfs "$cmd" "$p"
	done
}

append_to_default() {
	default="$1"
	src="${2:-$default}"
	[ "$src" = "$default" ] && return 0
	case "$src" in
		*.txt) : ;;
		*) echo "[x] only .txt files allowed: $src"; return 1 ;;
	esac
	[ -f "$src" ] || { echo "[x] file not found: $src"; return 1; }
	[ -r "$src" ] || { echo "[x] file not readable: $src"; return 1; }
	[ -s "$src" ] || { echo "[x] file empty: $src"; return 1; }

	cat "$src" >> "$default"

	tmp="${default}.tmp.$$"
	busybox awk '
		/^[[:space:]]*#/ { print; next }
		!seen[$0]++
	' "$default" > "$tmp" && {
		cat "$tmp" > "$default"
		rm -f "$tmp"
	}

	echo "[>] appended $src -> $default"
}

apply_sus_paths() { [ -n "$1" ] && { append_to_default "$PERSISTENT_DIR/sus_paths.txt" "$1" || return 1; }; apply_list "$PERSISTENT_DIR/sus_paths.txt" add_sus_path 1; }
apply_sus_paths_loop() { [ -n "$1" ] && { append_to_default "$PERSISTENT_DIR/sus_paths_loop.txt" "$1" || return 1; }; apply_list "$PERSISTENT_DIR/sus_paths_loop.txt" add_sus_path_loop 0; }
apply_sus_paths_loop_direct() {
	file="$1"
	[ -n "$file" ] || { echo "[x] no sus path loop file specified"; return 1; }
	[ -f "$file" ] && [ ! -L "$file" ] || { echo "[x] invalid sus path loop file: $file"; return 1; }
	[ -r "$file" ] || { echo "[x] sus path loop file not readable: $file"; return 1; }
	apply_list "$file" add_sus_path_loop 0
}
apply_sus_maps() { [ -n "$1" ] && { append_to_default "$PERSISTENT_DIR/sus_maps.txt" "$1" || return 1; }; apply_list "$PERSISTENT_DIR/sus_maps.txt" add_sus_map 1; }

apply_kstat() {
	mode="$1"
	[ -n "$2" ] && { append_to_default "$PERSISTENT_DIR/kstat_paths.txt" "$2" || return 1; }
	file="${3:-$PERSISTENT_DIR/kstat_paths.txt}"
	list=$(read_list "$file" 2>/dev/null) || list=
	[ -z "$list" ] && {
		echo "[*] no Sus Kstat entries configured"
		echo "[*] nothing applied"
		return 0
	}
	echo "$list" | while IFS= read -r line; do
		path=$(echo "$line" | awk '{print $1}')
		[ -z "$path" ] && continue
		[ -e "$path" ] || { echo "[!] skip missing path: $path"; continue; }
		args=$(printf '%s\n' "$line" | sed 's/^[^[:space:]]*[[:space:]]*//')
		case "$mode" in
			add)
				if [ -n "$args" ]; then
					echo "[>] add_sus_kstat_statically $path $args"
					susfs add_sus_kstat_statically "$path" $args
				else
					echo "[>] add_sus_kstat $path"
					susfs add_sus_kstat "$path"
				fi
				;;
			update)
				echo "[>] update_sus_kstat $path"
				susfs update_sus_kstat "$path"
				;;
		esac
	done
}

apply_kstat_add() { apply_kstat add "$1"; }
apply_kstat_update() { apply_kstat update "$1"; }
apply_kstat_add_direct() {
	file="$1"
	[ -n "$file" ] || { echo "[x] no Sus Kstat file specified"; return 1; }
	[ -f "$file" ] && [ ! -L "$file" ] || { echo "[x] invalid Sus Kstat file: $file"; return 1; }
	[ -r "$file" ] || { echo "[x] Sus Kstat file not readable: $file"; return 1; }
	apply_kstat add "" "$file"
}

apply_open_redirect() {
	[ -n "$1" ] && { append_to_default "$PERSISTENT_DIR/open_redirect.txt" "$1" || return 1; }
	file="$PERSISTENT_DIR/open_redirect.txt"
	list=$(read_list "$file" 2>/dev/null) || list=
	[ -z "$list" ] && {
		echo "[*] Open Redirect has no configured entries"
		echo "[*] this optional feature is off; nothing applied"
		return 0
	}
	echo "$list" | while IFS= read -r line; do
		target=$(echo "$line" | awk '{print $1}')
		redirect=$(echo "$line" | awk '{print $2}')
		scheme=$(echo "$line" | awk '{print $3}')
		[ -z "$target" ] || [ -z "$redirect" ] || [ -z "$scheme" ] && continue
		[ -e "$target" ] && [ -e "$redirect" ] || { echo "[!] skip: $target -> $redirect (missing endpoint)"; continue; }
		echo "[>] add_open_redirect $target -> $redirect (scheme $scheme)"
		susfs add_open_redirect "$target" "$redirect" "$scheme"
	done
}



apply_uname() {
	[ -n "$1" ] && {
		case "$1" in
			*.txt) : ;;
			*) echo "[x] only .txt files allowed: $1"; return 1 ;;
		esac
		[ -f "$1" ] || { echo "[x] file not found: $1"; return 1; }
		[ -r "$1" ] || { echo "[x] file not readable: $1"; return 1; }
		[ -s "$1" ] || { echo "[x] file empty: $1"; return 1; }

		release=$(grep "^release=" "$1" | tail -n1 | cut -d'=' -f2-)
		version=$(grep "^version=" "$1" | tail -n1 | cut -d'=' -f2-)

		[ -z "$release" ] && { echo "[x] release missing in $1"; return 1; }
		[ -z "$version" ] && { echo "[x] version missing in $1"; return 1; }

		[ -f "$PERSISTENT_DIR/uname.txt" ] && {
			cp "$PERSISTENT_DIR/uname.txt" "${PERSISTENT_DIR}/uname.txt.bak.$$"
			grep -v "^release=" "$PERSISTENT_DIR/uname.txt" > "${PERSISTENT_DIR}/uname.txt.tmp.$$"
			grep -v "^version=" "${PERSISTENT_DIR}/uname.txt.tmp.$$" > "$PERSISTENT_DIR/uname.txt"
			rm -f "${PERSISTENT_DIR}/uname.txt.tmp.$$" "${PERSISTENT_DIR}/uname.txt.bak.$$"
		}

		printf "release=%s\nversion=%s\n" "$release" "$version" >> "$PERSISTENT_DIR/uname.txt"
	}

	file="$PERSISTENT_DIR/uname.txt"
	[ -f "$file" ] || return

	release=$(grep "^release=" "$file" | tail -n1 | cut -d'=' -f2-)
	version=$(grep "^version=" "$file" | tail -n1 | cut -d'=' -f2-)

	[ -z "$release" ] && { echo "[x] release missing in $file"; return 1; }
	[ -z "$version" ] && { echo "[x] version missing in $file"; return 1; }

	echo "[>] set_uname '$release' '$version'"
	susfs set_uname "$release" "$version"
}

apply_cmdline_bootconfig() {
	[ -n "$1" ] && { append_to_default "$PERSISTENT_DIR/cmdline_or_bootconfig.txt" "$1" || return 1; }
	file="$PERSISTENT_DIR/cmdline_or_bootconfig.txt"
	apply_cmdline_bootconfig_direct "$file"
}

apply_cmdline_bootconfig_direct() {
	file="$1"
	[ -n "$file" ] || { echo "[x] no cmdline/bootconfig file specified"; return 1; }
	[ -f "$file" ] && [ ! -L "$file" ] || { echo "[x] invalid cmdline/bootconfig file: $file"; return 1; }
	[ -r "$file" ] || { echo "[x] cmdline/bootconfig file not readable: $file"; return 1; }
	[ -s "$file" ] || return
	list=$(read_list "$file" 2>/dev/null) || list=
	[ -n "$list" ] || {
		echo "[*] no custom cmdline/bootconfig entries configured"
		echo "[*] the fresh sanitized boot snapshot is applied automatically"
		return 0
	}
	echo "[>] set_cmdline_or_bootconfig $file"
	susfs set_cmdline_or_bootconfig "$file"
}

status_report() {
	generate_diagnostics
}

apply_toggles() {
	stage="$1"
	file="${2:-$PERSISTENT_DIR/config.txt}"
	result=0
	[ -f "$file" ] || return
	case "$stage" in
	early)
		hide_mnts=$(get_conf HIDE_SUS_MNTS_NON_SU "" "$file")
		enable_log=$(get_conf ENABLE_LOG "" "$file")
		avc_spoof=$(get_conf ENABLE_AVC_LOG_SPOOFING "" "$file")
		;;
	late)
		hide_mnts=$(get_conf HIDE_SUS_MNTS_LATE 0 "$file")
		enable_log=""
		avc_spoof=""
		;;
	current)
		hide_mnts=$(get_conf HIDE_SUS_MNTS_LATE 0 "$file")
		enable_log=$(get_conf ENABLE_LOG "" "$file")
		avc_spoof=$(get_conf ENABLE_AVC_LOG_SPOOFING "" "$file")
		;;
	*)
		echo "[x] invalid toggle stage: $stage"
		return 1
		;;
	esac

	case "$hide_mnts" in
	"") ;;
	0|1)
		echo "[>] hide_sus_mnts_for_non_su_procs $hide_mnts ($stage)"
		susfs hide_sus_mnts_for_non_su_procs "$hide_mnts" || result=1
		;;
	*) echo "[x] invalid hide-mounts value: $hide_mnts"; result=1 ;;
	esac
	case "$enable_log" in
	"") ;;
	0|1) echo "[>] enable_log $enable_log"; susfs enable_log "$enable_log" || result=1 ;;
	*) echo "[x] invalid log value: $enable_log"; result=1 ;;
	esac
	case "$avc_spoof" in
	"") ;;
	0|1) echo "[>] enable_avc_log_spoofing $avc_spoof"; susfs enable_avc_log_spoofing "$avc_spoof" || result=1 ;;
	*) echo "[x] invalid AVC-spoof value: $avc_spoof"; result=1 ;;
	esac
	return "$result"
}

stage_early() {
	echo "[+] stage: early (post-fs-data)"
	apply_kernel_umount_feature
	apply_kstat_add
	apply_uname
	apply_open_redirect
	apply_cmdline_bootconfig
	apply_toggles early
}

stage_late() {
	echo "[+] stage: late (boot-completed)"
	apply_kernel_umount_feature
	apply_kernel_umount_mounts
	apply_sus_paths
	apply_sus_paths_loop
	apply_sus_maps
	apply_kstat_update
	apply_toggles late
	sync_cron_scripts
}

run() {
	stage_early
	stage_late
}

action() { run; }

show_status() {
	susfs show version
	susfs show variant
	susfs show enabled_features
}

show_help () {
	banner
	echo "[%] $( grep '^description=' $MODDIR/module.prop | sed 's/description=//' )"
	echo "usage:"
	printf " --action \t\t\t\tfull apply (early+late stage)\n"
	printf " --stage-early \t\t\t\tpost-fs-data stage only\n"
	printf " --stage-late \t\t\t\tboot-completed stage only\n"
	printf " --status \t\t\t\tshow susfs version / variant / enabled features\n"
	printf " --force-update \t\t\tinstall the release-pinned, verified SuSFS binary\n"
	printf " --export-config \t\t\texport a validated Sus'AF configuration archive\n"
	printf " --restore-config <archive> \t\tstage, validate, and restore a Sus'AF archive\n"
	printf " --diagnostics \t\t\trefresh and print the private diagnostics snapshot\n"
	printf " --status-report \t\t\trefresh diagnostics without editing module.prop\n"
	printf " --coverage-scan [package] \t\tscan exact hiding coverage without changing config\n"
	printf " --coverage-apply <ids> \t\tcheckpoint and save selected scan candidates\n"
	printf "\n"
	printf "if [file] is given it is appended (deduped) into the default list, then applied:\n"
	printf " --apply-sus-paths [file] \t\tadd_sus_path from list\n"
	printf " --apply-sus-paths-loop [file] \t\tadd_sus_path_loop from list\n"
	printf " --apply-sus-paths-loop-direct <file> \tapply a generated list without saving it\n"
	printf " --apply-sus-maps [file] \t\tadd_sus_map from list\n"
	printf " --apply-kstat-add [file] \t\tstage add_sus_kstat from list\n"
	printf " --apply-kstat-add-direct <file> \tstage generated kstat data without saving it\n"
	printf " --apply-kstat-update [file] \t\tcommit update_sus_kstat from list\n"
	printf " --apply-open-redirect [file] \t\tadd_open_redirect from list\n"
	printf " --apply-uname [file] \t\t\tset_uname from config\n"
	printf " --apply-cmdline-bootconfig [file] \tset_cmdline_or_bootconfig from file\n"
	printf " --apply-cmdline-bootconfig-direct <file> \tapply generated data without saving it\n"
	printf " --apply-toggles <early|late|current> [file] \tapply staged mount/log/avc policy from config\n"
	printf " --apply-kernel-umount-feature [config] \tapply the KernelSU feature policy\n"
	printf " --apply-kernel-umount-mounts [config] [list] \tregister targeted mountpoints\n"
	printf " --run-script <file> \t\t\trun a user script from UserHub\n"
	printf " --run-postfs-scripts \t\t\trun all UserHub scripts flagged for post-fs-data\n"
	printf " --run-bootcompleted-scripts \t\trun all UserHub scripts flagged for boot-completed\n"
	printf " --sync-cron-scripts \t\t\trebuild the cron schedule from scripts_cron.txt\n"
	printf "\n"
	printf " --help \t\t\t\tdisplays this message\n"
}

case "$1" in
	--action) action; exit ;;
	--stage-early) stage_early; exit ;;
	--stage-late) stage_late; exit ;;
	--status) show_status; exit ;;
	--force-update) update_susfs; exit ;;
	--export-config) export_susaf_config; exit ;;
	--restore-config) restore_susaf_config "$2"; exit ;;
	--status-report) status_report; exit ;;
	--diagnostics) show_diagnostics; exit ;;
	--coverage-scan) coverage_scan "$2"; exit ;;
	--coverage-apply) coverage_apply_ids "$2"; exit ;;
	--apply-sus-paths) apply_sus_paths "$2"; exit ;;
	--apply-sus-paths-loop) apply_sus_paths_loop "$2"; exit ;;
	--apply-sus-paths-loop-direct) apply_sus_paths_loop_direct "$2"; exit ;;
	--apply-sus-maps) apply_sus_maps "$2"; exit ;;
	--apply-kstat-add) apply_kstat_add "$2"; exit ;;
	--apply-kstat-add-direct) apply_kstat_add_direct "$2"; exit ;;
	--apply-kstat-update) apply_kstat_update "$2"; exit ;;
	--apply-open-redirect) apply_open_redirect "$2"; exit ;;
	--apply-uname) apply_uname "$2"; exit ;;
	--apply-cmdline-bootconfig) apply_cmdline_bootconfig "$2"; exit ;;
	--apply-cmdline-bootconfig-direct) apply_cmdline_bootconfig_direct "$2"; exit ;;
	--apply-toggles) apply_toggles "$2" "$3"; exit ;;
	--apply-kernel-umount-feature) apply_kernel_umount_feature "$2"; exit ;;
	--apply-kernel-umount-mounts) apply_kernel_umount_mounts "$2" "$3"; exit ;;
	--run-script) shift; run_script "$1"; exit ;;
	--run-postfs-scripts) run_stage_scripts "$POSTFS_SCRIPTS_FILE"; exit ;;
	--run-bootcompleted-scripts) run_stage_scripts "$BOOTCOMPLETED_SCRIPTS_FILE"; exit ;;
	--sync-cron-scripts) sync_cron_scripts; exit ;;
	--help|*) show_help; exit ;;
esac

# EOF
