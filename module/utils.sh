#!/bin/sh
PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-${MODULE_DIR:-/data/adb/modules/susaf}}"
[ -f "$MODULE_DIR/common.sh" ] && . "$MODULE_DIR/common.sh"
MODDIR="$MODULE_DIR"

banner() {
	local dir="${1:-$MODDIR}"
	local module_prop="$dir/module.prop"
	local banner_file="$dir/banner"
	local author=$(sed -n 's/^author=//p' "$module_prop" 2>/dev/null)
	local version=$(sed -n 's/^version=//p' "$module_prop" 2>/dev/null)

	[ -f "$banner_file" ] && cat "$banner_file"

	echo "Authors:  ${author:-Unknown}"
	echo "Version: ${version:-Unknown}"
	echo
}

get_all_files() {
    local dir="$1"
    find "$dir" -type f 2>/dev/null | sed "s|^$dir/||"
}

updater_manifest_get() {
	local key="$1"
	local file="$2"
	grep "^$key=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2-
}

updater_version_ge() {
	local ver1="${1#v}" ver2="${2#v}"
	local major1 minor1 patch1 major2 minor2 patch2
	major1=$(printf '%s' "$ver1" | cut -d. -f1); major1=${major1:-0}
	minor1=$(printf '%s' "$ver1" | cut -d. -f2); minor1=${minor1:-0}
	patch1=$(printf '%s' "$ver1" | cut -d. -f3); patch1=${patch1:-0}
	major2=$(printf '%s' "$ver2" | cut -d. -f1); major2=${major2:-0}
	minor2=$(printf '%s' "$ver2" | cut -d. -f2); minor2=${minor2:-0}
	patch2=$(printf '%s' "$ver2" | cut -d. -f3); patch2=${patch2:-0}

	case "$major1$minor1$patch1$major2$minor2$patch2" in
		*[!0-9]*) return 1 ;;
	esac
	[ "$major1" -gt "$major2" ] && return 0
	[ "$major1" -lt "$major2" ] && return 1
	[ "$minor1" -gt "$minor2" ] && return 0
	[ "$minor1" -lt "$minor2" ] && return 1
	[ "$patch1" -ge "$patch2" ]
}

updater_sha256() {
	local file="$1"
	local sha_bin
	[ -f "$file" ] && [ ! -L "$file" ] || return 1
	if sha_bin=$(command -v sha256sum 2>/dev/null); then
		"$sha_bin" "$file" 2>/dev/null | awk '{ print $1; exit }'
	elif command -v busybox >/dev/null 2>&1; then
		busybox sha256sum "$file" 2>/dev/null | awk '{ print $1; exit }'
	else
		return 1
	fi
}

updater_prepare_report() {
	local report_dir
	UPDATER_REPORT_FILE="${SUSAF_UPDATER_REPORT:-$PERSISTENT_DIR/state/updater.report.txt}"
	UPDATER_REPORT_TEMP="${UPDATER_REPORT_FILE}.tmp.$$"
	report_dir=$(dirname "$UPDATER_REPORT_FILE")
	umask 077
	mkdir -p "$report_dir" || return 1
	chmod 700 "$PERSISTENT_DIR" "$PERSISTENT_DIR/state" "$report_dir" 2>/dev/null
	: > "$UPDATER_REPORT_TEMP" || return 1
	chmod 600 "$UPDATER_REPORT_TEMP" 2>/dev/null
}

updater_report() {
	printf '%s\n' "$*" >> "$UPDATER_REPORT_TEMP"
	printf '[updater] %s\n' "$*"
}

updater_finish() {
	local result="$1"
	updater_report "result=$result"
	mv "$UPDATER_REPORT_TEMP" "$UPDATER_REPORT_FILE"
}

download_file() {
	local url="$1" out="$2" attempt=1
	local curl_bin="${SUSAF_CURL_BIN:-}"
	local busybox_bin download_ok

	[ -n "$curl_bin" ] || curl_bin=$(command -v curl 2>/dev/null) || curl_bin=""
	busybox_bin=$(command -v busybox 2>/dev/null) || busybox_bin=""
	[ -n "$curl_bin" ] || [ -n "$busybox_bin" ] || {
		echo "[!] Neither curl nor BusyBox wget is available"
		return 1
	}

	while [ "$attempt" -le 3 ]; do
		echo "[*] Secure download attempt $attempt/3"
		rm -f "$out"
		download_ok=0
		if [ -n "$curl_bin" ]; then
			if "$curl_bin" --fail --location --silent --show-error \
				--proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 90 \
				--output "$out" "$url"; then
				download_ok=1
			fi
		else
			if "$busybox_bin" wget -q -T 90 -O "$out" "$url"; then
				download_ok=1
			fi
		fi
		if [ "$download_ok" = 1 ] && [ -s "$out" ]; then
			chmod 600 "$out" 2>/dev/null
			echo "[+] Download complete; verifying pinned digest"
			return 0
		fi
		rm -f "$out"
		[ "$attempt" -lt 3 ] && sleep 3
		attempt=$((attempt + 1))
	done

	echo "[!] Secure download failed"
	return 1
}

