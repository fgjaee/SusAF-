# Sus'AF current development state

**Last updated:** 2026-09-26  
**Development branch:** `capability-routing`  
**Pull request:** #1 — Refactor SUSFS capability routing

This document is the dated source of truth for the current development build.
It records what has been demonstrated on a real Android 17 device, what is still
an implementation gap, and what third-party detector results mean in context.
A detector result is evidence from one implementation and one runtime snapshot;
Sus'AF should optimize for coherent observable system state rather than hard-code
around one detector.

## Reference device

The current validation device is a Pixel 10 Pro Fold-class Pixel running Android
17 with a KernelSU/ReSukiSU kernel stack and SuSFS **v2.3.0 GKI**.

The running kernel reports these SuSFS features:

- `CONFIG_KSU_SUSFS_SUS_PATH`
- `CONFIG_KSU_SUSFS_SUS_MOUNT`
- `CONFIG_KSU_SUSFS_SUS_KSTAT`
- `CONFIG_KSU_SUSFS_SPOOF_UNAME`
- `CONFIG_KSU_SUSFS_ENABLE_LOG`
- `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS`
- `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG`
- `CONFIG_KSU_SUSFS_OPEN_REDIRECT`
- `CONFIG_KSU_SUSFS_SUS_MAP`

Sus'AF's capability registry matches the kernel-reported feature list. The
active helper is SuSFS v2.3.0 GKI; the shared external helper symlink is
preserved when compatible instead of being replaced blindly.

## Proven on-device

### Configuration and controller

- WebUI toggle persistence has been tested in both directions across page
  navigation.
- Sus'AF's central config controller performs validated, atomic writes instead
  of letting the WebUI edit `config.txt` directly.
- Existing persistent configuration under `/data/adb/SusAF` survives module
  updates.
- The current capability adapter correctly treats the old
  `set_sdcard_root_path` and `set_android_data_root_path` commands as
  unavailable on SuSFS v2.3.0. Those commands belong to the v1.5.8-v2.0.x
  transitional ABI.

### SUS_PATH and SUS_PATH_LOOP

Both paths have been tested end to end from Sus'AF into the running kernel.

A temporary `SUS_PATH_LOOP` target under shared storage became invisible to a
fresh untrusted Termux process after registration. A normal `SUS_PATH` target
was also demonstrated with a fresh app process. Registration failure handling
now continues through the list while returning a nonzero aggregate result and
identifying the exact failed entry.

The previous generic `sus_paths_loop.txt` list was intentionally cleared
during validation. Device policy should be evidence-based rather than populated
with stale generic app paths.

### Mount filtering and Android 17 zygote_next

This is the most important validated controller correction.

With early mount filtering enabled but the late filter disabled, the controller
successfully registered module-backed `kernel_umount` targets, yet Duck
Detector's Android 17 `zygote_next` isolated-process view could still observe
root-managed mounts.

The two confirmed module-backed mounts were:

- `/system/etc/hosts` from BindHosts
- `/apex/com.android.art/bin/dex2oat64` from Zygisk Vector

Turning `hide_sus_mnts_for_non_su_procs` back on live removed the mount
exposures and the associated large mount-ID finding. Persisting
`HIDE_SUS_MNTS_LATE=1` and rebooting kept Duck's mount checks clean.

Therefore the Android 17 validation profile requires:

```ini
HIDE_SUS_MNTS_NON_SU=1
HIDE_SUS_MNTS_LATE=1
```

This is a proven runtime behavior, not a conclusion derived from mount-ID
magnitude.

### Kernel umount discovery

Sus'AF automatically discovered and registered the BindHosts and Zygisk Vector
mountpoints. KernelSU reported both entries accepted, with no registration
failures.

A later ViPER4Android mount at `/vendor/lib/soundfx` was also present in
KernelSU's global umount list. Native Detector's earlier inconsistent-mount
finding disappeared when ViPER was disabled, isolating that finding to the
module's runtime mount behavior rather than a missing Sus'AF registration.

