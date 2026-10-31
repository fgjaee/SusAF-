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
    HARDEN_SVC_BIN="${SUSAF_SVC_BIN:-/system/bin/svc}"
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
    tries=0
    while [ "$tries" -lt 3 ]; do
        if [ -n "$HARDEN_RESETPROP_BIN" ] && [ -x "$HARDEN_RESETPROP_BIN" ]; then
            "$HARDEN_RESETPROP_BIN" persist.sys.usb.config "$value" >/dev/null 2>&1 || true
        fi
        "$HARDEN_SETPROP_BIN" persist.sys.usb.config "$value" >/dev/null 2>&1 || true
        [ "$(hardening_read_prop persist.sys.usb.config)" = "$value" ] && return 0
        "$HARDEN_SLEEP_BIN" 1
        tries=$((tries + 1))
    done
    return 1
}

hardening_adb_token_present() {
    case ",$1," in
        *,adb,*) return 0 ;;
        *) return 1 ;;
    esac
}

hardening_put_setting() {
    key="$1"
    wanted="$2"
    tries=0
    while [ "$tries" -lt 3 ]; do
        "$HARDEN_SETTINGS_BIN" put global "$key" "$wanted" >/dev/null 2>&1 || true
        [ "$(hardening_read_setting "$key")" = "$wanted" ] && return 0
        "$HARDEN_SLEEP_BIN" 1
        tries=$((tries + 1))
    done
    return 1
}

hardening_stop_adbd() {
    tries=0
    while [ "$tries" -lt 4 ]; do
        "$HARDEN_SETPROP_BIN" ctl.stop adbd >/dev/null 2>&1 || true
        [ -z "$(hardening_adbd_pids)" ] && return 0
        "$HARDEN_SLEEP_BIN" 1
        tries=$((tries + 1))
    done
    return 1
}

hardening_set_current_usb_no_adb() {
    current=$(hardening_read_prop sys.usb.config)
    desired=$(hardening_remove_adb_token "$current")
    tries=0
    while [ "$tries" -lt 3 ]; do
        if [ -x "$HARDEN_SVC_BIN" ]; then
            "$HARDEN_SVC_BIN" usb setFunctions "$desired" >/dev/null 2>&1 || true
        fi
        "$HARDEN_SETPROP_BIN" sys.usb.config "$desired" >/dev/null 2>&1 || true
        current=$(hardening_read_prop sys.usb.config)
        hardening_adb_token_present "$current" || return 0
        "$HARDEN_SLEEP_BIN" 1
        tries=$((tries + 1))
    done
    return 1
}

hardening_write_current_usb_exact() {
    value="$1"
    if [ -x "$HARDEN_SVC_BIN" ]; then
        "$HARDEN_SVC_BIN" usb setFunctions "$value" >/dev/null 2>&1 || true
    fi
    "$HARDEN_SETPROP_BIN" sys.usb.config "$value" >/dev/null 2>&1 || true
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
    [ -f "$snapshot" ] && snapshot_state=present || snapshot_state=none

    dev=$(hardening_read_setting development_settings_enabled)
    adb=$(hardening_read_setting adb_enabled)
    wifi=$(hardening_read_setting adb_wifi_enabled)
    adbd=$(hardening_read_prop init.svc.adbd)
    pids=$(hardening_adbd_pids)
    sys=$(hardening_read_prop sys.usb.config)
    persist=$(hardening_read_prop persist.sys.usb.config)

    hardened=1
    [ "$dev" = 0 ] || hardened=0
    [ "$adb" = 0 ] || hardened=0
    [ "$wifi" = 0 ] || hardened=0
    [ -z "$pids" ] || hardened=0
    hardening_adb_token_present "$sys" && hardened=0
    hardening_adb_token_present "$persist" && hardened=0

    if [ "$hardened" -eq 1 ]; then
        state=active
    elif [ "$snapshot_state" = present ]; then
        state=partial
    else
        state=inactive
    fi

    echo "schema=2"
    echo "state=$state"
    echo "active=$hardened"
    echo "snapshot=$snapshot_state"
    echo "development_settings_enabled=$dev"
    echo "adb_enabled=$adb"
    echo "adb_wifi_enabled=$wifi"
    echo "init.svc.adbd=$adbd"
    echo "adbd_pids=$pids"
    echo "sys.usb.config=$sys"
    echo "persist.sys.usb.config=$persist"
    hardening_adb_token_present "$sys" && echo "sys_usb_adb_token=present" || echo "sys_usb_adb_token=absent"
    hardening_adb_token_present "$persist" && echo "persist_usb_adb_token=present" || echo "persist_usb_adb_token=absent"
}

