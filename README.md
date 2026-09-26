# Sus'AF

[![Build Status](https://github.com/fgjaee/SusAF-/actions/workflows/release.yml/badge.svg?branch=susaf-dev)](https://github.com/fgjaee/SusAF-/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/fgjaee/SusAF-?label=Latest%20Release&color=00aa00)](https://github.com/fgjaee/SusAF-/releases)
[![Downloads](https://img.shields.io/github/downloads/fgjaee/SusAF-/total?label=Downloads&color=00aa00)](https://github.com/fgjaee/SusAF-/releases)
[![GitHub License](https://img.shields.io/github/license/fgjaee/SusAF-?logo=gnu)](/LICENSE)
[![SuSFS](https://img.shields.io/badge/SuSFS-4CAF50?&logo=gitlab&logoColor=white)](https://gitlab.com/simonpunk/susfs4ksu)
[![KernelSU](https://img.shields.io/badge/KernelSU-000000?&logo=github&logoColor=white)](https://github.com/tiann/KernelSU)
[![ReSukiSU](https://img.shields.io/badge/ReSukiSU-E91E63?&logo=github&logoColor=white)](https://github.com/ReSukiSU/ReSukiSU)

Sus'AF is an independently maintained [KernelSU](https://kernelsu.org) module
and WebUI for capability-aware SuSFS/KernelSU control, runtime verification,
diagnostics, migration, secure updating, backup/restore, and evidence-driven
policy generation. Product behavior and development decisions are defined by
this repository.

> [!WARNING]
> Sus'AF is currently a development build. Do not treat it as a stable daily-driver release until the prerelease checklist and device tests are complete.

The current branch is a development build. Installation is non-interactive;
there are no Volume Up/Down choices.

See the dated [current development state](docs/CURRENT_STATE.md), the
[roadmap](docs/ROADMAP.md), and the [device smoke test](docs/DEVICE_SMOKE_TEST.md)
before treating a build as release-ready.

## What Sus'AF owns

The canonical product branch is `susaf-dev`; active behavior, policy, UI, and
release decisions are Sus'AF-owned. Key layers include:

- **Autopilot policy generation:** inventories readable running application
  processes, mapped module files, distinct mount namespaces, live
  KernelSU/module-backed mounts, known artifacts, and supported spoof controls.
- **Evidence and risk, not a static target dump:** every generated correction
  records what was observed, the proposed action, its process/device scope, and
  a low/medium/high risk level. Low-risk corrections can apply after boot;
  riskier changes require an explicit WebUI warning.
- **Recoverable application:** atomic configuration writes, private provenance
  records, a pre-apply checkpoint, post-apply verification, and rollback.
- **KernelSU integration:** trusted daemon discovery, targeted `kernel_umount`,
  broad-target quarantine, already-registered detection, supported
  `selinux_hide` control, and compatibility with manager-packaged `libksud.so`.
- **Independent lifecycle:** the `/data/adb/SusAF` data model, guarded migration
  from older modules, configuration-preserving upgrades, a pinned fail-closed
  userspace updater, reproducible builds, and a Sus'AF-specific test suite.
- **Preserved user intent:** UserHub scripts and schedules survive upgrades;
  ADB and uname behavior remain independent controls and are never silently
  changed by Autopilot.

See [How Sus'AF Autopilot works](docs/AUTOPILOT.md) for the complete evidence,
policy, risk, verification, and rollback model.

## Requirements

- [KernelSU](https://kernelsu.org)

## Install

1. Download the [latest Sus'AF release](https://github.com/fgjaee/SusAF-/releases/latest)
2. Flash the zip in KernelSU Manager
3. Reboot
4. Autopilot audits the settled device after boot and applies only generated
   low-risk corrections
5. Open the bottom-bar **Autopilot** destination to review any medium/high-risk
   corrections before applying them
6. Optional: edit config files or use the Advanced controls to fine-tune the
   generated policy

## Config files

All optional, all live under `/data/adb/SusAF/`. Missing or empty files mean "nothing to apply" for that feature, no errors. Entries are appended in the order they appear, top line first.

| File | What it does |
|---|---|
| `sus_paths.txt` | hide static/read-only paths |
| `sus_paths_loop.txt` | hide frequently changing paths |
| `sus_maps.txt` | hide mapped library files |
| `kstat_paths.txt` | spoof file stat for bind mounted paths |
| `open_redirect.txt` | redirect a path to another path |
| `uname.txt` | spoof kernel release/version |
| `cmdline_or_bootconfig.txt` | spoof `/proc/cmdline` or `/proc/bootconfig` |
| `kernel_umount.txt` | extra validated KernelSU kernel-umount targets; broad partition roots are preserved but quarantined by default |
| `config.txt` | kernel flags plus explicit `kernel_umount` and Developer Options/ADB policies |
| `scripts/` | built-in scripts for spoofing and hiding |
| `scripts_postfs.txt` | scripts to run at post-fs-data stage |
| `scripts_bootcompleted.txt` | scripts to run at boot-completed stage |

## Built-in Scripts

Pre-made scripts for common spoofing and hiding tasks. They live in `/data/adb/SusAF/scripts/` and are enabled by default for set-and-forget users. They can be disabled by removing their filenames from `scripts_postfs.txt` or `scripts_bootcompleted.txt`.

Packaged built-ins use the `SusAF_` prefix. During migration, only the known
legacy built-in names are rewritten in schedule files; custom script names and
contents are left alone.

Baseline boot tasks are scheduled out of the box, and Autopilot adds only
evidence-backed low-risk corrections automatically. Power users can review
riskier generated corrections and fine-tune individual scripts through the
WebUI or by editing the files directly.

| Script | Stage | What it does |
|---|---|---|
| `SusAF_apply-cmdline-bootconfig.sh` | post-fs-data | hides bootloader unlock state from kernel cmdline/bootconfig |
| `SusAF_apply-kstat-add.sh` | post-fs-data | hides file stats for framework-managed paths |
| `SusAF_apply-ksu-settings.sh` | post-fs-data | sets KernelSU features for hiding and compatibility |
| `SusAF_apply-uname.sh` | post-fs-data | applies the existing independent uname configuration; Autopilot never edits it |
| `SusAF_apply-mount-hiding.sh` | boot-completed | hides module mounts redirected to system paths |
| `SusAF_apply-props.sh` | boot-completed | removes verified-boot error keys without rewriting build identity |
| `SusAF_apply-settings.sh` | boot-completed | applies the explicit Developer Options/ADB mode; defaults to unchanged |
| `SusAF_apply-sus-maps.sh` | boot-completed | applies exact `sus_maps.txt` targets; no blanket `.so` or font scan |
| `SusAF_apply-sus-paths-loop.sh` | boot-completed | hides selected recovery/root-tool paths; PTY nodes are explicit-only |
| `SusAF_apply-sus-paths.sh` | boot-completed | hides custom ROM traces and addon.d paths |
| `SusAF_cleanup-markers.sh` | boot-completed | removes susfs leftover markers from shared storage |

Sus'AF resolves the KernelSU daemon from trusted standalone locations and from
known manager-native locations, including ReSukiSU and KernelSU-Next's packaged
`libksud.so`.
The Diagnostics page shows the exact daemon selected so a missing manager
interface cannot be mistaken for missing kernel support. It also distinguishes
newly added kernel-umount entries from targets already present in KernelSU's
global list and shows the current `selinux_hide` support/state.
Whole-partition targets such as `/system_ext` are not registered unless
`ALLOW_BROAD_KERNEL_UMOUNT=1`; this prevents a legacy entry from creating a
different mount view for ordinary and isolated app processes.

`ADB_MODE=unchanged` is the safe default. `spoof-off` refuses without changing
the working transport because this stack cannot currently spoof Settings
provider reads safely. `actually-disable` requires
`ADB_DISABLE_CONFIRM=disable-adb`, then verifies that all three settings are
off and `adbd` has stopped.

## WebUI Features

- **Strong hiding by default**, built-in scripts are pre-enabled for set-and-forget users
- **Status dashboard**, see if SuSFS is active at a glance, tap for the full enabled-features breakdown straight from the kernel
- **Configuration summary**, live entry counts per feature and enabled script count, right on the home page
- **Private diagnostics page**, inspect KernelSU/SuSFS state, boot sanitation, ADB mode, boot-stage results, migration, and targeted-rule counts; refresh or export explicitly
- **Sus'AF Autopilot**, inventories running app processes and mount namespaces, generates supported hiding/spoof corrections, applies low-risk findings automatically, warns before risky changes, verifies state, and keeps a rollback checkpoint; see the [Autopilot guide](docs/AUTOPILOT.md)
- **Built-in code editor**, full-screen editor for every config file and user script, no terminal needed
- **File manager**, browse storage and load a custom file straight into any feature, without overwriting your default
- **User-friendly SuSFS configs**, every feature exposed as its own clean box: edit, apply, or load custom
- **Toggle switches**, flip kernel flags (mount hiding, logging, avc spoofing) without touching raw text
- **Built-in scripts manager**, view, enable, or disable pre-made spoofing and hiding scripts from the WebUI
- **UserHub**, create, edit, run, and delete your own shell scripts, with per-script toggles to run automatically at post-fs-data and/or boot-completed
- **Backup and restore**, export your whole config (and any UserHub scripts) into one archive, restore it on any device
- **Reboot button**, with confirmation, right in the header
- **Multi-language support**

## UserHub

A tab for managing your own shell scripts without a terminal:

- Create a new script from a blank template, or import an existing `.sh` file from storage
- Edit any script in the same full-screen code editor used for config files
- Run a script on demand, output streams live in the WebUI
- Toggle a script to run automatically at `post-fs-data` and/or `boot-completed`

Scripts live under `/data/adb/SusAF/scripts/`. Which scripts run at which stage is tracked in `scripts_postfs.txt` and `scripts_bootcompleted.txt` under the same directory.

## Migration

On first installation, Sus'AF can import understood configuration from legacy
data locations, including `/data/adb/ReSuSFS` and `/data/adb/susfs4ksu`.
Those names exist only as migration compatibility inputs; they are not active
Sus'AF product identity. Existing Sus'AF values win. UserHub scripts are copied
byte-for-byte with their executable modes, and their post-fs-data,
boot-completed, and cron assignments remain in the same stage.

After the import and stage-list verification succeed, the old top-level data
directories are moved intact into
`/data/adb/SusAF/migration/legacy-sources/`. This removes stale active-looking
folders without deleting their contents. Snapshots, rejected data, conflicts,
and renamed built-ins remain recoverable under `/data/adb/SusAF/migration/`.
An installed legacy module is disabled but retained so two boot services cannot
run at once.

## CLI

Every command can be run manually via `SusAF <flag>`. A temporary legacy CLI
compatibility alias may still be installed for migrated scripts; removal of
that alias is tracked in the roadmap.

```
  ____            _      _    _____
 / ___| _   _ ___| |    / \  |  ___|
 \___ \| | | / __| |   / _ \ | |_
  ___) | |_| \__ \ |  / ___ \|  _|
 |____/ \__,_|___/_| /_/   \_\_|

                         Sus'AF

[%] status: active ✅ | susfs v2.3.0 (GKI) | features: 9 🧩
usage:
 --action 				full apply (early+late stage)
 --stage-early 				post-fs-data stage only
 --stage-late 				boot-completed stage only
 --status 				show susfs version / variant / enabled features
 --diagnostics 			refresh and print the private diagnostics snapshot
 --status-report 			refresh diagnostics without editing module.prop
 --coverage-scan [package] 		audit all running apps or one package
 --coverage-apply <ids> 		checkpoint and apply selected candidates
 --coverage-apply-safe 		apply all generated low-risk candidates
 --coverage-verify 			rescan and verify the generated policy
 --coverage-rollback 		restore the last Autopilot checkpoint
 --autopilot-boot 			audit and apply safe candidates after boot

if [file] is given it is appended (deduped) into the default list, then applied:
 --apply-sus-paths [file] 		add_sus_path from list
 --apply-sus-paths-loop [file] 		add_sus_path_loop from list
 --apply-sus-maps [file] 		add_sus_map from list
 --apply-kstat-add [file] 		stage add_sus_kstat from list
 --apply-kstat-add-direct <file> 	stage generated kstat data without saving it
 --apply-kstat-update [file] 		commit update_sus_kstat from list
 --apply-open-redirect [file] 		add_open_redirect from list
 --apply-uname [file] 			set_uname from config
 --apply-cmdline-bootconfig [file] 	set_cmdline_or_bootconfig from file
 --apply-toggles <early|late> [file] 	apply hide_sus_mnts/enable_log/avc_log_spoofing from config
 --run-script <file> 			run a user script from UserHub
 --run-postfs-scripts 			run all UserHub scripts flagged for post-fs-data
 --run-bootcompleted-scripts 		run all UserHub scripts flagged for boot-completed

 --help 				displays this message

```

Every `--apply-*` flag accepts an optional file path. Passing one appends that file's contents into the default config file (deduplicated, comments preserved), then applies the merged default. It does not run standalone or get discarded after, it becomes a permanent part of your saved config:

```sh
SusAF --apply-sus-paths /sdcard/my_paths.txt
```

Check status any time to confirm SuSFS is active and see which kernel features are enabled:

```sh
SusAF --status
```

`SusAF --diagnostics` atomically refreshes
`/data/adb/SusAF/state/diagnostics.properties` and prints it. The snapshot is
mode `0600`; it includes system state and counts but excludes configured target
paths and UserHub script contents. The bottom-bar **Autopilot** page reads the
last boot snapshot without changing device configuration, with separate
Refresh and Export actions. Export refreshes the snapshot first so the saved
report describes the current audit state instead of a stale boot snapshot.

Autopilot is evidence-driven rather than a raw filesystem crawl. A full audit
examines every readable running application process (UID 10000 or higher), its
file-backed maps, each distinct readable mount namespace, the global mount
view, current root/recovery artifacts, and supported KernelSU/SuSFS controls.
It generates exact `SUS_MAP`, `SUS_PATH_LOOP`, `kernel_umount`, and supported
control changes. Medium/high-risk candidates are selected for review but never
silently applied. A focused audit remains available when one package needs to
be isolated.

Autopilot verifies the policy it controls; it does not claim to repair TEE
verdicts, anonymous-memory hooks, package visibility, certificates, or kernel
behavior for which the installed stack provides no hook. Audit, apply, Verify,
and rollback show their live stage and elapsed time while the device is busy.
Verify also refuses to call the kernel layer clean when the KernelSU daemon or
its feature/mount interface is unavailable. Reboot before using a third-party
detector as the final namespace check.

The same workflow is available from a root shell:

```sh
SusAF --coverage-scan
SusAF --coverage-scan com.example.detector
SusAF --coverage-apply 1,3
SusAF --coverage-verify
SusAF --coverage-rollback
```

## Current validated state

The active development state changes as device testing progresses. The dated
[current development state](docs/CURRENT_STATE.md) is the authoritative summary
of what has been proven on-device, what remains detector-specific, and which
behaviors are still pending implementation. Historical validation remains in
[reference device validation](docs/DEVICE_VALIDATION.md).

## Secure SuSFS userspace updates

Installation, the module-manager action, and the WebUI update control use the
same fail-closed updater. Each Sus'AF release bundles the executable pinned to
an immutable source commit and SHA-256 digest in `update-manifest.properties`;
a moving branch cannot silently change the executable delivered by an existing
release, and installation does not require a live download.

The updater prefers the bundled copy and uses the pinned HTTPS URL only as a
recovery fallback. It verifies the digest and AArch64 ELF identity, probes the
kernel SuSFS version/variant, then installs with a same-directory atomic rename.
The module-local verified copy remains usable if a root-manager update removes
the global command. A verified working binary is retained for rollback. Source,
hashes, probe results, backup, rollback, and final status appear on the
Diagnostics page.

## Backup and share your config

The WebUI exports recognized Sus'AF settings, boot schedules, WebUI assets,
and UserHub scripts into a schema-marked archive. Restore validates every
member before extraction, uses a private staging directory, and keeps replaced
files under `/data/adb/SusAF/restore/`. If the merge fails, it rolls installed
files back instead of leaving a partial configuration.

Export creates the archive in `/storage/emulated/0/Download/`. Unknown paths,
links, special files, traversal, duplicate members, invalid manifests, and
oversized archives are rejected.

## Community

Report Sus'AF bugs and follow development in this fork:

- **Issues:** [Sus'AF issue tracker](https://github.com/fgjaee/SusAF-/issues)

## Credits

- [SuSFS](https://gitlab.com/simonpunk/susfs4ksu) by simonpunk
- WebUI foundation based on [bindhosts](https://github.com/bindhosts/bindhosts) by the bindhosts team

## Author

[fgjaee](https://github.com/fgjaee). Historical ancestry remains available in Git history.

## License

[GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)
