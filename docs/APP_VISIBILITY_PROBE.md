# Sus'AF Full Visibility Audit (preview)

This is one complete workflow, not a detector score or one-pass root-shell inventory:

1. **Discover:** Inspect direct children of `/data/local/tmp` with recognizable root-runtime names, and the known optional virtual APEX `/apex/com.android.virt/bin/su`. No recursive disk search and no file contents read.
2. **Verify with a separate Android app:** After the user explicitly installs the bundled `SusAF-Visibility-Probe.apk`, the normal audit batches up to 32 exact paths per Binder call. The app issues `Os.lstat` from its own Android application UID and returns `VISIBLE`, `MISSING`, `DENIED`, or `ERROR`. KernelSU/SusAF root processes do **not** perform these app-side checks.
3. **Explain:** Sus'AF combines root-shell type/evidence, detected SUSFS backend, configured rules, and the app result. A root-shell discovery alone is **not** proof that apps see it.
4. **Review:** Only paths that the app actually reported **VISIBLE**, and which have a usable SUSFS operation, are eligible for a high-risk candidate. Never silently stage or auto-apply them. Static-only LKM rules use `sus_paths.txt`; patched-kernel loop rules use `sus_paths_loop.txt`.
5. **Apply with a checkpoint:** The existing risk-confirmation dialog, private config checkpoint, provenance log, and runtime apply pipeline are reused.
6. **Re-audit:** The existing Verify flow repeats the separate app observation. An app-visible path is an **attention** result even if the kernel policy itself looks healthy.
7. **Rollback:** Restore the previous config and schedule. Kernel rules may persist until a reboot; rollback cannot claim to clear an existing in-kernel rule immediately.

## Normal usage

Open **Autopilot / Diagnostics** in Sus'AF WebUI. Tap **Audit everything**. If the app verifier is not installed, tap **Install / update app verifier** and confirm. The APK ships inside the module ZIP; no third-party download is required. Sus'AF reruns the audit automatically after successful installation.

Review any app-visible runtime-artifact candidates. They are **high-risk**, since hiding a live `ksud` or temporary-root socket could affect root. Only apply after reading the explicit risk review and ensuring you have a recovery/reboot plan. The default boot Autopilot applies **low-risk** candidates only and does not auto-apply these new candidates.

**No new app installed?** Sus'AF still provides root-side observations, but labels app visibility `not-tested` and never produces app-visible artifact candidates.

## Trust and limitations

- The verifier has no requested runtime permissions, no root privilege, no network capabilities, and no launcher. It is a normal Android app exporting a ContentProvider that refuses calls from Android UIDs other than shell, root, or itself.
- The controller requires an app UID (>= 10000), an exact response version, the expected path count, and one validated verdict per requested path.
- A reported `MISSING` or `DENIED` means **this verifier app process** could not stat the path. It does not prove *why* or that all apps will see the same result. SELinux, DAC access, namespace contexts, and app-specific settings can differ.
- App launch and Android package security may behave differently between OnePlus 12R (Android 15) and Pixel 10 Pro Fold (Android 17). The current CI validates the Java build and mocked controller protocol but **cannot** substitute for an on-device test.
- Probe APKs built in GitHub Actions without optional signing secrets use **temporary CI keys**. A later preview may not update an earlier preview without uninstalling the old verifier; the installer does not silently uninstall it.
- The source is in `probe-app/`. The CI verifies the APK signature and bundles the signed APK under `module/probe/`. Nothing is automatically installed merely by installing the Sus'AF module.
- This is **not** Google Play Integrity attestation, TEE/StrongBox testing, or a universal bypass of root detection.
- Root filesystem findings do not include package-manager enumeration, framework hooks, Zygisk/LSPosed, and kernel timing checks.
- A shell or app failure must be `unavailable`, `not-tested`, `error`, or `attention`, never a false claim that the phone is stock.

## CLI and reports

```sh
su -c 'sh /data/adb/modules/susaf/SusAF.sh --coverage-scan'
su -c 'sh /data/adb/modules/susaf/SusAF.sh --coverage-verify'
```

The private report under `/data/adb/SusAF/state/coverage.report.txt` contains:
- `exposure.probe_status` and `exposure.probe_uid`;
- root-observed paths and types;
- `exposure.N.app_visibility` for each path;
- `exposure.visible_count`, `exposure.missing_count`, `exposure.denied_count`;
- `candidate.N.risk=high` only for separately app-visible, backend-supported targets.

The diagnostics export retains aggregate counts/status rather than the raw list of private paths.

## Maintainer verification

CI:
- `tests/test-exposure-audit.sh`: bounded root-side discovery, socket/symlink and missing paths.
- `tests/test-probe-verify.sh`: protocol parsing, genuine app UID, no app, mismatches.
- `tests/test-reviewed-exposure.sh`: static and loop review, checkpoint/rollback, tampered reports.
- `tests/test-full-audit-flow.sh`: simulated scan → app verdict → high-risk review → apply → rescan/verify → rollback.
- Android 35 SDK compilation and debug-signed APK validation.
- Existing shell suite, WebUI compilation, module packaging.

On-device smoke tests are still required for each root backend before a stable release.
