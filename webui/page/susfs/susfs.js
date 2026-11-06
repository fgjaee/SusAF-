import { exec } from 'kernelsu-alt';
import { showPrompt, basePath, moduleDirectory, filePaths, applyFlags, runSusAF, fetchText, updateUIVisibility, writeTextFileAtomic } from '../../utils/util.js';
import { getString } from '../../utils/language.js';
import { openEditor } from '../../utils/editor.js';
import { FileSelector } from '../../utils/file_selector.js';

/**
 * One organized box per config file SusAF reads. Each box is fully
 * self-contained: edit the default file, apply it, or apply a custom file
 * picked from storage without touching the default at all.
 */
const CONFIG_BOXES = [
    {
        key: 'sus_paths',
        title: 'susfs_sus_paths_title',
        description: 'susfs_sus_paths_desc',
        applyLabel: 'box_apply',
        command: 'add_sus_path',
    },
    {
        key: 'sus_paths_loop',
        title: 'susfs_sus_paths_loop_title',
        description: 'susfs_sus_paths_loop_desc',
        applyLabel: 'box_apply',
        command: 'add_sus_path_loop',
    },
    {
        key: 'sus_maps',
        title: 'susfs_sus_maps_title',
        description: 'susfs_sus_maps_desc',
        applyLabel: 'box_apply',
        command: 'add_sus_map',
    },
    {
        key: 'kstat_paths',
        title: 'susfs_kstat_paths_title',
        description: 'susfs_kstat_paths_desc',
        applyLabel: 'box_stage',
        command: 'add_sus_kstat',
    },
    {
        key: 'open_redirect',
        title: 'susfs_open_redirect_title',
        description: 'susfs_open_redirect_desc',
        applyLabel: 'box_apply',
        command: 'add_open_redirect',
    },
    {
        key: 'uname',
        title: 'susfs_uname_title',
        description: 'susfs_uname_desc',
        applyLabel: 'box_apply',
        command: 'set_uname',
    },
    {
        key: 'cmdline_bootconfig',
        title: 'susfs_cmdline_title',
        description: 'susfs_cmdline_desc',
        applyLabel: 'box_apply',
        command: 'set_cmdline_or_bootconfig',
    },
];

const pencilIcon = `<svg xmlns="http://www.w3.org/2000/svg" height="20px" viewBox="0 -960 960 960" width="20px"><path d="M200-200h57l391-391-57-57-391 391v57Zm-80 80v-170l528-527q12-11 26.5-17t30.5-6q16 0 31 6t26 18l55 56q12 11 17.5 26t5.5 30q0 16-5.5 30.5T817-647L290-120H120Z"/></svg>`;
const playIcon = `<svg xmlns="http://www.w3.org/2000/svg" height="20px" viewBox="0 -960 960 960" width="20px"><path d="M320-200v-560l440 280-440 280Z"/></svg>`;
const folderIcon = `<svg xmlns="http://www.w3.org/2000/svg" height="20px" viewBox="0 -960 960 960" width="20px"><path d="M160-160q-33 0-56.5-23.5T80-240v-480q0-33 23.5-56.5T160-800h240l80 80h320q33 0 56.5 23.5T880-640H447l-80-80H160v480l96-320h684L837-217q-8 26-29.5 41.5T760-160H160Z"/></svg>`;

let capabilityCache = null;
let capabilityPromise = null;

function capabilityKey(command) {
    return `CMD_${command.toUpperCase()}`;
}

