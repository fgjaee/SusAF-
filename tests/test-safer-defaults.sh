#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
PERSISTENT_DIR="$TEST_ROOT/persistent"
STATE_DIR="$TEST_ROOT/device-state"
MUTATION_LOG="$TEST_ROOT/mutations.log"
mkdir -p "$TEST_ROOT/bin" "$PERSISTENT_DIR" "$STATE_DIR"
: > "$MUTATION_LOG"

for key in development_settings_enabled adb_enabled adb_wifi_enabled; do
	printf '1\n' > "$STATE_DIR/$key"
done
printf 'running\n' > "$STATE_DIR/adbd-service"
printf '321\n' > "$STATE_DIR/adbd-pid"
printf 'mtp,adb\n' > "$STATE_DIR/sys-usb-config"
printf 'mtp,adb\n' > "$STATE_DIR/sys-usb-state"
printf 'mtp,adb\n' > "$STATE_DIR/persist-usb-config"

cat > "$TEST_ROOT/bin/settings" <<'EOF'
#!/bin/sh
case "$1" in
	get) cat "$SUSAF_FAKE_DEVICE_STATE/$3" ;;
	put)
		printf '%s\n' "$*" >> "$SUSAF_FAKE_MUTATION_LOG"
		printf '%s\n' "$4" > "$SUSAF_FAKE_DEVICE_STATE/$3"
		;;
	*) exit 1 ;;
esac
EOF

cat > "$TEST_ROOT/bin/getprop" <<'EOF'
#!/bin/sh
case "$1" in
	init.svc.adbd) cat "$SUSAF_FAKE_DEVICE_STATE/adbd-service" ;;
	sys.usb.config) cat "$SUSAF_FAKE_DEVICE_STATE/sys-usb-config" ;;
	sys.usb.state) cat "$SUSAF_FAKE_DEVICE_STATE/sys-usb-state" ;;
	persist.sys.usb.config) cat "$SUSAF_FAKE_DEVICE_STATE/persist-usb-config" ;;
	*) exit 1 ;;
esac
EOF

cat > "$TEST_ROOT/bin/setprop" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SUSAF_FAKE_MUTATION_LOG"
if [ "$1 $2" = "ctl.stop adbd" ]; then
	printf 'stopped\n' > "$SUSAF_FAKE_DEVICE_STATE/adbd-service"
	rm -f "$SUSAF_FAKE_DEVICE_STATE/adbd-pid"
fi
EOF

cat > "$TEST_ROOT/bin/pidof" <<'EOF'
#!/bin/sh
[ -f "$SUSAF_FAKE_DEVICE_STATE/adbd-pid" ] || exit 1
cat "$SUSAF_FAKE_DEVICE_STATE/adbd-pid"
EOF

cat > "$TEST_ROOT/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$TEST_ROOT/bin/settings" "$TEST_ROOT/bin/getprop" "$TEST_ROOT/bin/setprop" "$TEST_ROOT/bin/pidof" "$TEST_ROOT/bin/sleep"

SUSAF_SETTINGS_BIN="$TEST_ROOT/bin/settings"
SUSAF_GETPROP_BIN="$TEST_ROOT/bin/getprop"
SUSAF_SETPROP_BIN="$TEST_ROOT/bin/setprop"
SUSAF_PIDOF_BIN="$TEST_ROOT/bin/pidof"
SUSAF_SLEEP_BIN="$TEST_ROOT/bin/sleep"
SUSAF_FAKE_DEVICE_STATE="$STATE_DIR"
SUSAF_FAKE_MUTATION_LOG="$MUTATION_LOG"
export SUSAF_SETTINGS_BIN SUSAF_GETPROP_BIN SUSAF_SETPROP_BIN SUSAF_PIDOF_BIN SUSAF_SLEEP_BIN
export SUSAF_FAKE_DEVICE_STATE SUSAF_FAKE_MUTATION_LOG PERSISTENT_DIR

