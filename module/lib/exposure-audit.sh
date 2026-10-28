#!/bin/sh

# Read-only temporary-root evidence collection. These observations are NOT
# automatic hiding candidates. Root-side reads cannot prove app visibility.

exposure_object_type() {
    if [ -L "$1" ]; then printf 'symlink\n'
    elif [ -S "$1" ]; then printf 'socket\n'
    elif [ -f "$1" ]; then printf 'file\n'
    elif [ -d "$1" ]; then printf 'directory\n'
    else printf 'other\n'
    fi
}

exposure_backend() {
    if command -v susfs_has_command >/dev/null 2>&1; then
        if susfs_has_command add_sus_path_loop; then printf 'loop\n'; return; fi
        if susfs_has_command add_sus_path; then printf 'static-only\n'; return; fi
        printf 'unsupported\n'
    else
        printf 'not-checked\n'
    fi
}

exposure_configured() {
    local path="$1"
    if coverage_list_contains "$PERSISTENT_DIR/sus_paths_loop.txt" "$path"; then
        printf 'listed-loop\n'
    elif coverage_list_contains "$PERSISTENT_DIR/sus_paths.txt" "$path"; then
        printf 'listed-static\n'
    else
        printf 'not-listed\n'
    fi
}

exposure_record() {
    local output="$1" path="$2" scope="$3" backend="$4"
    coverage_path_is_safe "$path" || return 0
    [ -e "$path" ] || [ -L "$path" ] || return 0
    # A local tab-delimited record: no file contents, socket bytes, or FDs.
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$path" "$(exposure_object_type "$path")" "$scope" \
        "$(exposure_configured "$path")" "$backend" >> "$output"
}

exposure_scan() {
    local output="$1" tmp_root="${SUSAF_EXPOSURE_TMP_ROOT:-/data/local/tmp}"
    local apex_su="${SUSAF_EXPOSURE_APEX_SU:-/apex/com.android.virt/bin/su}"
    local max="${SUSAF_EXPOSURE_MAX_ITEMS:-64}"
    local entry name count=0 backend
    EXPOSURE_TMP_CHECK=not-checked
    EXPOSURE_APEX_CHECK=not-checked
    EXPOSURE_TRUNCATED=0
    case "$max" in ''|*[!0-9]*) max=64 ;; esac
    [ "$max" -ge 1 ] && [ "$max" -le 128 ] || max=64
    : > "$output" || return 1
    backend=$(exposure_backend)

    if [ -d "$tmp_root" ] && [ -r "$tmp_root" ] && [ -x "$tmp_root" ]; then
        EXPOSURE_TMP_CHECK=checked
        # Direct children only; never recurse or follow directory symlinks.
        for entry in "$tmp_root"/* "$tmp_root"/.[!.]* "$tmp_root"/..?*; do
            [ -e "$entry" ] || [ -L "$entry" ] || continue
            name=${entry##*/}
            case "$name" in
                su|su.*|*.su|.*su_*|*su.sock|ksud|ksud.*|*ksu*|*KSU*|*root*|*Root*|*magisk*|*Magisk*|*zygisk*|*Zygisk*|*ghostlock*|*GhostLock*|*bakasu*|*resukisu*|*.sock)
                    [ "$count" -lt "$max" ] || { EXPOSURE_TRUNCATED=1; break; }
                    exposure_record "$output" "$entry" temp-root "$backend" || return 1
                    count=$((count + 1))
                    ;;
            esac
        done
    else
        EXPOSURE_TMP_CHECK=unavailable
    fi

    # One known APEX path; explicitly do not enumerate APEX contents.
    if [ -d "${apex_su%/*}" ] && [ -x "${apex_su%/*}" ]; then
        EXPOSURE_APEX_CHECK=checked
        if [ -e "$apex_su" ] || [ -L "$apex_su" ]; then
            if [ "$count" -lt "$max" ]; then
                exposure_record "$output" "$apex_su" apex-su "$backend" || return 1
            else
                EXPOSURE_TRUNCATED=1
            fi
        fi
    elif [ "$apex_su" = /apex/com.android.virt/bin/su ] &&
         [ -d /apex ] && [ -x /apex ]; then
        # The optional virtual APEX is absent on many devices. Its absence
        # is evidence of no such root-side path, not a scan failure.
        EXPOSURE_APEX_CHECK=absent
    else
        EXPOSURE_APEX_CHECK=unavailable
    fi
}