async function loadCapabilities() {
    if (capabilityCache) return capabilityCache;
    if (capabilityPromise) return capabilityPromise;

    capabilityPromise = exec(`sh "${moduleDirectory}/SusAF.sh" --capabilities`).then(result => {
        if (result.errno !== 0 || !result.stdout.trim()) return null;

        const values = {};
        const features = new Set();
        const registry = [];
        const unmapped = [];
        result.stdout.split(/\r?\n/).forEach(line => {
            if (!line) return;
            if (line.startsWith('FEATURE=')) {
                features.add(line.slice('FEATURE='.length).trim());
                return;
            }
            if (line.startsWith('REGISTRY=')) {
                const [id, mode, available, source, replacement] =
                    line.slice('REGISTRY='.length).split('|');
                if (id && mode) {
                    registry.push({
                        id,
                        mode,
                        available: available === '1',
                        source: source || '',
                        replacement: replacement || 'none',
                    });
                }
                return;
            }
            if (line.startsWith('UNMAPPED_FEATURE=')) {
                const feature = line.slice('UNMAPPED_FEATURE='.length).trim();
                if (feature) unmapped.push(feature);
                return;
            }
            const split = line.indexOf('=');
            if (split <= 0) return;
            values[line.slice(0, split).trim()] = line.slice(split + 1).trim();
        });

        capabilityCache = { values, features, registry, unmapped };
        return capabilityCache;
    }).catch(error => {
        console.error('Failed to read SUSFS capabilities:', error);
        return null;
    }).finally(() => {
        capabilityPromise = null;
    });

    return capabilityPromise;
}

function supportsCommand(capabilities, command) {
    if (!capabilities || !command) return true;
    return capabilities.values[capabilityKey(command)] !== '0';
}

const FEATURE_LABELS = {
    sus_path: 'SUS Path',
    sus_path_loop: 'SUS Path Loop',
    sus_map: 'SUS Maps',
    sus_kstat: 'SUS Kstat',
    open_redirect: 'Open Redirect',
    uname: 'Uname Spoof',
    cmdline_bootconfig: 'Cmdline / Bootconfig Spoof',
    sdcard_root: 'SUS_PATH SD Card Root',
    android_data_root: 'SUS_PATH Android Data Root',
    mount_filter: 'Mount Filtering',
    kernel_log: 'SUSFS Kernel Logging',
    avc_log_spoofing: 'AVC Log Spoofing',
    kernel_umount: 'KernelSU Kernel Umount',
    sus_mount: 'Legacy SUS Mount',
    try_umount: 'Try Umount',
    sus_su: 'SUS_SU',
    auto_default_mount: 'Auto Default Mount Handling',
    auto_bind_mount: 'Auto Bind-Mount Handling',
    auto_try_umount_bind: 'Auto Bind-Mount Try-Umount',
    hide_symbols: 'SUSFS Symbol Hiding',
    magic_mount: 'Magic Mount Support',
    overlayfs: 'OverlayFS Support',
};

