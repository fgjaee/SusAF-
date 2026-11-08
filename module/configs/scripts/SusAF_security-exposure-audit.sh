#!/system/bin/sh
#title=Security Exposure Audit
#author=fgjaee
#desc=Read-only report of debugging state and security-sensitive packages previously surfaced by detector scans.
#tags=security,audit,packages,adb

GETPROP="${SUSAF_GETPROP_BIN:-/system/bin/getprop}"
SETTINGS="${SUSAF_SETTINGS_BIN:-/system/bin/settings}"
PM="${SUSAF_PM_BIN:-/system/bin/pm}"
PIDOF="${SUSAF_PIDOF_BIN:-/system/bin/pidof}"

echo "schema=1"
echo "generated.epoch=$(date +%s 2>/dev/null)"
echo "development_settings_enabled=$("$SETTINGS" get global development_settings_enabled 2>/dev/null)"
echo "adb_enabled=$("$SETTINGS" get global adb_enabled 2>/dev/null)"
echo "adb_wifi_enabled=$("$SETTINGS" get global adb_wifi_enabled 2>/dev/null)"
echo "init.svc.adbd=$("$GETPROP" init.svc.adbd 2>/dev/null)"
echo "adbd_pids=$("$PIDOF" adbd 2>/dev/null || true)"
echo "persist.sys.usb.config=$("$GETPROP" persist.sys.usb.config 2>/dev/null)"

for pkg in \
  moe.shizuku.privileged.api \
  com.resukisu.resukisu \
  com.resukisu.resukisu.dev \
  com.coderstory.toolkit \
  org.frknkrc44.hma_oss \
  com.alex193a.rootmypixel \
  com.termux \
  tw.fatminmin.xposed.minminguard.next
do
  if "$PM" path "$pkg" >/dev/null 2>&1; then
    echo "package.$pkg=installed"
  else
    echo "package.$pkg=not-installed"
  fi
done
