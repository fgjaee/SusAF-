#!/bin/sh

# Targeted coverage discovery for Sus'AF. This library is deliberately
# read-only while scanning: it reports exact, reviewable candidates and never
# turns a directory or every shared library into a hiding rule.

coverage_clean_value() {
	printf '%s' "$*" | tr '\r\n\t' '   ' | sed 's/[[:cntrl:]]//g'
}

coverage_put() {
	local key="$1"
	shift
	printf '%s=%s\n' "$key" "$(coverage_clean_value "$@")"
}

coverage_property() {
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

coverage_package_is_safe() {
	local package="$1"
	[ -n "$package" ] && [ "${#package}" -le 255 ] || return 1
	case "$package" in
		.*|*..*|*[!A-Za-z0-9._]*) return 1 ;;
	esac
	case "$package" in
		*.*) return 0 ;;
	esac
	return 1
}

coverage_path_is_safe() {
	local path="$1"
	[ -n "$path" ] && [ "${#path}" -lt 4096 ] || return 1
	case "$path" in
		/*) ;;
		*) return 1 ;;
	esac
	case "$path" in
		/|*/../*|*/..|*/./*|*/.|*#*|*[![:print:]]*) return 1 ;;
	esac
	return 0
}

coverage_map_path_is_allowed() {
	local path="$1"
	local roots root old_ifs
	roots="${SUSAF_COVERAGE_MAP_ROOTS:-/data/adb/modules:/data/adb/modules_update:/data/adb/ksu:/data/adb/ap}"
	old_ifs=$IFS
	IFS=:
	for root in $roots; do
		[ -n "$root" ] || continue
		case "$path" in
			"$root"/*) IFS=$old_ifs; return 0 ;;
		esac
	done
	IFS=$old_ifs
	return 1
}

coverage_path_is_curated() {
	local candidate="$1"
	local path
	for path in \
		/storage/emulated/0/Fox \
		/storage/emulated/0/TWRP \
		/data/recovery \
		/vendor/bin/install-recovery.sh \
		/system/bin/install-recovery.sh \
		/sdcard/TWRP \
		/sdcard/MT2 \
		/sdcard/APKTool \
		/sdcard/Apktool_M \
		/sdcard/AppManager \
		/sdcard/Android/data/io.github.muntashirakon.AppManager \
		/sdcard/Android/media/io.github.muntashirakon.AppManager \
		/data/media/0/TWRP \
		/data/media/0/MT2 \
		/data/media/0/AppManager \
		/data/media/0/Android/data/io.github.muntashirakon.AppManager \
		/data/media/0/Android/media/io.github.muntashirakon.AppManager \
		/data/media/0/Android/data/com.termux \
		/data/media/0/Android/media/com.termux \
		/data/media/0/Android/data/ru.maximoff.apktool \
		/data/media/0/Android/media/ru.maximoff.apktool \
		/data/media/0/Android/data/top.hookvip.pro \
		/data/media/0/Android/media/top.hookvip.pro \
		/data/local/tmp/main.jar; do
		[ "$candidate" = "$path" ] && return 0
	done
	return 1
}

coverage_list_contains() {
	local file="$1"
	local path="$2"
	awk -v path="$path" '
		{
			line=$0
			sub(/[[:space:]]*#.*/, "", line)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
			if (line == path) found=1
		}
		END { exit !found }
	' "$file" 2>/dev/null
}

