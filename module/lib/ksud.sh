#!/bin/sh

# Resolve the KernelSU daemon without trusting a user-writable PATH. Current
# managers may expose ksud either as a standalone binary or as the packaged
# native executable libksud.so.

ksud_candidate_is_usable() {
	[ -n "$1" ] && [ -f "$1" ] && [ -x "$1" ]
}

resolve_ksud_bin() {
	local data_app_root package candidate

	if [ -n "${SUSAF_KSUD_BIN:-}" ]; then
		ksud_candidate_is_usable "$SUSAF_KSUD_BIN" || return 1
		printf '%s\n' "$SUSAF_KSUD_BIN"
		return 0
	fi

	for candidate in \
		"${DEST_BIN_DIR:-/data/adb/ksu/bin}/ksud" \
		/data/adb/ksu/bin/ksud \
		/data/adb/ap/bin/ksud
	do
		if ksud_candidate_is_usable "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	data_app_root="${SUSAF_DATA_APP_ROOT:-/data/app}"
	[ -d "$data_app_root" ] || return 1

	# Restrict discovery to known KernelSU-family manager package IDs. Do not
	# execute an arbitrary libksud.so found in another installed application.
	for package in \
		com.rifsxd.ksunext \
		com.resukisu.resukisu \
		me.weishu.kernelsu \
		com.sukisu.ultra
	do
		for candidate in \
			"$data_app_root"/*/"$package"-*/lib/*/libksud.so \
			"$data_app_root"/"$package"-*/lib/*/libksud.so
		do
			if ksud_candidate_is_usable "$candidate"; then
				printf '%s\n' "$candidate"
				return 0
			fi
		done
	done

	return 1
}
