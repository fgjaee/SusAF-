#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
node --input-type=module <<'JS'
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source = fs.readFileSync('webui/page/diagnostics/diagnostics.js', 'utf8');
const fn = source.slice(source.indexOf('async function waitForCoverageBackground('), source.indexOf('async function startCoverageBackground('));
const progress = 'operation=audit\nstatus=complete\nupdated.epoch=1794087545';
const report = 'schema=2\nresult=ok\naudit.completed=1\ngenerated.epoch=1794087530';
let calls = 0;
const context = vm.createContext({
    coverageRequestSequence: 1, basePath: '/fixture', console, Date,
    pollCoverageProgress: async () => {},
    parseDiagnostics: text => Object.fromEntries(text.split('\n').map(line => line.split('='))),
    exec: async command => ({errno: 0, stdout: command.includes('progress.txt') ? progress : report}),
    getCoverageBackgroundStatus: async () => { calls++; throw new Error('bridge disconnected'); },
});
vm.runInContext(fn, context);
assert.equal(await vm.runInContext('waitForCoverageBackground(1)', context), report);
assert.equal(calls, 0, 'committed completion must not require a live status bridge');
// A temporary bridge rejection must not fail an otherwise completed audit.
let reads = 0;
context.exec = async command => {
    if (++reads === 1) throw new Error('temporary bridge interruption');
    return {errno: 0, stdout: command.includes('progress.txt') ? progress : report};
};
context.getCoverageBackgroundStatus = async () => ({status: 'running'});
context.window = {setTimeout: callback => callback()};
assert.equal(await vm.runInContext('waitForCoverageBackground(1)', context), report);
// An old success must not satisfy a newer request.
let clock = 0;
context.Date = {now: () => clock += 16000};
context.getCoverageBackgroundStatus = async () => ({status: 'idle'});
await assert.rejects(vm.runInContext('waitForCoverageBackground(1, 1794088000)', context), /no matching completed report/);
// Android can lose the worker PID while the audit still updates progress.
// The UI must wait for its committed report instead of declaring failure.
let tick = 0;
const liveEpoch = 1794153153;
const liveReport = 'schema=2\nresult=ok\naudit.completed=1\ngenerated.epoch=1794153157';
context.Date = {now: () => (liveEpoch + tick++) * 1000};
context.exec = async command => ({errno: 0, stdout: command.includes('progress.txt')
    ? (tick < 5 ? `operation=audit\nstatus=running\nupdated.epoch=${liveEpoch + tick}`
        : `operation=audit\nstatus=complete\nupdated.epoch=${liveEpoch + tick}`)
    : liveReport});
assert.equal(await vm.runInContext(`waitForCoverageBackground(1, ${liveEpoch})`, context), liveReport);
// Applying a saved candidate must not trigger another device audit.
const applyFn = source.slice(source.indexOf('async function applyCoverageIds('), source.indexOf('async function saveCoverageSelection('));
const scans = [];
const applyContext = vm.createContext({
    moduleDirectory: '/module', setCoverageBusy: () => {}, setCoverageMessage: () => {},
    runCoverageCommand: async () => ({errno: 0, stdout: 'result=applied\nadded.sus_maps=1'}),
    finishCoverageOperation: async () => {},
    parseDiagnostics: text => Object.fromEntries(text.split('\n').map(line => line.split('='))),
    loadCoverage: async scan => scans.push(scan), getString: key => key, console,
});
vm.runInContext(applyFn, applyContext);
await vm.runInContext('applyCoverageIds([1])', applyContext);
assert.deepEqual(scans, [false], 'apply must only reload the saved report');
let rendered = null;
const loadFn = source.slice(source.indexOf('async function loadCoverage('), source.indexOf('async function scanAppCoverage('));
const savedContext = vm.createContext({
    coverageRequestSequence: 0, basePath: '/fixture', setCoverageBusy: () => {},
    setCoverageMessage: () => {}, console,
    exec: async command => ({errno: 0, stdout: command.includes('coverage.apply.txt')
        ? 'schema=1\nreport.epoch=1794153157\nids=1' : liveReport}),
    parseDiagnostics: text => Object.fromEntries(text.split('\n').map(line => line.split('='))),
    renderCoverage: (values, applied) => { rendered = {values, applied}; },
});
vm.runInContext(loadFn, savedContext);
await vm.runInContext('loadCoverage(false)', savedContext);
assert.equal(rendered?.applied?.ids, '1', 'saved report must include applied action state');
const xml = fs.readFileSync('webui/public/locales/strings/en.xml', 'utf8');
for (const stage of ['exposure', 'verifying_app']) {
    assert.ok(xml.includes(`name="coverage_stage_${stage}"`), `${stage} needs its own label`);
}
console.log('Audit UI completion and stage labels passed');
JS
