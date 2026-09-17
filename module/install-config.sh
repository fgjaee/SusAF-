#!/bin/sh

# Non-interactive, preservation-first installation of packaged configuration.
# Existing user configuration and UserHub schedules always win.

_install_note() {
	if command -v ui_print >/dev/null 2>&1; then
		ui_print "$1"
	else
		echo "$1"
	fi
}

INSTALL_CONFIG_KEYS_ADDED=0
INSTALL_SCHEDULE_REPAIRS=0
INSTALL_BUILTIN_UPDATES_PENDING=0
INSTALL_CHECKPOINT=not-needed

installer_prepare_report() {
	local state_dir="$PERSISTENT_DIR/state"
	INSTALLER_REPORT_FILE="${SUSAF_INSTALLER_REPORT:-$state_dir/installer.report.txt}"
	INSTALLER_REPORT_TEMP="${INSTALLER_REPORT_FILE}.tmp.$$"
	umask 077
	mkdir -p "$state_dir" || return 1
	chmod 700 "$PERSISTENT_DIR" "$state_dir" 2>/dev/null
	: > "$INSTALLER_REPORT_TEMP" || return 1
	chmod 600 "$INSTALLER_REPORT_TEMP" 2>/dev/null
}

installer_finish_report() {
	local result="$1"
	[ -n "${INSTALLER_REPORT_TEMP:-}" ] || return 0
	printf 'checkpoint=%s\n' "$INSTALL_CHECKPOINT" >> "$INSTALLER_REPORT_TEMP"
	printf 'config_keys_added=%s\n' "$INSTALL_CONFIG_KEYS_ADDED" >> "$INSTALLER_REPORT_TEMP"
	printf 'schedule_repairs=%s\n' "$INSTALL_SCHEDULE_REPAIRS" >> "$INSTALLER_REPORT_TEMP"
	printf 'builtin_updates_pending=%s\n' "$INSTALL_BUILTIN_UPDATES_PENDING" >> "$INSTALLER_REPORT_TEMP"
	printf 'result=%s\n' "$result" >> "$INSTALLER_REPORT_TEMP"
	mv "$INSTALLER_REPORT_TEMP" "$INSTALLER_REPORT_FILE"
}

checkpoint_existing_install() {
	local stamp root rel src dst file copied
	local existing=0

	for rel in config.txt kernel_umount.txt kstat_paths.txt open_redirect.txt \
		scripts_postfs.txt scripts_bootcompleted.txt scripts_cron.txt sus_maps.txt \
		sus_paths.txt sus_paths_loop.txt uname.txt cmdline_or_bootconfig.txt scripts .webui_config; do
		[ -e "$PERSISTENT_DIR/$rel" ] && existing=1
	done
	[ "$existing" -eq 1 ] || return 0

	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	root="$PERSISTENT_DIR/migration/installer-$stamp-$$/pre-upgrade"
	mkdir -p "$root" || return 1
	chmod 700 "$PERSISTENT_DIR/migration" "$(dirname "$root")" "$root" 2>/dev/null
	copied=0

	for rel in config.txt kernel_umount.txt kstat_paths.txt open_redirect.txt \
		scripts_postfs.txt scripts_bootcompleted.txt scripts_cron.txt sus_maps.txt \
		sus_paths.txt sus_paths_loop.txt uname.txt cmdline_or_bootconfig.txt; do
		src="$PERSISTENT_DIR/$rel"
		[ -e "$src" ] || continue
		[ -f "$src" ] && [ ! -L "$src" ] || {
			_install_note "[!] Refusing unsafe pre-upgrade source: $src"
			return 1
		}
		dst="$root/$rel"
		mkdir -p "$(dirname "$dst")" || return 1
		cp -p "$src" "$dst" || return 1
		chmod 600 "$dst" 2>/dev/null
		copied=$((copied + 1))
	done

	for rel in scripts .webui_config; do
		src="$PERSISTENT_DIR/$rel"
		[ -e "$src" ] || continue
		[ -d "$src" ] && [ ! -L "$src" ] || {
			_install_note "[!] Refusing unsafe pre-upgrade directory: $src"
			return 1
		}
		if find "$src" ! -type d ! -type f -print -quit 2>/dev/null | grep -q .; then
			_install_note "[!] Refusing special file in pre-upgrade directory: $src"
			return 1
		fi
		find "$src" -type f 2>/dev/null | while IFS= read -r file; do
			dst="$root/${file#"$PERSISTENT_DIR"/}"
			mkdir -p "$(dirname "$dst")" || exit 1
			cp -p "$file" "$dst" || exit 1
			chmod 600 "$dst" 2>/dev/null
		done || return 1
	done

	INSTALL_CHECKPOINT="$root"
	_install_note "[+] Saved a pre-upgrade configuration checkpoint: $root"
}

