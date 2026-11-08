#!/bin/sh

# Optional, bounded, real-app filesystem visibility check.
# Only the companion APK performs lstat, in its own unprivileged process.
# No probe APK / provider means an explicit NOT_TESTED result.

probe_parse_reply() {
    # The content CLI wraps Bundle values differently across Android builds.
    # Extract only the bounded protocol fields, never trailing wrapper text.
    printf '%s\n' "$1" | sed -n \
        's/^.*SUSAFPROBEV1__\([0-9][0-9]*\)__\([0-9][0-9]*\)__\([A-Z_,][A-Z_,]*\).*$/\1|\2|\3/p' |
        sed -n '1p'
}

probe_record_error() {
    local reason="$1" reply="${2:-}" parsed="${3:-}" file="$PERSISTENT_DIR/state/probe.last_error.txt"
    mkdir -p "$PERSISTENT_DIR/state" 2>/dev/null || return 0
    umask 077
    {
        printf 'epoch=%s\n' "$(date +%s 2>/dev/null)"
        printf 'reason=%s\n' "$reason"
        printf 'parsed=%s\n' "$(printf '%s' "$parsed" | tr '\r\n\t' '   ' | sed 's/[[:cntrl:]]//g' | cut -c1-240)"
        printf 'reply=%s\n' "$(printf '%s' "$reply" | tr '\r\n\t' '   ' | sed 's/[[:cntrl:]]//g' | cut -c1-240)"
    } > "${file}.tmp.$$" 2>/dev/null && mv "${file}.tmp.$$" "$file" ||
        rm -f "${file}.tmp.$$"
}

probe_check_batch() {
    local file="$1" out="$2" start="$3" stop="$4"
    local payload reply parsed uid remainder size states expected_count attempt rc
    payload=$(awk -F '\t' -v first="$start" -v last="$stop" '
        NR>=first && NR<=last { if (NR>first) printf "\n"; printf "%s", $1 }
    ' "$file") || return 1
    [ -n "$payload" ] || return 1
    parsed=""
    attempt=1
    while [ "$attempt" -le 3 ]; do
        if reply=$("$PROBE_CONTENT_BIN" call --uri content://com.fgjaee.susaf.probe --method scan --arg "$payload" 2>&1); then
            parsed=$(probe_parse_reply "$reply" 2>/dev/null) || parsed=""
            [ -n "$parsed" ] && break
        else
            rc=$?
        fi
        rc=${rc:-0}
        probe_record_error "call-attempt-$attempt-exit-$rc" "$reply"
        [ "$attempt" -ge 3 ] || sleep "${SUSAF_PROBE_RETRY_DELAY:-1}"
        attempt=$((attempt + 1))
        rc=
    done
    [ -n "$parsed" ] || return 1
    uid=${parsed%%|*}
    remainder=${parsed#*|}
    size=${remainder%%|*}
    states=${remainder#*|}
    # Validate the parsed protocol fields directly. On-device diagnostics
    # showed a valid UID rejected by the shell's glob-based digit check.
    printf '%s\n' "$uid" | grep -Eq '^[0-9]+$' || { probe_record_error invalid-app-uid "$reply" "$parsed"; return 1; }
    printf '%s\n' "$size" | grep -Eq '^[0-9]+$' || { probe_record_error invalid-count "$reply" "$parsed"; return 1; }
    [ "$uid" -ge 10000 ] || { probe_record_error non-app-uid "$reply" "$parsed"; return 1; }
    expected_count=$((stop - start + 1))
    [ "$size" -eq "$expected_count" ] || { probe_record_error count-mismatch "$reply" "$parsed"; return 1; }
    printf '%s\n' "$states" | grep -Eq '^[A-Z_,]+$' || { probe_record_error invalid-states "$reply" "$parsed"; return 1; }

    awk -F '\t' -v first="$start" -v last="$stop" -v values="$states" -v uid="$uid" '
        BEGIN {
            n=split(values, a, ",")
            if (n != last-first+1) exit 1
            for (i=1; i<=n; i++) {
                if (a[i]!="VISIBLE" && a[i]!="MISSING" && a[i]!="DENIED" &&
                    a[i]!="ERROR" && a[i]!="INVALID") exit 1
            }
        }
        NR>=first && NR<=last { print $0 "\t" a[NR-first+1] "\t" uid }
    ' "$file" >> "$out" || { probe_record_error invalid-state-list "$reply" "$parsed"; return 1; }
    PROBE_UID="$uid"
}

probe_verify_file() {
    local file="$1" total start stop tmp probe_limit=32 result=ready
    PROBE_STATUS=not-installed
    PROBE_UID=0
    rm -f "$PERSISTENT_DIR/state/probe.last_error.txt"
    [ -f "$file" ] || return 1
    total=$(awk 'END { print NR + 0 }' "$file")
    [ "$total" -gt 0 ] || { PROBE_STATUS=no-targets; return 0; }

    PROBE_CONTENT_BIN="${SUSAF_PROBE_CONTENT_BIN:-/system/bin/content}"
    PROBE_PM_BIN="${SUSAF_PROBE_PM_BIN:-/system/bin/pm}"
    if [ ! -x "$PROBE_CONTENT_BIN" ] || [ ! -x "$PROBE_PM_BIN" ]; then
        PROBE_STATUS=tools-unavailable
        return 0
    fi
    if ! "$PROBE_PM_BIN" path com.fgjaee.susaf.probe 2>/dev/null |
        grep -q '^package:'; then
        PROBE_STATUS=not-installed
        return 0
    fi

    tmp="${file}.verified.$$"
    : > "$tmp" || return 1
    start=1
    while [ "$start" -le "$total" ]; do
        stop=$((start + probe_limit - 1))
        [ "$stop" -le "$total" ] || stop="$total"
        if ! probe_check_batch "$file" "$tmp" "$start" "$stop"; then
            result=call-failed
            break
        fi
        start=$((stop + 1))
    done
    if [ "$result" != ready ]; then
        awk -F '\t' -v first="$start" 'NR>=first { print $0 "\tNOT_TESTED\t0" }' "$file" >> "$tmp"
    fi
    [ "$(awk 'END { print NR+0 }' "$tmp")" -eq "$total" ] || {
        rm -f "$tmp"
        PROBE_STATUS=invalid-response
        return 0
    }
    mv "$tmp" "$file" || return 1
    PROBE_STATUS="$result"
    if [ "$result" = ready ]; then
        rm -f "$PERSISTENT_DIR/state/probe.last_error.txt"
    fi
    return 0
}
