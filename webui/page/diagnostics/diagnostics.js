import { exec } from 'kernelsu-alt';
import { basePath, moduleDirectory, showPrompt, updateUIVisibility } from '../../utils/util.js';
import { getString } from '../../utils/language.js';

const GROUPS = {
    runtime: [
        ['module.name', 'diagnostics_module'],
        ['module.version', 'diagnostics_module_version'],
        ['module.status', 'diagnostics_module_status'],
        ['persistent.owner', 'diagnostics_config_owner'],
        ['persistent.mode', 'diagnostics_config_mode'],
        ['kernelsu.version', 'diagnostics_kernelsu_version'],
        ['kernelsu.binary', 'diagnostics_kernelsu_binary'],
        ['susfs.status', 'diagnostics_susfs_status'],
        ['susfs.binary', 'diagnostics_susfs_binary'],
        ['susfs.version', 'diagnostics_susfs_version'],
        ['susfs.variant', 'diagnostics_susfs_variant'],
        ['susfs.feature_count', 'diagnostics_susfs_feature_count'],
        ['susfs.features', 'diagnostics_susfs_features'],
    ],
    kernel: [
        ['selinux_hide.support', 'diagnostics_selinux_hide_support'],
        ['selinux_hide.current', 'diagnostics_selinux_hide_current'],
        ['mount_filter.early', 'diagnostics_mount_filter_early'],
        ['mount_filter.late', 'diagnostics_mount_filter_late'],
        ['kernel_umount.configured', 'diagnostics_kernel_configured'],
        ['kernel_umount.auto', 'diagnostics_kernel_auto'],
        ['kernel_umount.allow_broad', 'diagnostics_kernel_allow_broad'],
        ['kernel_umount.support', 'diagnostics_kernel_support'],
        ['kernel_umount.current', 'diagnostics_kernel_current'],
        ['kernel_umount.feature_result', 'diagnostics_kernel_feature_result'],
        ['kernel_umount.mount_result', 'diagnostics_kernel_mount_result'],
        ['kernel_umount.candidates', 'diagnostics_kernel_candidates'],
        ['kernel_umount.added', 'diagnostics_kernel_added'],
        ['kernel_umount.existing', 'diagnostics_kernel_existing'],
        ['kernel_umount.inactive', 'diagnostics_kernel_inactive'],
        ['kernel_umount.broad_skipped', 'diagnostics_kernel_broad_skipped'],
        ['kernel_umount.skipped', 'diagnostics_kernel_skipped'],
        ['kernel_umount.rejected', 'diagnostics_kernel_rejected'],
        ['kernel_umount.failures', 'diagnostics_kernel_failures'],
        ['kernel_umount.notify', 'diagnostics_kernel_notify'],
    ],
    boot: [
        ['boot.source', 'diagnostics_boot_source'],
        ['boot.format', 'diagnostics_boot_format'],
        ['boot.live_error_keys', 'diagnostics_boot_live_errors'],
        ['boot.generated', 'diagnostics_boot_generated'],
        ['boot.generated_bytes', 'diagnostics_boot_generated_bytes'],
        ['boot.generated_error_keys', 'diagnostics_boot_generated_errors'],
        ['proc.version', 'diagnostics_proc_version'],
        ['uname.release', 'diagnostics_uname_release'],
        ['uname.version', 'diagnostics_uname_version'],
    ],
    adb: [
        ['adb.configured', 'diagnostics_adb_configured'],
        ['adb.last_result', 'diagnostics_adb_last_result'],
        ['adb.developer_options', 'diagnostics_adb_developer_options'],
        ['adb.usb_debugging', 'diagnostics_adb_usb_debugging'],
        ['adb.wifi_debugging', 'diagnostics_adb_wifi_debugging'],
        ['adb.service', 'diagnostics_adb_service'],
        ['adb.pid', 'diagnostics_adb_pid'],
        ['adb.usb_config', 'diagnostics_adb_usb_config'],
        ['adb.usb_state', 'diagnostics_adb_usb_state'],
        ['adb.persist_usb_config', 'diagnostics_adb_persist_usb_config'],
    ],
    stages: [
        ['stage.postfs.status', 'diagnostics_postfs_status'],
        ['stage.postfs.started', 'diagnostics_postfs_started'],
        ['stage.postfs.finished', 'diagnostics_postfs_finished'],
        ['stage.postfs.duration', 'diagnostics_postfs_duration'],
        ['stage.postfs.exit', 'diagnostics_postfs_exit'],
        ['stage.boot.status', 'diagnostics_boot_stage_status'],
        ['stage.boot.started', 'diagnostics_boot_stage_started'],
        ['stage.boot.finished', 'diagnostics_boot_stage_finished'],
        ['stage.boot.duration', 'diagnostics_boot_stage_duration'],
        ['stage.boot.exit', 'diagnostics_boot_stage_exit'],
    ],
    migration: [
        ['migration.resusfs', 'diagnostics_migration_resusfs'],
        ['migration.susfs4ksu', 'diagnostics_migration_susfs4ksu'],
        ['installer.last_result', 'diagnostics_installer_result'],
        ['installer.checkpoint', 'diagnostics_installer_checkpoint'],
        ['installer.config_keys_added', 'diagnostics_installer_config_keys'],
        ['installer.schedule_repairs', 'diagnostics_installer_schedule_repairs'],
        ['installer.builtin_updates_pending', 'diagnostics_installer_builtin_updates'],
        ['updater.source_repository', 'diagnostics_updater_source'],
        ['updater.source_commit', 'diagnostics_updater_commit'],
        ['updater.verification', 'diagnostics_updater_verification'],
        ['updater.expected_sha256', 'diagnostics_updater_expected'],
        ['updater.actual_sha256', 'diagnostics_updater_actual'],
        ['updater.installed_sha256', 'diagnostics_updater_installed'],
        ['updater.candidate_version', 'diagnostics_updater_version'],
        ['updater.candidate_variant', 'diagnostics_updater_variant'],
        ['updater.backup', 'diagnostics_updater_backup'],
        ['updater.rollback', 'diagnostics_updater_rollback'],
        ['updater.last_result', 'diagnostics_updater_last_result'],
    ],
};

