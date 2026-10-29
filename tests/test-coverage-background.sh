#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export PERSISTENT_DIR="$TEST_ROOT/SusAF"
export MODULE_DIR="$TEST_ROOT/module"
mkdir -p "$PERSISTENT_DIR/state" "$MODULE_DIR"

cat > "$MODULE_DIR/SusAF.sh" <<'WORKER'
#!/bin/sh
if [ "$1" = "--coverage-scan-worker" ]; then
    printf 'run\n' >> "$PERSISTENT_DIR/state/worker-count"
    sleep 1
    cat > "$PERSISTENT_DIR/state/coverage.report.txt" <<'EOF'
schema=2
mode=autopilot
result=ok
EOF
    cat > "$PERSISTENT_DIR/state/coverage.progress.txt" <<'EOF'
schema=1
operation=audit
status=complete
stage=complete
current=1
total=1
detail=audit_complete
EOF
    rm -f "$PERSISTENT_DIR/state/coverage.audit.pid" "$PERSISTENT_DIR/state/coverage.audit.package"
    exit 0
fi
exit 2
WORKER
chmod 755 "$MODULE_DIR/SusAF.sh"

. "$ROOT/module/lib/coverage.sh"

started=$(coverage_scan_background)
printf '%s\n' "$started" | grep -Fqx 'status=started'
printf '%s\n' "$started" | grep -Eq '^pid=[0-9]+$'

status=$(coverage_scan_background_status)
printf '%s\n' "$status" | grep -Fqx 'status=running'

# Starting again while the first audit is alive must attach to it, not spawn a second worker.
again=$(coverage_scan_background)
printf '%s\n' "$again" | grep -Fqx 'status=running'
[ "$(wc -l < "$PERSISTENT_DIR/state/worker-count" | tr -d '[:space:]')" = 1 ]

sleep 2
status=$(coverage_scan_background_status)
printf '%s\n' "$status" | grep -Fqx 'status=idle'
grep -Fqx 'status=complete' "$PERSISTENT_DIR/state/coverage.progress.txt"
grep -Fqx 'schema=2' "$PERSISTENT_DIR/state/coverage.report.txt"

if coverage_scan_background 'bad;package' >/dev/null 2>&1; then
    echo 'unsafe background package accepted' >&2
    exit 1
fi

echo 'coverage background tests passed'
