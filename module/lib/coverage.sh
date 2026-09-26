#!/bin/sh

# Sus'AF Autopilot inventories the live device and generates an editable
# policy. Candidates must be backed by an existing artifact, a file mapped
# into a running app, a module-backed mount visible in a live namespace, or an
# available KernelSU/SuSFS control.

coverage_clean_value() {
	printf '%s' "$*" | tr '\r\n\t' '   ' | sed 's/[[:cntrl:]]//g'
}

coverage_put() {
	local key="$1"
	shift
	printf '%s=%s\n' "$key" "$(coverage_clean_value "$@")"
}

coverage_progress_write() {
	local stage="${1:-preparing}" current="${2:-0}" total="${3:-0}" status="${4:-running}" detail="${5:-$stage}"
	local state_dir output temp
	state_dir="$PERSISTENT_DIR/state"
	output="$state_dir/coverage.progress.txt"
	temp="${output}.tmp.$$"
	[ "${SUSAF_COVERAGE_PROGRESS:-1}" = 1 ] || return 0
	umask 077
	mkdir -p "$state_dir" || return 0
	{
		coverage_put schema 1
		coverage_put operation "${COVERAGE_OPERATION:-audit}"
		coverage_put status "$status"
		coverage_put stage "$stage"
		coverage_put current "$current"
		coverage_put total "$total"
		coverage_put detail "$detail"
		coverage_put updated.epoch "$(date +%s 2>/dev/null)"
	} > "$temp" || return 0
	chmod 600 "$temp" 2>/dev/null
	mv "$temp" "$output" 2>/dev/null || rm -f "$temp"
}

coverage_property() {
	local file="$1" key="$2" fallback="${3:-}" value
	value=$(awk -F= -v key="$key" '$1 == key { value=substr($0, index($0, "=") + 1) } END { print value }' "$file" 2>/dev/null)
	[ -n "$value" ] || value="$fallback"
	printf '%s\n' "$value"
}

coverage_conf() {
	local key="$1" fallback="$2" file="${3:-$PERSISTENT_DIR/config.txt}" value
	if command -v get_conf >/dev/null 2>&1; then
		get_conf "$key" "$fallback" "$file"
		return
	fi
	value=$(sed -n "s/^${key}=//p" "$file" 2>/dev/null | tail -n 1)
	[ -n "$value" ] || value="$fallback"
	printf '%s\n' "$value"
}

coverage_package_is_safe() {
	local package="$1"
	[ -n "$package" ] && [ "${#package}" -le 255 ] || return 1
	case "$package" in .*|*..*|*[!A-Za-z0-9._]*) return 1 ;; *.*) return 0 ;; esac
	return 1
}

coverage_path_is_safe() {
	local path="$1"
	[ -n "$path" ] && [ "${#path}" -lt 4096 ] || return 1
	case "$path" in /*) ;; *) return 1 ;; esac
	case "$path" in /|*/../*|*/..|*/./*|*/.|*#*|*[![:print:]]*) return 1 ;; esac
	return 0
}

coverage_map_path_is_allowed() {
	local path="$1" roots root old_ifs
	roots="${SUSAF_COVERAGE_MAP_ROOTS:-/data/adb/modules:/data/adb/modules_update:/data/adb/ksu:/data/adb/ap:/data/adb/magisk}"
	old_ifs=$IFS; IFS=:
	for root in $roots; do
		[ -n "$root" ] || continue
		case "$path" in "$root"/*) IFS=$old_ifs; return 0 ;; esac
	done
	IFS=$old_ifs
	return 1
}

coverage_config_target_is_allowed() {
	case "$1" in
		HIDE_SUS_MNTS_NON_SU=1|HIDE_SUS_MNTS_LATE=1|ENABLE_LOG=0|ENABLE_AVC_LOG_SPOOFING=1|\
		KERNEL_UMOUNT_MODE=enabled|AUTO_KERNEL_UMOUNT=1|ALLOW_BROAD_KERNEL_UMOUNT=1|SELINUX_HIDE_MODE=enabled)
			return 0 ;;
	esac
	return 1
}

coverage_path_is_curated() {
	case "$1" in
		/storage/emulated/0/Fox|/storage/emulated/0/TWRP|/sdcard/TWRP|/data/media/0/TWRP|\
		/data/recovery|/vendor/bin/install-recovery.sh|/system/bin/install-recovery.sh|\
		/sdcard/MT2|/sdcard/APKTool|/sdcard/Apktool_M|/sdcard/AppManager|\
		/data/media/0/MT2|/data/media/0/AppManager|/data/local/tmp/main.jar|\
		/system/bin/su|/system/xbin/su|/vendor/bin/su|/sbin/su|/debug_ramdisk|\
		/data/adb/ksu|/data/adb/ap|/data/adb/magisk|/data/adb/modules|\
		/data/adb/modules_update|/data/adb/SusAF|/data/adb/susfs4ksu)
			return 0 ;;
	esac
	return 1
}

coverage_list_contains() {
	local file="$1" path="$2"
	awk -v path="$path" '{ line=$0; sub(/[[:space:]]*#.*/, "", line); gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if (line == path) found=1 } END { exit !found }' "$file" 2>/dev/null
}

coverage_list_count() {
	awk '{ line=$0; sub(/[[:space:]]*#.*/, "", line); gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if (line != "") count++ } END { print count + 0 }' "$1" 2>/dev/null
}