function humanizeFeatureId(id) {
    if (FEATURE_LABELS[id]) return FEATURE_LABELS[id];
    return id.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

function registryModeLabel(entry) {
    if (entry.mode === 'legacy') return 'Legacy / replaced';
    if (entry.mode === 'status') return 'Kernel managed';
    return 'Sus\'AF control';
}

function registryDetail(entry) {
    if (entry.mode === 'legacy' && entry.replacement && entry.replacement !== 'none') {
        return `Replaced by ${humanizeFeatureId(entry.replacement)}`;
    }
    if (entry.mode === 'status') return 'Detected from the running kernel; no duplicate Sus\'AF toggle.';
    return 'Available through the active SUSFS/KernelSU interface.';
}

function renderCapabilityRegistry(capabilities) {
    const versionBadge = document.getElementById('capability-version');
    const summary = document.getElementById('capability-summary');
    const list = document.getElementById('capability-list');
    const unmappedBox = document.getElementById('capability-unmapped');
    if (!versionBadge || !summary || !list || !unmappedBox) return;

    if (!capabilities || capabilities.values.SUSFS_AVAILABLE === '0') {
        versionBadge.textContent = 'Unavailable';
        summary.textContent = '';
        list.innerHTML = '<div class="capability-copy"><small>SUSFS capability data is not available from the installed helper.</small></div>';
        unmappedBox.hidden = true;
        return;
    }

    const version = capabilities.values.SUSFS_VERSION || 'unknown';
    const variant = capabilities.values.SUSFS_VARIANT || 'unknown';
    const backend = capabilities.values.UMOUNT_BACKEND || 'unavailable';
    versionBadge.textContent = version;

    summary.innerHTML = '';
    const mountFilterBackend = capabilities.values.MOUNT_FILTER_BACKEND || 'unavailable';
    [
        `Variant: ${variant}`,
        `Umount backend: ${backend}`,
        `Mount filter: ${mountFilterBackend}`,
        `Kernel features: ${capabilities.features.size}`,
    ].forEach(text => {
        const chip = document.createElement('span');
        chip.className = 'capability-chip';
        chip.textContent = text;
        summary.appendChild(chip);
    });

    const modeOrder = { control: 0, status: 1, legacy: 2 };
    const visibleEntries = capabilities.registry
        .filter(entry => entry.available || entry.mode === 'legacy')
        .sort((a, b) => {
            const modeCompare = (modeOrder[a.mode] ?? 9) - (modeOrder[b.mode] ?? 9);
            return modeCompare || humanizeFeatureId(a.id).localeCompare(humanizeFeatureId(b.id));
        });

    list.innerHTML = '';
    visibleEntries.forEach(entry => {
        const row = document.createElement('div');
        row.className = 'capability-row';
        row.dataset.mode = entry.mode;

        const copy = document.createElement('div');
        copy.className = 'capability-copy';

        const title = document.createElement('strong');
        title.textContent = humanizeFeatureId(entry.id);
        const detail = document.createElement('small');
        detail.textContent = registryDetail(entry);

        const mode = document.createElement('span');
        mode.className = 'capability-mode';
        mode.textContent = registryModeLabel(entry);

        copy.append(title, detail);
        row.append(copy, mode);
        list.appendChild(row);
    });

    if (capabilities.unmapped.length) {
        unmappedBox.hidden = false;
        unmappedBox.textContent =
            `Unmapped kernel feature${capabilities.unmapped.length === 1 ? '' : 's'}: ${capabilities.unmapped.join(', ')}`;
    } else {
        unmappedBox.hidden = true;
        unmappedBox.textContent = '';
    }
}

async function applyCapabilityVisibility() {
    const capabilities = await loadCapabilities();
    if (!capabilities) return;

    renderCapabilityRegistry(capabilities);

    CONFIG_BOXES.forEach(box => {
        const element = document.getElementById(`box-${box.key}`);
        if (element) element.hidden = !supportsCommand(capabilities, box.command);
    });

    TOGGLE_ROWS.forEach(({ id, command, capability }) => {
        const row = document.getElementById(id);
        if (!row) return;
        const supported = capability
            ? capabilities.values[capability] !== '0'
            : supportsCommand(capabilities, command);
        row.hidden = !supported;
        const toggle = row.querySelector('md-switch');
        if (toggle) toggle.disabled = !supported;
    });
}

/**
 * Count non-comment, non-blank lines in a config file under PERSISTENT_DIR.
 * @param {string} fileName
 * @returns {Promise<number>}
 */
async function countEntries(fileName) {
    const result = await exec(`sed 's/#.*//' "${basePath}/${fileName}" 2>/dev/null | grep -c '[^[:space:]]'`);
    if (result.errno !== 0) return 0;
    const n = parseInt(result.stdout.trim(), 10);
    return Number.isFinite(n) ? n : 0;
}

/**
 * Build the DOM for a single config box.
 * @param {object} box entry from CONFIG_BOXES
 * @returns {HTMLElement}
 */
function buildBox(box) {
    const el = document.createElement('div');
    el.className = 'box translucent config-box';
    el.id = `box-${box.key}`;
    el.innerHTML = `
        <div class="box-header">
            <h2>${getString(box.title)}</h2>
            <span class="entry-badge" id="badge-${box.key}">-</span>
        </div>
        <p class="box-description">${getString(box.description)}</p>
        <div class="box-actions">
            <md-outlined-icon-button class="box-edit-btn" id="edit-${box.key}" title="${getString('box_edit')}">
                <md-icon>${pencilIcon}</md-icon>
            </md-outlined-icon-button>
            <md-outlined-icon-button class="box-custom-btn" id="custom-${box.key}" title="${getString('box_custom_file')}">
                <md-icon>${folderIcon}</md-icon>
            </md-outlined-icon-button>
            <md-filled-button class="box-apply-btn" id="apply-${box.key}">
                <md-icon slot="icon">${playIcon}</md-icon>
                ${getString(box.applyLabel)}
            </md-filled-button>
        </div>
    `;
    return el;
}

/**
 * Refresh the entry-count badge for every box.
 * @returns {Promise<void>}
 */
async function refreshBadges() {
    const commands = CONFIG_BOXES.map(box => {
        const fileName = filePaths[box.key];
        return `printf '%s=' '${box.key}'; sed 's/#.*//' "${basePath}/${fileName}" 2>/dev/null | grep -c '[^[:space:]]' || true`;
    });
    const result = await exec(commands.join('; '));
    const counts = new Map();

    if (result.errno === 0 || result.stdout) {
        result.stdout.split(/\r?\n/).forEach(line => {
            const split = line.indexOf('=');
            if (split <= 0) return;
            const key = line.slice(0, split).trim();
            const count = parseInt(line.slice(split + 1).trim(), 10);
            counts.set(key, Number.isFinite(count) ? count : 0);
        });
    }

    CONFIG_BOXES.forEach(box => {
        const badge = document.getElementById(`badge-${box.key}`);
        if (badge) badge.textContent = getString('box_entry_count', counts.get(box.key) ?? 0);
    });
}

/**
 * Wire up the three buttons of every box.
 * @returns {void}
 */
function setupBoxActions() {
    CONFIG_BOXES.forEach(box => {
        document.getElementById(`edit-${box.key}`).onclick = () => openConfigEditor(box.key);
        document.getElementById(`apply-${box.key}`).onclick = () => runSusAF(applyFlags[box.key]);
        document.getElementById(`custom-${box.key}`).onclick = () => applyCustomFile(box.key);
    });
}

/**
 * Let the user pick an arbitrary file and apply it directly, without
 * touching the box's default persistent file.
 * @param {string} key
 * @returns {Promise<void>}
 */
async function applyCustomFile(key) {
    const path = await FileSelector.getFilePath('txt');
    if (!path) return;
    runSusAF(applyFlags[key], path);
}

// Toggles box

const TOGGLE_ROWS = [
    { id: 'toggle-hide-mnts', key: 'HIDE_SUS_MNTS_NON_SU', command: 'hide_sus_mnts_for_non_su_procs' },
    { id: 'toggle-hide-mnts-late', key: 'HIDE_SUS_MNTS_LATE', command: 'hide_sus_mnts_for_non_su_procs' },
    { id: 'toggle-allow-broad-umount', key: 'ALLOW_BROAD_KERNEL_UMOUNT', capability: 'KERNEL_UMOUNT' },
    { id: 'toggle-enable-log', key: 'ENABLE_LOG', command: 'enable_log' },
    { id: 'toggle-avc-spoof', key: 'ENABLE_AVC_LOG_SPOOFING', command: 'enable_avc_log_spoofing' },
];

async function loadToggles() {
    const result = await exec(`sh "${moduleDirectory}/SusAF.sh" --config-show`);
    const content = result.errno === 0 ? result.stdout : '';
    TOGGLE_ROWS.forEach(({ id, key }) => {
        const match = content.match(new RegExp(`^${key}=(.*)$`, 'm'));
        const value = match ? match[1].trim() : '0';
        const row = document.getElementById(id);
        row.querySelector('md-switch').selected = value === '1';
    });
}

let toggleSavePromise = Promise.resolve();

async function saveTogglesNow() {
    const values = {};
    TOGGLE_ROWS.forEach(({ id, key }) => {
        const row = document.getElementById(id);
        values[key] = row.querySelector('md-switch').selected ? '1' : '0';
    });

    const assignments = Object.entries(values).map(([key, value]) => `${key}=${value}`);
    const result = await exec(
        `sh "${moduleDirectory}/SusAF.sh" --config-set ${assignments.join(' ')}`
    );
    if (result.errno !== 0) {
        showPrompt(getString('global_save_fail'), false);
        console.error('Failed to save toggles through SusAF controller:', result.stderr);
        throw new Error(result.stderr || 'SusAF config save failed');
    }
}

function saveToggles() {
    toggleSavePromise = toggleSavePromise
        .catch(() => {})
        .then(() => saveTogglesNow());
    return toggleSavePromise;
}

function setupToggles() {
    TOGGLE_ROWS.forEach(({ id }) => {
        document.getElementById(id).querySelector('md-switch').addEventListener('change', saveToggles);
    });
    document.getElementById('apply-toggles').onclick = async () => {
        await saveToggles();
        runSusAF('--apply-toggles', 'current');
    };
}

async function openConfigEditor(key) {
    const fileName = filePaths[key];
    const content = await fetchText('link/PERSISTENT_DIR/' + fileName, `${basePath}/${fileName}`).catch(() => '');

    openEditor(fileName, content, async (newContent) => {
        const normalized = newContent.endsWith('\n') ? newContent : `${newContent}\n`;
        const result = await writeTextFileAtomic(`${basePath}/${fileName}`, normalized, '600');
        if (result.errno === 0) {
            showPrompt(getString('global_saved', `${basePath}/${fileName}`));
        } else {
            showPrompt(getString('global_save_fail'), false);
            console.error('Failed to save file:', result.stderr);
        }
        refreshBadges();
    });
}

export function mount() {
    const container = document.getElementById('susfs-boxes');
    const togglesBox = document.getElementById('toggles-box');
    CONFIG_BOXES.forEach(box => container.insertBefore(buildBox(box), togglesBox));

    setupBoxActions();
    setupToggles();
}

const playIcon2 = `<svg xmlns="http://www.w3.org/2000/svg" height="34px" viewBox="0 -960 960 960" width="34px"><path d="M320-200v-560l440 280-440 280Z"/></svg>`;
const refreshIcon2 = `<svg xmlns="http://www.w3.org/2000/svg" height="24px" viewBox="0 -960 960 960" width="24px"><path d="m296-224-56-56 240-240 240 240-56 56-184-183-184 183Zm0-240-56-56 240-240 240 240-56 56-184-183-184 183Z"/></svg>`;

function restoreFabIcons() {
    const actionIcon = document.querySelector('#action-btn md-icon');
    const forceUpdateIcon = document.querySelector('#force-update-btn md-icon');
    if (actionIcon) actionIcon.innerHTML = playIcon2;
    if (forceUpdateIcon) forceUpdateIcon.innerHTML = refreshIcon2;
}

export function onShow() {
    updateUIVisibility();
    restoreFabIcons();
    const actionBtn = document.getElementById('action-btn');
    const forceUpdateButton = document.getElementById('force-update-btn');
    actionBtn.onclick = () => runSusAF('--action');
    forceUpdateButton.onclick = () => {
        capabilityCache = null;
        runSusAF('--force-update');
    };
    refreshBadges();
    loadToggles();
    applyCapabilityVisibility();
}

export function onHide() {
    document.querySelectorAll('.fab-container').forEach(c => c.classList.remove('show', 'inTerminal'));
    document.getElementById('save-btn')?.classList.remove('show');
    document.getElementById('line-wrap-btn')?.classList.remove('show');
}
