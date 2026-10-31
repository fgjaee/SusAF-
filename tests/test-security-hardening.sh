#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
PERSISTENT_DIR="$T/SusAF"; export PERSISTENT_DIR
mkdir -p "$PERSISTENT_DIR/state" "$T/bin"

cat > "$T/settings.db" <<'EOF'
development_settings_enabled=1
adb_enabled=1
adb_wifi_enabled=1
EOF
cat > "$T/props.db" <<'EOF'
init.svc.adbd=running
sys.usb.config=adb
persist.sys.usb.config=adb
EOF
printf "4321\n" > "$T/adbd.pid"

cat > "$T/bin/settings" <<'EOF'
#!/bin/sh
DB="$SUSAF_TEST_SETTINGS_DB"
op="$1"; scope="$2"; key="$3"; value="${4:-}"
[ "$scope" = global ] || exit 1
case "$op" in
 get) sed -n "s/^$key=//p" "$DB" | tail -n1 ;;
 put)
   tmp="$DB.tmp"
   awk -F= -v k="$key" -v v="$value" 'BEGIN{done=0}$1==k&&!done{print k"="v;done=1;next}$1==k{next}{print}END{if(!done)print k"="v}' "$DB" > "$tmp"
   mv "$tmp" "$DB" ;;
 *) exit 1 ;;
esac
EOF

cat > "$T/bin/getprop" <<'EOF'
#!/bin/sh
sed -n "s/^$1=//p" "$SUSAF_TEST_PROPS_DB" | tail -n1
EOF

cat > "$T/bin/setprop" <<'EOF'
#!/bin/sh
DB="$SUSAF_TEST_PROPS_DB"; key="$1"; value="${2:-}"
setv() {
  tmp="$DB.tmp"
  awk -F= -v k="$1" -v v="$2" 'BEGIN{done=0}$1==k&&!done{print k"="v;done=1;next}$1==k{next}{print}END{if(!done)print k"="v}' "$DB" > "$tmp"
  mv "$tmp" "$DB"
}
case "$key" in
 ctl.stop) [ "$value" = adbd ] || exit 1; : > "$SUSAF_TEST_PID"; setv init.svc.adbd stopped ;;
 ctl.start) [ "$value" = adbd ] || exit 1; printf "4321\n" > "$SUSAF_TEST_PID"; setv init.svc.adbd running ;;
 *) setv "$key" "$value" ;;
esac
EOF

cat > "$T/bin/pidof" <<'EOF'
#!/bin/sh
[ "$1" = adbd ] || exit 1
cat "$SUSAF_TEST_PID" 2>/dev/null
EOF
cat > "$T/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$T/bin/"*

export SUSAF_TEST_SETTINGS_DB="$T/settings.db"
export SUSAF_TEST_PROPS_DB="$T/props.db"
export SUSAF_TEST_PID="$T/adbd.pid"
export SUSAF_SETTINGS_BIN="$T/bin/settings"
export SUSAF_GETPROP_BIN="$T/bin/getprop"
export SUSAF_SETPROP_BIN="$T/bin/setprop"
export SUSAF_PIDOF_BIN="$T/bin/pidof"
export SUSAF_SLEEP_BIN="$T/bin/sleep"
export SUSAF_RESETPROP_BIN="/nonexistent"

. "$ROOT/module/lib/security-hardening.sh"

hardening_enter >/dev/null
[ "$(sed -n 's/^development_settings_enabled=//p' "$T/settings.db")" = 0 ]
[ "$(sed -n 's/^adb_enabled=//p' "$T/settings.db")" = 0 ]
[ "$(sed -n 's/^adb_wifi_enabled=//p' "$T/settings.db")" = 0 ]
[ "$(sed -n 's/^persist.sys.usb.config=//p' "$T/props.db")" = mtp ]
[ ! -s "$T/adbd.pid" ]
[ -f "$PERSISTENT_DIR/state/security-hardening.snapshot" ]

status=$(hardening_status)
printf "%s\n" "$status" | grep -Fqx "active=1"
printf "%s\n" "$status" | grep -Fqx "usb_adb_token=absent"

hardening_restore >/dev/null
[ "$(sed -n 's/^development_settings_enabled=//p' "$T/settings.db")" = 1 ]
[ "$(sed -n 's/^adb_enabled=//p' "$T/settings.db")" = 1 ]
[ "$(sed -n 's/^adb_wifi_enabled=//p' "$T/settings.db")" = 1 ]
[ "$(sed -n 's/^persist.sys.usb.config=//p' "$T/props.db")" = adb ]
[ -s "$T/adbd.pid" ]
[ ! -f "$PERSISTENT_DIR/state/security-hardening.snapshot" ]
[ -f "$PERSISTENT_DIR/state/security-hardening.last-snapshot" ]

echo "security hardening tests passed"
