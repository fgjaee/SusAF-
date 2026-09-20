# Sus'AF Changelog

This changelog covers Sus'AF development. Upstream history remains available in
Git history and the upstream project; it is not repeated here.

## v0.1.0-dev.10 — 2026-09-20

- Replaced the manual-first Coverage Assistant with Sus'AF Autopilot. A full
  audit now inventories all readable running application processes, their
  distinct mount namespaces, mapped module files, live module-backed mounts,
  existing root/recovery artifacts, and supported KernelSU/SuSFS controls.
- Generated a complete editable policy instead of requiring the user to know
  SUS_PATH, SUS_MAP, or kernel-umount targets. Evidence-backed low-risk fixes
  can apply automatically after boot; medium/high-risk fixes are preselected
  but show a clear notification before application.
- Added real spoof attempts for high mount/peer IDs, AVC context exposure, and
  supported KernelSU SELinux hiding. High mount-ID spoofing uses the installed
  SuSFS application-view filter and is explicitly marked high risk.
- Added immediate application, post-apply verification, atomic configuration
  updates, provenance logs, recoverable checkpoints, and one-tap rollback.
  Runtime rules are never reported as fully cleared until the required reboot.
- Kept uname unchanged unless its existing independent control is manually
  enabled. No KPM integration or blanket anonymous-memory claim was added.

## v0.1.0-dev.9 — 2026-09-17

- Added a conservative Coverage Assistant to Diagnostics. It audits configured
  rules and schedules, scans one explicitly selected running app for exact
  file-backed module mappings, and requires manual review before saving.
- Kept `SUS_MAP` targeted: the assistant neither crawls every shared library
  nor creates broad directory rules. Unsupported anonymous maps, kernel/TEE
  signals, properties, packages, and user certificates are called out instead
  of being presented as fixed.
- Added private scan reports, strict package/path validation, recoverable
  checkpoints, provenance logging, and idempotent CLI support through
  `--coverage-scan` and `--coverage-apply`.
- Reworked upgrade preservation so existing configuration values, disabled
  schedule entries, custom scripts, and locally edited built-ins survive
  reinstall. Packaged updates to edited built-ins are staged for review.
- Added a pre-upgrade checkpoint and installer result report to Diagnostics,
  plus atomic WebUI saves for config files, schedules, and UserHub scripts.
- Fixed the custom-ROM path scan so every recognized ROM prefix is checked
  rather than only the final prefix in the list.

## v0.1.0-dev.8 — 2026-09-16

- Traced the remaining cross-process mount warning to a migrated explicit
  `/system_ext` kernel-umount target. ReSukiSU applies registered targets to
  isolated processes even when the ordinary app UID is not selected for
  module unmounting, which creates two observable mount views.
- Preserved broad legacy targets in `kernel_umount.txt` but quarantined exact
  partition/root mountpoints from automatic registration by default. Narrow
  file and directory targets continue to work normally.
- Added an explicit `ALLOW_BROAD_KERNEL_UMOUNT` compatibility override, WebUI
  control, and diagnostic counts for quarantined targets.

## v0.1.0-dev.7 — 2026-09-15

- Fixed an inherited boot-stage bug that kept broad Sus mount filtering enabled
  after boot even though the configuration documentation described turning it
  off. The early zygote guard remains enabled by default; the late blanket
  filter now defaults off while targeted KernelSU umount and Sus path rules stay
  active.
- Added separate early and late mount-filter controls to the WebUI. Existing
  configurations without the new late key safely default to off.
- Added both staged filter values to Diagnostics; enabling the late blanket
  compatibility mode is now visibly treated as degraded configuration.

## v0.1.0-dev.6 — 2026-09-14

- Correctly classifies KernelSU umount targets that are already registered,
  rather than reporting the kernel's duplicate response as a failed add. True
  add failures are recorded separately and now degrade the diagnostic status.
- Reports safe explicit paths that are not current mountpoints as inactive
  instead of rejected.
- Added KernelSU SELinux-hide support/state and already-registered umount counts
  to the WebUI Diagnostics page.
