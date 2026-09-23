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
        result.stdout.split(/\r?\n/).forEach(line => {
            if (!line) return;
            if (line.startsWith('FEATURE=')) {
                features.add(line.slice('FEATURE='.length).trim());
                return;
            }
            const split = line.indexOf('=');
            if (split <= 0) return;
            values[line.slice(0, split).trim()] = line.slice(split + 1).trim();
        });

        capabilityCache = { values, features };
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

async function applyCapabilityVisibility() {
    const capabilities = await loadCapabilities();
    if (!capabilities) return;

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
    for (const box of CONFIG_BOXES) {
        const count = await countEntries(filePaths[box.key]);
        const badge = document.getElementById(`badge-${box.key}`);
        if (badge) badge.textContent = getString('box_entry_count', count);
    }
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
    const result = await exec(`cat "${basePath}/${filePaths.config}" 2>/dev/null`);
    const content = result.errno === 0 ? result.stdout : '';
    TOGGLE_ROWS.forEach(({ id, key }) => {
        const match = content.match(new RegExp(`^${key}=(.*)$`, 'm'));
        const value = match ? match[1].trim() : '0';
        const row = document.getElementById(id);
        row.querySelector('md-switch').selected = value === '1';
    });
}

async function saveToggles() {
    const values = {};
    TOGGLE_ROWS.forEach(({ id, key }) => {
        const row = document.getElementById(id);
        values[key] = row.querySelector('md-switch').selected ? '1' : '0';
    });

    const command = `
        f="${basePath}/${filePaths.config}"
		tmp="\${f}.webui.$$"
		trap 'rm -f "$tmp"' EXIT HUP INT TERM
		[ -f "$f" ] && cp "$f" "$tmp" || : > "$tmp"
        for kv in ${Object.entries(values).map(([k, v]) => `${k}=${v}`).join(' ')}; do
            key=\${kv%%=*}
            val=\${kv#*=}
			if grep -q "^\${key}=" "$tmp" 2>/dev/null; then
				sed -i "s/^\${key}=.*/\${key}=\${val}/" "$tmp"
            else
				echo "\${key}=\${val}" >> "$tmp"
            fi
        done
		chmod 600 "$tmp" && mv "$tmp" "$f"
		trap - EXIT HUP INT TERM
    `;
    const result = await exec(command);
    if (result.errno !== 0) {
        showPrompt(getString('global_save_fail'), false);
        console.error('Failed to save toggles:', result.stderr);
    }
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
    forceUpdateButton.onclick = () => runSusAF('--force-update');
    refreshBadges();
    loadToggles();
    applyCapabilityVisibility();
}

export function onHide() {
    document.querySelectorAll('.fab-container').forEach(c => c.classList.remove('show', 'inTerminal'));
    document.getElementById('save-btn')?.classList.remove('show');
    document.getElementById('line-wrap-btn')?.classList.remove('show');
}
