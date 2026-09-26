#!/bin/sh

# Generate a compact, shell-native diagnostics snapshot. Values are normalized
# onto one line and no configured target paths or UserHub script bodies are
# included. The WebUI treats every value as text.

diagnostics_clean_value() {
	printf '%s' "$*" | tr '\r\n\t' '   ' | sed 's/[[:cntrl:]]//g'
}

diagnostics_put() {
	local key="$1"
	shift
	printf '%s=%s\n' "$key" "$(diagnostics_clean_value "$@")"
}

diagnostics_property() {
	local file="$1"
	local key="$2"
	local fallback="${3:-}"
	local value

	value=$(awk -F= -v key="$key" '
		$1 == key { value=substr($0, index($0, "=") + 1) }
		END { print value }
	' "$file" 2>/dev/null)
	[ -n "$value" ] || value="$fallback"
	printf '%s\n' "$value"
}

diagnostics_module_property() {
	diagnostics_property "$MODDIR/module.prop" "$1" "${2:-unknown}"
}

diagnostics_list_count() {
	local file="$1"
	awk '
		{ sub(/[[:space:]]*#.*/, "") }
		$0 !~ /^[[:space:]]*$/ { count++ }
		END { print count + 0 }
	' "$file" 2>/dev/null
}

diagnostics_invalid_count() {
	local file="$1"
	local kind="$2"
	awk -v kind="$kind" '
		{
			line=$0
			sub(/[[:space:]]*#.*/, "", line)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
			if (line == "") next
			count=split(line, field, /[[:space:]]+/)
			invalid=0
			if (kind == "path") invalid=(field[1] !~ /^\// || field[1] == "/" || field[1] ~ /(^|\/)\.\.?($|\/)/)
			else if (kind == "redirect") invalid=(count < 3 || field[1] !~ /^\// || field[2] !~ /^\//)
			if (invalid) bad++
		}
		END { print bad + 0 }
	' "$file" 2>/dev/null
}

diagnostics_report_count() {
	local file="$1"
	local prefix="$2"
	awk -v prefix="$prefix" 'index($0, prefix) == 1 { count++ } END { print count + 0 }' "$file" 2>/dev/null
}

diagnostics_file_size() {
	local file="$1"
	if [ -f "$file" ]; then
		wc -c < "$file" 2>/dev/null | tr -d '[:space:]'
	else
		printf '0\n'
	fi
}

diagnostics_boot_error_count() {
	local file="$1"
	local format="$2"
	awk -v format="$format" '
		function trim(value) {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			return value
		}
		function is_error_key(key) {
			return key == "verifiedbooterror" || key == "verifyerrorpart" || key ~ /\.verifiedbooterror$/ || key ~ /\.verifyerrorpart$/
		}
		format == "bootconfig" {
			key=$0
			sub(/[[:space:]]*=.*/, "", key)
			if (is_error_key(trim(key))) count++
			next
		}
		{
			for (i=1; i<=NF; i++) {
				key=$i
				sub(/=.*/, "", key)
				if (is_error_key(key)) count++
			}
		}
		END { print count + 0 }
	' "$file" 2>/dev/null
}

diagnostics_migration_status() {
	local marker="$1"
	local legacy="$2"
	if [ -f "$marker" ]; then
		printf 'complete\n'
	elif [ -d "$legacy" ]; then
		printf 'pending\n'
	else
		printf 'not-needed\n'
	fi
}

diagnostics_setting() {
	local key="$1"
	local settings_bin="${SUSAF_SETTINGS_BIN:-settings}"
	local value
	value=$("$settings_bin" get global "$key" 2>/dev/null) || value="unavailable"
	[ -n "$value" ] || value="unset"
	printf '%s\n' "$value"
}

diagnostics_prop() {
	local key="$1"
	local getprop_bin="${SUSAF_GETPROP_BIN:-getprop}"
	local value
	value=$("$getprop_bin" "$key" 2>/dev/null) || value="unavailable"
	[ -n "$value" ] || value="unset"
	printf '%s\n' "$value"
}

diagnostics_pidof() {
	local pidof_bin="${SUSAF_PIDOF_BIN:-pidof}"
	local value
	value=$("$pidof_bin" adbd 2>/dev/null) || value=""
	[ -n "$value" ] || value="none"
	printf '%s\n' "$value"
}

generate_diagnostics() {
	local state_dir="$PERSISTENT_DIR/state"
	local output="${SUSAF_DIAGNOSTICS_FILE:-$state_dir/diagnostics.properties}"
	local temp="$state_dir/.diagnostics.$$"
	local feature_report="$state_dir/kernel_umount.feature.txt"
	local mount_report="$state_dir/kernel_umount.report.txt"
	local adb_report="$state_dir/adb_mode.report.txt"
	local updater_report="$state_dir/updater.report.txt"
	local installer_report="$state_dir/installer.report.txt"
	local generated_boot="$state_dir/cmdline_or_bootconfig.generated.txt"
	local generated_mounts="$state_dir/mount_hiding.generated.txt"
	local postfs_report="$state_dir/stage.post-fs-data.properties"
	local boot_report="$state_dir/stage.boot-completed.properties"
	local coverage_report="$state_dir/coverage.report.txt"
	local coverage_verify="$state_dir/coverage.verify.txt"
	local coverage_progress="$state_dir/coverage.progress.txt"
	local mountinfo_file="${SUSAF_MOUNTINFO:-/proc/1/mountinfo}"
	local candidates="$state_dir/.diagnostics.mounts.$$"
	local boot_source boot_format live_error_count generated_error_count
	local module_status overall susfs_status susfs_version susfs_variant
	local features feature_count ksu_bin ksu_check ksu_current ksu_version kernel_mode
	local selinux_check selinux_current mount_filter_early mount_filter_late allow_broad mount_result mount_failures
	local persistent_owner persistent_mode proc_version uname_release uname_version
	local coverage_verify_result

	umask 077
	mkdir -p "$state_dir" || return 1
	chmod 700 "$PERSISTENT_DIR" "$state_dir" 2>/dev/null

	module_status=enabled
	[ -f "$MODDIR/disable" ] && module_status=disabled

	susfs_status=missing
	susfs_version=unavailable
	susfs_variant=unavailable
	features=""
	feature_count=0
	if [ -x "$SUSFS_BIN" ]; then
		susfs_version=$(susfs_version_value)
		susfs_variant=$(susfs_variant_value)
		features=$(susfs_features | tr ',;' '  ' | awk '{
			for (i = 1; i <= NF; i++) {
				token = $i
				gsub(/^[,;[:space:]]+|[,;[:space:]]+$/, "", token)
				if (token ~ /^CONFIG_KSU_SUSFS_[A-Z0-9_]+$/ && !seen[token]++) {
					value = value (value == "" ? "" : " | ") token
				}
			}
		} END { print value }')
		feature_count=$(susfs_features | tr ',;' '  ' | awk '{
			for (i = 1; i <= NF; i++) {
				token = $i
				gsub(/^[,;[:space:]]+|[,;[:space:]]+$/, "", token)
				if (token ~ /^CONFIG_KSU_SUSFS_[A-Z0-9_]+$/ && !seen[token]++) count++
			}
		} END { print count + 0 }')
		if [ -n "$susfs_version" ] && [ "$susfs_version" != "unavailable" ] && version_ge "$susfs_version" "$SUSFS_MIN_VERSION"; then
			susfs_status=active
		else
			susfs_status=unsupported
		fi
	fi
	[ -n "$susfs_version" ] || susfs_version=unavailable
	[ -n "$susfs_variant" ] || susfs_variant=unavailable
	[ -n "$features" ] || features=none

	if [ "$module_status" = disabled ]; then
		overall=disabled
	elif [ "$susfs_status" = active ]; then
		overall=healthy
	else
		overall=degraded
	fi

	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=""
	if [ -n "$ksu_bin" ]; then
		ksu_check=$(kernel_umount_check_feature "$ksu_bin")
		ksu_current=$("$ksu_bin" feature get kernel_umount 2>/dev/null | awk -F': ' '$1 == "Status" { print $2; exit }') || ksu_current="unknown"
		[ -n "$ksu_current" ] || ksu_current=unknown
		ksu_version=$("$ksu_bin" --version 2>/dev/null | sed -n '1p') || ksu_version="unavailable"
		[ -n "$ksu_version" ] || ksu_version=unavailable
	else
		ksu_check=unavailable
		ksu_current=unknown
		ksu_version=unavailable
	fi
	if [ -n "$ksu_bin" ]; then
		selinux_check=$("$ksu_bin" feature check selinux_hide 2>/dev/null) || selinux_check=unavailable
		case "$selinux_check" in
			supported|managed|unsupported) ;;
			*) selinux_check=unavailable ;;
		esac
		selinux_current=$("$ksu_bin" feature get selinux_hide 2>/dev/null | awk -F': ' '$1 == "Status" { print $2; exit }') || selinux_current=unknown
		[ -n "$selinux_current" ] || selinux_current=unknown
	else
		selinux_check=unavailable
		selinux_current=unknown
	fi
	kernel_mode=$(get_conf KERNEL_UMOUNT_MODE enabled "$PERSISTENT_DIR/config.txt")
	mount_filter_early=$(get_conf HIDE_SUS_MNTS_NON_SU 0 "$PERSISTENT_DIR/config.txt")
	mount_filter_late=$(get_conf HIDE_SUS_MNTS_LATE 1 "$PERSISTENT_DIR/config.txt")
	allow_broad=$(get_conf ALLOW_BROAD_KERNEL_UMOUNT 0 "$PERSISTENT_DIR/config.txt")
	mount_result=$(diagnostics_property "$mount_report" result not-recorded)
	mount_failures=$(diagnostics_property "$mount_report" failed "")
	if [ -z "$mount_failures" ]; then
		mount_failures=$(awk '/^add=.*\|failed(\||$)/ { count++ } END { print count + 0 }' "$mount_report" 2>/dev/null)
	fi
	if [ "$module_status" != disabled ] && [ "$kernel_mode" = enabled ]; then
		case "$ksu_check" in
			supported|managed) ;;
			*) overall=degraded ;;
		esac
		case "$mount_failures" in
			''|*[!0-9]*) overall=degraded ;;
			*) [ "$mount_failures" -eq 0 ] || overall=degraded ;;
		esac
		[ "$mount_result" = ok ] || overall=degraded
	fi
	case "$mount_filter_late" in
	0|1) ;;
	*) [ "$module_status" = disabled ] || overall=degraded ;;
	esac
	case "$allow_broad" in
	0) ;;
	*) [ "$module_status" = disabled ] || overall=degraded ;;
	esac
	coverage_verify_result=$(diagnostics_property "$coverage_verify" result not-run)
	[ "$coverage_verify_result" != attention ] || [ "$module_status" = disabled ] || overall=degraded

	: > "$candidates"
	collect_kernel_umount_candidates "$mountinfo_file" "$candidates" 2>/dev/null || : > "$candidates"

	if [ -s "${SUSAF_BOOTCONFIG_SOURCE:-/proc/bootconfig}" ]; then
		boot_source="${SUSAF_BOOTCONFIG_SOURCE:-/proc/bootconfig}"
		boot_format=bootconfig
	else
		boot_source="${SUSAF_CMDLINE_SOURCE:-/proc/cmdline}"
		boot_format=cmdline
	fi
	live_error_count=$(diagnostics_boot_error_count "$boot_source" "$boot_format") || live_error_count=0
	generated_error_count=$(diagnostics_boot_error_count "$generated_boot" "$boot_format") || generated_error_count=0

	persistent_owner=$(stat -c '%u:%g' "$PERSISTENT_DIR" 2>/dev/null) || persistent_owner=unavailable
	persistent_mode=$(stat -c '%a' "$PERSISTENT_DIR" 2>/dev/null) || persistent_mode=unavailable
	proc_version=$(sed -n '1p' "${SUSAF_PROC_VERSION:-/proc/version}" 2>/dev/null) || proc_version=unavailable
	uname_release=$(uname -r 2>/dev/null) || uname_release=unavailable
	uname_version=$(uname -v 2>/dev/null) || uname_version=unavailable

	{
		diagnostics_put schema 1
		diagnostics_put generated.at "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
		diagnostics_put generated.epoch "$(date +%s 2>/dev/null)"
		diagnostics_put overall.status "$overall"
		diagnostics_put module.id "$(diagnostics_module_property id susaf)"
		diagnostics_put module.name "$(diagnostics_module_property name "Sus'AF")"
		diagnostics_put module.version "$(diagnostics_module_property version unknown)"
		diagnostics_put module.version_code "$(diagnostics_module_property versionCode unknown)"
		diagnostics_put module.status "$module_status"
		diagnostics_put persistent.owner "$persistent_owner"
		diagnostics_put persistent.mode "$persistent_mode"

		diagnostics_put susfs.status "$susfs_status"
		diagnostics_put susfs.binary "$SUSFS_BIN"
		diagnostics_put susfs.version "$susfs_version"
		diagnostics_put susfs.variant "$susfs_variant"
		diagnostics_put susfs.feature_count "$feature_count"
		diagnostics_put susfs.features "$features"
		diagnostics_put susfs.capability_source "runtime"

		diagnostics_put kernelsu.version "$ksu_version"
		diagnostics_put kernelsu.binary "${ksu_bin:-unavailable}"
		diagnostics_put selinux_hide.support "$selinux_check"
		diagnostics_put selinux_hide.current "$selinux_current"
		diagnostics_put mount_filter.early "$mount_filter_early"
		diagnostics_put mount_filter.late "$mount_filter_late"
		diagnostics_put kernel_umount.configured "$kernel_mode"
		diagnostics_put kernel_umount.auto "$(get_conf AUTO_KERNEL_UMOUNT 1 "$PERSISTENT_DIR/config.txt")"
		diagnostics_put kernel_umount.allow_broad "$allow_broad"
		diagnostics_put kernel_umount.support "$ksu_check"
		diagnostics_put kernel_umount.current "$ksu_current"
		diagnostics_put kernel_umount.feature_result "$(diagnostics_property "$feature_report" result not-recorded)"
		diagnostics_put kernel_umount.mount_result "$mount_result"
		diagnostics_put kernel_umount.candidates "$(diagnostics_list_count "$candidates")"
		diagnostics_put kernel_umount.added "$(diagnostics_property "$mount_report" added 0)"
		diagnostics_put kernel_umount.existing "$(diagnostics_property "$mount_report" existing 0)"
		diagnostics_put kernel_umount.inactive "$(diagnostics_property "$mount_report" inactive 0)"
		diagnostics_put kernel_umount.broad_skipped "$(diagnostics_property "$mount_report" broad_skipped 0)"
		diagnostics_put kernel_umount.skipped "$(diagnostics_report_count "$mount_report" 'skip=')"
		diagnostics_put kernel_umount.rejected "$(diagnostics_property "$mount_report" rejected 0)"
		diagnostics_put kernel_umount.failures "$mount_failures"
		diagnostics_put kernel_umount.notify "$(diagnostics_property "$mount_report" notify not-recorded)"

		diagnostics_put targets.sus_paths "$(diagnostics_list_count "$PERSISTENT_DIR/sus_paths.txt")"
		diagnostics_put targets.sus_paths_malformed "$(diagnostics_invalid_count "$PERSISTENT_DIR/sus_paths.txt" path)"
		diagnostics_put targets.sus_paths_loop "$(diagnostics_list_count "$PERSISTENT_DIR/sus_paths_loop.txt")"
		diagnostics_put targets.sus_paths_loop_malformed "$(diagnostics_invalid_count "$PERSISTENT_DIR/sus_paths_loop.txt" path)"
		diagnostics_put targets.sus_maps "$(diagnostics_list_count "$PERSISTENT_DIR/sus_maps.txt")"
		diagnostics_put targets.sus_maps_malformed "$(diagnostics_invalid_count "$PERSISTENT_DIR/sus_maps.txt" path)"
		diagnostics_put targets.kstat "$(diagnostics_list_count "$PERSISTENT_DIR/kstat_paths.txt")"
		diagnostics_put targets.kstat_malformed "$(diagnostics_invalid_count "$PERSISTENT_DIR/kstat_paths.txt" path)"
		diagnostics_put targets.open_redirect "$(diagnostics_list_count "$PERSISTENT_DIR/open_redirect.txt")"
		diagnostics_put targets.open_redirect_malformed "$(diagnostics_invalid_count "$PERSISTENT_DIR/open_redirect.txt" redirect)"
		diagnostics_put targets.kernel_umount "$(diagnostics_list_count "$PERSISTENT_DIR/kernel_umount.txt")"
		diagnostics_put targets.kernel_umount_malformed "$(diagnostics_invalid_count "$PERSISTENT_DIR/kernel_umount.txt" path)"
		diagnostics_put targets.pty "$(awk '{ sub(/[[:space:]]*#.*/, ""); if ($1 ~ /^\/dev\/pts\//) seen[$1]=1 } END { for (path in seen) count++; print count + 0 }' "$PERSISTENT_DIR/sus_paths.txt" "$PERSISTENT_DIR/sus_paths_loop.txt" 2>/dev/null)"
		diagnostics_put targets.mount_hiding_generated "$(diagnostics_list_count "$generated_mounts")"

		diagnostics_put autopilot.report "$([ -s "$coverage_report" ] && printf present || printf missing)"
		diagnostics_put autopilot.generated_at "$(diagnostics_property "$coverage_report" generated.at not-recorded)"
		diagnostics_put autopilot.mode "$(diagnostics_property "$coverage_report" mode not-recorded)"
		diagnostics_put autopilot.processes "$(diagnostics_property "$coverage_report" process.count 0)"
		diagnostics_put autopilot.mount_namespaces "$(diagnostics_property "$coverage_report" mount.namespaces 0)"
		diagnostics_put autopilot.high_id_namespaces "$(diagnostics_property "$coverage_report" mount.high_id_namespaces 0)"
		diagnostics_put autopilot.candidates "$(diagnostics_property "$coverage_report" candidate.count 0)"
		diagnostics_put autopilot.safe_candidates "$(diagnostics_property "$coverage_report" candidate.safe 0)"
		diagnostics_put autopilot.risky_candidates "$(diagnostics_property "$coverage_report" candidate.risky 0)"
		diagnostics_put autopilot.stale_configured "$(diagnostics_property "$coverage_report" missing.total 0)"
		diagnostics_put autopilot.verification_result "$coverage_verify_result"
		diagnostics_put autopilot.verification_at "$(diagnostics_property "$coverage_verify" generated.at not-recorded)"
		diagnostics_put autopilot.verification_stale "$(diagnostics_property "$coverage_verify" missing.configured 0)"
		diagnostics_put autopilot.verification_mount_failures "$(diagnostics_property "$coverage_verify" mount.failures 0)"
		diagnostics_put autopilot.verification_remaining "$(diagnostics_property "$coverage_verify" remaining.candidates 0)"
		diagnostics_put autopilot.verification_runtime_available "$(diagnostics_property "$coverage_verify" runtime.available not-recorded)"
		diagnostics_put autopilot.verification_feature_result "$(diagnostics_property "$coverage_verify" kernel_umount.feature_result not-recorded)"
		diagnostics_put autopilot.verification_mount_result "$(diagnostics_property "$coverage_verify" kernel_umount.mount_result not-recorded)"
		diagnostics_put autopilot.progress_operation "$(diagnostics_property "$coverage_progress" operation none)"
		diagnostics_put autopilot.progress_status "$(diagnostics_property "$coverage_progress" status idle)"
		diagnostics_put autopilot.progress_stage "$(diagnostics_property "$coverage_progress" stage none)"
		diagnostics_put autopilot.progress_current "$(diagnostics_property "$coverage_progress" current 0)"
		diagnostics_put autopilot.progress_total "$(diagnostics_property "$coverage_progress" total 0)"
		diagnostics_put autopilot.progress_updated_epoch "$(diagnostics_property "$coverage_progress" updated.epoch 0)"

		diagnostics_put boot.source "$boot_source"
		diagnostics_put boot.format "$boot_format"
		diagnostics_put boot.live_error_keys "$live_error_count"
		diagnostics_put boot.generated "$([ -s "$generated_boot" ] && printf present || printf missing)"
		diagnostics_put boot.generated_bytes "$(diagnostics_file_size "$generated_boot")"
		diagnostics_put boot.generated_error_keys "$generated_error_count"
		diagnostics_put proc.version "$proc_version"
		diagnostics_put uname.release "$uname_release"
		diagnostics_put uname.version "$uname_version"

		diagnostics_put adb.configured "$(get_conf ADB_MODE unchanged "$PERSISTENT_DIR/config.txt")"
		diagnostics_put adb.last_result "$(diagnostics_property "$adb_report" result not-recorded)"
		diagnostics_put adb.developer_options "$(diagnostics_setting development_settings_enabled)"
		diagnostics_put adb.usb_debugging "$(diagnostics_setting adb_enabled)"
		diagnostics_put adb.wifi_debugging "$(diagnostics_setting adb_wifi_enabled)"
		diagnostics_put adb.service "$(diagnostics_prop init.svc.adbd)"
		diagnostics_put adb.pid "$(diagnostics_pidof)"
		diagnostics_put adb.usb_config "$(diagnostics_prop sys.usb.config)"
		diagnostics_put adb.usb_state "$(diagnostics_prop sys.usb.state)"
		diagnostics_put adb.persist_usb_config "$(diagnostics_prop persist.sys.usb.config)"

		diagnostics_put stage.postfs.status "$(diagnostics_property "$postfs_report" status not-recorded)"
		diagnostics_put stage.postfs.started "$(diagnostics_property "$postfs_report" started_at unknown)"
		diagnostics_put stage.postfs.finished "$(diagnostics_property "$postfs_report" finished_at unknown)"
		diagnostics_put stage.postfs.duration "$(diagnostics_property "$postfs_report" duration_seconds unknown)"
		diagnostics_put stage.postfs.exit "$(diagnostics_property "$postfs_report" exit_status unknown)"
		diagnostics_put stage.boot.status "$(diagnostics_property "$boot_report" status not-recorded)"
		diagnostics_put stage.boot.started "$(diagnostics_property "$boot_report" started_at unknown)"
		diagnostics_put stage.boot.finished "$(diagnostics_property "$boot_report" finished_at unknown)"
		diagnostics_put stage.boot.duration "$(diagnostics_property "$boot_report" duration_seconds unknown)"
		diagnostics_put stage.boot.exit "$(diagnostics_property "$boot_report" exit_status unknown)"

		diagnostics_put migration.resusfs "$(diagnostics_migration_status "$state_dir/migrations/v1-resusfs.done" "$LEGACY_RESUSFS_DIR")"
		diagnostics_put migration.susfs4ksu "$(diagnostics_migration_status "$state_dir/migrations/v1-susfs4ksu.done" "$LEGACY_SUSFS4KSU_DIR")"
		diagnostics_put installer.last_result "$(diagnostics_property "$installer_report" result not-recorded)"
		diagnostics_put installer.checkpoint "$(diagnostics_property "$installer_report" checkpoint not-recorded)"
		diagnostics_put installer.config_keys_added "$(diagnostics_property "$installer_report" config_keys_added 0)"
		diagnostics_put installer.schedule_repairs "$(diagnostics_property "$installer_report" schedule_repairs 0)"
		diagnostics_put installer.builtin_updates_pending "$(diagnostics_property "$installer_report" builtin_updates_pending 0)"
		diagnostics_put updater.source_repository "$(diagnostics_property "$updater_report" source_repository not-recorded)"
		diagnostics_put updater.source_commit "$(diagnostics_property "$updater_report" source_commit not-recorded)"
		diagnostics_put updater.verification "$(diagnostics_property "$updater_report" verification not-recorded)"
		diagnostics_put updater.expected_sha256 "$(diagnostics_property "$updater_report" expected_sha256 not-recorded)"
		diagnostics_put updater.actual_sha256 "$(diagnostics_property "$updater_report" actual_sha256 not-recorded)"
		diagnostics_put updater.installed_sha256 "$(diagnostics_property "$updater_report" installed_sha256 not-recorded)"
		diagnostics_put updater.candidate_version "$(diagnostics_property "$updater_report" candidate_version not-recorded)"
		diagnostics_put updater.candidate_variant "$(diagnostics_property "$updater_report" candidate_variant not-recorded)"
		diagnostics_put updater.backup "$(diagnostics_property "$updater_report" backup not-recorded)"
		diagnostics_put updater.rollback "$(diagnostics_property "$updater_report" rollback not-recorded)"
		diagnostics_put updater.last_result "$(diagnostics_property "$updater_report" result not-recorded)"
	} > "$temp" || {
		rm -f "$temp" "$candidates"
		return 1
	}

	chmod 600 "$temp" 2>/dev/null
	mv "$temp" "$output" || {
		rm -f "$temp" "$candidates"
		return 1
	}
	rm -f "$candidates"
	printf '[+] diagnostics snapshot: %s\n' "$output"
}

show_diagnostics() {
	local output="${SUSAF_DIAGNOSTICS_FILE:-$PERSISTENT_DIR/state/diagnostics.properties}"
	generate_diagnostics >/dev/null || return 1
	cat "$output"
}