const TARGETS = [
    ['targets.sus_paths', 'targets.sus_paths_malformed', 'diagnostics_target_sus_paths'],
    ['targets.sus_paths_loop', 'targets.sus_paths_loop_malformed', 'diagnostics_target_sus_paths_loop'],
    ['targets.sus_maps', 'targets.sus_maps_malformed', 'diagnostics_target_sus_maps'],
    ['targets.kstat', 'targets.kstat_malformed', 'diagnostics_target_kstat'],
    ['targets.open_redirect', 'targets.open_redirect_malformed', 'diagnostics_target_open_redirect'],
    ['targets.kernel_umount', 'targets.kernel_umount_malformed', 'diagnostics_target_kernel_umount'],
    ['targets.pty', null, 'diagnostics_target_pty'],
    ['targets.mount_hiding_generated', null, 'diagnostics_target_generated_mounts'],
];

let requestSequence = 0;
let coverageRequestSequence = 0;
let currentCoverage = null;
let pendingCoverageIds = [];
let coverageProgressTimer = null;
let coverageElapsedTimer = null;
let coverageProgressInFlight = false;
let coverageOperation = '';
let coverageOperationStartedAt = 0;

export function parseDiagnostics(text) {
    const values = {};
    for (const line of text.split(/\r?\n/)) {
        const separator = line.indexOf('=');
        if (separator <= 0) continue;
        values[line.slice(0, separator)] = line.slice(separator + 1);
    }
    return values;
}

function displayValue(value) {
    return value === undefined || value === '' ? getString('diagnostics_unknown') : value;
}

