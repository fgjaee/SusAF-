#!/bin/sh

# Optional, bounded, real-app filesystem visibility check.
# Only the companion APK performs lstat, in its own unprivileged process.
# No probe APK / provider means an explicit NOT_TESTED result.

probe_parse_reply() {
    local token uid count states
    case "$1" in
        *SUSAFPROBEV1__*) token=${1#*SUSAFPROBEV1__} ;;
        *) return 1 ;;
    esac
    uid=${token%%__*}
    [ "$uid" != "$token" ] || return 1
    token=${token#*__}
    count=${token%%__*}
    [ "$count" != "$token" ] || return 1
    states=${token#*__}
    states=${states%%\}*}
    states=${states%%]*}
    printf '%s|%s|%s\n' "$uid" "$count" "$states"
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
        mkdir -p "$PERSISTENT_DIR/state" 2>/dev/null || true
        {
            printf 'epoch=%s\n' "$(date +%s 2>/dev/null)"
            printf 'attempt=%s\n' "$attempt"
            printf 'exit=%s\n' "$rc"
            printf 'reply=%s\n' "$(printf '%s' "$reply" | tr '\r\n\t' '   ' | sed 's/[[:cntrl:]]//g' | cut -c1-500)"
        } > "$PERSISTENT_DIR/state/probe.last_error.txt" 2>/dev/null || true
        chmod 600 "$PERSISTENT_DIR/state/probe.last_error.txt" 2>/dev/null || true
        [ "$attempt" -ge 3 ] || sleep "${SUSAF_PROBE_RETRY_DELAY:-1}"
        attempt=$((attempt + 1))
        rc=
    done
    [ -n "$parsed" ] || return 1
    uid=${parsed%%|*}
    remainder=${parsed#*|}
    size=${remainder%%|*}
    states=${remainder#*|}
    case "$uid" in ''|*[!0-9]*) return 1 ;; esac
    case "$size" in ''|*[!0-9]*) return 1 ;; esac
    [ "$uid" -ge 10000 ] || return 1
    expected_count=$((stop - start + 1))
    [ "$size" -eq "$expected_count" ] || return 1
    case "$states" in ''|*[!A-Z_,]*) return 1 ;; esac

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
    ' "$file" >> "$out" || return 1
    PROBE_UID="$uid"
}

probe_verify_file() {
    local file="$1" total start stop tmp probe_limit=32 result=ready
    PROBE_STATUS=not-installed
    PROBE_UID=0
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
}
