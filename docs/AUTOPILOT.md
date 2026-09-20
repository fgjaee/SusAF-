# Sus'AF Autopilot

Sus'AF Autopilot turns live device evidence into an editable SuSFS/KernelSU
policy. It is designed for users who should not have to know every `SUS_MAP`,
`SUS_PATH`, or `kernel_umount` target in advance.

Autopilot is one of the main reasons Sus'AF is more than a renamed ReSuSFS
fork. ReSuSFS remains the credited foundation, while the audit engine, policy
schema, risk model, application transaction, verification, and rollback flow
are maintained as Sus'AF features.

## Boot behavior

After Android reports `sys.boot_completed=1`, the service runs:

```sh
SusAF --autopilot-boot
```

With the defaults below, it inventories the settled device, applies only
low-risk generated corrections, rescans, and leaves riskier findings for WebUI
review.

```ini
AUTOPILOT_SCAN_ON_BOOT=1
AUTOPILOT_APPLY_SAFE=1
SELINUX_HIDE_MODE=unchanged
```

The boot log and generated report are private files under
`/data/adb/SusAF/state/`.

## What Audit everything inspects

The full audit uses live evidence rather than asking for a package name:

1. Every readable running process with Android UID 10000 or higher.
2. Existing file-backed mappings in each process's `/proc/<pid>/maps`.
3. The global mount view and every distinct readable application mount
   namespace.
4. KernelSU/module-backed mounts identified by Sus'AF's validated mount
   collector.
5. Existing curated recovery, root-tool, `su`, module, and legacy-module
   artifacts.
6. Supported KernelSU/SuSFS controls and their current state.

**Audit everything is not a blind disk crawl.** Arbitrary files do not become
hiding rules merely because root can read them. Map candidates must be actual
mapped files beneath approved module/root-manager roots. Filesystem-artifact
candidates must exist and belong to the curated catalog. Mount candidates must
come from the validated live mount collector.

The optional **Focused app audit** applies the same checks to a validated
package name when one app needs to be isolated.

## Generated policy

Every candidate contains a kind, exact target, evidence reason, risk, action,
and scope.

| Evidence | Generated policy | Risk |
|---|---|---|
| Existing module-backed file mapped by an app | Exact `SUS_MAP` entry | Low |
| Existing recovery artifact | Exact `SUS_PATH_LOOP` entry | Low |
| Existing root-tool, `su`, or root-runtime artifact | Exact `SUS_PATH_LOOP` entry | Medium or high |
| Narrow live KernelSU/module-backed mount | Exact `kernel_umount` target | Low |
| Hosts, APEX, partition-root, or other broad mount | Exact `kernel_umount` target | High |
| Mount ID at least 1,000,000,000 or peer/master/propagation ID at least 100,000 | `HIDE_SUS_MNTS_LATE=1` mount-view attempt | High |
| SuSFS logging enabled | `ENABLE_LOG=0` | Low |
| AVC context spoofing disabled | `ENABLE_AVC_LOG_SPOOFING=1` | Low |
| Kernel umount or automatic mount discovery disabled | Enable the supported control | Low |
| Supported KernelSU `selinux_hide` control disabled | `SELINUX_HIDE_MODE=enabled` | Medium |

The peer-group threshold includes the previously observed `199949` value.
Because late blanket mount filtering can create different views between normal
and isolated processes, it is a high-risk attempt and is never enabled by the
safe boot pass.

Selecting an actually broad mount target is the only generated action that
also enables `ALLOW_BROAD_KERNEL_UMOUNT=1`. An unrelated warning does not
release broad targets already quarantined in `kernel_umount.txt`.

## Risk and WebUI flow

Open **More → Diagnostics → Sus'AF Autopilot**.

- **Audit everything** refreshes the full-device policy.
- **Focused app audit** scans one currently running package.
- Every generated candidate is preselected so the user can see the complete
  proposed policy without knowing which rule type to choose.
- Low-risk-only selections apply immediately.
- Any medium/high-risk selection opens **Review risky corrections**, lists the
  exact affected targets, and requires **Apply anyway**.
- Individual candidates can be unchecked before applying.

Manual files and Advanced controls remain available. Autopilot generates a
starting policy; it does not remove the user's ability to edit it.

## Apply, verification, and rollback

Before applying selected candidates, Sus'AF checkpoints:

- `config.txt`
- `kernel_umount.txt`
- `sus_maps.txt`
- `sus_paths_loop.txt`

It validates every selected ID against the private scan report, rejects unknown
kinds/actions or out-of-scope paths, writes through private temporary files,
atomically replaces the live policy, and attempts the supported runtime apply.
The provenance log records the candidate IDs, counts, checkpoint, and runtime
result without storing detector output in a public location.

**Verify** rescans the policy, reports missing configured paths, mount
registration failures, and remaining candidates. This verifies Sus'AF's own
policy health; it is not a substitute for a third-party detector.

**Undo last changes** restores the most recent checkpoint and reapplies the
restored policy. Reboot is required to fully remove rules already registered in
the running kernel and to give applications a fresh namespace.

Equivalent root-shell commands are:

```sh
SusAF --coverage-scan
SusAF --coverage-scan com.example.detector
SusAF --coverage-apply 1,3
SusAF --coverage-apply-safe
SusAF --coverage-verify
SusAF --coverage-rollback
```

## Deliberate boundaries

Autopilot does not:

- enable or require KPM;
- edit uname configuration;
- change Developer Options or ADB while `ADB_MODE=unchanged`;
- indiscriminately hide every module library or filesystem path;
- wipe KernelSU's global umount list;
- silently enable broad mount filtering or broad partition unmounts;
- claim to fix TEE, certificate, package, property, or anonymous-memory
  evidence without an installed supported hook; or
- promise that every third-party detector will report a stock device.

Read [Reference device validation](DEVICE_VALIDATION.md) for the measured
2026-09-20 result and its remaining coverage limitations.