coverage_list_count() {
	local file="$1"
	awk '
		{
			line=$0
			sub(/[[:space:]]*#.*/, "", line)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
			if (line != "") count++
		}
		END { print count + 0 }
	' "$file" 2>/dev/null
}

coverage_missing_count() {
	local file="$1"
	local line count
	count=0
	[ -f "$file" ] && [ ! -L "$file" ] || {
		printf '0\n'
		return
	}
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%%#*}
		line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		[ -n "$line" ] || continue
		coverage_path_is_safe "$line" || continue
		[ -e "$line" ] || count=$((count + 1))
	done < "$file"
	printf '%s\n' "$count"
}

coverage_schedule_status() {
	local file="$1"
	local name="$2"
	[ -f "$file" ] && [ ! -L "$file" ] || {
		printf 'missing\n'
		return
	}
	grep -Fqx "$name" "$file" 2>/dev/null && {
		printf 'enabled\n'
		return
	}
	grep -Fqx "!$name" "$file" 2>/dev/null && {
		printf 'disabled\n'
		return
	}
	printf 'not-scheduled\n'
}

coverage_add_candidate() {
	local output="$1"
	local kind="$2"
	local path="$3"
	local reason="$4"
	coverage_path_is_safe "$path" || return 1
	case "$path$reason" in
		*"$(printf '\t')"*) return 1 ;;
	esac
	printf '%s\t%s\t%s\n' "$kind" "$path" "$reason" >> "$output"
}

coverage_collect_curated_paths() {
	local output="$1"
	local list_file="$PERSISTENT_DIR/sus_paths_loop.txt"
	local path
	for path in \
		/storage/emulated/0/Fox \
		/storage/emulated/0/TWRP \
		/data/recovery \
		/vendor/bin/install-recovery.sh \
		/system/bin/install-recovery.sh \
		/sdcard/TWRP \
		/sdcard/MT2 \
		/sdcard/APKTool \
		/sdcard/Apktool_M \
		/sdcard/AppManager \
		/sdcard/Android/data/io.github.muntashirakon.AppManager \
		/sdcard/Android/media/io.github.muntashirakon.AppManager \
		/data/media/0/TWRP \
		/data/media/0/MT2 \
		/data/media/0/AppManager \
		/data/media/0/Android/data/io.github.muntashirakon.AppManager \
		/data/media/0/Android/media/io.github.muntashirakon.AppManager \
		/data/media/0/Android/data/com.termux \
		/data/media/0/Android/media/com.termux \
		/data/media/0/Android/data/ru.maximoff.apktool \
		/data/media/0/Android/media/ru.maximoff.apktool \
		/data/media/0/Android/data/top.hookvip.pro \
		/data/media/0/Android/media/top.hookvip.pro \
		/data/local/tmp/main.jar; do
		[ -e "$path" ] || continue
		coverage_list_contains "$list_file" "$path" && continue
		coverage_add_candidate "$output" sus_path_loop "$path" known_artifact
	done
}

coverage_collect_app_maps() {
	local package="$1"
	local output="$2"
	local pidof_bin="${SUSAF_PIDOF_BIN:-pidof}"
	local proc_root="${SUSAF_PROC_ROOT:-/proc}"
	local require_exists="${SUSAF_COVERAGE_REQUIRE_EXISTS:-1}"
	local raw_paths="${output}.maps.$$"
	local pids pid maps_file path

	COVERAGE_PROCESS_COUNT=0
	COVERAGE_PROCESS_IDS=none
	pids=$("$pidof_bin" "$package" 2>/dev/null) || pids=""
	[ -n "$pids" ] || return 0
	COVERAGE_PROCESS_IDS=""
	: > "$raw_paths"
	for pid in $pids; do
		case "$pid" in
			''|*[!0-9]*) continue ;;
		esac
		maps_file="$proc_root/$pid/maps"
		[ -f "$maps_file" ] && [ -r "$maps_file" ] || continue
		COVERAGE_PROCESS_COUNT=$((COVERAGE_PROCESS_COUNT + 1))
		COVERAGE_PROCESS_IDS="${COVERAGE_PROCESS_IDS}${COVERAGE_PROCESS_IDS:+,}$pid"
		awk '
			NF >= 6 {
				path=$6
				for (i=7; i<=NF; i++) path=path " " $i
				if (substr(path, 1, 1) == "/" && path !~ / \(deleted\)$/) print path
			}
		' "$maps_file" >> "$raw_paths"
	done
	[ -n "$COVERAGE_PROCESS_IDS" ] || COVERAGE_PROCESS_IDS=none

	sort -u "$raw_paths" 2>/dev/null | while IFS= read -r path || [ -n "$path" ]; do
		coverage_path_is_safe "$path" || continue
		coverage_map_path_is_allowed "$path" || continue
		[ "$require_exists" = 0 ] || [ -e "$path" ] || continue
		coverage_list_contains "$PERSISTENT_DIR/sus_maps.txt" "$path" && continue
		coverage_add_candidate "$output" sus_map "$path" mapped_module_file
	done
	rm -f "$raw_paths"
}