coverage_missing_count() {
	local file="$1" line count=0
	[ -f "$file" ] && [ ! -L "$file" ] || { printf '0\n'; return; }
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%%#*}; line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		[ -n "$line" ] || continue
		coverage_path_is_safe "$line" || continue
		[ -e "$line" ] || count=$((count + 1))
	done < "$file"
	printf '%s\n' "$count"
}

coverage_schedule_status() {
	local file="$1" name="$2"
	[ -f "$file" ] && [ ! -L "$file" ] || { printf 'missing\n'; return; }
	grep -Fqx "$name" "$file" 2>/dev/null && { printf 'enabled\n'; return; }
	grep -Fqx "!$name" "$file" 2>/dev/null && { printf 'disabled\n'; return; }
	printf 'not-scheduled\n'
}

# Candidate columns: kind, target, reason, risk, action, scope.
coverage_add_candidate() {
	local output="$1" kind="$2" target="$3" reason="$4" risk="$5" action="$6" scope="${7:-device}"
	case "$kind" in
		sus_map|sus_path_loop|kernel_umount) coverage_path_is_safe "$target" || return 1 ;;
		config_toggle|kernel_feature) coverage_config_target_is_allowed "$target" || return 1 ;;
		*) return 1 ;;
	esac
	case "$risk" in low|medium|high) ;; *) return 1 ;; esac
	case "$target$reason$action$scope" in *"$(printf '\t')"*) return 1 ;; esac
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$target" "$reason" "$risk" "$action" "$scope" >> "$output"
}

coverage_collect_curated_paths() {
	local output="$1" list_file="$PERSISTENT_DIR/sus_paths_loop.txt" path risk reason
	while IFS='|' read -r path risk reason || [ -n "$path$risk$reason" ]; do
		[ -n "$path" ] && [ -e "$path" ] || continue
		coverage_list_contains "$list_file" "$path" && continue
		coverage_add_candidate "$output" sus_path_loop "$path" "$reason" "$risk" hide_path device
	done <<'EOF'
/storage/emulated/0/Fox|low|recovery_artifact
/storage/emulated/0/TWRP|low|recovery_artifact
/sdcard/TWRP|low|recovery_artifact
/data/media/0/TWRP|low|recovery_artifact
/data/recovery|low|recovery_artifact
/vendor/bin/install-recovery.sh|low|recovery_artifact
/system/bin/install-recovery.sh|low|recovery_artifact
/sdcard/MT2|medium|root_tool_artifact
/sdcard/APKTool|medium|root_tool_artifact
/sdcard/Apktool_M|medium|root_tool_artifact
/sdcard/AppManager|medium|root_tool_artifact
/data/media/0/MT2|medium|root_tool_artifact
/data/media/0/AppManager|medium|root_tool_artifact
/data/local/tmp/main.jar|medium|root_tool_artifact
/system/bin/su|medium|su_binary
/system/xbin/su|medium|su_binary
/vendor/bin/su|medium|su_binary
/sbin/su|medium|su_binary
/debug_ramdisk|high|root_runtime_path
/data/adb/ksu|medium|root_runtime_path
/data/adb/ap|medium|root_runtime_path
/data/adb/magisk|medium|root_runtime_path
/data/adb/modules|medium|root_module_path
/data/adb/modules_update|medium|root_module_path
/data/adb/SusAF|medium|susaf_runtime_path
/data/adb/susfs4ksu|medium|legacy_runtime_path
EOF
}

coverage_pid_is_app() {
	local proc_dir="$1" uid
	uid=$(awk '/^Uid:/ { print $2; exit }' "$proc_dir/status" 2>/dev/null)
	case "$uid" in ''|*[!0-9]*) return 1 ;; esac
	[ "$uid" -ge 10000 ]
}

coverage_pid_scope() {
	local proc_dir="$1" pid="$2" scope
	scope=$(tr '\000' ' ' < "$proc_dir/cmdline" 2>/dev/null | sed 's/[[:space:]].*//')
	[ -n "$scope" ] || scope="pid:$pid"
	coverage_clean_value "$scope"
}

