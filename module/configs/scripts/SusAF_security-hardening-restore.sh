#!/system/bin/sh
#title=Security Hardening Mode — Restore
#author=fgjaee
#desc=Restore the Developer Options, ADB, wireless debugging, adbd, and USB state saved before hardening mode.
#tags=security,hardening,adb,restore

MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
exec sh "$MODULE_DIR/SusAF.sh" --hardening-restore