function valueWarns(key, value) {
    if (key.endsWith('_malformed') || key.endsWith('.failures') || key.endsWith('_error_keys')) {
        return Number.parseInt(value, 10) > 0;
    }
    if (key.endsWith('.mount_result')) return value === 'partial';
    if (key === 'mount_filter.late') return value === '1';
    if (key === 'kernel_umount.allow_broad') return value !== '0';
    return false;
}

function renderRows(containerId, fields, values) {
    const container = document.getElementById(containerId);
    container.textContent = '';

    for (const [key, labelKey] of fields) {
        const row = document.createElement('div');
        row.className = 'diagnostics-row';

        const label = document.createElement('span');
        label.className = 'diagnostics-label';
        label.textContent = getString(labelKey);

        const value = document.createElement('span');
        value.className = 'diagnostics-value';
        value.textContent = displayValue(values[key]);
        value.classList.toggle('warning', valueWarns(key, values[key]));

        row.append(label, value);
        container.appendChild(row);
    }
}

function renderTargets(values) {
    const grid = document.getElementById('diagnostics-target-grid');
    grid.textContent = '';

    for (const [countKey, malformedKey, labelKey] of TARGETS) {
        const card = document.createElement('div');
        card.className = 'diagnostics-count-card';

        const count = document.createElement('span');
        count.className = 'diagnostics-count';
        count.textContent = displayValue(values[countKey]);

        const label = document.createElement('span');
        label.className = 'diagnostics-count-label';
        label.textContent = getString(labelKey);

        card.append(count, label);
        if (malformedKey) {
            const malformed = document.createElement('span');
            const malformedCount = values[malformedKey] || '0';
            malformed.className = 'diagnostics-count-malformed';
            malformed.classList.toggle('warning', Number.parseInt(malformedCount, 10) > 0);
            malformed.textContent = getString('diagnostics_malformed_count', malformedCount);
            card.appendChild(malformed);
        }
        grid.appendChild(card);
    }
}

function renderSnapshot(values) {
    if (values.schema !== '1') throw new Error('unsupported diagnostics schema');

    const overall = values['overall.status'] || 'degraded';
    const statusDot = document.getElementById('diagnostics-status-dot');
    statusDot.className = `diagnostics-status-dot ${overall}`;
    document.getElementById('diagnostics-status-title').textContent = getString(`diagnostics_overall_${overall}`);
    document.getElementById('diagnostics-status-summary').textContent = getString(
        'diagnostics_summary',
        displayValue(values['module.version']),
        displayValue(values['susfs.version'])
    );
    document.getElementById('diagnostics-generated').textContent = getString(
        'diagnostics_generated_at',
        displayValue(values['generated.at'])
    );

    renderRows('diagnostics-runtime-rows', GROUPS.runtime, values);
    renderRows('diagnostics-kernel-rows', GROUPS.kernel, values);
    renderRows('diagnostics-boot-rows', GROUPS.boot, values);
    renderRows('diagnostics-adb-rows', GROUPS.adb, values);
    renderRows('diagnostics-stage-rows', GROUPS.stages, values);
    renderRows('diagnostics-migration-rows', GROUPS.migration, values);
    renderTargets(values);

    document.getElementById('diagnostics-content').hidden = false;
    document.getElementById('diagnostics-error').classList.remove('show');
}

function setBusy(busy) {
    const refresh = document.getElementById('diagnostics-refresh');
    const exportButton = document.getElementById('diagnostics-export');
    if (refresh) refresh.disabled = busy;
    if (exportButton) exportButton.disabled = busy;
}

function coveragePackageIsSafe(packageName) {
    return packageName.length <= 255
        && packageName.includes('.')
        && !packageName.startsWith('.')
        && !packageName.includes('..')
        && /^[A-Za-z0-9._]+$/.test(packageName);
}

function setCoverageBusy(busy) {
    for (const id of [
        'coverage-system-scan', 'coverage-app-scan', 'coverage-save-selected',
        'coverage-verify', 'coverage-rollback', 'coverage-package'
    ]) {
        const element = document.getElementById(id);
        if (element) element.disabled = busy;
    }
    if (!busy) {
        updateCoverageSelection();
        const rollback = document.getElementById('coverage-rollback');
        if (rollback) rollback.disabled = currentCoverage?.['rollback.available'] !== '1';
    }
}