coverage_collect_process_maps() {
	local package="$1" output="$2" pidof_bin="${SUSAF_PIDOF_BIN:-pidof}" proc_root="${SUSAF_PROC_ROOT:-/proc}"
	local require_exists="${SUSAF_COVERAGE_REQUIRE_EXISTS:-1}" raw_paths="${output}.maps.$$"
	local pids="" proc_dir pid maps_file path scope progress_current=0 progress_total=0
	COVERAGE_PROCESS_COUNT=0; COVERAGE_PROCESS_IDS=none; : > "$raw_paths"
	if [ -n "$package" ]; then
		pids=$("$pidof_bin" "$package" 2>/dev/null) || pids=""
	else
		for proc_dir in "$proc_root"/[0-9]*; do
			[ -d "$proc_dir" ] || continue
			coverage_pid_is_app "$proc_dir" || continue
			pid=${proc_dir##*/}; pids="${pids}${pids:+ }$pid"
		done
	fi
	for pid in $pids; do progress_total=$((progress_total + 1)); done
	coverage_progress_write process_maps 0 "$progress_total" running reading_application_maps
	COVERAGE_PROCESS_IDS=""
	for pid in $pids; do
		progress_current=$((progress_current + 1))
		if [ $((progress_current % 5)) -eq 0 ] || [ "$progress_current" -eq "$progress_total" ]; then
			coverage_progress_write process_maps "$progress_current" "$progress_total" running reading_application_maps
		fi
		case "$pid" in ''|*[!0-9]*) continue ;; esac
		proc_dir="$proc_root/$pid"; maps_file="$proc_dir/maps"
		[ -f "$maps_file" ] && [ -r "$maps_file" ] || continue
		COVERAGE_PROCESS_COUNT=$((COVERAGE_PROCESS_COUNT + 1))
		COVERAGE_PROCESS_IDS="${COVERAGE_PROCESS_IDS}${COVERAGE_PROCESS_IDS:+,}$pid"
		scope=$(coverage_pid_scope "$proc_dir" "$pid")
		awk 'NF >= 6 { path=$6; for (i=7; i<=NF; i++) path=path " " $i; if (substr(path, 1, 1) == "/" && path !~ / \(deleted\)$/) print path }' "$maps_file" |
		while IFS= read -r path || [ -n "$path" ]; do
			coverage_path_is_safe "$path" || continue
			coverage_map_path_is_allowed "$path" || continue
			[ "$require_exists" = 0 ] || [ -e "$path" ] || continue
			printf '%s\t%s\n' "$path" "$scope" >> "$raw_paths"
		done
	done
	[ -n "$COVERAGE_PROCESS_IDS" ] || COVERAGE_PROCESS_IDS=none
	sort -u "$raw_paths" 2>/dev/null | while IFS="$(printf '\t')" read -r path scope || [ -n "$path$scope" ]; do
		coverage_list_contains "$PERSISTENT_DIR/sus_maps.txt" "$path" && continue
		coverage_add_candidate "$output" sus_map "$path" mapped_module_file low hide_map "$scope"
	done
	rm -f "$raw_paths"
}

