#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
export SUSAF_MODULE_DIR="$MODULE_DIR"
export SUSAF_PERSISTENT_DIR="$TEST_ROOT/persistent"
export SUSAF_BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$SUSAF_PERSISTENT_DIR" "$SUSAF_BIN_DIR" "$TEST_ROOT/fake-bin"

. "$MODULE_DIR/common.sh"
MODDIR="$MODULE_DIR"
. "$MODULE_DIR/utils.sh"

printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\267\000' > "$TEST_ROOT/aarch64.elf"
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\003\000' > "$TEST_ROOT/wrong-machine.elf"
validate_susfs_elf "$TEST_ROOT/aarch64.elf"
! validate_susfs_elf "$TEST_ROOT/wrong-machine.elf"

cat > "$TEST_ROOT/fake-bin/getprop" <<'EOF'
#!/bin/sh
[ "$1" = ro.product.cpu.abi ] && printf 'arm64-v8a\n'
EOF
chmod 755 "$TEST_ROOT/fake-bin/getprop"
PATH="$TEST_ROOT/fake-bin:$PATH"
export PATH

cat > "$TEST_ROOT/candidate" <<'EOF'
#!/bin/sh
# candidate-v2
exit 0
EOF
chmod 755 "$TEST_ROOT/candidate"
expected=$(sha256sum "$TEST_ROOT/candidate" | awk '{ print $1 }')

write_manifest() {
	commit="${1:-26958b7c3dca487c17227b62a6dd7cf11645b49a}"
	digest="${2:-$expected}"
	{
		printf 'schema=1\n'
		printf 'component=ksu_susfs\n'
		printf 'source_repository=sidex15/susfs4ksu-binaries\n'
		printf 'source_commit=%s\n' "$commit"
		printf 'artifact=ksu_susfs_arm64\n'
		printf 'sha256=%s\n' "$digest"
		printf 'abi=arm64-v8a\n'
		printf 'min_kernel_susfs_version=v2.2.0\n'
	} > "$TEST_ROOT/manifest"
}
write_manifest
SUSAF_UPDATE_MANIFEST="$TEST_ROOT/manifest"
SUSAF_UPDATER_REPORT="$TEST_ROOT/updater.report"
export SUSAF_UPDATE_MANIFEST SUSAF_UPDATER_REPORT

# The pipeline behavior is tested with host fixtures; ELF architecture and
# target execution have their own production helpers and are not bypassed on-device.
validate_susfs_elf() {
	[ -s "$1" ]
}
probe_susfs_binary() {
	file="$1"
	if [ "${SUSAF_TEST_REJECT_PATH:-}" = "$file" ]; then
		return 1
	fi
	if [ "${SUSAF_TEST_FAIL_INSTALLED:-0}" = 1 ] && [ "$file" = "$DEST_BIN_DIR/ksu_susfs" ] && grep -Fq 'candidate-v2' "$file"; then
		return 1
	fi
	UPDATER_PROBE_VERSION=v2.3.0
	UPDATER_PROBE_VARIANT=GKI
	return 0
}
download_file() {
	printf '%s\n' "$1" > "$TEST_ROOT/download.url"
	cp "$SUSAF_TEST_DOWNLOAD_SOURCE" "$2"
	chmod 600 "$2"
}

cat > "$DEST_BIN_DIR/ksu_susfs" <<'EOF'
#!/bin/sh
# known-good-v1
exit 0
EOF
chmod 755 "$DEST_BIN_DIR/ksu_susfs"
cp "$DEST_BIN_DIR/ksu_susfs" "$TEST_ROOT/expected-backup"

