#!/system/bin/sh

# Reversible device-hardening helpers for temporarily disabling Android
# debugging surfaces during a security review. This changes the real system
# state; it does not spoof detector results.

hardening_state_dir() {
    printf "%s\n" "$PERSISTENT_DIR/state"
}

hardening_snapshot_file() {
    printf "%s\n" "$(hardening_state_dir)/security-hardening.snapshot"
}

hardening_report_file() {
    printf "%s\n" "$(hardening_state_dir)/security-hardening.report.txt"
}

hardening_init() {
    HARDEN_SETTINGS_BIN="${SUSAF_SETTINGS_BIN:-/system/bin/settings}"
    HARDEN_GETPROP_BIN="${SUSAF_GETPROP_BIN:-/system/bin/getprop}"
    HARDEN_SETPROP_BIN="${SUSAF_SETPROP_BIN:-/system/bin/setprop}"
    HARDEN_PIDOF_BIN="${SUSAF_PIDOF_BIN:-/system/bin/pidof}"
    HARDEN_SLEEP_BIN="${SUSAF_SLEEP_BIN:-/system/bin/sleep}"
    HARDEN_RESETPROP_BIN="${SUSAF_RESETPROP_BIN:-}"
    if [ -z "$HARDEN_RESETPROP_BIN" ]; then
        HARDEN_RESETPROP_BIN=$(command -v resetprop 2>/dev/null || true)
    fi
    mkdir -p "$(hardening_state_dir)" || return 1
    chmod 700 "$(hardening_state_dir)" 2>/dev/null || true
}

hardening_one_line() {
    printf "%s" "$1" | tr "\r\n\t" "   " | sed "s/[[:space:]][[:space:]]*/ /g;s/^ //;s/ $//"
}

hardening_read_setting() {
    value=$("$HARDEN_SETTINGS_BIN" get global "$1" 2>/dev/null) || value=unavailable
    hardening_one_line "$value"
}

hardening_read_prop() {
    value=$("$HARDEN_GETPROP_BIN" "$1" 2>/dev/null) || value=unavailable
    hardening_one_line "$value"
}

hardening_adbd_pids() {
    value=$("$HARDEN_PIDOF_BIN" adbd 2>/dev/null) || value=
    hardening_one_line "$value"
}

hardening_remove_adb_token() {
    input="$1"
    oldifs="$IFS"
    IFS=,
    out=
    for token in $input; do
        IFS="$oldifs"
        token=$(printf "%s" "$token" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")
        [ -n "$token" ] || { IFS=,; continue; }
        [ "$token" = adb ] && { IFS=,; continue; }
        if [ -n "$out" ]; then out="$out,$token"; else out="$token"; fi
        IFS=,
    done
    IFS="$oldifs"
    [ -n "$out" ] || out=mtp
    printf "%s\n" "$out"
}

hardening_write_persist_usb() {
    value="$1"
    if [ -n "$HARDEN_RESETPROP_BIN" ] && [ -x "$HARDEN_RESETPROP_BIN" ]; then
        "$HARDEN_RESETPROP_BIN" persist.sys.usb.config "$value" >/dev/null 2>&1 && return 0
    fi
    "$HARDEN_SETPROP_BIN" persist.sys.usb.config "$value" >/dev/null 2>&1
}

hardening_snapshot() {
    hardening_init || return 1
    file=$(hardening_snapshot_file)
    [ -f "$file" ] && return 0
    tmp="${file}.tmp.$$"
    umask 077
    {
        echo "schema=1"
        echo "created.epoch=$(date +%s 2>/dev/null)"
        echo "development_settings_enabled=$(hardening_read_setting development_settings_enabled)"
        echo "adb_enabled=$(hardening_read_setting adb_enabled)"
        echo "adb_wifi_enabled=$(hardening_read_setting adb_wifi_enabled)"
        echo "init.svc.adbd=$(hardening_read_prop init.svc.adbd)"
        echo "adbd_pids=$(hardening_adbd_pids)"
        echo "sys.usb.config=$(hardening_read_prop sys.usb.config)"
        echo "persist.sys.usb.config=$(hardening_read_prop persist.sys.usb.config)"
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$file"
}

hardening_snapshot_value() {
    sed -n "s/^$1=//p" "$(hardening_snapshot_file)" 2>/dev/null | tail -n1
}

hardening_status() {
    hardening_init || return 1
    snapshot=$(hardening_snapshot_file)
    [ -f "$snapshot" ] && active=1 || active=0
    persist=$(hardening_read_prop persist.sys.usb.config)
    echo "schema=1"
    echo "active=$active"
    echo "snapshot=$([ -f "$snapshot" ] && printf present || printf none)"
    echo "development_settings_enabled=$(hardening_read_setting development_settings_enabled)"
    echo "adb_enabled=$(hardening_read_setting adb_enabled)"
    echo "adb_wifi_enabled=$(hardening_read_setting adb_wifi_enabled)"
    echo "init.svc.adbd=$(hardening_read_prop init.svc.adbd)"
    echo "adbd_pids=$(hardening_adbd_pids)"
    echo "sys.usb.config=$(hardening_read_prop sys.usb.config)"
    echo "persist.sys.usb.config=$persist"
    case ",$persist," in
        *,adb,*) echo "usb_adb_token=present" ;;
        *) echo "usb_adb_token=absent" ;;
    esac
}