normalize_stage_schedule() {
	local dst="$1"
	local tmp="${dst}.normalize.$$"
	awk '
		{
			lines[NR]=$0
			if ($0 ~ /^![^!]/) disabled[substr($0, 2)]=1
		}
		END {
			for (i=1; i<=NR; i++) {
				line=lines[i]
				if (line == "" || line ~ /^[[:space:]]*#/) { print line; continue }
				if (line ~ /^![^!]/) {
					key=substr(line, 2)
					if (!seen[key]++) print "!" key
					continue
				}
				key=line
				if (disabled[key]) continue
				if (!seen[key]++) print line
			}
		}
	' "$dst" > "$tmp" || {
		rm -f "$tmp"
		return 1
	}
	if cmp -s "$dst" "$tmp"; then
		rm -f "$tmp"
	else
		mv "$tmp" "$dst" || return 1
		INSTALL_SCHEDULE_REPAIRS=$((INSTALL_SCHEDULE_REPAIRS + 1))
		_install_note "[+] Normalized duplicate stage entries in $(basename "$dst")"
	fi
	chmod 600 "$dst" 2>/dev/null
}

merge_schedule_defaults() {
	local src="$1"
	local dst="$2"

	[ -f "$src" ] && [ ! -L "$src" ] || return 0
	mkdir -p "$(dirname "$dst")" || return 1
	if [ ! -e "$dst" ]; then
		cp "$src" "$dst" || return 1
		chmod 600 "$dst" 2>/dev/null
		_install_note "[+] Installed default schedule: $(basename "$dst")"
		return 0
	fi
	[ -f "$dst" ] && [ ! -L "$dst" ] || {
		_install_note "[!] Refusing to replace non-regular schedule: $dst"
		return 1
	}

	# Existing schedules are user state. Do not silently re-enable packaged
	# tasks that the user removed. A disabled (!name) entry wins over a bare
	# duplicate so upgrades cannot flip it back on.
	normalize_stage_schedule "$dst" || return 1
	_install_note "[+] Preserved existing schedule without adding packaged defaults: $(basename "$dst")"
}

merge_config_defaults() {
	local src="$1"
	local dst="$2"
	local tmp key line added

	[ -f "$src" ] && [ ! -L "$src" ] || return 0
	mkdir -p "$(dirname "$dst")" || return 1
	if [ ! -e "$dst" ]; then
		cp "$src" "$dst" || return 1
		chmod 600 "$dst" 2>/dev/null
		_install_note "[+] Installed default config: $(basename "$dst")"
		return 0
	fi
	[ -f "$dst" ] && [ ! -L "$dst" ] || return 1
	tmp="${dst}.defaults.$$"
	cp "$dst" "$tmp" || return 1
	added=0
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			*=*) ;;
			*) continue ;;
		esac
		key=${line%%=*}
		case "$key" in
			''|[0-9]*|*[!A-Za-z0-9_]*) continue ;;
		esac
		if ! grep -q "^${key}=" "$tmp" 2>/dev/null; then
			printf '%s\n' "$line" >> "$tmp" || {
				rm -f "$tmp"
				return 1
			}
			added=$((added + 1))
		fi
	done < "$src"
	chmod 600 "$tmp" 2>/dev/null
	mv "$tmp" "$dst" || return 1
	INSTALL_CONFIG_KEYS_ADDED=$((INSTALL_CONFIG_KEYS_ADDED + added))
	_install_note "[+] Preserved config.txt; added $added new default key(s)"
}

