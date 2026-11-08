#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
node --input-type=module <<'JS'
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const source = fs.readFileSync('webui/page/diagnostics/diagnostics.js', 'utf8');
const fn = source.slice(source.indexOf('async function exportDiagnostics()'), source.indexOf('async function installVisibilityProbe()'));
const status = {};
let calls = 0, command = '', painted = false, release;
const pending = new Promise(resolve => release = resolve);
const context = vm.createContext({
    document: {getElementById: () => status},
    basePath: '/fixture', setBusy: () => {}, getString: key => key, showPrompt: () => {}, console,
    waitForCoveragePaint: async () => { painted = true; },
    exec: async cmd => { assert.ok(painted); calls++; command = cmd; await pending; return {errno: 0, stdout: '/fixture/export.txt'}; },
});
vm.runInContext('let diagnosticsExportInFlight = false;\n' + fn, context);
const first = vm.runInContext('exportDiagnostics()', context);
await vm.runInContext('exportDiagnostics()', context);
release();
await first;
assert.equal(calls, 1, 'double taps must not start another export');
assert.ok(!command.includes('--diagnostics'), 'export must not trigger fresh diagnostics');
assert.ok(command.includes('tail -n 160'), 'audit log size must be bounded');
assert.ok(command.includes('coverage.background.log'));
assert.equal(spawnSync('sh', ['-n'], {input: command}).status, 0);
assert.equal(vm.runInContext('diagnosticsExportInFlight', context), false);
assert.equal(status.className, 'diagnostics-export-status success');
context.exec = async () => { throw new Error('bridge unavailable'); };
context.console = {warn: () => {}};
await vm.runInContext('exportDiagnostics()', context);
assert.equal(vm.runInContext('diagnosticsExportInFlight', context), false);
assert.equal(status.className, 'diagnostics-export-status error');
console.log('Export cached-only, double-tap, shell syntax, and failure recovery passed');
JS