. "$MODULE_DIR/lib/adb-mode.sh"

cat > "$TEST_ROOT/unchanged.conf" <<'EOF'
ADB_MODE=unchanged
EOF
SUSAF_ADB_MODE_REPORT="$TEST_ROOT/unchanged.report"
export SUSAF_ADB_MODE_REPORT
apply_adb_mode "$TEST_ROOT/unchanged.conf"
[ ! -s "$MUTATION_LOG" ]
grep -Fqx 'before.adb_enabled=1' "$TEST_ROOT/unchanged.report"
grep -Fqx 'after.adb_enabled=1' "$TEST_ROOT/unchanged.report"
grep -Fqx 'result=unchanged' "$TEST_ROOT/unchanged.report"

cat > "$TEST_ROOT/spoof.conf" <<'EOF'
ADB_MODE=spoof-off
EOF
SUSAF_ADB_MODE_REPORT="$TEST_ROOT/spoof.report"
export SUSAF_ADB_MODE_REPORT
set +e
apply_adb_mode "$TEST_ROOT/spoof.conf"
spoof_status=$?
set -e
[ "$spoof_status" -eq 1 ]
[ ! -s "$MUTATION_LOG" ]
grep -Fqx 'result=refused-no-safe-settings-spoof' "$TEST_ROOT/spoof.report"

cat > "$TEST_ROOT/unconfirmed.conf" <<'EOF'
ADB_MODE=actually-disable
ADB_DISABLE_CONFIRM=
EOF
SUSAF_ADB_MODE_REPORT="$TEST_ROOT/unconfirmed.report"
export SUSAF_ADB_MODE_REPORT
set +e
apply_adb_mode "$TEST_ROOT/unconfirmed.conf"
unconfirmed_status=$?
set -e
[ "$unconfirmed_status" -eq 1 ]
[ ! -s "$MUTATION_LOG" ]
grep -Fqx 'result=refused-confirmation-required' "$TEST_ROOT/unconfirmed.report"

cat > "$TEST_ROOT/disable.conf" <<'EOF'
ADB_MODE=actually-disable
ADB_DISABLE_CONFIRM=disable-adb
EOF
SUSAF_ADB_MODE_REPORT="$TEST_ROOT/disable.report"
export SUSAF_ADB_MODE_REPORT
apply_adb_mode "$TEST_ROOT/disable.conf"
for key in development_settings_enabled adb_enabled adb_wifi_enabled; do
	grep -Fqx "put global $key 0" "$MUTATION_LOG"
	grep -Fqx '0' "$STATE_DIR/$key"
done
grep -Fqx 'ctl.stop adbd' "$MUTATION_LOG"
grep -Fqx 'after.init.svc.adbd=stopped' "$TEST_ROOT/disable.report"
grep -Fqx 'after.adbd_pid=' "$TEST_ROOT/disable.report"
grep -Fqx 'result=disabled' "$TEST_ROOT/disable.report"

! grep -Fq 'for pty in /dev/pts/*' "$MODULE_DIR/configs/scripts/SusAF_apply-sus-paths-loop.sh"
! grep -Fq 'find /data/adb/modules -name "*.so"' "$MODULE_DIR/configs/scripts/SusAF_apply-sus-maps.sh"
! grep -Fq 'find /data/adb/modules -type f' "$MODULE_DIR/configs/scripts/SusAF_apply-sus-maps.sh"

PROPS_SCRIPT="$MODULE_DIR/configs/scripts/SusAF_apply-props.sh"
for property in ro.build.fingerprint ro.build.tags ro.build.type ro.product.model \
	ro.boot.verifiedbootstate ro.boot.flash.locked ro.secure ro.debuggable; do
	! grep -Fq "$property" "$PROPS_SCRIPT"
