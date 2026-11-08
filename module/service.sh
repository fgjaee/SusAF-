#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
	sleep 1
done

# Late-loaded KernelSU may start this service after Android has already passed
# the normal boot-completed event. Ensure SUSFS exists and replay only paths.
STARTUP_STATE="$PERSISTENT_DIR/state"
mkdir -p "$STARTUP_STATE"
{
	echo "SusAF SUSFS startup replay: $(date)"
	sh "$MODULE_DIR/SusAF.sh" --apply-sus-paths
	static_rc=$?
	sh "$MODULE_DIR/SusAF.sh" --apply-sus-paths-loop
	loop_rc=$?
	echo "static_rc=$static_rc"
	echo "loop_rc=$loop_rc"
} > "$STARTUP_STATE/susfs-startup.log" 2>&1

# Inventory the settled device state and apply evidence-backed low-risk fixes.
# Risky findings are generated for WebUI review and are never silently applied.
sh "$MODULE_DIR/SusAF.sh" --autopilot-boot > /dev/null 2>&1 || true

# One event-based snapshot after Android finishes booting. The WebUI can
# explicitly refresh it later; no installed module file is rewritten.
sh "$MODULE_DIR/SusAF.sh" --status-report > /dev/null 2>&1
