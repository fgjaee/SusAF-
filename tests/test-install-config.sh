#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export PERSISTENT_DIR="$TEST_ROOT/SusAF"
PACKAGE_DIR="$TEST_ROOT/package"
. "$(dirname "$0")/../module/install-config.sh"

mkdir -p "$PACKAGE_DIR/scripts" "$PERSISTENT_DIR/scripts"
printf 'BuiltInEarly.sh\n' > "$PACKAGE_DIR/scripts_postfs.txt"
printf 'BuiltInLate.sh\n' > "$PACKAGE_DIR/scripts_bootcompleted.txt"
cat > "$PACKAGE_DIR/config.txt" <<'EOF'
KEEP_VALUE=packaged
NEW_OPTION=1
EOF
printf '# clean bootconfig template\n' > "$PACKAGE_DIR/cmdline_or_bootconfig.txt"
printf '#!/system/bin/sh\nprintf "new built-in\\n"\n' > "$PACKAGE_DIR/scripts/BuiltInLate.sh"
printf '#!/system/bin/sh\nprintf "updated safe built-in\\n"\n' > "$PACKAGE_DIR/scripts/BuiltInSafe.sh"

cat > "$PERSISTENT_DIR/scripts_bootcompleted.txt" <<'EOF'
Max_Saturation.sh
BuiltInLate.sh
!BuiltInLate.sh
Max_Saturation.sh
EOF
cat > "$PERSISTENT_DIR/config.txt" <<'EOF'
KEEP_VALUE=custom
CUSTOM_VALUE=keep
EOF
printf '#!/system/bin/sh\nprintf "old built-in\\n"\n' > "$PERSISTENT_DIR/scripts/BuiltInLate.sh"
printf '#!/system/bin/sh\nprintf "old safe built-in\\n"\n' > "$PERSISTENT_DIR/scripts/BuiltInSafe.sh"
printf '#!/system/bin/sh\nprintf "mine\\n"\n' > "$PERSISTENT_DIR/scripts/MyCustom.sh"
mkdir -p "$PERSISTENT_DIR/state/builtin-baselines" "$PERSISTENT_DIR/.webui_config"
cp "$PERSISTENT_DIR/scripts/BuiltInSafe.sh" "$PERSISTENT_DIR/state/builtin-baselines/BuiltInSafe.sh"
printf '/* keep */\n' > "$PERSISTENT_DIR/.webui_config/custom.css"
awk 'BEGIN { for (i = 0; i < 8200; i++) printf "x" }' > "$PERSISTENT_DIR/cmdline_or_bootconfig.txt"
cat > "$PERSISTENT_DIR/kstat_paths.txt" <<'EOF'
# keep this comment
/system/etc/hosts 100 default default 64 default default default default default default 1 4096
/system/etc/hosts 101 default default 64 default default default default default default 1 4096
/data/adb/ReSuSFS default default default default default default default default default default default default
/data/adb/SusAF default default default default default default default default default default default default
EOF

installer_prepare_report
checkpoint_existing_install
merge_schedule_defaults "$PACKAGE_DIR/scripts_postfs.txt" "$PERSISTENT_DIR/scripts_postfs.txt"
merge_schedule_defaults "$PACKAGE_DIR/scripts_bootcompleted.txt" "$PERSISTENT_DIR/scripts_bootcompleted.txt"
merge_config_defaults "$PACKAGE_DIR/config.txt" "$PERSISTENT_DIR/config.txt"
install_packaged_builtins "$PACKAGE_DIR/scripts" "$PERSISTENT_DIR/scripts"
install_missing_defaults "$PACKAGE_DIR" "$PERSISTENT_DIR"
repair_oversized_cmdline_bootconfig "$PACKAGE_DIR/cmdline_or_bootconfig.txt"
remove_generated_kstat_entries
installer_finish_report ok

grep -Fqx 'Max_Saturation.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt"
grep -Fqx '!BuiltInLate.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt"
! grep -Fqx 'BuiltInLate.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt"
[ "$(grep -Fxc 'Max_Saturation.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt")" -eq 1 ]
grep -Fqx 'BuiltInEarly.sh' "$PERSISTENT_DIR/scripts_postfs.txt"
grep -Fqx 'KEEP_VALUE=custom' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'CUSTOM_VALUE=keep' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'NEW_OPTION=1' "$PERSISTENT_DIR/config.txt"
grep -Fq 'old built-in' "$PERSISTENT_DIR/scripts/BuiltInLate.sh"
grep -Fq 'new built-in' "$PERSISTENT_DIR/state/builtin-updates/BuiltInLate.sh"
grep -Fq 'updated safe built-in' "$PERSISTENT_DIR/scripts/BuiltInSafe.sh"
grep -Fq 'updated safe built-in' "$PERSISTENT_DIR/state/builtin-baselines/BuiltInSafe.sh"
[ ! -e "$PERSISTENT_DIR/state/builtin-updates/BuiltInSafe.sh" ]
grep -Fq 'mine' "$PERSISTENT_DIR/scripts/MyCustom.sh"
cmp "$PACKAGE_DIR/cmdline_or_bootconfig.txt" "$PERSISTENT_DIR/cmdline_or_bootconfig.txt"
find "$PERSISTENT_DIR/migration" -path '*/repaired-config/cmdline_or_bootconfig.txt' -size 8200c | grep -q .
grep -Fqx '# keep this comment' "$PERSISTENT_DIR/kstat_paths.txt"
! grep -Fqx '/system/etc/hosts 100 default default 64 default default default default default default 1 4096' "$PERSISTENT_DIR/kstat_paths.txt"
grep -Fqx '/system/etc/hosts 101 default default 64 default default default default default default 1 4096' "$PERSISTENT_DIR/kstat_paths.txt"
! grep -Fq '/data/adb/ReSuSFS' "$PERSISTENT_DIR/kstat_paths.txt"
! grep -Fq '/data/adb/SusAF' "$PERSISTENT_DIR/kstat_paths.txt"
kstat_backup=$(find "$PERSISTENT_DIR/migration" -path '*/repaired-config/kstat_paths.txt' -print -quit)
[ -n "$kstat_backup" ]
grep -Fq '/data/adb/ReSuSFS' "$kstat_backup"
grep -Fq '/system/etc/hosts 100 default default 64' "$kstat_backup"
checkpoint=$(sed -n 's/^checkpoint=//p' "$PERSISTENT_DIR/state/installer.report.txt")
[ -d "$checkpoint" ]
grep -Fq 'old built-in' "$checkpoint/scripts/BuiltInLate.sh"
grep -Fq '/* keep */' "$checkpoint/.webui_config/custom.css"
grep -Fqx 'config_keys_added=1' "$PERSISTENT_DIR/state/installer.report.txt"
grep -Fqx 'schedule_repairs=1' "$PERSISTENT_DIR/state/installer.report.txt"
grep -Fqx 'builtin_updates_pending=1' "$PERSISTENT_DIR/state/installer.report.txt"
grep -Fqx 'result=ok' "$PERSISTENT_DIR/state/installer.report.txt"

! grep -Eq 'VOLUME (UP|DOWN)|getevent|detect_key_press' "$(dirname "$0")/../module/customize.sh"

echo "install config tests passed"