exposure_emit_report() {
    local file="$1" count index=0 path type scope configured backend app_state app_uid
    local visible missing denied errors checked=0 verification overall=not-tested
    count=$(awk 'END { print NR + 0 }' "$file")
    visible=$(awk -F '\t' '$6=="VISIBLE" { n++ } END { print n+0 }' "$file")
    missing=$(awk -F '\t' '$6=="MISSING" { n++ } END { print n+0 }' "$file")
    denied=$(awk -F '\t' '$6=="DENIED" { n++ } END { print n+0 }' "$file")
    errors=$(awk -F '\t' '$6=="ERROR" || $6=="INVALID" { n++ } END { print n+0 }' "$file")
    checked=$((visible + missing + denied + errors))
    if [ "$checked" -gt 0 ]; then
        if [ "$checked" -eq "$count" ]; then verification=checked
        else verification=partial
        fi
    fi
    coverage_put exposure.schema 2
    coverage_put exposure.observer root-shell
    coverage_put exposure.tmp_check "$EXPOSURE_TMP_CHECK"
    coverage_put exposure.apex_check "$EXPOSURE_APEX_CHECK"
    coverage_put exposure.truncated "$EXPOSURE_TRUNCATED"
    coverage_put exposure.count "$count"
    coverage_put exposure.app_visibility "$verification"
    coverage_put exposure.verification_method "$([ "$checked" -gt 0 ] && printf companion-contentprovider || printf none)"
    coverage_put exposure.probe_status "${PROBE_STATUS:-not-run}"
    coverage_put exposure.probe_uid "${PROBE_UID:-0}"
    coverage_put exposure.visible_count "$visible"
    coverage_put exposure.missing_count "$missing"
    coverage_put exposure.denied_count "$denied"
    coverage_put exposure.error_count "$errors"
    coverage_put exposure.policy_action none
    if [ "$EXPOSURE_TMP_CHECK" != checked ] ||
        { [ "$EXPOSURE_APEX_CHECK" != checked ] && [ "$EXPOSURE_APEX_CHECK" != absent ]; } ||
        [ "$EXPOSURE_TRUNCATED" = 1 ]; then
        overall=incomplete
    elif [ "$count" -eq 0 ]; then
        overall=no-observations-unverified
    elif [ "$visible" -gt 0 ]; then
        overall=observed-app-visible
    elif [ "$verification" = checked ]; then
        overall=observed-app-not-visible
    else
        overall=observed-unverified
    fi
    coverage_put exposure.result "$overall"
    while IFS="$(printf '\t')" read -r path type scope configured backend app_state app_uid ||
        [ -n "$path$type$scope$configured$backend$app_state$app_uid" ]; do
        [ -n "$path" ] || continue
        index=$((index + 1))
        case "$app_state" in
            VISIBLE) app_state=visible ;;
            MISSING) app_state=not-found ;;
            DENIED) app_state=permission-denied ;;
            ERROR|INVALID) app_state=error ;;
            *) app_state=not-tested ;;
        esac
        coverage_put "exposure.$index.path" "$path"
        coverage_put "exposure.$index.type" "$type"
        coverage_put "exposure.$index.scope" "$scope"
        coverage_put "exposure.$index.configured" "$configured"
        coverage_put "exposure.$index.backend_supported" "$backend"
        coverage_put "exposure.$index.operation_result" not-attempted
        coverage_put "exposure.$index.app_visibility" "$app_state"
        coverage_put "exposure.$index.verification_method" "$([ "$app_state" != not-tested ] && printf companion-contentprovider || printf none)"
        coverage_put "exposure.$index.probe_uid" "${app_uid:-0}"
    done < "$file"
}