SUSAF_TEST_DOWNLOAD_SOURCE="$TEST_ROOT/candidate"
export SUSAF_TEST_DOWNLOAD_SOURCE
update_susfs
cmp "$TEST_ROOT/candidate" "$DEST_BIN_DIR/ksu_susfs"
cmp "$TEST_ROOT/expected-backup" "$PERSISTENT_DIR/state/updater/ksu_susfs.backup"
grep -Fqx 'verification=verified' "$SUSAF_UPDATER_REPORT"
grep -Fqx "actual_sha256=$expected" "$SUSAF_UPDATER_REPORT"
grep -Fqx "installed_sha256=$expected" "$SUSAF_UPDATER_REPORT"
grep -Fqx 'candidate_version=v2.3.0' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'candidate_variant=GKI' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'backup=created' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'rollback=not-needed' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'result=installed' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'https://raw.githubusercontent.com/sidex15/susfs4ksu-binaries/26958b7c3dca487c17227b62a6dd7cf11645b49a/ksu_susfs_arm64' "$TEST_ROOT/download.url"

# A verified current binary is accepted without another network request.
rm -f "$TEST_ROOT/download.url"
update_susfs
[ ! -e "$TEST_ROOT/download.url" ]
grep -Fqx "installed_sha256=$expected" "$SUSAF_UPDATER_REPORT"
grep -Fqx 'result=already-current' "$SUSAF_UPDATER_REPORT"

# A verified copy bundled with the module installs without network access.
rm -f "$DEST_BIN_DIR/ksu_susfs" "$TEST_ROOT/download.url"
SUSAF_BUNDLED_SUSFS_BIN="$TEST_ROOT/candidate"
export SUSAF_BUNDLED_SUSFS_BIN
update_susfs
cmp "$TEST_ROOT/candidate" "$DEST_BIN_DIR/ksu_susfs"
[ ! -e "$TEST_ROOT/download.url" ]
grep -Fqx 'candidate_source=bundled' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'result=installed' "$SUSAF_UPDATER_REPORT"
unset SUSAF_BUNDLED_SUSFS_BIN

# A digest mismatch never replaces the current binary.
cp "$DEST_BIN_DIR/ksu_susfs" "$TEST_ROOT/before-mismatch"
printf 'tampered download\n' > "$TEST_ROOT/tampered"
SUSAF_TEST_DOWNLOAD_SOURCE="$TEST_ROOT/tampered"
export SUSAF_TEST_DOWNLOAD_SOURCE
write_manifest 26958b7c3dca487c17227b62a6dd7cf11645b49a "$(printf '0%.0s' $(seq 1 64))"
set +e
update_susfs
mismatch_status=$?
set -e
[ "$mismatch_status" -eq 1 ]
cmp "$TEST_ROOT/before-mismatch" "$DEST_BIN_DIR/ksu_susfs"
grep -Fqx 'verification=failed' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'result=digest-mismatch' "$SUSAF_UPDATER_REPORT"

# If the installed candidate fails its post-install probe, restore the previous
# known-good binary atomically.
cat > "$DEST_BIN_DIR/ksu_susfs" <<'EOF'
#!/bin/sh
# rollback-target-v1
exit 0
EOF
chmod 755 "$DEST_BIN_DIR/ksu_susfs"
cp "$DEST_BIN_DIR/ksu_susfs" "$TEST_ROOT/rollback-expected"
write_manifest
SUSAF_TEST_DOWNLOAD_SOURCE="$TEST_ROOT/candidate"
SUSAF_TEST_FAIL_INSTALLED=1
export SUSAF_TEST_DOWNLOAD_SOURCE SUSAF_TEST_FAIL_INSTALLED
set +e
update_susfs
rollback_status=$?
set -e
[ "$rollback_status" -eq 1 ]
cmp "$TEST_ROOT/rollback-expected" "$DEST_BIN_DIR/ksu_susfs"
grep -Fqx 'backup=created' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'rollback=restored' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'result=post-install-probe-failed' "$SUSAF_UPDATER_REPORT"
unset SUSAF_TEST_FAIL_INSTALLED