### Mount provenance examples

Testing separated several visually similar mount findings by actual ownership:

- MoveCertificate created `/mnt/instaler` and bind mounts over the Conscrypt
  CA directories. Disabling the module removed that entire mount family.
- BindHosts owns the live `/system/etc/hosts` module mount.
- Zygisk Vector owns the live ART `dex2oat64` module mount.
- ViPER4Android owns the `/vendor/lib/soundfx` work mount.

These results are why future Autopilot logic must identify provenance and mount
topology instead of labeling every unusual mount as equivalent.

## Detector snapshot

Current detector results are useful validation signals, not product
requirements by themselves.

- **Duck Detector:** clean after reboot with persistent late SuSFS mount
  filtering enabled.
- **KKND Detector 3.3:** after updating the detector, all previously reported
  false/stale findings cleared except the real user-installed CA certificate.
- **Native Detector 7.7:** concrete inconsistent-mount findings cleared; a
  generic experimental "abnormal environment" score may remain and is not
  currently treated as an actionable Sus'AF defect.
- **Disclosure:** still reports a "Futile hide (build date...)" finding when the
  kernel's real identity is exposed.

## Kernel identity finding

The current kernel's real identity is internally coherent but conspicuously
custom:

```text
uname release:
6.6.143-android15-Wild

uname version:
/proc/version build:
#1 SMP PREEMPT Thu Jan 1 00:00:00 UTC 1970
```

The current SuSFS `set_uname` feature can change the visible UTS release and
version, for example to a stock-looking Pixel value, but it does not also change
`/proc/version`.

Testing established both sides of the tradeoff:

1. With the stock-looking uname spoof active, Disclosure became clean but
   `uname` and `/proc/version` disagreed.
2. Returning to `default/default` live made Disclosure clean temporarily
   because the two live surfaces matched, while Duck correctly detected that
   the live value no longer matched the identity cached by Zygote earlier in
   boot.
3. Booting from the start with `default/default` restored Duck to clean state,
   while Disclosure again reported the underlying custom/1970 kernel metadata.

Conclusion: current `set_uname` is a **partial identity spoof**. Sus'AF should
not label it verified unless all observable kernel-identity surfaces are
coherent. The roadmap includes a Sus'AF kernel identity profile with an optional
kernel-side provider for the remaining surfaces.

## Known issues and incomplete work

- The SuSFS WebUI page still has noticeable opening lag. Seven serial badge
  subprocesses were reduced to one, but more profiling is required.
- `--coverage-scan` can finish successfully and write
  `state/coverage.report.txt` while producing no stdout.
- The current Autopilot high-mount-ID heuristic is invalid on the reference
  device: all readable application namespaces used high IDs. Raw ID magnitude
  must be diagnostic only.
- Autopilot still mixes curated known-artifact entries with genuine runtime
  discoveries. Those sources must be represented separately.
- Capability status currently focuses on supported/unsupported. The target
  model is **Supported / Configured / Runtime verified**.
- Active product documentation and assets still contain legacy ancestry
  references. Sus'AF product identity is being separated from those references;
  legacy path names should remain only where required for migration
  compatibility.
- Coherent kernel identity spoofing is not implemented yet.
- The user-installed CA certificate is a real external artifact, not something
  Sus'AF should silently hide.

## Current safe baseline

For continued development on the reference device:

- keep late and early non-superuser SuSFS mount filtering enabled;
- keep Autopilot from acting on raw high mount IDs;
- keep kernel identity at `default/default` until coherent identity support
  exists;
- treat module-specific mounts by provenance rather than hard-coded suspicion;
- keep BRENE and other competing policy engines disabled while validating
  Sus'AF so only one controller changes the same kernel state.

See [ROADMAP.md](ROADMAP.md) for the implementation order.