coverage_scan() {
	local package="${1:-}"
	local state_dir="$PERSISTENT_DIR/state"
	local output="${SUSAF_COVERAGE_REPORT:-$state_dir/coverage.report.txt}"
	local temp="${output}.tmp.$$"
	local candidates="${output}.candidates.$$"
	local unique="${output}.unique.$$"
	local mount_candidates="${output}.mounts.$$"
	local kernel_report="$state_dir/kernel_umount.report.txt"
	local kind path reason index candidate_count map_count path_count
	local mount_count missing_total

	if [ -n "$package" ] && ! coverage_package_is_safe "$package"; then
		echo "[x] invalid package name: $package"
		return 1
	fi

	umask 077
	mkdir -p "$state_dir" || return 1
	chmod 700 "$PERSISTENT_DIR" "$state_dir" 2>/dev/null
	trap 'rm -f "$temp" "$candidates" "$unique" "$mount_candidates"' EXIT HUP INT TERM
	: > "$candidates"
	: > "$mount_candidates"
	COVERAGE_PROCESS_COUNT=0
	COVERAGE_PROCESS_IDS=none

	coverage_collect_curated_paths "$candidates"
	[ -z "$package" ] || coverage_collect_app_maps "$package" "$candidates"
	awk -F '\t' '!seen[$1 FS $2]++' "$candidates" > "$unique"

	if command -v collect_kernel_umount_candidates >/dev/null 2>&1; then
		collect_kernel_umount_candidates "${SUSAF_MOUNTINFO:-/proc/1/mountinfo}" "$mount_candidates" 2>/dev/null || : > "$mount_candidates"
	fi
	mount_count=$(coverage_list_count "$mount_candidates")
	missing_total=$((
		$(coverage_missing_count "$PERSISTENT_DIR/sus_maps.txt") +
		$(coverage_missing_count "$PERSISTENT_DIR/sus_paths.txt") +
		$(coverage_missing_count "$PERSISTENT_DIR/sus_paths_loop.txt")
	))
	candidate_count=$(coverage_list_count "$unique")
	map_count=$(awk -F '\t' '$1 == "sus_map" { count++ } END { print count + 0 }' "$unique")
	path_count=$(awk -F '\t' '$1 == "sus_path_loop" { count++ } END { print count + 0 }' "$unique")

	{
		coverage_put schema 1
		coverage_put generated.at "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
		coverage_put generated.epoch "$(date +%s 2>/dev/null)"
		coverage_put mode "$([ -n "$package" ] && printf app || printf system)"
		coverage_put package "${package:-none}"
		coverage_put process.count "$COVERAGE_PROCESS_COUNT"
		coverage_put process.ids "$COVERAGE_PROCESS_IDS"
		coverage_put configured.sus_maps "$(coverage_list_count "$PERSISTENT_DIR/sus_maps.txt")"
		coverage_put configured.sus_paths "$(coverage_list_count "$PERSISTENT_DIR/sus_paths.txt")"
		coverage_put configured.sus_paths_loop "$(coverage_list_count "$PERSISTENT_DIR/sus_paths_loop.txt")"
		coverage_put configured.kernel_umount "$(coverage_list_count "$PERSISTENT_DIR/kernel_umount.txt")"
		coverage_put missing.sus_maps "$(coverage_missing_count "$PERSISTENT_DIR/sus_maps.txt")"
		coverage_put missing.sus_paths "$(coverage_missing_count "$PERSISTENT_DIR/sus_paths.txt")"
		coverage_put missing.sus_paths_loop "$(coverage_missing_count "$PERSISTENT_DIR/sus_paths_loop.txt")"
		coverage_put missing.total "$missing_total"
		coverage_put mount.candidates "$mount_count"
		coverage_put mount.failures "$(coverage_property "$kernel_report" failed 0)"
		coverage_put schedule.sus_maps "$(coverage_schedule_status "$PERSISTENT_DIR/scripts_postfs.txt" SusAF_apply-sus-maps.sh)"
		coverage_put schedule.sus_paths "$(coverage_schedule_status "$PERSISTENT_DIR/scripts_postfs.txt" SusAF_apply-sus-paths.sh)"
		coverage_put schedule.sus_paths_loop "$(coverage_schedule_status "$PERSISTENT_DIR/scripts_postfs.txt" SusAF_apply-sus-paths-loop.sh)"
		coverage_put legacy.resusfs "$([ -d "${LEGACY_RESUSFS_DIR:-/data/adb/ReSuSFS}" ] && printf present || printf absent)"
		coverage_put legacy.susfs4ksu "$([ -d "${LEGACY_SUSFS4KSU_DIR:-/data/adb/susfs4ksu}" ] && printf present || printf absent)"
		coverage_put candidate.count "$candidate_count"
		coverage_put candidate.sus_maps "$map_count"
		coverage_put candidate.sus_paths_loop "$path_count"
		index=0
		while IFS="$(printf '\t')" read -r kind path reason || [ -n "$kind$path$reason" ]; do
			[ -n "$kind" ] && [ -n "$path" ] || continue
			index=$((index + 1))
			coverage_put "candidate.$index.kind" "$kind"
			coverage_put "candidate.$index.path" "$path"
			coverage_put "candidate.$index.reason" "$reason"
			coverage_put "candidate.$index.status" review
		done < "$unique"
		coverage_put limitation.sus_map exact_file_backed_mappings_only
		coverage_put limitation.anonymous_maps not_supported
		coverage_put limitation.mount_namespace kernel_or_root_manager
		coverage_put limitation.tee_integrity outside_susaf
		coverage_put result ok
	} > "$temp" || return 1
	chmod 600 "$temp" 2>/dev/null
	mv "$temp" "$output" || return 1
	trap - EXIT HUP INT TERM
	rm -f "$candidates" "$unique" "$mount_candidates"
	cat "$output"
}