install_packaged_builtins() {
	local src_dir="$1"
	local dst_dir="$2"
	local state_root baseline_root updates_root list_file src name dst baseline pending

	[ -d "$src_dir" ] && [ ! -L "$src_dir" ] || return 0
	state_root="$PERSISTENT_DIR/state"
	baseline_root="$state_root/builtin-baselines"
	updates_root="$state_root/builtin-updates"
	list_file="$state_root/.builtin-list.$$"
	mkdir -p "$dst_dir" || return 1
	mkdir -p "$baseline_root" "$updates_root" || return 1
	chmod 700 "$state_root" "$baseline_root" "$updates_root" 2>/dev/null
	find "$src_dir" -type f -name '*.sh' 2>/dev/null > "$list_file" || return 1
	while IFS= read -r src; do
		name="${src#"$src_dir"/}"
		case "$name" in
			*.sh) ;;
			*) _install_note "[!] Rejected unexpected built-in path: $name"; return 1 ;;
		esac
		dst="$dst_dir/$name"
		baseline="$baseline_root/$name"
		pending="$updates_root/$name"
		mkdir -p "$(dirname "$dst")" || return 1
		mkdir -p "$(dirname "$baseline")" "$(dirname "$pending")" || return 1
		if [ ! -e "$dst" ]; then
			cp "$src" "$dst" || return 1
			cp "$src" "$baseline" || return 1
			rm -f "$pending"
			chmod 755 "$dst" 2>/dev/null
			chmod 600 "$baseline" 2>/dev/null
			_install_note "[+] Installed built-in: $name"
			continue
		else
			[ -f "$dst" ] && [ ! -L "$dst" ] || {
				_install_note "[!] Refusing to replace non-regular built-in: $dst"
				return 1
			}
			if cmp -s "$src" "$dst"; then
				cp "$src" "$baseline" || return 1
				rm -f "$pending"
				chmod 755 "$dst" 2>/dev/null
				chmod 600 "$baseline" 2>/dev/null
				continue
			fi
			if [ -f "$baseline" ] && [ ! -L "$baseline" ] && cmp -s "$dst" "$baseline"; then
				cp "$src" "$dst" || return 1
				cp "$src" "$baseline" || return 1
				rm -f "$pending"
				chmod 755 "$dst" 2>/dev/null
				chmod 600 "$baseline" 2>/dev/null
				_install_note "[+] Updated unmodified built-in: $name"
				continue
			fi
		fi

		# No trustworthy baseline, or the live script differs from it: keep the
		# user's file and stage the packaged replacement for manual review.
		cp "$src" "$pending" || return 1
		chmod 600 "$pending" 2>/dev/null
		INSTALL_BUILTIN_UPDATES_PENDING=$((INSTALL_BUILTIN_UPDATES_PENDING + 1))
		_install_note "[*] Preserved edited built-in; packaged update staged: $name"
	done < "$list_file"
	rm -f "$list_file"
}

install_missing_defaults() {
	local src_dir="$1"
	local dst_dir="$2"
	local src rel dst

	[ -d "$src_dir" ] && [ ! -L "$src_dir" ] || return 0
	find "$src_dir" -type f ! -path "$src_dir/scripts/*" \
		! -name 'scripts_postfs.txt' ! -name 'scripts_bootcompleted.txt' 2>/dev/null |
	while IFS= read -r src; do
		rel="${src#"$src_dir"/}"
		[ "$rel" != config.txt ] || continue
		dst="$dst_dir/$rel"
		if [ ! -e "$dst" ]; then
			mkdir -p "$(dirname "$dst")" || return 1
			cp "$src" "$dst" || return 1
			chmod 600 "$dst" 2>/dev/null
			_install_note "[+] Installed default config: $rel"
		elif [ ! -f "$dst" ] || [ -L "$dst" ]; then
			_install_note "[!] Refusing non-regular config destination: $dst"
			return 1
		else
			_install_note "[+] Preserved existing config: $rel"
		fi
	done
}

repair_oversized_cmdline_bootconfig() {
	local template="$1"
	local config="$PERSISTENT_DIR/cmdline_or_bootconfig.txt"
	local limit="${SUSAF_BOOTCONFIG_MAX_BYTES:-8191}"
	local size stamp backup temp

	[ -e "$config" ] || return 0
	[ -f "$config" ] && [ ! -L "$config" ] || {
		_install_note "[!] Refusing non-regular cmdline/bootconfig config: $config"
		return 1
	}
	size=$(wc -c < "$config" 2>/dev/null | tr -d '[:space:]')
	case "$size" in
		''|*[!0-9]*) _install_note "[!] Could not measure $config"; return 1 ;;
	esac
	[ "$size" -gt "$limit" ] || return 0
	[ -f "$template" ] && [ ! -L "$template" ] || {
		_install_note "[!] Packaged cmdline/bootconfig template is unavailable"
		return 1
	}

	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	backup="$PERSISTENT_DIR/migration/installer-$stamp-$$/repaired-config/cmdline_or_bootconfig.txt"
	temp="${config}.repair.$$"
	mkdir -p "$(dirname "$backup")" || return 1
	cp -p "$config" "$backup" || return 1
	cp "$template" "$temp" || return 1
	chmod 600 "$backup" "$temp" 2>/dev/null
	mv "$temp" "$config" || {
		rm -f "$temp"
		return 1
	}
	_install_note "[+] Archived oversized cmdline/bootconfig data ($size bytes) and restored a clean template"
}