- Added a recoverable upgrade repair for the exact legacy hosts-file Kstat
  default. The removed line is archived under Sus'AF's migration directory.
- Reduced the inherited property task to the requested `verifiedbooterror` and
  `verifyerrorpart` sanitation. It no longer rewrites fingerprint, build type,
  tags, lock state, ADB, product, or other boot properties after initialization.
- Replaced the WebUI's runtime download of upstream ReSuSFS documentation with
  bundled Sus'AF documentation, preventing old branding, donation material, or
  root-manager commentary from reappearing through the module interface.

## v0.1.0-dev.5 — 2026-09-14

- Added trusted discovery of manager-packaged KernelSU daemons, including
  ReSukiSU's executable `libksud.so`, so `kernel_umount` feature control and
  mount registration no longer depend on a standalone `ksud` in `PATH`.
- Made kernel-umount reports and the WebUI Diagnostics page show the selected
  daemon path. An enabled but unreachable interface now marks the snapshot as
  degraded and distinguishes daemon and interface failures from unsupported
  kernel functionality.
- Updated the built-in KernelSU-settings and uname tasks to use the same daemon
  resolver while preserving uname's existing no-daemon fallback.
- Removed the hard-coded hosts-file Kstat spoof from the built-in task; mount
  identity is handled by targeted KernelSU umount registration instead.

## v0.1.0-dev.4 — 2026-09-13

- Made empty Open Redirect configuration report that the optional feature is
  off instead of opening a blank action screen. Silent actions now receive a
  generic terminal message as a final fallback.
- Added an upgrade repair that recoverably archives cmdline/bootconfig files
  larger than the kernel interface's 8,191-byte limit and restores the clean
  template; normal boot continues to generate a fresh sanitized snapshot.
- Stopped the built-in Sus Kstat task from appending generated module paths to
  persistent user configuration. Known generated ReSuSFS/SusAF entries are
  archived and removed on upgrade, and missing targets are skipped cleanly.

## v0.1.0-dev.3 — 2026-09-13

- Bundled the release-pinned, digest-verified `ksu_susfs` binary so installation
  and recovery no longer depend on a live download.
- Added a module-local executable fallback and support for both KernelSU and
  APatch binary directories, preventing a missing global copy from breaking
  boot scripts or the WebUI status check.
- Removed the leftover Telegram prompt from the WebUI home page.

## v0.1.0-dev.2 — 2026-09-12

- Removed the timed Volume Up/Down installer prompts. Existing configuration
  now wins, packaged schedule entries are merged without duplicates, and
  UserHub stage assignments are preserved.
- Added repair logic for early Sus'AF builds that could replace a migrated
  `scripts_bootcompleted.txt`, including the Max Saturation assignment.
- Rebranded packaged built-ins from `ReSuSFS_*` to `SusAF_*`; known old
  built-ins and schedule files are moved to a recoverable migration archive.
- Changed completed legacy migration to move `/data/adb/ReSuSFS` and
  `/data/adb/susfs4ksu` into
  `/data/adb/SusAF/migration/legacy-sources/` instead of leaving stale top-level
  directories.
- Changed the module display name to typographic `Sus’AF`, avoiding the
  installer parser error caused by the ASCII apostrophe while preserving the
  intended displayed name.
- Replaced the inherited changelog with project-neutral Sus'AF release notes.
- Kept the `ReSuSFS` command only as a compatibility entry point for migrated
  UserHub scripts.

## v0.1.0-dev.1 — 2026-09-12

- Added KernelSU kernel-umount handling and validated targeted mount discovery.
- Added fresh bootconfig generation and verified-boot error sanitation.
- Preserved uname behavior while preventing stale generated data.
- Added explicit Developer Options/ADB policies: `unchanged`, `spoof-off`, and
  confirmed `actually-disable`.
- Removed blanket PTY and shared-library hiding from the defaults.
- Added a private WebUI diagnostics page.
- Added a fail-closed, digest-pinned SuSFS userspace updater.
- Added validated backup/restore and safe legacy configuration import.