function setCoverageMessage(message, isError = false) {
    const element = document.getElementById('coverage-message');
    element.textContent = message;
    element.classList.toggle('error', isError);
    element.classList.toggle('show', Boolean(message));
}

function coverageOperationTitle(operation) {
    const key = `coverage_progress_${operation}`;
    const label = getString(key);
    return label === key ? getString('coverage_progress_audit') : label;
}

function coverageStageLabel(stage) {
    const key = `coverage_stage_${stage}`;
    const label = getString(key);
    return label === key ? getString('coverage_stage_preparing') : label;
}

function updateCoverageElapsed() {
    const target = document.getElementById('coverage-progress-elapsed');
    if (!target || !coverageOperationStartedAt) return;
    const seconds = Math.max(0, Math.floor((Date.now() - coverageOperationStartedAt) / 1000));
    target.textContent = getString('coverage_progress_elapsed', seconds);
}

function renderCoverageProgress(values) {
    if (values.schema !== '1' || values.operation !== coverageOperation) return;
    const updated = Number.parseInt(values['updated.epoch'] || '0', 10);
    const started = Math.floor(coverageOperationStartedAt / 1000) - 1;
    if (updated > 0 && updated < started) return;

    const current = Number.parseInt(values.current || '0', 10);
    const total = Number.parseInt(values.total || '0', 10);
    const bar = document.getElementById('coverage-progress-bar');
    const count = document.getElementById('coverage-progress-count');
    document.getElementById('coverage-operation-stage').textContent = coverageStageLabel(values.stage || 'preparing');

    if (total > 0) {
        const percent = Math.min(100, Math.max(4, Math.round((current / total) * 100)));
        bar.classList.remove('indeterminate');
        bar.style.width = `${percent}%`;
        count.textContent = getString('coverage_progress_count', current, total);
    } else {
        bar.classList.add('indeterminate');
        bar.style.width = '';
        count.textContent = getString('coverage_progress_working');
    }
}

async function pollCoverageProgress() {
    if (!coverageOperation || coverageProgressInFlight) return;
    coverageProgressInFlight = true;
    try {
        const result = await exec(`cat "${basePath}/state/coverage.progress.txt" 2>/dev/null`);
        if (result.errno === 0 && result.stdout.trim()) {
            renderCoverageProgress(parseDiagnostics(result.stdout));
        }
    } catch (error) {
        console.debug('Autopilot progress is not readable yet:', error);
    } finally {
        coverageProgressInFlight = false;
    }
}

function beginCoverageOperation(operation) {
    coverageOperation = operation;
    coverageOperationStartedAt = Date.now();
    const overlay = document.getElementById('coverage-operation-overlay');
    const bar = document.getElementById('coverage-progress-bar');
    const spinner = document.getElementById('coverage-operation-spinner');
    document.getElementById('coverage-operation-title').textContent = coverageOperationTitle(operation);
    document.getElementById('coverage-operation-stage').textContent = coverageStageLabel('preparing');
    document.getElementById('coverage-progress-count').textContent = getString('coverage_progress_working');
    spinner.classList.remove('complete');
    bar.classList.add('indeterminate');
    bar.style.width = '';
    overlay.hidden = false;
    document.body.setAttribute('aria-busy', 'true');
    updateCoverageElapsed();
    coverageProgressTimer = window.setInterval(() => void pollCoverageProgress(), 900);
    coverageElapsedTimer = window.setInterval(updateCoverageElapsed, 1000);
}

async function waitForCoveragePaint() {
    await new Promise(resolve => window.requestAnimationFrame(() => window.requestAnimationFrame(resolve)));
}