hardening_enter() {
    hardening_init || return 1
    hardening_snapshot || return 1
    report=$(hardening_report_file)
    umask 077
    {
        echo "schema=2"
        echo "operation=enter"
        echo "started.epoch=$(date +%s 2>/dev/null)"
    } > "$report"

    # Android 17 can reassert ADB from framework observers while these values
    # change. Apply the shutdown in stages, then repeat the decisive controls.
    hardening_put_setting adb_wifi_enabled 0 || echo "warning=wireless-debugging-reasserted" >> "$report"
    hardening_put_setting adb_enabled 0 || echo "warning=usb-debugging-reasserted" >> "$report"

    persist=$(hardening_read_prop persist.sys.usb.config)
    desired_persist=$(hardening_remove_adb_token "$persist")

    hardening_stop_adbd || echo "warning=adbd-still-running-first-pass" >> "$report"
    hardening_set_current_usb_no_adb || echo "warning=current-usb-adb-reasserted-first-pass" >> "$report"
    hardening_write_persist_usb "$desired_persist" || echo "warning=persist-usb-adb-reasserted-first-pass" >> "$report"

    hardening_put_setting development_settings_enabled 0 || echo "warning=developer-options-reasserted" >> "$report"

    # Final enforcement pass after Developer Options changed. This catches the
    # framework/property race seen on Pixel Android 17.
    hardening_put_setting adb_wifi_enabled 0 || true
    hardening_put_setting adb_enabled 0 || true
    hardening_stop_adbd || true
    hardening_set_current_usb_no_adb || true
    hardening_write_persist_usb "$desired_persist" || true
    "$HARDEN_SLEEP_BIN" 1

    hardening_status >> "$report"
    final_state=$(sed -n 's/^state=//p' "$report" | tail -n1)
    if [ "$final_state" = active ]; then
        echo "result=active" >> "$report"
        cat "$report"
        return 0
    fi

    echo "result=verification-failed:partial-hardening" >> "$report"
    cat "$report"
    return 1
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

    # Restore Developer Options first so Android will accept the saved ADB state.
    hardening_restore_setting development_settings_enabled || {
        echo "result=settings-restore-failed:development_settings_enabled" >> "$report"
        cat "$report"
        return 1
    }

    persist=$(hardening_snapshot_value persist.sys.usb.config)
    sys=$(hardening_snapshot_value sys.usb.config)
    adbd=$(hardening_snapshot_value init.svc.adbd)
    case "$persist" in ""|unavailable) ;; *) hardening_write_persist_usb "$persist" || { echo "result=persist-usb-restore-failed" >> "$report"; cat "$report"; return 1; } ;; esac
    case "$sys" in ""|unavailable) ;; *) hardening_write_current_usb_exact "$sys" ;; esac

    for key in adb_enabled adb_wifi_enabled; do
        hardening_restore_setting "$key" || {
            echo "result=settings-restore-failed:$key" >> "$report"
            cat "$report"
            return 1
        }
    done

    case "$adbd" in running|restarting) "$HARDEN_SETPROP_BIN" ctl.start adbd >/dev/null 2>&1 || true ;; esac

    archived="$(hardening_state_dir)/security-hardening.last-snapshot"
    mv "$snapshot" "$archived" || return 1
    echo "snapshot.archived=$archived" >> "$report"
    echo "result=restored" >> "$report"
    cat "$report"
}