remove_generated_kstat_entries() {
	local config="$PERSISTENT_DIR/kstat_paths.txt"
	local stamp backup temp

	[ -e "$config" ] || return 0
	[ -f "$config" ] && [ ! -L "$config" ] || {
		_install_note "[!] Refusing non-regular Sus Kstat config: $config"
		return 1
	}
	temp="${config}.repair.$$"
	awk '
	function generated_module_entry(    i) {
		if ($1 != "/data/adb/ReSuSFS" && $1 != "/data/adb/SusAF") return 0
		if (NF != 13) return 0
		for (i = 2; i <= NF; i++) if ($i != "default") return 0
		return 1
	}
	function legacy_hosts_entry() {
		return NF == 13 && $1 == "/system/etc/hosts" && $2 == "100" &&
			$3 == "default" && $4 == "default" && $5 == "64" &&
			$6 == "default" && $7 == "default" && $8 == "default" &&
			$9 == "default" && $10 == "default" && $11 == "default" &&
			$12 == "1" && $13 == "4096"
	}
	!generated_module_entry() && !legacy_hosts_entry() { print }
	' "$config" > "$temp" || {
		rm -f "$temp"
		return 1
	}
	if cmp -s "$config" "$temp"; then
		rm -f "$temp"
		return 0
	fi

	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	backup="$PERSISTENT_DIR/migration/installer-$stamp-$$/repaired-config/kstat_paths.txt"
	mkdir -p "$(dirname "$backup")" || { rm -f "$temp"; return 1; }
	cp -p "$config" "$backup" || { rm -f "$temp"; return 1; }
	chmod 600 "$backup" "$temp" 2>/dev/null
	mv "$temp" "$config" || { rm -f "$temp"; return 1; }
	_install_note "[+] Archived and removed stale generated Kstat entries"
}

_rewrite_legacy_builtin_schedule() {
	local schedule="$1"
	local backup_root="$2"
	local staged next suffix

	[ -e "$schedule" ] || return 0
	[ -f "$schedule" ] && [ ! -L "$schedule" ] || return 1
	grep -Fq 'ReSuSFS_' "$schedule" 2>/dev/null || return 0
	staged="${schedule}.rename.$$"
	cp "$schedule" "$staged" || return 1
	for suffix in \
		apply-cmdline-bootconfig apply-kstat-add apply-ksu-settings apply-uname \
		apply-mount-hiding apply-props apply-settings apply-sus-maps \
		apply-sus-paths-loop apply-sus-paths cleanup-markers; do
		next="${staged}.next"
		sed "s/ReSuSFS_${suffix}\.sh/SusAF_${suffix}.sh/g" "$staged" > "$next" || {
			rm -f "$staged" "$next"
			return 1
		}
		mv "$next" "$staged" || return 1
	done
	awk '!seen[$0]++' "$staged" > "${staged}.unique" || return 1
	mv "${staged}.unique" "$staged" || return 1
	if ! cmp -s "$schedule" "$staged"; then
		mkdir -p "$backup_root/schedules" || return 1
		cp -p "$schedule" "$backup_root/schedules/$(basename "$schedule")" || return 1
		mv "$staged" "$schedule" || return 1
		chmod 600 "$schedule" 2>/dev/null
		_install_note "[+] Updated legacy built-in names in $(basename "$schedule")"
	else
		rm -f "$staged"
	fi
}

retire_legacy_builtin_names() {
	local stamp backup_root suffix old
	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	backup_root="$PERSISTENT_DIR/migration/renamed-builtins-$stamp-$$"

	for old in scripts_postfs.txt scripts_bootcompleted.txt scripts_cron.txt; do
		_rewrite_legacy_builtin_schedule "$PERSISTENT_DIR/$old" "$backup_root" || return 1
	done

	for suffix in \
		apply-cmdline-bootconfig apply-kstat-add apply-ksu-settings apply-uname \
		apply-mount-hiding apply-props apply-settings apply-sus-maps \
		apply-sus-paths-loop apply-sus-paths cleanup-markers; do
		old="$PERSISTENT_DIR/scripts/ReSuSFS_${suffix}.sh"
		[ -e "$old" ] || continue
		[ -f "$old" ] && [ ! -L "$old" ] || {
			_install_note "[!] Refusing unexpected legacy built-in: $old"
			return 1
		}
		mkdir -p "$backup_root/scripts" || return 1
		mv "$old" "$backup_root/scripts/$(basename "$old")" || return 1
		chmod 600 "$backup_root/scripts/$(basename "$old")" 2>/dev/null
		_install_note "[+] Archived renamed built-in: $(basename "$old")"
	done
}