hardening_enter() {
    hardening_init || return 1
    hardening_snapshot || return 1
    report=$(hardening_report_file)
    umask 077
    {
        echo "schema=1"
        echo "operation=enter"
        echo "started.epoch=$(date +%s 2>/dev/null)"
    } > "$report"

    for key in development_settings_enabled adb_enabled adb_wifi_enabled; do
        "$HARDEN_SETTINGS_BIN" put global "$key" 0 >/dev/null 2>&1 || {
            echo "result=settings-write-failed:$key" >> "$report"
            cat "$report"
            return 1
        }
    done

    persist=$(hardening_read_prop persist.sys.usb.config)
    sys=$(hardening_read_prop sys.usb.config)
    desired_persist=$(hardening_remove_adb_token "$persist")
    desired_sys=$(hardening_remove_adb_token "$sys")

    hardening_write_persist_usb "$desired_persist" || {
        echo "result=persist-usb-write-failed" >> "$report"
        cat "$report"
        return 1
    }
    case ",$sys," in
        *,adb,*) "$HARDEN_SETPROP_BIN" sys.usb.config "$desired_sys" >/dev/null 2>&1 || true ;;
    esac

    "$HARDEN_SETPROP_BIN" ctl.stop adbd >/dev/null 2>&1 || {
        echo "result=adbd-stop-request-failed" >> "$report"
        cat "$report"
        return 1
    }

    wait_count=0
    while [ "$wait_count" -lt 5 ] && [ -n "$(hardening_adbd_pids)" ]; do
        "$HARDEN_SLEEP_BIN" 1
        wait_count=$((wait_count + 1))
    done

    hardening_status >> "$report"
    [ "$(hardening_read_setting development_settings_enabled)" = 0 ] || { echo "result=verification-failed:developer-options" >> "$report"; cat "$report"; return 1; }
    [ "$(hardening_read_setting adb_enabled)" = 0 ] || { echo "result=verification-failed:usb-debugging" >> "$report"; cat "$report"; return 1; }
    [ "$(hardening_read_setting adb_wifi_enabled)" = 0 ] || { echo "result=verification-failed:wireless-debugging" >> "$report"; cat "$report"; return 1; }
    [ -z "$(hardening_adbd_pids)" ] || { echo "result=verification-failed:adbd" >> "$report"; cat "$report"; return 1; }
    case ",$(hardening_read_prop persist.sys.usb.config)," in
        *,adb,*) echo "result=verification-failed:usb-config" >> "$report"; cat "$report"; return 1 ;;
    esac
    echo "result=active" >> "$report"
    cat "$report"
}

hardening_restore_setting() {
    key="$1"
    value=$(hardening_snapshot_value "$key")
    case "$value" in ""|unavailable) return 0 ;; esac
    "$HARDEN_SETTINGS_BIN" put global "$key" "$value" >/dev/null 2>&1
}

hardening_restore() {
    hardening_init || return 1
    snapshot=$(hardening_snapshot_file)
    [ -f "$snapshot" ] || { echo "[x] no security hardening snapshot found"; return 1; }
    report=$(hardening_report_file)
    umask 077
    { echo "schema=1"; echo "operation=restore"; echo "started.epoch=$(date +%s 2>/dev/null)"; } > "$report"

    for key in development_settings_enabled adb_enabled adb_wifi_enabled; do
        hardening_restore_setting "$key" || {
            echo "result=settings-restore-failed:$key" >> "$report"
            cat "$report"
            return 1
        }
    done

    persist=$(hardening_snapshot_value persist.sys.usb.config)
    sys=$(hardening_snapshot_value sys.usb.config)
    adbd=$(hardening_snapshot_value init.svc.adbd)
    case "$persist" in ""|unavailable) ;; *) hardening_write_persist_usb "$persist" || { echo "result=persist-usb-restore-failed" >> "$report"; cat "$report"; return 1; } ;; esac
    case "$sys" in ""|unavailable) ;; *) "$HARDEN_SETPROP_BIN" sys.usb.config "$sys" >/dev/null 2>&1 || true ;; esac
    case "$adbd" in running|restarting) "$HARDEN_SETPROP_BIN" ctl.start adbd >/dev/null 2>&1 || true ;; esac

    archived="$(hardening_state_dir)/security-hardening.last-snapshot"
    mv "$snapshot" "$archived" || return 1
    echo "snapshot.archived=$archived" >> "$report"
    echo "result=restored" >> "$report"
    cat "$report"
}