async function finishCoverageOperation(outcome = 'complete') {
    if (coverageProgressTimer) window.clearInterval(coverageProgressTimer);
    if (coverageElapsedTimer) window.clearInterval(coverageElapsedTimer);
    coverageProgressTimer = null;
    coverageElapsedTimer = null;
    await pollCoverageProgress();

    const spinner = document.getElementById('coverage-operation-spinner');
    const bar = document.getElementById('coverage-progress-bar');
    spinner.classList.toggle('complete', outcome === 'complete');
    bar.classList.remove('indeterminate');
    bar.style.width = '100%';
    document.getElementById('coverage-operation-stage').textContent = getString(`coverage_progress_${outcome}_stage`);
    await new Promise(resolve => window.setTimeout(resolve, outcome === 'complete' ? 450 : 800));
    document.getElementById('coverage-operation-overlay').hidden = true;
    document.body.removeAttribute('aria-busy');
    coverageOperation = '';
    coverageOperationStartedAt = 0;
}

async function runCoverageCommand(operation, command) {
    beginCoverageOperation(operation);
    await waitForCoveragePaint();
    return exec(command);
}

function renderCoverageVerification(values) {
    const panel = document.getElementById('coverage-verification');
    if (!values || values.schema !== '1') {
        panel.hidden = true;
        return;
    }

    const result = values.result || 'not-run';
    if (result === 'not-run') {
        panel.hidden = true;
        return;
    }

    const stale = values['missing.configured'] || '0';
    const failures = values['mount.failures'] || '0';
    const remaining = values['remaining.candidates'] || '0';
    panel.className = 'coverage-verification';
    if (result === 'attention') panel.classList.add('attention');
    if (result === 'clean-with-stale') panel.classList.add('stale');
    document.getElementById('coverage-verification-title').textContent = getString(`coverage_verify_${result.replaceAll('-', '_')}`);
    document.getElementById('coverage-verification-detail').textContent = getString(
        'coverage_verify_detail',
        stale,
        failures,
        remaining
    );
    const runtime = document.getElementById('coverage-verification-runtime');
    const featureResult = values['kernel_umount.feature_result'] || 'not-recorded';
    const mountResult = values['kernel_umount.mount_result'] || 'not-recorded';
    runtime.className = 'coverage-verification-runtime';
    runtime.textContent = values['runtime.available'] === '0'
        ? getString('coverage_verify_runtime_unavailable', featureResult, mountResult)
        : '';
    panel.hidden = false;
}

async function loadCoverageVerification() {
    const result = await exec(`cat "${basePath}/state/coverage.verify.txt" 2>/dev/null`);
    if (result.errno !== 0 || !result.stdout.trim()) {
        renderCoverageVerification(null);
        return;
    }
    renderCoverageVerification(parseDiagnostics(result.stdout));
}

function updateCoverageSelection() {
    const saveButton = document.getElementById('coverage-save-selected');
    if (!saveButton) return;
    const selected = Array.from(document.querySelectorAll('#coverage-candidates md-checkbox'))
        .some(checkbox => checkbox.checked);
    saveButton.disabled = !selected;
}

function candidateReason(reason) {
    const key = `coverage_reason_${reason}`;
    const translated = getString(key);
    return translated === key ? reason : translated;
}

function candidateType(kind, action) {
    const actionKey = `coverage_action_${action}`;
    const actionLabel = getString(actionKey);
    if (actionLabel !== actionKey) return actionLabel;
    const kindKey = `coverage_type_${kind}`;
    const kindLabel = getString(kindKey);
    return kindLabel === kindKey ? kind : kindLabel;
}

function selectedCoverageIds() {
    return Array.from(document.querySelectorAll('#coverage-candidates md-checkbox'))
        .filter(checkbox => checkbox.checked)
        .map(checkbox => checkbox.dataset.candidateId)
        .filter(id => /^\d+$/.test(id));
}

