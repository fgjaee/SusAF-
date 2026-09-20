# Sus'AF device smoke test

Complete this checklist on a supported arm64 test device before creating the
first non-development tag. Record the device, Android build, kernel, root
manager, SuSFS version, tester, date, and result for every section.

## Recovery preparation

- Confirm a current device backup and a known way to enter KernelSU safe mode.
- Keep a working computer-side ADB session available.
- Save the current module list and `/data/adb/ReSuSFS`, `/data/adb/susfs4ksu`,
  and `/data/adb/SusAF` configuration directories when present.
- Verify the release ZIP against `SHA256SUMS` before installation.

## Fresh installation and identity

- Install on a device without an existing Sus'AF persistent directory.
- Confirm the module manager shows `Sus'AF` with module ID `susaf`.
- Confirm persistent configuration is created at `/data/adb/SusAF` with private
  directory/file permissions.
- Confirm both `SusAF` and the `ReSuSFS` compatibility command work.
- Reboot twice and confirm there is no bootloop, SystemUI crash, or repeated
  service process.

## Legacy migration

- Repeat from a snapshot containing useful `/data/adb/ReSuSFS` and
  `/data/adb/susfs4ksu` configuration.
- Confirm migration markers and review snapshots are created, then confirm the
  old top-level directories are gone and their intact contents are recoverable
  under `/data/adb/SusAF/migration/legacy-sources/`.
- Compare the Max Saturation UserHub script byte-for-byte before and after.
- Confirm its original post-fs-data, boot-completed, or cron schedule remains
  unchanged; no script moves to another stage.
- Confirm conflicts preserve the existing Sus'AF value and are placed in the
  migration review area.

## Boot state and uname

- Confirm generated bootconfig/cmdline state contains only the current value
  for each managed key after two boots.
- Confirm `androidboot.verifiedbooterror` and `androidboot.verifyerrorpart` are
  absent from the generated state.
- Compare effective uname release/version with the expected existing ReSuSFS
  behavior, then test one explicit custom uname and restore the default.

## Kernel umount and hiding

- Refresh Diagnostics and confirm `kernelsu.binary` identifies the selected
  standalone `ksud` or known manager-native `libksud.so` before recording
  whether `feature check kernel_umount` is supported.
- With mode `unchanged`, confirm Sus'AF does not change the feature.
- With mode `enabled`, confirm only validated KSU/module-backed mountpoints and
  explicit entries are registered, followed by module-mounted notification.
- Confirm Diagnostics reports early mount filter `1` and late blanket mount
  filter `0`; targeted KernelSU umount entries remain registered after the late
  blanket filter is released.
- Confirm a migrated `/system_ext` entry remains in `kernel_umount.txt` but is
  reported as a quarantined broad target and does not enter the live kernel
  list while `ALLOW_BROAD_KERNEL_UMOUNT=0`.
- Run the late stage twice and confirm existing entries are reported as already
  registered rather than failures; no global umount-list wipe may occur.
- Confirm Diagnostics shows the current `selinux_hide` support and state.
- Confirm unsupported kernels degrade visibly without blocking boot.
- Confirm no blanket `/dev/pts/*` enumeration occurs.
- Confirm SUS_MAP applies only explicit `sus_maps.txt` targets and never every
  module `.so` or font.
- Confirm the exact legacy `/system/etc/hosts 100 ... 1 4096` Kstat default is
  removed on upgrade and recoverable from the migration archive.

## Autopilot policy generation

- Reboot with `AUTOPILOT_SCAN_ON_BOOT=1` and confirm the private boot report is
  generated after Android reaches boot complete.
- Confirm `AUTOPILOT_APPLY_SAFE=1` applies only low-risk candidates. Medium and
  high-risk candidates must remain pending for WebUI confirmation.
- Run **Audit everything** with several ordinary apps and the detector open.
  Confirm the report counts readable app processes and distinct mount
  namespaces and records evidence, action, scope, and risk for every candidate.
- Confirm generated `SUS_MAP` targets are exact existing mapped files beneath
  approved module/root-manager roots. An arbitrary out-of-scope map must be
  rejected during apply.
- If a mount or peer/master/propagation ID exceeds the documented threshold,
  confirm the late mount-view attempt is classified high risk and displays the
  warning before apply.
- Confirm selecting a broad mount target is the only generated path that sets
  `ALLOW_BROAD_KERNEL_UMOUNT=1`.
- Apply a mixed selection, confirm a private checkpoint and provenance entry
  are created, then reboot and run **Verify**.
- Run **Undo last changes**, reboot, and confirm the prior four policy files are
  restored and runtime state matches them.
- Confirm Autopilot does not edit uname, enable KPM, or change ADB while its
  mode remains `unchanged`.
- Record the third-party detector result separately from Sus'AF verification;
  use the format in [Reference device validation](DEVICE_VALIDATION.md).

## Verified-boot property sanitation

- Confirm `verifiedbooterror` and `verifyerrorpart` properties are removed when
  present.
- Confirm the built-in task does not rewrite fingerprint, build type, tags,
  product identity, lock state, Developer Options, or ADB properties.

## Developer Options and ADB

- In `unchanged`, confirm Developer Options, USB debugging, wireless debugging,
  USB functions, and `adbd` remain unchanged.
- In `spoof-off`, confirm the mode either preserves working ADB while hiding a
  supported indicator or refuses clearly; it must never claim a false success.
- Test `actually-disable` only with independent recovery access. Confirm the
  WebUI requires explicit confirmation and `adbd` actually stops.
- Return to `unchanged` and restore the intended debugging state.

## Diagnostics, update, and restore

- Confirm the Diagnostics page loads offline, refreshes on demand, exports a
  text report, and contains no configured target paths or script bodies.
- Run `SusAF --force-update`; verify the pinned source commit, expected and
  installed SHA-256, compatibility probe, backup, and result in Diagnostics.
- Run it again and confirm `already-current` without a second download.
- Export configuration, inspect the archive manifest, restore it, and confirm
  collision backups are retained under `/data/adb/SusAF/restore`.
- Confirm restored Max Saturation and another custom UserHub script are
  byte-identical and retain their schedules after reboot.
- Try an archive with an unknown member and a symlink on the test device;
  confirm restore refuses it without changing live configuration.

## Release gate

- Confirm the GitHub build job passes and its two independently built ZIPs are
  byte-identical before the duplicate is discarded.
- Install the exact `SusAF.zip` artifact produced by that run, not a locally
  repacked copy.
- Mark the candidate releasable only when every applicable check above passes
  and all deviations have an issue or an explicit documented waiver.
