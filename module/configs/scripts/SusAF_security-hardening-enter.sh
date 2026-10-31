#!/system/bin/sh
#title=Security Hardening Mode — Enter
#author=fgjaee
#desc=Snapshot your debugging state, disable Developer Options/ADB, stop adbd, and remove the adb USB token. Reversible.
#tags=security,hardening,adb,privacy

MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
exec sh "$MODULE_DIR/SusAF.sh" --hardening-enter