function renderCoverage(values) {
    if (values.schema !== '2') throw new Error('unsupported coverage schema');
    currentCoverage = values;

    const packageName = values.package || 'none';
    const isAppScan = values.mode === 'app';
    document.getElementById('coverage-result-title').textContent = isAppScan
        ? getString('coverage_result_app', packageName)
        : getString('coverage_result_autopilot');
    document.getElementById('coverage-result-detail').textContent = isAppScan
        ? getString('coverage_process_detail', values['process.count'] || '0')
        : getString(
            'coverage_autopilot_detail',
            values['process.count'] || '0',
            values['mount.namespaces'] || '0',
            values['mount.high_id_namespaces'] || '0'
        );
    document.getElementById('coverage-map-candidates').textContent = values['candidate.sus_maps'] || '0';
    document.getElementById('coverage-path-candidates').textContent = values['candidate.sus_paths_loop'] || '0';
    document.getElementById('coverage-mount-candidates').textContent = values['candidate.kernel_umount'] || '0';
    document.getElementById('coverage-spoof-candidates').textContent = values['candidate.spoof'] || '0';
    document.getElementById('coverage-rollback').disabled = values['rollback.available'] !== '1';

    const container = document.getElementById('coverage-candidates');
    const empty = document.getElementById('coverage-empty');
    container.textContent = '';
    const candidateCount = Number.parseInt(values['candidate.count'] || '0', 10);
    let rendered = 0;

    for (let id = 1; id <= candidateCount; id++) {
        const path = values[`candidate.${id}.target`] || values[`candidate.${id}.path`];
        const kind = values[`candidate.${id}.kind`];
        const reason = values[`candidate.${id}.reason`];
        const risk = values[`candidate.${id}.risk`] || 'low';
        const action = values[`candidate.${id}.action`] || kind;
        const scope = values[`candidate.${id}.scope`] || 'device';
        if (!path || !kind) continue;

        const row = document.createElement('label');
        row.className = 'coverage-candidate';

        const checkbox = document.createElement('md-checkbox');
        checkbox.dataset.candidateId = String(id);
        checkbox.checked = true;
        checkbox.addEventListener('change', updateCoverageSelection);

        const copy = document.createElement('span');
        copy.className = 'coverage-candidate-copy';

        const type = document.createElement('strong');
        type.textContent = candidateType(kind, action);

        const badges = document.createElement('span');
        badges.className = 'coverage-candidate-badges';
        const riskBadge = document.createElement('span');
        riskBadge.className = `coverage-risk ${risk}`;
        riskBadge.textContent = getString(`coverage_risk_${risk}`);
        const scopeBadge = document.createElement('span');
        scopeBadge.className = 'coverage-scope';
        scopeBadge.textContent = scope;
        badges.append(riskBadge, scopeBadge);

        const exactPath = document.createElement('code');
        exactPath.textContent = path;

        const why = document.createElement('small');
        why.textContent = candidateReason(reason);

        copy.append(type, badges, exactPath, why);
        row.append(checkbox, copy);
        container.appendChild(row);
        rendered++;
    }

    empty.hidden = rendered > 0;
    document.getElementById('coverage-results').hidden = false;
    setCoverageMessage('');
    updateCoverageSelection();
}

async function loadCoverage(scan = false, packageName = '') {
    const sequence = ++coverageRequestSequence;
    setCoverageBusy(true);
    setCoverageMessage(scan ? getString('coverage_scanning') : '');
    const command = scan
        ? `sh "${moduleDirectory}/SusAF.sh" --coverage-scan${packageName ? ` "${packageName}"` : ''}`
        : `cat "${basePath}/state/coverage.report.txt"`;

    try {
        const result = scan ? await runCoverageCommand('audit', command) : await exec(command);
        if (sequence !== coverageRequestSequence) return;
        if (result.errno !== 0 || !result.stdout.trim()) {
            if (!scan) {
                setCoverageMessage(getString('coverage_not_scanned'));
                return;
            }
            throw new Error(result.stderr || result.stdout || 'coverage scan failed');
        }
        renderCoverage(parseDiagnostics(result.stdout));
        if (scan) {
            await finishCoverageOperation('complete');
            showPrompt(getString('coverage_scan_complete'));
        }
    } catch (error) {
        if (sequence !== coverageRequestSequence) return;
        if (scan && coverageOperation) await finishCoverageOperation('failed');
        setCoverageMessage(getString('coverage_scan_failed'), true);
        console.warn('Coverage scan failed:', error);
    } finally {
        if (sequence === coverageRequestSequence) setCoverageBusy(false);
    }
}

