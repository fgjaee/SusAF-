#!/bin/sh

# Manual recovery for paths ALREADY configured in Sus'AF and confirmed
# visible by the unprivileged companion. Never changes persistent policy.
# A runtime registration is only considered effective after a fresh probe.

coverage_repair_visible() {
    local state_dir="$PERSISTENT_DIR/state" before report temp snapshot targets
    local count index path configured backend app_state observed support command status
    local item=0 accepted=0 rejected=0 unsupported=0 visible=0 not_visible=0 unknown=0
    local after_count after_index after_path after_state outcome found result exit_result=0

    state_dir="$PERSISTENT_DIR/state"
    before="$state_dir/coverage.report.txt"
    report="$state_dir/coverage.repair.txt"
    temp="$state_dir/coverage.repair.tmp.$$"
    snapshot="$state_dir/coverage.repair.before.$$"
    targets="$state_dir/coverage.repair.targets.$$"
    umask 077
    mkdir -p "$state_dir" || return 1

    # Never act on an old saved app-side observation.
    if ! coverage_scan >/dev/null; then
        coverage_put result pre-scan-failed
        return 1
    fi
    if [ "$(coverage_property "$before" exposure.probe_status not-run)" != ready ] ||
       [ "$(coverage_property "$before" exposure.app_visibility not-tested)" != checked ]; then
        coverage_put result probe-not-ready
        return 1
    fi
    count=$(coverage_property "$before" exposure.count 0)
    case "$count" in ''|*[!0-9]*) coverage_put result invalid-evidence; return 1 ;; esac
    [ "$count" -le 128 ] || { coverage_put result invalid-evidence; return 1; }
    cp "$before" "$snapshot" || return 1
    : > "$targets" || { rm -f "$snapshot"; return 1; }

    {
        coverage_put schema 1
        coverage_put operation manual-runtime-repair
        coverage_put generated.at "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
        coverage_put policy.changed 0
        coverage_put before.visible "$(coverage_property "$snapshot" exposure.visible_count 0)"
        coverage_put before.configured_visible "$(coverage_property "$snapshot" exposure.configured_visible_count 0)"
    } > "$temp" || { rm -f "$snapshot" "$targets" "$temp"; return 1; }

    index=1
    while [ "$index" -le "$count" ]; do
        path=$(coverage_property "$snapshot" "exposure.$index.path" "")
        configured=$(coverage_property "$snapshot" "exposure.$index.configured" "")
        backend=$(coverage_property "$snapshot" "exposure.$index.backend_supported" "")
        app_state=$(coverage_property "$snapshot" "exposure.$index.app_visibility" "")
        index=$((index + 1))
        [ "$app_state" = visible ] || continue
        case "$configured" in listed-loop|listed-static) ;; *) continue ;; esac
        coverage_runtime_path_is_reviewable "$path" || continue
        coverage_path_is_safe "$path" || continue

        item=$((item + 1))
        command=""
        status=unsupported
        case "$backend" in
            loop)
                if command -v susfs_has_command >/dev/null 2>&1 &&
                   susfs_has_command add_sus_path_loop; then
                    command=add_sus_path_loop
                fi ;;
            static-only)
                if command -v susfs_has_command >/dev/null 2>&1 &&
                   susfs_has_command add_sus_path; then
                    command=add_sus_path
                fi ;;
        esac

        if [ -z "$command" ]; then
            unsupported=$((unsupported + 1))
        elif [ ! -e "$path" ] && [ ! -L "$path" ]; then
            status=disappeared-before-apply
            unknown=$((unknown + 1))
        elif susfs "$command" "$path" >/dev/null 2>&1; then
            status=registration-accepted
            accepted=$((accepted + 1))
        else
            status=registration-rejected
            rejected=$((rejected + 1))
        fi
        printf '%s\t%s\n' "$path" "$status" >> "$targets"
        {
            coverage_put "item.$item.path" "$path"
            coverage_put "item.$item.backend" "$backend"
            coverage_put "item.$item.command" "$command"
            coverage_put "item.$item.registration" "$status"
        } >> "$temp"
    done

    {
        coverage_put attempted "$item"
        coverage_put registrations.accepted "$accepted"
        coverage_put registrations.rejected "$rejected"
        coverage_put registrations.unsupported "$unsupported"
    } >> "$temp"

    if [ "$item" -eq 0 ]; then
        result=no-configured-visible-paths
    elif ! coverage_scan >/dev/null; then
        result=post-scan-failed
        exit_result=1
    elif [ "$(coverage_property "$before" exposure.probe_status not-run)" != ready ] ||
         [ "$(coverage_property "$before" exposure.app_visibility not-tested)" != checked ]; then
        result=post-probe-not-ready
        exit_result=1
    else
        after_count=$(coverage_property "$before" exposure.count 0)
        case "$after_count" in ''|*[!0-9]*) after_count=0 ;; esac
        {
            coverage_put after.visible "$(coverage_property "$before" exposure.visible_count 0)"
            coverage_put after.configured_visible "$(coverage_property "$before" exposure.configured_visible_count 0)"
        } >> "$temp"

        while IFS="$(printf '\t')" read -r path status || [ -n "$path$status" ]; do
            [ -n "$path" ] || continue
            outcome=not-observed
            found=0
            after_index=1
            while [ "$after_index" -le "$after_count" ]; do
                after_path=$(coverage_property "$before" "exposure.$after_index.path" "")
                if [ "$after_path" = "$path" ]; then
                    after_state=$(coverage_property "$before" "exposure.$after_index.app_visibility" not-tested)
                    found=1
                    case "$after_state" in
                        visible) outcome=still-visible; visible=$((visible + 1)) ;;
                        not-found|permission-denied) outcome=not-visible-to-probe; not_visible=$((not_visible + 1)) ;;
                        *) outcome=unverified; unknown=$((unknown + 1)) ;;
                    esac
                    break
                fi
                after_index=$((after_index + 1))
            done
            if [ "$found" -eq 0 ]; then
                # No longer present in a root-side scan is not proof of hiding.
                unknown=$((unknown + 1))
            fi
            coverage_put "verification.$((visible + not_visible + unknown)).path" "$path" >> "$temp"
            coverage_put "verification.$((visible + not_visible + unknown)).result" "$outcome" >> "$temp"
        done < "$targets"
        if [ "$visible" -gt 0 ]; then
            result=still-visible
            exit_result=1
        elif [ "$unknown" -gt 0 ] || [ "$rejected" -gt 0 ] || [ "$unsupported" -gt 0 ]; then
            result=incomplete
            exit_result=1
        else
            result=not-visible-to-probe
        fi
    fi
    {
        coverage_put verified.not_visible "$not_visible"
        coverage_put verified.still_visible "$visible"
        coverage_put verified.unknown "$unknown"
        coverage_put result "$result"
    } >> "$temp"
    chmod 600 "$temp" 2>/dev/null
    mv "$temp" "$report" || { rm -f "$snapshot" "$targets" "$temp"; return 1; }
    rm -f "$snapshot" "$targets"
    cat "$report"
    return "$exit_result"
}
