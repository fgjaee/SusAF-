#!/bin/sh

. "$MODPATH/common.sh"
. "$MODPATH/utils.sh"
. "$MODPATH/migrate.sh"
. "$MODPATH/install-config.sh"

export MODULE_HOT_INSTALL_REQUEST="true"
export MODULE_HOT_RUN_SCRIPT="hotinstall.sh"

banner "$MODPATH"

ui_print "[%] customize.sh "

CONFIG_DIR="$MODPATH/configs"

[ ! -d "$CONFIG_DIR" ] || [ -z "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ] && ui_print "[!] No config files found" && exit 0

mkdir -p "$PERSISTENT_DIR" || exit 1
chmod 700 "$PERSISTENT_DIR" 2>/dev/null
installer_prepare_report || exit 1
checkpoint_existing_install || {
	installer_finish_report checkpoint-failed
	exit 1
}

ui_print "[*] Migrating legacy configuration into $PERSISTENT_DIR"
migrate_legacy_configs || {
	ui_print "[!] Migration did not complete. Installation stopped before changing the legacy module."
	exit 1
}

repair_legacy_schedule_entries || {
	ui_print "[!] Could not preserve all legacy UserHub stage assignments. Installation stopped."
	exit 1
}

retire_legacy_builtin_names || {
	ui_print "[!] Could not safely migrate legacy built-in names. Installation stopped."
	exit 1
}

merge_schedule_defaults "$CONFIG_DIR/scripts_postfs.txt" "$PERSISTENT_DIR/scripts_postfs.txt" || exit 1
merge_schedule_defaults "$CONFIG_DIR/scripts_bootcompleted.txt" "$PERSISTENT_DIR/scripts_bootcompleted.txt" || exit 1
merge_config_defaults "$CONFIG_DIR/config.txt" "$PERSISTENT_DIR/config.txt" || exit 1
install_packaged_builtins "$CONFIG_DIR/scripts" "$PERSISTENT_DIR/scripts" || exit 1
install_missing_defaults "$CONFIG_DIR" "$PERSISTENT_DIR" || exit 1
repair_oversized_cmdline_bootconfig "$CONFIG_DIR/cmdline_or_bootconfig.txt" || exit 1

rm -rf "$CONFIG_DIR"

[ -f "$MODPATH/bin/ksu_susfs" ] && [ ! -L "$MODPATH/bin/ksu_susfs" ] || {
	ui_print "[!] The bundled ksu_susfs binary is missing or unsafe"
	exit 1
}
chmod 755 "$MODPATH/bin/ksu_susfs" || exit 1
update_susfs || exit 1

chmod 755 "$MODPATH/SusAF.sh" "$MODPATH/ReSuSFS.sh"
chmod 644 "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/uninstall.sh" 2>/dev/null

if [ -d "$DEST_BIN_DIR" ]; then
	ui_print "[+] Creating SusAF and ReSuSFS compatibility commands in $DEST_BIN_DIR"
	ln -sf "$MODULE_DIR/SusAF.sh" "$SUSAF_CLI"
	ln -sf "$MODULE_DIR/SusAF.sh" "$RESUSFS_COMPAT_CLI"
fi

if [ ! -d "$PERSISTENT_DIR/.webui_config" ] || [ ! -f "$PERSISTENT_DIR/.webui_config/custom.css" ]; then
	mkdir -p "$PERSISTENT_DIR/.webui_config"
	mv "$MODPATH/custom.css" "$PERSISTENT_DIR/.webui_config/custom.css"
else
	rm -f "$MODPATH/custom.css"
fi

disable_legacy_resusfs_module || {
	ui_print "[!] Could not disable the legacy ReSuSFS module; disable it manually before reboot"
	exit 1
}

archive_legacy_sources || {
	ui_print "[!] Legacy configuration was migrated but could not be archived; it remains in its original location"
	exit 1
}

remove_generated_kstat_entries || exit 1

installer_finish_report ok

# EOF