done
! grep -Fq 'resetprop -c' "$PROPS_SCRIPT"
grep -Fqx 'HIDE_SUS_MNTS_NON_SU=1' "$MODULE_DIR/configs/config.txt"
grep -Fqx 'HIDE_SUS_MNTS_LATE=0' "$MODULE_DIR/configs/config.txt"
grep -Fqx 'ALLOW_BROAD_KERNEL_UMOUNT=0' "$MODULE_DIR/configs/config.txt"

cat > "$TEST_ROOT/bin/resetprop" <<'EOF'
#!/bin/sh
if [ "$#" -eq 0 ]; then
	printf '[ro.boot.verifiedbooterror]: [failed]\n'
	printf '[vendor.boot.verifyerrorpart]: [vbmeta]\n'
	printf '[ro.build.fingerprint]: [stock]\n'
	exit 0
fi
printf '%s\n' "$*" >> "$SUSAF_FAKE_RESETPROP_LOG"
EOF
chmod 755 "$TEST_ROOT/bin/resetprop"
SUSAF_FAKE_RESETPROP_LOG="$TEST_ROOT/resetprop.log"
export SUSAF_FAKE_RESETPROP_LOG
: > "$SUSAF_FAKE_RESETPROP_LOG"
PATH="$TEST_ROOT/bin:$PATH" sh "$PROPS_SCRIPT"
grep -Fqx -- '-d ro.boot.verifiedbooterror' "$SUSAF_FAKE_RESETPROP_LOG"
grep -Fqx -- '-d -p ro.boot.verifiedbooterror' "$SUSAF_FAKE_RESETPROP_LOG"
grep -Fqx -- '-d vendor.boot.verifyerrorpart' "$SUSAF_FAKE_RESETPROP_LOG"
grep -Fqx -- '-d -p vendor.boot.verifyerrorpart' "$SUSAF_FAKE_RESETPROP_LOG"
! grep -Fq 'ro.build.fingerprint' "$SUSAF_FAKE_RESETPROP_LOG"

cat > "$TEST_ROOT/bin/SusAF" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SUSAF_FAKE_CLI_LOG"
[ "$1" != "--apply-sus-paths-loop" ] || cp "$2" "$SUSAF_FAKE_PATH_LIST"
[ "$1" != "--apply-kstat-add-direct" ] || cp "$2" "$SUSAF_FAKE_KSTAT_LIST"
EOF
chmod 755 "$TEST_ROOT/bin/SusAF"
SUSAF_FAKE_CLI_LOG="$TEST_ROOT/cli.log"
SUSAF_FAKE_PATH_LIST="$TEST_ROOT/path-list"
SUSAF_FAKE_KSTAT_LIST="$TEST_ROOT/kstat-list"
export SUSAF_FAKE_CLI_LOG SUSAF_FAKE_PATH_LIST SUSAF_FAKE_KSTAT_LIST
: > "$SUSAF_FAKE_CLI_LOG"

SUSAF_CLI_COMMAND="$TEST_ROOT/bin/SusAF" \
sh "$MODULE_DIR/configs/scripts/SusAF_apply-sus-maps.sh"
grep -Fqx -- '--apply-sus-maps' "$SUSAF_FAKE_CLI_LOG"

SUSAF_CLI_COMMAND="$TEST_ROOT/bin/SusAF" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
sh "$MODULE_DIR/configs/scripts/SusAF_apply-sus-paths-loop.sh"
! grep -Fq '/dev/pts/' "$SUSAF_FAKE_PATH_LIST"

SUSAF_CLI_COMMAND="$TEST_ROOT/bin/SusAF" \
SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
sh "$MODULE_DIR/configs/scripts/SusAF_apply-kstat-add.sh"
grep -Fqx -- "--apply-kstat-add-direct $PERSISTENT_DIR/state/kstat.generated.txt" "$SUSAF_FAKE_CLI_LOG"
grep -Fqx '/data/adb/SusAF default default default default default default default default default default default default' "$SUSAF_FAKE_KSTAT_LIST"
! grep -Fq '/system/etc/hosts' "$SUSAF_FAKE_KSTAT_LIST"

echo "safer-default tests passed"