coverage_apply_ids() {
	local ids="$1"
	local report="${SUSAF_COVERAGE_REPORT:-$PERSISTENT_DIR/state/coverage.report.txt}"
	local stamp checkpoint maps_file paths_file maps_temp paths_temp provenance provenance_temp
	local package id kind path reason selected token added_maps added_paths duplicate_count
	local old_ifs

	case "$ids" in
		''|*[!0-9,]*) echo '[x] invalid candidate selection'; return 1 ;;
	esac
	[ -f "$report" ] && [ ! -L "$report" ] || {
		echo '[x] no trusted coverage scan is available'
		return 1
	}
	[ "$(coverage_property "$report" schema unknown)" = 1 ] || {
		echo '[x] unsupported coverage report'
		return 1
	}

	stamp=$(date +%Y%m%d_%H%M%S 2>/dev/null)
	checkpoint="$PERSISTENT_DIR/checkpoints/coverage-${stamp:-unknown}-$$"
	maps_file="$PERSISTENT_DIR/sus_maps.txt"
	paths_file="$PERSISTENT_DIR/sus_paths_loop.txt"
	maps_temp="${maps_file}.coverage.$$"
	paths_temp="${paths_file}.coverage.$$"
	provenance="$PERSISTENT_DIR/state/coverage.applied.log"
	provenance_temp="${provenance}.tmp.$$"
	package=$(coverage_property "$report" package none)
	selected=""
	added_maps=0
	added_paths=0
	duplicate_count=0

	umask 077
	mkdir -p "$PERSISTENT_DIR" "$PERSISTENT_DIR/state" || return 1
	[ ! -e "$maps_file" ] || { [ -f "$maps_file" ] && [ ! -L "$maps_file" ]; } || return 1
	[ ! -e "$paths_file" ] || { [ -f "$paths_file" ] && [ ! -L "$paths_file" ]; } || return 1
	[ -f "$maps_file" ] && cp "$maps_file" "$maps_temp" || : > "$maps_temp"
	[ -f "$paths_file" ] && cp "$paths_file" "$paths_temp" || : > "$paths_temp"

	old_ifs=$IFS
	IFS=,
	for token in $ids; do
		IFS=$old_ifs
		case "$token" in
			''|*[!0-9]*) rm -f "$maps_temp" "$paths_temp"; return 1 ;;
		esac
		case ",$selected," in
			*,"$token",*) duplicate_count=$((duplicate_count + 1)); IFS=,; continue ;;
		esac
		selected="${selected}${selected:+,}$token"
		id="$token"
		kind=$(coverage_property "$report" "candidate.$id.kind" "")
		path=$(coverage_property "$report" "candidate.$id.path" "")
		reason=$(coverage_property "$report" "candidate.$id.reason" "")
		coverage_path_is_safe "$path" || {
			rm -f "$maps_temp" "$paths_temp"
			echo "[x] rejected unsafe candidate: $id"
			return 1
		}
		[ -e "$path" ] || {
			rm -f "$maps_temp" "$paths_temp"
			echo "[x] candidate no longer exists: $path"
			return 1
		}
		case "$kind:$reason" in
			sus_map:mapped_module_file)
				coverage_map_path_is_allowed "$path" || {
					rm -f "$maps_temp" "$paths_temp"
					echo "[x] rejected out-of-scope map: $path"
					return 1
				}
				if ! coverage_list_contains "$maps_temp" "$path"; then
					printf '%s\n' "$path" >> "$maps_temp"
					added_maps=$((added_maps + 1))
				fi
				;;
			sus_path_loop:known_artifact)
				coverage_path_is_curated "$path" || {
					rm -f "$maps_temp" "$paths_temp"
					echo "[x] rejected unrecognized path: $path"
					return 1
				}
				if ! coverage_list_contains "$paths_temp" "$path"; then
					printf '%s\n' "$path" >> "$paths_temp"
					added_paths=$((added_paths + 1))
				fi
				;;
			*)
				rm -f "$maps_temp" "$paths_temp"
				echo "[x] rejected unsupported candidate: $id"
				return 1
				;;
		esac
		IFS=,
	done
	IFS=$old_ifs

	if [ "$added_maps" -eq 0 ] && [ "$added_paths" -eq 0 ]; then
		rm -f "$maps_temp" "$paths_temp"
		coverage_put result no-changes
		coverage_put duplicates "$duplicate_count"
		return 0
	fi

	mkdir -p "$checkpoint" || {
		rm -f "$maps_temp" "$paths_temp"
		return 1
	}
	chmod 700 "$PERSISTENT_DIR/checkpoints" "$checkpoint" 2>/dev/null
	[ -f "$maps_file" ] && cp -p "$maps_file" "$checkpoint/sus_maps.txt"
	[ -f "$paths_file" ] && cp -p "$paths_file" "$checkpoint/sus_paths_loop.txt"
	chmod 600 "$checkpoint"/*.txt 2>/dev/null

	chmod 600 "$maps_temp" "$paths_temp" 2>/dev/null
	mv "$maps_temp" "$maps_file" || return 1
	if ! mv "$paths_temp" "$paths_file"; then
		if [ -f "$checkpoint/sus_maps.txt" ]; then
			cp -p "$checkpoint/sus_maps.txt" "$maps_file"
		else
			rm -f "$maps_file"
		fi
		return 1
	fi
	[ -f "$provenance" ] && [ ! -L "$provenance" ] && cp "$provenance" "$provenance_temp" || : > "$provenance_temp"
	printf '%s\tpackage=%s\tids=%s\tmaps=%s\tpaths=%s\tcheckpoint=%s\n' \
		"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$package" "$selected" \
		"$added_maps" "$added_paths" "$checkpoint" >> "$provenance_temp"
	chmod 600 "$provenance_temp" 2>/dev/null
	mv "$provenance_temp" "$provenance"

	coverage_put result saved
	coverage_put added.sus_maps "$added_maps"
	coverage_put added.sus_paths_loop "$added_paths"
	coverage_put checkpoint "$checkpoint"
	coverage_put reboot.required 1
}