validate_susfs_elf() {
	local file="$1"
	local magic class byte_order machine
	[ -f "$file" ] && [ ! -L "$file" ] && [ -s "$file" ] || return 1
	magic=$(dd if="$file" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
	class=$(dd if="$file" bs=1 skip=4 count=1 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
	byte_order=$(dd if="$file" bs=1 skip=5 count=1 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
	machine=$(dd if="$file" bs=1 skip=18 count=2 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
	[ "$magic" = 7f454c46 ] && [ "$class" = 02 ] && [ "$byte_order" = 01 ] && [ "$machine" = b700 ]
}

probe_susfs_binary() {
	local file="$1"
	local min_version="$2"
	local version variant
	[ -x "$file" ] || return 1
	version=$("$file" show version 2>/dev/null) || return 1
	variant=$("$file" show variant 2>/dev/null) || return 1
	[ -n "$version" ] && [ -n "$variant" ] || return 1
	updater_version_ge "$version" "$min_version" || return 1
	UPDATER_PROBE_VERSION="$version"
	UPDATER_PROBE_VARIANT="$variant"
	return 0
}

select_susfs_binary() {
	local min_version="${1:-v0.0.0}"
	local external="$DEST_BIN_DIR/ksu_susfs"
	local bundled="$SUSFS_BUNDLED_BIN"

	if [ -n "${SUSAF_SUSFS_BIN:-}" ]; then
		SUSFS_BIN="$SUSAF_SUSFS_BIN"
		SUSFS_BIN_SOURCE=override
		export SUSFS_BIN SUSFS_BIN_SOURCE
		return 0
	fi

	if [ -x "$external" ] && probe_susfs_binary "$external" "$min_version"; then
		SUSFS_BIN="$external"
		SUSFS_BIN_SOURCE=external
		export SUSFS_BIN SUSFS_BIN_SOURCE
		return 0
	fi

	if [ -x "$bundled" ] && probe_susfs_binary "$bundled" "$min_version"; then
		SUSFS_BIN="$bundled"
		SUSFS_BIN_SOURCE=bundled
		export SUSFS_BIN SUSFS_BIN_SOURCE
		return 0
	fi

	if [ -x "$external" ]; then
		SUSFS_BIN="$external"
		SUSFS_BIN_SOURCE=external-incompatible
	elif [ -x "$bundled" ]; then
		SUSFS_BIN="$bundled"
		SUSFS_BIN_SOURCE=bundled-incompatible
	else
		SUSFS_BIN="$external"
		SUSFS_BIN_SOURCE=unavailable
	fi
	export SUSFS_BIN SUSFS_BIN_SOURCE
	return 1
}

restore_susfs_backup() {
	local backup="$1" destination="$2"
	local restore_temp="${destination}.restore.$$"
	cp "$backup" "$restore_temp" || return 1
	chmod 755 "$restore_temp" 2>/dev/null || {
		rm -f "$restore_temp"
		return 1
	}
	mv -f "$restore_temp" "$destination" || {
		rm -f "$restore_temp"
		return 1
	}
}

update_susfs() {
	local module_root="${MODPATH:-${MODDIR:-$MODULE_DIR}}"
	local manifest="${SUSAF_UPDATE_MANIFEST:-$module_root/update-manifest.properties}"
	local schema component repository commit artifact expected abi min_version url
	local arch state_dir candidate destination install_temp backup backup_temp bundled
	local actual current_sha installed_sha bundled_sha backup_valid=0
	local destination_target

	updater_prepare_report || {
		echo "[!] Could not create private updater report"
		return 1
	}

	schema=$(updater_manifest_get schema "$manifest")
	component=$(updater_manifest_get component "$manifest")
	repository=$(updater_manifest_get source_repository "$manifest")
	commit=$(updater_manifest_get source_commit "$manifest")
	artifact=$(updater_manifest_get artifact "$manifest")
	expected=$(updater_manifest_get sha256 "$manifest")
	abi=$(updater_manifest_get abi "$manifest")
	min_version=$(updater_manifest_get min_kernel_susfs_version "$manifest")
	updater_report "schema=$schema"
	updater_report "component=$component"
	updater_report "source_repository=$repository"
	updater_report "source_commit=$commit"
	updater_report "artifact=$artifact"
	updater_report "expected_sha256=$expected"
	updater_report "abi=$abi"

	if [ "$schema" != 1 ] || [ "$component" != ksu_susfs ] || \
		[ "$repository" != sidex15/susfs4ksu-binaries ] || \
		[ "$artifact" != ksu_susfs_arm64 ] || [ "$abi" != arm64-v8a ]; then
		updater_finish invalid-manifest
		return 1
	fi
	if [ "${#commit}" -ne 40 ] || [ "${#expected}" -ne 64 ]; then
		updater_finish invalid-manifest
		return 1
	fi
	case "$commit$expected" in
		*[!0-9a-f]*) updater_finish invalid-manifest; return 1 ;;
	esac
	case "$min_version" in
		v[0-9]*.[0-9]*.[0-9]*) ;;
		*) updater_finish invalid-manifest; return 1 ;;
	esac

	url="https://raw.githubusercontent.com/$repository/$commit/$artifact"
	updater_report "source_url=$url"
	updater_report "min_kernel_susfs_version=$min_version"

	arch=$(getprop ro.product.cpu.abi 2>/dev/null)
	updater_report "device_abi=$arch"
	if [ "$arch" != "$abi" ]; then
		updater_finish unsupported-architecture
		return 1
	fi
	if [ ! -e "$DEST_BIN_DIR" ]; then
		mkdir -p "$DEST_BIN_DIR" 2>/dev/null || {
			updater_finish destination-directory-failed
			return 1
		}
		chmod 755 "$DEST_BIN_DIR" 2>/dev/null
	fi
	if [ ! -d "$DEST_BIN_DIR" ] || [ -L "$DEST_BIN_DIR" ]; then
		updater_finish unsafe-destination-directory
		return 1
	fi

	state_dir="$PERSISTENT_DIR/state/updater"
	candidate="$state_dir/.ksu_susfs.candidate.$$"
	destination="$DEST_BIN_DIR/ksu_susfs"
	install_temp="$DEST_BIN_DIR/.ksu_susfs.susaf.$$"
	backup="$state_dir/ksu_susfs.backup"
	backup_temp="$state_dir/.ksu_susfs.backup.$$"
	mkdir -p "$state_dir" || {
		updater_finish state-directory-failed
		return 1
	}
	chmod 700 "$state_dir" 2>/dev/null
	rm -f "$candidate" "$install_temp" "$backup_temp"

	if [ -L "$destination" ]; then
		destination_target=$(readlink -f "$destination" 2>/dev/null) || destination_target=
		updater_report "destination_owner=external-symlink"
		updater_report "destination_target=$destination_target"

		case "$destination_target" in
			"$DEST_BIN_DIR"/*) ;;
			*)
				updater_report "external_compatibility=unsafe-target"
				updater_finish unsafe-destination
				return 1
				;;
		esac

		if [ -f "$destination_target" ] && [ -x "$destination" ] && probe_susfs_binary "$destination" "$min_version"; then
			updater_report "external_compatibility=compatible"
			updater_report "candidate_version=$UPDATER_PROBE_VERSION"
			updater_report "candidate_variant=$UPDATER_PROBE_VARIANT"
			updater_report "verification=external-managed"
			updater_report "backup=not-applicable"
			updater_report "rollback=not-needed"
			updater_finish external-compatible
			return 0
		fi

		bundled="${SUSAF_BUNDLED_SUSFS_BIN:-$module_root/bin/ksu_susfs}"
		if [ -f "$bundled" ] && [ ! -L "$bundled" ]; then
			bundled_sha=$(updater_sha256 "$bundled" 2>/dev/null) || bundled_sha=unavailable
			if [ "$bundled_sha" = "$expected" ] && validate_susfs_elf "$bundled" && probe_susfs_binary "$bundled" "$min_version"; then
				updater_report "external_compatibility=incompatible"
				updater_report "fallback=bundled"
				updater_report "candidate_version=$UPDATER_PROBE_VERSION"
				updater_report "candidate_variant=$UPDATER_PROBE_VARIANT"
				updater_report "verification=verified"
				updater_report "backup=not-applicable"
				updater_report "rollback=not-needed"
				updater_finish external-preserved-bundled-fallback
				return 0
			fi
		fi

		updater_report "external_compatibility=incompatible"
		updater_report "fallback=unavailable"
		updater_report "verification=failed"
		updater_report "backup=not-applicable"
		updater_report "rollback=not-needed"
		updater_finish external-incompatible-no-fallback
		return 1
	fi

	if [ -e "$destination" ] && [ ! -f "$destination" ]; then
		updater_finish unsafe-destination
		return 1
	fi
	current_sha=$(updater_sha256 "$destination" 2>/dev/null) || current_sha=none
	updater_report "previous_sha256=$current_sha"
	if [ "$current_sha" = "$expected" ] && validate_susfs_elf "$destination" && probe_susfs_binary "$destination" "$min_version"; then
		updater_report "verification=verified"
		updater_report "installed_sha256=$current_sha"
		updater_report "candidate_version=$UPDATER_PROBE_VERSION"
		updater_report "candidate_variant=$UPDATER_PROBE_VARIANT"
		if cp -p "$destination" "$backup_temp" && chmod 700 "$backup_temp" 2>/dev/null && mv -f "$backup_temp" "$backup"; then
			updater_report "backup=seeded"
		else
			rm -f "$backup_temp"
			updater_report "backup=unchanged"
		fi
		updater_report "rollback=not-needed"
		updater_finish already-current
		return 0
	fi

	bundled="${SUSAF_BUNDLED_SUSFS_BIN:-$module_root/bin/ksu_susfs}"
	if [ -f "$bundled" ] && [ ! -L "$bundled" ]; then
		bundled_sha=$(updater_sha256 "$bundled" 2>/dev/null) || bundled_sha=unavailable
		if [ "$bundled_sha" = "$expected" ] && cp "$bundled" "$candidate"; then
			chmod 600 "$candidate" 2>/dev/null
			updater_report "candidate_source=bundled"
		else
			updater_report "bundled_verification=failed"
			rm -f "$candidate"
		fi
	fi
	if [ ! -s "$candidate" ]; then
		updater_report "candidate_source=download"
		if ! download_file "$url" "$candidate"; then
			updater_report "verification=not-performed"
			updater_report "backup=unchanged"
			updater_report "rollback=not-needed"
			updater_finish download-failed
			return 1
		fi
	fi
	actual=$(updater_sha256 "$candidate" 2>/dev/null) || actual=unavailable
	updater_report "actual_sha256=$actual"
	if [ "$actual" != "$expected" ]; then
		rm -f "$candidate"
		updater_report "verification=failed"
		updater_report "backup=unchanged"
		updater_report "rollback=not-needed"
		updater_finish digest-mismatch
		return 1
	fi
	updater_report "verification=verified"
	if ! validate_susfs_elf "$candidate"; then
		rm -f "$candidate"
		updater_report "backup=unchanged"
		updater_report "rollback=not-needed"
		updater_finish invalid-elf
		return 1
	fi
	chmod 700 "$candidate" 2>/dev/null
	if ! probe_susfs_binary "$candidate" "$min_version"; then
		rm -f "$candidate"
		updater_report "backup=unchanged"
		updater_report "rollback=not-needed"
		updater_finish compatibility-probe-failed
		return 1
	fi
	updater_report "candidate_version=$UPDATER_PROBE_VERSION"
	updater_report "candidate_variant=$UPDATER_PROBE_VARIANT"

	if [ -f "$destination" ] && [ ! -L "$destination" ] && probe_susfs_binary "$destination" "$min_version"; then
		if cp -p "$destination" "$backup_temp" && chmod 700 "$backup_temp" 2>/dev/null && mv -f "$backup_temp" "$backup"; then
			backup_valid=1
			updater_report "backup=created"
		else
			rm -f "$candidate" "$backup_temp"
			updater_report "backup=failed"
			updater_report "rollback=not-needed"
			updater_finish backup-failed
			return 1
		fi
	elif [ -f "$backup" ] && [ ! -L "$backup" ] && probe_susfs_binary "$backup" "$min_version"; then
		backup_valid=1
		updater_report "backup=retained"
	else
		updater_report "backup=none"
	fi

	if ! cp "$candidate" "$install_temp" || ! chmod 755 "$install_temp" 2>/dev/null || ! mv -f "$install_temp" "$destination"; then
		rm -f "$candidate" "$install_temp"
		updater_report "rollback=not-needed"
		updater_finish install-failed
		return 1
	fi
	rm -f "$candidate"

	installed_sha=$(updater_sha256 "$destination" 2>/dev/null) || installed_sha=unavailable
	updater_report "installed_sha256=$installed_sha"
	if [ "$installed_sha" = "$expected" ] && validate_susfs_elf "$destination" && probe_susfs_binary "$destination" "$min_version"; then
		if [ "$backup_valid" = 0 ]; then
			if cp -p "$destination" "$backup_temp" && chmod 700 "$backup_temp" 2>/dev/null && mv -f "$backup_temp" "$backup"; then
				updater_report "backup=seeded"
			else
				rm -f "$backup_temp"
				updater_report "backup=seed-failed"
			fi
		fi
		updater_report "rollback=not-needed"
		updater_finish installed
		return 0
	fi

	if [ "$backup_valid" = 1 ] && restore_susfs_backup "$backup" "$destination" && probe_susfs_binary "$destination" "$min_version"; then
		updater_report "rollback=restored"
		updater_finish post-install-probe-failed
	else
		rm -f "$destination"
		updater_report "rollback=failed"
		updater_finish post-install-probe-failed
	fi
	return 1
}

# EOF