async function scanAppCoverage() {
    const field = document.getElementById('coverage-package');
    const packageName = field.value.trim();
    if (!coveragePackageIsSafe(packageName)) {
        setCoverageMessage(getString('coverage_invalid_package'), true);
        return;
    }
    await loadCoverage(true, packageName);
}

async function applyCoverageIds(ids) {
    if (ids.length === 0) return;

    setCoverageBusy(true);
    const result = await runCoverageCommand('apply', `sh "${moduleDirectory}/SusAF.sh" --coverage-apply "${ids.join(',')}"`);
    await finishCoverageOperation(result.errno === 0 ? 'complete' : 'failed');
    setCoverageBusy(false);
    if (result.errno !== 0) {
        setCoverageMessage(getString('coverage_apply_failed'), true);
        console.warn('Coverage apply failed:', result.stderr || result.stdout);
        return;
    }

    const outcome = parseDiagnostics(result.stdout);
    const added = Number.parseInt(outcome['added.sus_maps'] || '0', 10)
        + Number.parseInt(outcome['added.sus_paths_loop'] || '0', 10)
        + Number.parseInt(outcome['added.kernel_umount'] || '0', 10)
        + Number.parseInt(outcome['changed.config'] || '0', 10);
    showPrompt(getString('coverage_applied', added));
    const packageName = currentCoverage?.mode === 'app' && currentCoverage.package !== 'none'
        ? currentCoverage.package
        : '';
    await loadCoverage(true, packageName);
}

async function saveCoverageSelection() {
    const ids = selectedCoverageIds();
    if (ids.length === 0) return;
    const risky = ids.filter(id => (currentCoverage?.[`candidate.${id}.risk`] || 'low') !== 'low');
    if (risky.length === 0) {
        await applyCoverageIds(ids);
        return;
    }

    pendingCoverageIds = ids;
    const list = document.getElementById('coverage-risk-list');
    list.textContent = '';
    for (const id of risky) {
        const item = document.createElement('code');
        item.textContent = currentCoverage[`candidate.${id}.target`] || '';
        list.appendChild(item);
    }
    document.getElementById('coverage-risk-dialog').show();
}

async function verifyCoverage() {
    setCoverageBusy(true);
    const result = await runCoverageCommand('verify', `sh "${moduleDirectory}/SusAF.sh" --coverage-verify`);
    const outcome = result.stdout.trim() ? parseDiagnostics(result.stdout) : null;
    await finishCoverageOperation(result.errno === 0 ? 'complete' : 'attention');
    setCoverageBusy(false);
    await loadCoverage(false);
    renderCoverageVerification(outcome);
    if (result.errno === 0) {
        showPrompt(getString(outcome?.result === 'clean-with-stale' ? 'coverage_verified_stale' : 'coverage_verified'));
    } else {
        setCoverageMessage(getString('coverage_verify_attention_detail'), true);
    }
}

async function rollbackCoverage() {
    setCoverageBusy(true);
    const result = await runCoverageCommand('rollback', `sh "${moduleDirectory}/SusAF.sh" --coverage-rollback`);
    await finishCoverageOperation(result.errno === 0 ? 'complete' : 'failed');
    setCoverageBusy(false);
    if (result.errno === 0) {
        showPrompt(getString('coverage_rollback_done'));
        await loadCoverage(true);
    } else {
        setCoverageMessage(getString('coverage_rollback_failed'), true);
    }
}