coverage_mount_risk() {
	case "$1" in
		/system/etc/hosts|/etc/hosts|/apex/*|/system|/system_ext|/vendor|/product|/odm|/apex|/debug_ramdisk|/data|/metadata|/mnt|/storage|/dev|/proc|/sys) printf 'high\n' ;;
		*) printf 'low\n' ;;
	esac
}

coverage_collect_mount_file() {
	local file="$1" scope="$2" output="$3" temp="${output}.mount.$$" target reason risk
	[ -f "$file" ] && [ -r "$file" ] || return 0
	: > "$temp"
	if command -v collect_kernel_umount_candidates >/dev/null 2>&1; then
		collect_kernel_umount_candidates "$file" "$temp" 2>/dev/null || : > "$temp"
	fi
	while IFS="$(printf '\t')" read -r target reason || [ -n "$target$reason" ]; do
		[ -n "$target" ] || continue
		coverage_list_contains "$PERSISTENT_DIR/kernel_umount.txt" "$target" && continue
		risk=$(coverage_mount_risk "$target")
		coverage_add_candidate "$output" kernel_umount "$target" module_mount "$risk" hide_mount "$scope"
	done < "$temp"
	rm -f "$temp"
}

coverage_mount_file_has_high_ids() {
	local file="$1"
	[ -f "$file" ] && [ -r "$file" ] || return 1
	awk '$1 ~ /^[0-9]+$/ && $1 + 0 >= 1000000000 { found=1; exit } { for (i=7; i<=NF && $i != "-"; i++) { split($i, f, ":"); if ((f[1] == "shared" || f[1] == "master" || f[1] == "propagate_from") && f[2] + 0 >= 100000) { found=1; exit } } } END { exit !found }' "$file"
}

coverage_collect_mount_namespaces() {
	local package="$1" output="$2" proc_root="${SUSAF_PROC_ROOT:-/proc}" mountinfo="${SUSAF_MOUNTINFO:-/proc/1/mountinfo}"
	local seen="${output}.namespaces.$$" pid proc_dir ns scope pids progress_total progress_current=0
	COVERAGE_MOUNT_NAMESPACE_COUNT=0; COVERAGE_HIGH_ID_COUNT=0; : > "$seen"
	progress_total=$((COVERAGE_PROCESS_COUNT + 1))
	coverage_progress_write mount_namespaces 0 "$progress_total" running reading_mount_namespaces
	coverage_collect_mount_file "$mountinfo" global "$output"
	COVERAGE_MOUNT_NAMESPACE_COUNT=1
	progress_current=1
	coverage_progress_write mount_namespaces "$progress_current" "$progress_total" running reading_mount_namespaces
	coverage_mount_file_has_high_ids "$mountinfo" && COVERAGE_HIGH_ID_COUNT=$((COVERAGE_HIGH_ID_COUNT + 1))
	[ "$COVERAGE_PROCESS_IDS" = none ] && pids="" || pids=$(printf '%s' "$COVERAGE_PROCESS_IDS" | tr ',' ' ')
	for pid in $pids; do
		proc_dir="$proc_root/$pid"; [ -r "$proc_dir/mountinfo" ] || continue
		ns=$(readlink "$proc_dir/ns/mnt" 2>/dev/null) || ns="pid:$pid"
		grep -Fqx "$ns" "$seen" 2>/dev/null && continue
		printf '%s\n' "$ns" >> "$seen"; scope=$(coverage_pid_scope "$proc_dir" "$pid")
		coverage_collect_mount_file "$proc_dir/mountinfo" "$scope" "$output"
		COVERAGE_MOUNT_NAMESPACE_COUNT=$((COVERAGE_MOUNT_NAMESPACE_COUNT + 1))
		progress_current=$COVERAGE_MOUNT_NAMESPACE_COUNT
		if [ $((progress_current % 5)) -eq 0 ] || [ "$progress_current" -eq "$progress_total" ]; then
			coverage_progress_write mount_namespaces "$progress_current" "$progress_total" running reading_mount_namespaces
		fi
		coverage_mount_file_has_high_ids "$proc_dir/mountinfo" && COVERAGE_HIGH_ID_COUNT=$((COVERAGE_HIGH_ID_COUNT + 1))
	done
	rm -f "$seen"
	coverage_progress_write mount_namespaces "$COVERAGE_MOUNT_NAMESPACE_COUNT" "$COVERAGE_MOUNT_NAMESPACE_COUNT" running reading_mount_namespaces
	# Large mount/peer/master/propagation IDs are retained as diagnostic
	# telemetry only. Android 17 validation showed that every readable app
	# namespace can legitimately use the same large-ID family, so ID magnitude
	# alone must never generate a hiding-policy change.
}

coverage_collect_controls() {
	local output="$1" ksu_bin check current
	[ "$(coverage_conf HIDE_SUS_MNTS_NON_SU 0)" = 1 ] || coverage_add_candidate "$output" config_toggle HIDE_SUS_MNTS_NON_SU=1 mount_filter_disabled low enable_mount_filter zygote
	[ "$(coverage_conf ENABLE_LOG 1)" = 0 ] || coverage_add_candidate "$output" config_toggle ENABLE_LOG=0 susfs_logging low disable_detection_log device
	[ "$(coverage_conf ENABLE_AVC_LOG_SPOOFING 0)" = 1 ] || coverage_add_candidate "$output" config_toggle ENABLE_AVC_LOG_SPOOFING=1 avc_context_visible low spoof_avc_context device
	[ "$(coverage_conf KERNEL_UMOUNT_MODE disabled)" = enabled ] || coverage_add_candidate "$output" config_toggle KERNEL_UMOUNT_MODE=enabled kernel_umount_disabled low enable_kernel_umount device
	[ "$(coverage_conf AUTO_KERNEL_UMOUNT 0)" = 1 ] || coverage_add_candidate "$output" config_toggle AUTO_KERNEL_UMOUNT=1 auto_mount_discovery_disabled low enable_mount_discovery device
	command -v resolve_ksud_bin >/dev/null 2>&1 || return 0
	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=""; [ -n "$ksu_bin" ] || return 0
	check=$("$ksu_bin" feature check selinux_hide 2>/dev/null) || check=unavailable
	case "$check" in supported|managed) ;; *) return 0 ;; esac
	current=$("$ksu_bin" feature get selinux_hide 2>/dev/null | awk -F': ' '$1 == "Status" { print $2; exit }') || current=unknown
	case "$current" in enabled|1|true) return 0 ;; esac
	coverage_add_candidate "$output" kernel_feature SELINUX_HIDE_MODE=enabled selinux_policy_visible medium spoof_selinux_status device
}

coverage_scan() {
	local package="${1:-}" operation="${2:-audit}" state_dir="$PERSISTENT_DIR/state" output temp candidates unique kernel_report feature_report
	local kind target reason risk action scope index candidate_count map_count path_count mount_count spoof_count low_count risky_count missing_total
	output="${SUSAF_COVERAGE_REPORT:-$state_dir/coverage.report.txt}"; temp="${output}.tmp.$$"; candidates="${output}.candidates.$$"; unique="${output}.unique.$$"; kernel_report="$state_dir/kernel_umount.report.txt"; feature_report="$state_dir/kernel_umount.feature.txt"
	if [ -n "$package" ] && ! coverage_package_is_safe "$package"; then echo "[x] invalid package name: $package"; return 1; fi
	COVERAGE_OPERATION="$operation"
	coverage_progress_write preparing 0 0 running preparing_audit
	umask 077; mkdir -p "$state_dir" || return 1; chmod 700 "$PERSISTENT_DIR" "$state_dir" 2>/dev/null
	trap "rm -f '$temp' '$candidates' '$unique' '${candidates}.'*" EXIT HUP INT TERM
	: > "$candidates"
	coverage_progress_write artifacts 0 0 running checking_device_artifacts
	coverage_collect_curated_paths "$candidates"
	coverage_collect_process_maps "$package" "$candidates"
	coverage_collect_mount_namespaces "$package" "$candidates"
	coverage_progress_write controls 0 0 running checking_supported_controls
	coverage_collect_controls "$candidates"
	coverage_progress_write finalizing 0 0 running generating_policy
	awk -F '\t' '!seen[$1 FS $2]++' "$candidates" > "$unique"
	missing_total=$(( $(coverage_missing_count "$PERSISTENT_DIR/sus_maps.txt") + $(coverage_missing_count "$PERSISTENT_DIR/sus_paths.txt") + $(coverage_missing_count "$PERSISTENT_DIR/sus_paths_loop.txt") ))
	candidate_count=$(coverage_list_count "$unique")
	map_count=$(awk -F '\t' '$1 == "sus_map" { count++ } END { print count + 0 }' "$unique")
	path_count=$(awk -F '\t' '$1 == "sus_path_loop" { count++ } END { print count + 0 }' "$unique")
	mount_count=$(awk -F '\t' '$1 == "kernel_umount" { count++ } END { print count + 0 }' "$unique")
	spoof_count=$(awk -F '\t' '$5 ~ /^spoof_/ { count++ } END { print count + 0 }' "$unique")
	low_count=$(awk -F '\t' '$4 == "low" { count++ } END { print count + 0 }' "$unique")
	risky_count=$(awk -F '\t' '$4 != "low" { count++ } END { print count + 0 }' "$unique")
	{
		coverage_put schema 2
		coverage_put generated.at "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
		coverage_put generated.epoch "$(date +%s 2>/dev/null)"
		coverage_put mode "$([ -n "$package" ] && printf app || printf autopilot)"
		coverage_put package "${package:-all-running-apps}"
		coverage_put process.count "$COVERAGE_PROCESS_COUNT"; coverage_put process.ids "$COVERAGE_PROCESS_IDS"
		coverage_put mount.namespaces "$COVERAGE_MOUNT_NAMESPACE_COUNT"; coverage_put mount.high_id_namespaces "$COVERAGE_HIGH_ID_COUNT"
		coverage_put configured.sus_maps "$(coverage_list_count "$PERSISTENT_DIR/sus_maps.txt")"
		coverage_put configured.sus_paths "$(coverage_list_count "$PERSISTENT_DIR/sus_paths.txt")"
		coverage_put configured.sus_paths_loop "$(coverage_list_count "$PERSISTENT_DIR/sus_paths_loop.txt")"
		coverage_put configured.kernel_umount "$(coverage_list_count "$PERSISTENT_DIR/kernel_umount.txt")"
		coverage_put missing.total "$missing_total"; coverage_put mount.failures "$(coverage_property "$kernel_report" failed 0)"
		coverage_put kernel_umount.feature_result "$(coverage_property "$feature_report" result not-recorded)"
		coverage_put kernel_umount.mount_result "$(coverage_property "$kernel_report" result not-recorded)"
		coverage_put schedule.sus_maps "$(coverage_schedule_status "$PERSISTENT_DIR/scripts_postfs.txt" SusAF_apply-sus-maps.sh)"
		coverage_put schedule.sus_paths "$(coverage_schedule_status "$PERSISTENT_DIR/scripts_postfs.txt" SusAF_apply-sus-paths.sh)"
		coverage_put schedule.sus_paths_loop "$(coverage_schedule_status "$PERSISTENT_DIR/scripts_postfs.txt" SusAF_apply-sus-paths-loop.sh)"
		coverage_put candidate.count "$candidate_count"; coverage_put candidate.safe "$low_count"; coverage_put candidate.risky "$risky_count"
		coverage_put candidate.sus_maps "$map_count"; coverage_put candidate.sus_paths_loop "$path_count"; coverage_put candidate.kernel_umount "$mount_count"; coverage_put candidate.spoof "$spoof_count"
		index=0
		while IFS="$(printf '\t')" read -r kind target reason risk action scope || [ -n "$kind$target$reason$risk$action$scope" ]; do
			[ -n "$kind" ] && [ -n "$target" ] || continue; index=$((index + 1))
			coverage_put "candidate.$index.kind" "$kind"; coverage_put "candidate.$index.target" "$target"; coverage_put "candidate.$index.path" "$target"
			coverage_put "candidate.$index.reason" "$reason"; coverage_put "candidate.$index.risk" "$risk"; coverage_put "candidate.$index.action" "$action"; coverage_put "candidate.$index.scope" "$scope"; coverage_put "candidate.$index.status" recommended
		done < "$unique"
		coverage_put verification.last "$(coverage_property "$state_dir/coverage.verify.txt" result not-run)"
		coverage_put rollback.available "$([ -f "$state_dir/coverage.last_checkpoint" ] && printf 1 || printf 0)"
		coverage_put limitation.tee_integrity outside_susaf; coverage_put limitation.anonymous_maps requires_injection_backend; coverage_put result ok
	} > "$temp" || return 1
	chmod 600 "$temp" 2>/dev/null; mv "$temp" "$output" || return 1
	trap - EXIT HUP INT TERM
	rm -f "$candidates" "$unique" "${candidates}."*
	if [ "$operation" = verify ]; then
		coverage_progress_write evaluating 0 0 running evaluating_policy
	else
		coverage_progress_write complete 1 1 complete audit_complete
	fi
	# stdout is a supported CLI surface. Emit only after the report has been
	# atomically installed and the progress state has reached its final stage.
	cat "$output"
}

coverage_set_config_value() {
	local file="$1" key="$2" value="$3" temp="${file}.set.$$"
	awk -F= -v key="$key" -v value="$value" 'BEGIN { replaced=0 } $1 == key { if (!replaced) print key "=" value; replaced=1; next } { print } END { if (!replaced) print key "=" value }' "$file" 2>/dev/null > "$temp" || return 1
	mv "$temp" "$file"
}

coverage_checkpoint() {
	local checkpoint="$1" file name
	mkdir -p "$checkpoint" || return 1; chmod 700 "$PERSISTENT_DIR/checkpoints" "$checkpoint" 2>/dev/null
	for name in config.txt kernel_umount.txt sus_maps.txt sus_paths_loop.txt; do
		file="$PERSISTENT_DIR/$name"
		if [ -f "$file" ] && [ ! -L "$file" ]; then cp -p "$file" "$checkpoint/$name" || return 1; else : > "$checkpoint/$name.absent"; fi
	done
	printf '%s\n' "$checkpoint" > "$checkpoint/checkpoint.path"; chmod 600 "$checkpoint"/* 2>/dev/null
}

coverage_apply_persistent_features() {
	local mode ksu_bin check desired
	mode=$(coverage_conf SELINUX_HIDE_MODE unchanged)
	case "$mode" in unchanged|'') return 0 ;; enabled) desired=1 ;; disabled) desired=0 ;; *) return 1 ;; esac
	command -v resolve_ksud_bin >/dev/null 2>&1 || return 1
	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=""; [ -n "$ksu_bin" ] || return 1
	check=$("$ksu_bin" feature check selinux_hide 2>/dev/null) || check=unavailable
	case "$check" in supported|managed) ;; *) return 1 ;; esac
	KSU_MODULE="${MODULE_ID:-susaf}" "$ksu_bin" feature set selinux_hide "$desired" >/dev/null 2>&1
}

coverage_apply_runtime() {
	local result=0
	if command -v apply_sus_maps >/dev/null 2>&1; then apply_sus_maps || result=1; fi
	if command -v apply_sus_paths_loop >/dev/null 2>&1; then apply_sus_paths_loop || result=1; fi
	if command -v apply_kernel_umount_feature >/dev/null 2>&1; then apply_kernel_umount_feature || result=1; fi
	if command -v apply_kernel_umount_mounts >/dev/null 2>&1; then apply_kernel_umount_mounts || result=1; fi
	if command -v apply_toggles >/dev/null 2>&1; then apply_toggles current || result=1; fi
	coverage_apply_persistent_features || result=1
	return "$result"
}

coverage_apply_ids() {
	local ids="$1" report="${SUSAF_COVERAGE_REPORT:-$PERSISTENT_DIR/state/coverage.report.txt}" stamp checkpoint
	local config_file mounts_file maps_file paths_file config_temp mounts_temp maps_temp paths_temp provenance provenance_temp
	local id kind target reason risk action selected token old_ifs key value file
	local added_maps=0 added_paths=0 added_mounts=0 changed_config=0 duplicate_count=0 apply_result=ok
	case "$ids" in ''|*[!0-9,]*) echo '[x] invalid candidate selection'; return 1 ;; esac
	[ -f "$report" ] && [ ! -L "$report" ] || { echo '[x] no trusted Autopilot scan is available'; return 1; }
	[ "$(coverage_property "$report" schema unknown)" = 2 ] || { echo '[x] unsupported Autopilot report'; return 1; }
	COVERAGE_OPERATION=apply
	coverage_progress_write preparing 0 0 running preparing_changes
	stamp=$(date +%Y%m%d_%H%M%S 2>/dev/null); checkpoint="$PERSISTENT_DIR/checkpoints/coverage-${stamp:-unknown}-$$"
	config_file="$PERSISTENT_DIR/config.txt"; mounts_file="$PERSISTENT_DIR/kernel_umount.txt"; maps_file="$PERSISTENT_DIR/sus_maps.txt"; paths_file="$PERSISTENT_DIR/sus_paths_loop.txt"
	config_temp="${config_file}.coverage.$$"; mounts_temp="${mounts_file}.coverage.$$"; maps_temp="${maps_file}.coverage.$$"; paths_temp="${paths_file}.coverage.$$"
	provenance="$PERSISTENT_DIR/state/coverage.applied.log"; provenance_temp="${provenance}.tmp.$$"; selected=""
	umask 077; mkdir -p "$PERSISTENT_DIR" "$PERSISTENT_DIR/state" "$PERSISTENT_DIR/checkpoints" || return 1
	for file in "$config_file" "$mounts_file" "$maps_file" "$paths_file"; do [ ! -e "$file" ] || { [ -f "$file" ] && [ ! -L "$file" ]; } || return 1; done
	[ -f "$config_file" ] && cp "$config_file" "$config_temp" || : > "$config_temp"
	[ -f "$mounts_file" ] && cp "$mounts_file" "$mounts_temp" || : > "$mounts_temp"
	[ -f "$maps_file" ] && cp "$maps_file" "$maps_temp" || : > "$maps_temp"
	[ -f "$paths_file" ] && cp "$paths_file" "$paths_temp" || : > "$paths_temp"
	trap "rm -f '$config_temp' '$mounts_temp' '$maps_temp' '$paths_temp' '$provenance_temp'" EXIT HUP INT TERM
	old_ifs=$IFS; IFS=,
	for token in $ids; do
		IFS=$old_ifs; case "$token" in ''|*[!0-9]*) return 1 ;; esac
		case ",$selected," in *,"$token",*) duplicate_count=$((duplicate_count + 1)); IFS=,; continue ;; esac
		selected="${selected}${selected:+,}$token"; id="$token"
		kind=$(coverage_property "$report" "candidate.$id.kind" ""); target=$(coverage_property "$report" "candidate.$id.target" "")
		reason=$(coverage_property "$report" "candidate.$id.reason" ""); risk=$(coverage_property "$report" "candidate.$id.risk" ""); action=$(coverage_property "$report" "candidate.$id.action" "")
		case "$risk" in low|medium|high) ;; *) return 1 ;; esac
		case "$kind:$action" in
			sus_map:hide_map)
				coverage_path_is_safe "$target" && coverage_map_path_is_allowed "$target" && [ -e "$target" ] || return 1
				coverage_list_contains "$maps_temp" "$target" || { printf '%s\n' "$target" >> "$maps_temp"; added_maps=$((added_maps + 1)); } ;;
			sus_path_loop:hide_path)
				coverage_path_is_safe "$target" && coverage_path_is_curated "$target" && [ -e "$target" ] || return 1
				coverage_list_contains "$paths_temp" "$target" || { printf '%s\n' "$target" >> "$paths_temp"; added_paths=$((added_paths + 1)); } ;;
			kernel_umount:hide_mount)
				coverage_path_is_safe "$target" || return 1
				coverage_list_contains "$mounts_temp" "$target" || { printf '%s\n' "$target" >> "$mounts_temp"; added_mounts=$((added_mounts + 1)); }
				if command -v kernel_umount_target_is_broad >/dev/null 2>&1 && kernel_umount_target_is_broad "$target"; then
					coverage_set_config_value "$config_temp" ALLOW_BROAD_KERNEL_UMOUNT 1 || return 1
					changed_config=$((changed_config + 1))
				fi ;;
			config_toggle:*|kernel_feature:*)
				coverage_config_target_is_allowed "$target" || return 1; key=${target%%=*}; value=${target#*=}
				coverage_set_config_value "$config_temp" "$key" "$value" || return 1; changed_config=$((changed_config + 1)) ;;
			*) echo "[x] rejected unsupported candidate: $id ($kind/$action/$reason)"; return 1 ;;
		esac
		IFS=,
	done
	IFS=$old_ifs
	if [ "$added_maps" -eq 0 ] && [ "$added_paths" -eq 0 ] && [ "$added_mounts" -eq 0 ] && [ "$changed_config" -eq 0 ]; then
		trap - EXIT HUP INT TERM
		rm -f "$config_temp" "$mounts_temp" "$maps_temp" "$paths_temp" "$provenance_temp"
		coverage_progress_write complete 1 1 complete no_changes
		coverage_put result no-changes; coverage_put duplicates "$duplicate_count"; return 0
	fi
	coverage_progress_write checkpoint 0 0 running creating_checkpoint
	coverage_checkpoint "$checkpoint" || return 1
	coverage_progress_write policy 0 0 running saving_generated_policy
	chmod 600 "$config_temp" "$mounts_temp" "$maps_temp" "$paths_temp" 2>/dev/null
	mv "$config_temp" "$config_file" || return 1; mv "$mounts_temp" "$mounts_file" || return 1; mv "$maps_temp" "$maps_file" || return 1; mv "$paths_temp" "$paths_file" || return 1
	printf '%s\n' "$checkpoint" > "$PERSISTENT_DIR/state/coverage.last_checkpoint.tmp.$$"; chmod 600 "$PERSISTENT_DIR/state/coverage.last_checkpoint.tmp.$$" 2>/dev/null; mv "$PERSISTENT_DIR/state/coverage.last_checkpoint.tmp.$$" "$PERSISTENT_DIR/state/coverage.last_checkpoint"
	coverage_progress_write runtime 0 0 running applying_runtime_policy
	coverage_apply_runtime || apply_result=partial
	[ -f "$provenance" ] && [ ! -L "$provenance" ] && cp "$provenance" "$provenance_temp" || : > "$provenance_temp"
	printf '%s\tids=%s\tmaps=%s\tpaths=%s\tmounts=%s\tconfig=%s\tcheckpoint=%s\tapply=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$selected" "$added_maps" "$added_paths" "$added_mounts" "$changed_config" "$checkpoint" "$apply_result" >> "$provenance_temp"
	chmod 600 "$provenance_temp" 2>/dev/null; mv "$provenance_temp" "$provenance"; trap - EXIT HUP INT TERM
	coverage_put result applied; coverage_put runtime.result "$apply_result"; coverage_put added.sus_maps "$added_maps"; coverage_put added.sus_paths_loop "$added_paths"; coverage_put added.kernel_umount "$added_mounts"; coverage_put changed.config "$changed_config"; coverage_put checkpoint "$checkpoint"; coverage_put reboot.required 1
	coverage_progress_write complete 1 1 complete changes_applied
	[ "$apply_result" = ok ]
}

coverage_apply_safe() {
	local report="${SUSAF_COVERAGE_REPORT:-$PERSISTENT_DIR/state/coverage.report.txt}" count id=1 ids="" risk
	[ -f "$report" ] || coverage_scan >/dev/null || return 1
	[ "$(coverage_property "$report" schema unknown)" = 2 ] || return 1
	count=$(coverage_property "$report" candidate.count 0)
	while [ "$id" -le "$count" ]; do risk=$(coverage_property "$report" "candidate.$id.risk" ""); [ "$risk" != low ] || ids="${ids}${ids:+,}$id"; id=$((id + 1)); done
	[ -n "$ids" ] || { coverage_put result no-safe-changes; return 0; }
	coverage_apply_ids "$ids"
}

coverage_verify() {
	local state_dir="$PERSISTENT_DIR/state" report temp missing mount_failures remaining kernel_mode feature_result mount_result runtime_available=1 result=clean exit_result=0
	report="$state_dir/coverage.verify.txt"; temp="${report}.tmp.$$"; coverage_scan '' verify >/dev/null || return 1
	missing=$(coverage_property "$state_dir/coverage.report.txt" missing.total 0)
	mount_failures=$(coverage_property "$state_dir/kernel_umount.report.txt" failed 0)
	remaining=$(coverage_property "$state_dir/coverage.report.txt" candidate.count 0)
	kernel_mode=$(coverage_conf KERNEL_UMOUNT_MODE enabled)
	feature_result=$(coverage_property "$state_dir/kernel_umount.feature.txt" result not-recorded)
	mount_result=$(coverage_property "$state_dir/kernel_umount.report.txt" result not-recorded)
	case "$missing" in ''|*[!0-9]*) missing=0 ;; esac
	case "$mount_failures" in ''|*[!0-9]*) mount_failures=0 ;; esac
	case "$remaining" in ''|*[!0-9]*) remaining=0 ;; esac
	if [ "$kernel_mode" = enabled ] && { [ "$feature_result" != ok ] || [ "$mount_result" != ok ]; }; then
		runtime_available=0
	fi
	if [ "$runtime_available" -ne 1 ] || [ "$mount_failures" -gt 0 ] || [ "$remaining" -gt 0 ]; then
		result=attention
		exit_result=1
	elif [ "$missing" -gt 0 ]; then
		result=clean-with-stale
	fi
	{ coverage_put schema 1; coverage_put generated.at "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; coverage_put missing.configured "$missing"; coverage_put mount.failures "$mount_failures"; coverage_put remaining.candidates "$remaining"; coverage_put kernel_umount.mode "$kernel_mode"; coverage_put kernel_umount.feature_result "$feature_result"; coverage_put kernel_umount.mount_result "$mount_result"; coverage_put runtime.available "$runtime_available"; coverage_put result "$result"; coverage_put note app_restart_or_reboot_required_for_namespace_verification; } > "$temp" || return 1
	chmod 600 "$temp" 2>/dev/null; mv "$temp" "$report"
	coverage_progress_write complete 1 1 "$([ "$exit_result" -eq 0 ] && printf complete || printf attention)" "verification_$result"
	cat "$report"
	return "$exit_result"
}

coverage_rollback() {
	local state_file="$PERSISTENT_DIR/state/coverage.last_checkpoint" checkpoint name source destination
	[ -f "$state_file" ] && [ ! -L "$state_file" ] || { echo '[x] no Autopilot checkpoint available'; return 1; }
	COVERAGE_OPERATION=rollback
	coverage_progress_write preparing 0 0 running preparing_rollback
	checkpoint=$(sed -n '1p' "$state_file"); case "$checkpoint" in "$PERSISTENT_DIR"/checkpoints/coverage-*) ;; *) return 1 ;; esac
	[ -d "$checkpoint" ] && [ ! -L "$checkpoint" ] || return 1
	coverage_progress_write policy 0 0 running restoring_policy
	for name in config.txt kernel_umount.txt sus_maps.txt sus_paths_loop.txt; do
		source="$checkpoint/$name"; destination="$PERSISTENT_DIR/$name"
		if [ -f "$source" ] && [ ! -L "$source" ]; then cp -p "$source" "${destination}.rollback.$$" || return 1; mv "${destination}.rollback.$$" "$destination" || return 1
		elif [ -f "$checkpoint/$name.absent" ]; then rm -f "$destination"; else return 1; fi
	done
	coverage_progress_write runtime 0 0 running restoring_runtime_policy
	coverage_apply_runtime >/dev/null 2>&1 || true
	coverage_progress_write complete 1 1 complete rollback_complete
	coverage_put result restored; coverage_put checkpoint "$checkpoint"; coverage_put reboot.required 1; coverage_put note runtime_rules_are_fully_cleared_on_reboot
}

coverage_autopilot_boot() {
	local state_dir="$PERSISTENT_DIR/state" log
	log="$state_dir/autopilot.boot.log"; [ "$(coverage_conf AUTOPILOT_SCAN_ON_BOOT 1)" = 1 ] || return 0
	mkdir -p "$state_dir" || return 1
	{
		printf '[autopilot] scan started %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
		coverage_scan >/dev/null || { printf '[autopilot] scan failed\n'; exit 1; }
		if [ "$(coverage_conf AUTOPILOT_APPLY_SAFE 1)" = 1 ]; then
			coverage_apply_safe || printf '[autopilot] safe apply incomplete\n'
			coverage_scan >/dev/null || printf '[autopilot] post-apply rescan failed\n'
		else
			printf '[autopilot] safe auto-apply disabled\n'
		fi
		printf '[autopilot] risky findings=%s (awaiting WebUI confirmation)\n' "$(coverage_property "$state_dir/coverage.report.txt" candidate.risky 0)"
	} > "${log}.tmp.$$" 2>&1
	chmod 600 "${log}.tmp.$$" 2>/dev/null; mv "${log}.tmp.$$" "$log"
}
