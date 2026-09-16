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
    setBusy(true);
    const result = await exec(`
REPORT="${basePath}/state/diagnostics.properties"
[ -f "$REPORT" ] || exit 1
OUT="/storage/emulated/0/Download/SusAF_diagnostics_$(date +%Y%m%d_%H%M%S).txt"
cp "$REPORT" "$OUT" || exit 1
printf '%s\n' "$OUT"
    `);
    setBusy(false);

    if (result.errno === 0 && result.stdout.trim()) {
        showPrompt(getString('diagnostics_exported', result.stdout.trim()));
    } else {
        showPrompt(getString('diagnostics_export_failed'), false);
    }
}

export function mount() {
    document.getElementById('diagnostics-refresh').onclick = () => loadDiagnostics(true);
    document.getElementById('diagnostics-export').onclick = () => exportDiagnostics();
}

export function onShow() {
    updateUIVisibility();
    loadDiagnostics(false);
}

export function onHide() {
    requestSequence++;
}