# An externally managed helper symlink is preserved when it is compatible.
write_manifest
rm -f "$DEST_BIN_DIR/ksu_susfs" "$DEST_BIN_DIR/susfs" "$TEST_ROOT/download.url"
cat > "$DEST_BIN_DIR/susfs" <<'EOF'
#!/bin/sh
# externally-managed-helper
exit 0
EOF
chmod 755 "$DEST_BIN_DIR/susfs"
ln -s "$DEST_BIN_DIR/susfs" "$DEST_BIN_DIR/ksu_susfs"
cp "$DEST_BIN_DIR/susfs" "$TEST_ROOT/external-before"
update_susfs
[ -L "$DEST_BIN_DIR/ksu_susfs" ]
[ "$(readlink -f "$DEST_BIN_DIR/ksu_susfs")" = "$DEST_BIN_DIR/susfs" ]
cmp "$TEST_ROOT/external-before" "$DEST_BIN_DIR/susfs"
[ ! -e "$TEST_ROOT/download.url" ]
grep -Fqx 'destination_owner=external-symlink' "$SUSAF_UPDATER_REPORT"
grep -Fqx "destination_target=$DEST_BIN_DIR/susfs" "$SUSAF_UPDATER_REPORT"
grep -Fqx 'external_compatibility=compatible' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'result=external-compatible' "$SUSAF_UPDATER_REPORT"

# If the external symlink is incompatible, preserve it and rely on the verified
# bundled helper instead of replacing another module's shared path.
SUSAF_BUNDLED_SUSFS_BIN="$TEST_ROOT/candidate"
SUSAF_TEST_REJECT_PATH="$DEST_BIN_DIR/ksu_susfs"
export SUSAF_BUNDLED_SUSFS_BIN SUSAF_TEST_REJECT_PATH
update_susfs
[ -L "$DEST_BIN_DIR/ksu_susfs" ]
[ "$(readlink -f "$DEST_BIN_DIR/ksu_susfs")" = "$DEST_BIN_DIR/susfs" ]
cmp "$TEST_ROOT/external-before" "$DEST_BIN_DIR/susfs"
grep -Fqx 'external_compatibility=incompatible' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'fallback=bundled' "$SUSAF_UPDATER_REPORT"
grep -Fqx 'result=external-preserved-bundled-fallback' "$SUSAF_UPDATER_REPORT"
unset SUSAF_BUNDLED_SUSFS_BIN SUSAF_TEST_REJECT_PATH

# Malformed pin metadata is rejected before any download or replacement.
cp "$DEST_BIN_DIR/ksu_susfs" "$TEST_ROOT/before-invalid"
rm -f "$TEST_ROOT/download.url"
write_manifest branch-name
set +e
update_susfs
invalid_status=$?
set -e
[ "$invalid_status" -eq 1 ]
cmp "$TEST_ROOT/before-invalid" "$DEST_BIN_DIR/ksu_susfs"
[ ! -e "$TEST_ROOT/download.url" ]
grep -Fqx 'result=invalid-manifest' "$SUSAF_UPDATER_REPORT"

! grep -Fq -- '--no-check-certificate' "$MODULE_DIR/utils.sh"
! grep -Eq '/(main|master|universal-binary)/ksu_susfs_arm64' "$MODULE_DIR/utils.sh" "$MODULE_DIR/update-manifest.properties"
grep -Fqx 'source_commit=26958b7c3dca487c17227b62a6dd7cf11645b49a' "$MODULE_DIR/update-manifest.properties"
grep -Fqx 'sha256=8a626ce3bae27a7bcaa2e7f5f7b91e786ecc57f8e57d19c7856719a89b54b6fa' "$MODULE_DIR/update-manifest.properties"
[ "$(sha256sum "$MODULE_DIR/bin/ksu_susfs" | awk '{ print $1 }')" = 8a626ce3bae27a7bcaa2e7f5f7b91e786ecc57f8e57d19c7856719a89b54b6fa ]
grep -Fq -- '--force-update)' "$MODULE_DIR/SusAF.sh"

echo "secure-updater tests passed"