async function loadDiagnostics(refresh = false) {
    const sequence = ++requestSequence;
    setBusy(true);
    const command = refresh
        ? `sh "${moduleDirectory}/SusAF.sh" --diagnostics`
        : `cat "${basePath}/state/diagnostics.properties"`;

    try {
        const result = await exec(command);
        if (sequence !== requestSequence) return;
        if (result.errno !== 0 || !result.stdout.trim()) throw new Error(result.stderr || 'snapshot unavailable');
        renderSnapshot(parseDiagnostics(result.stdout));
        if (refresh) showPrompt(getString('diagnostics_refreshed'));
    } catch (error) {
        if (sequence !== requestSequence) return;
        const errorBox = document.getElementById('diagnostics-error');
        errorBox.textContent = getString('diagnostics_unavailable');
        errorBox.classList.add('show');
        document.getElementById('diagnostics-content').hidden = true;
        console.warn('Diagnostics load failed:', error);
    } finally {
        if (sequence === requestSequence) setBusy(false);
    }
}

async function exportDiagnostics() {
    const status = document.getElementById('diagnostics-export-status');
    setBusy(true);
    status.className = 'diagnostics-export-status exporting';
    status.textContent = getString('diagnostics_exporting');
    status.hidden = false;
    let result;
    try {
        result = await exec(`
REPORT="${basePath}/state/diagnostics.properties"
sh "${moduleDirectory}/SusAF.sh" --diagnostics >/dev/null || exit 1
OUT="/storage/emulated/0/Download/SusAF_diagnostics_$(date +%Y%m%d_%H%M%S).txt"
cp "$REPORT" "$OUT" || exit 1
printf '%s\n' "$OUT"
    `);
        if (result.errno === 0 && result.stdout.trim()) {
            const path = result.stdout.trim();
            status.className = 'diagnostics-export-status success';
            status.textContent = getString('diagnostics_exported', path);
            showPrompt(status.textContent, true, 5000);
        } else {
            status.className = 'diagnostics-export-status error';
            status.textContent = getString('diagnostics_export_failed');
            showPrompt(status.textContent, false, 5000);
        }
    } catch (error) {
        status.className = 'diagnostics-export-status error';
        status.textContent = getString('diagnostics_export_failed');
        showPrompt(status.textContent, false, 5000);
        console.warn('Diagnostics export failed:', error);
    } finally {
        setBusy(false);
    }
}

export function mount() {
    document.getElementById('diagnostics-refresh').onclick = () => loadDiagnostics(true);
    document.getElementById('diagnostics-export').onclick = () => exportDiagnostics();
    document.getElementById('coverage-system-scan').onclick = () => loadCoverage(true);
    document.getElementById('coverage-app-scan').onclick = () => scanAppCoverage();
    document.getElementById('coverage-save-selected').onclick = () => saveCoverageSelection();
    document.getElementById('coverage-verify').onclick = () => verifyCoverage();
    document.getElementById('coverage-rollback').onclick = () => rollbackCoverage();
    document.getElementById('coverage-risk-cancel').onclick = () => {
        pendingCoverageIds = [];
        document.getElementById('coverage-risk-dialog').close();
    };
    document.getElementById('coverage-risk-apply').onclick = async () => {
        const ids = pendingCoverageIds;
        pendingCoverageIds = [];
        document.getElementById('coverage-risk-dialog').close();
        await applyCoverageIds(ids);
    };
}

export function onShow() {
    updateUIVisibility();
    loadDiagnostics(false);
    loadCoverage(false);
    loadCoverageVerification();
}

export function onHide() {
    requestSequence++;
    coverageRequestSequence++;
    if (coverageProgressTimer) window.clearInterval(coverageProgressTimer);
    if (coverageElapsedTimer) window.clearInterval(coverageElapsedTimer);
    coverageProgressTimer = null;
    coverageElapsedTimer = null;
    coverageOperation = '';
    coverageOperationStartedAt = 0;
    document.getElementById('coverage-operation-overlay').hidden = true;
    document.body.removeAttribute('aria-busy');
}
