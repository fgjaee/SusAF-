#!/system/bin/sh
#title=Security Hardening Mode — Status
#author=fgjaee
#desc=Show the current Security Hardening Mode and ADB/debugging state.
#tags=security,hardening,adb,status

MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
exec sh "$MODULE_DIR/SusAF.sh" --hardening-status
