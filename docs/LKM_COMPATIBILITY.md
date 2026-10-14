# YukiSU/BakaSU LKM compatibility (staged, safe-first)

This development branch adapts Sus'AF's existing userspace policy runner to
**already-running** built-in or separately loaded SUSFS. It does **not**
install a SUSFS kernel module, build a kernel, write `boot` or `init_boot`,
insmod an LKM, or perform an automatic reboot.

## Why the distinction matters

YukiSU and BakaSU are root/manager implementations. SUSFS is a separate kernel
capability. A root manager or a file called `ksu_susfs` does not prove the
matching kernel interface is active. A loaded LKM is kernel-build/KMI dependent.
The 2026-10-14 OnePlus 12R used an Android 13 / 5.15 family kernel with Android
15 userspace; select kernel modules by the **kernel release**, not the Android
OS version. Do not reuse the Android 17 Pixel kernel's broad mount rules.

Sus'AF's new `--compat-check` validates, without changing kernel state:

1. arm64 architecture and current kernel release;
2. the selected existing `ksu_susfs` tool is an executable regular file;
3. `show version` responds with at least SUSFS v2.2.0 (including suffixes such
   as `v2.3.0-r18.1`);
4. `show variant` responds; and
5. `show enabled_features` succeeds.

An exact `susfs`-family entry in `/proc/modules` is reported as
`backend=loaded-lkm`; otherwise `backend=not-listed`. The latter does **not**
rule out built-in support, and a listed module does **not** override a failed
kernel query. Feature-specific checks still need to pass before any individual
rule is applied.

## Installation and operation

**Do not flash this development branch onto the OnePlus yet.** First use a
read-only device-side audit to confirm the running kernel, manager, tool and
features; test with a matching unmodified LKM separately and with a recovery
path. This branch is for repository development and regression testing.

The installer now **preserves the existing manager-owned**
`/data/adb/ksu/bin/ksu_susfs` instead of automatically overwriting it.
The bundled userspace tool remains a fallback. `--force-update` is a separate
explicit action that *does* replace the global tool; avoid it on an LKM
installation unless compatibility has been proven and rollback planned.

Automatic `--stage-early`, `--stage-late`, `--action`,
`--run-postfs-scripts`, `--run-bootcompleted-scripts`,
`--autopilot-boot`, `--coverage-apply`, and `--coverage-apply-safe`
are blocked when the preflight fails. Read-only `--coverage-scan`,
`--status-report`, and `--compat-check` remain available.

## Root detections and scope

Existing Sus'AF Autopilot inventories cross-process module-backed mounts. The
OnePlus scan found:

- Vector ART `dex2oat32` and `dex2oat64` bind mounts; and
- Re-Malwack's `/system/etc/hosts` bind mount.

These are **high-risk** targets under the current policy because they affect
ART/APEX or system hosts and can create differences between app namespaces.
The default `ALLOW_BROAD_KERNEL_UMOUNT=0` and
`HIDE_SUS_MNTS_LATE=0` must remain in place until live LKM features are
verified and an app-versus-isolated-process comparison has been completed.

SUSFS cannot be assumed to remove timing-based syscall detections, to hide
every `u:r:su:s0` process, or to make third-party safety checks universally
clean. Never disable root management, TEE Sim, or kernel verification solely
to improve a detector score.

## Validation required before release

- tests/test-lkm-compat.sh and existing regression tests;
- read-only OnePlus kernel and LKM inventory;
- recovery snapshot independent of the phone;
- verify a supported feature individually before *any* apply;
- inspect mounts across normal and isolated app namespaces before and after;
- preserve the existing YukiSU/BakaSU, Vector, Re-Malwack, and TEE Sim setup;
- no automatic reboot or unsafe broad mount-hiding.

## No SUSFS on the October 14 OnePlus (verified)

The device's read-only STEP 78 output showed:

- kernel `5.15.167-android13-8-o-01140-g043e86cdd499`, arm64;
- YukiSU/BakaSU `ksud 1.7.0-5f85169d` (UAPI 5);
- `feature check kernel_umount` -> `supported`;
- `feature check selinux_hide` -> `supported`;
- **no** detected SUSFS module, `/sys/module` entry or installed
  `ksu_susfs` tool.

Sus'AF must report **SUSFS unavailable** on this device: KernelSU LKM
root support is not the SUSFS LKM. The GitHub-hosted SUSFS LKM loader at
`matsuzaka-yuki/susfs-lkm-module` distributes an android13-5.15 KMI
build, but its README explicitly states its other KMIs besides
android15-6.6 have *not* been validated on-device; this is not proof
of safety on the OnePlus vendor kernel. Do not load it as part of
these changes.

### Read-only KernelSU-only mode

`SusAF --ksu-only-audit` uses the existing trusted `ksud` resolver
and calls only `feature check` and `feature get` for
`kernel_umount` and `selinux_hide`. It reports mountpoints from
`/proc/1/mountinfo`, including the known Vector ART and Re-Malwack
hosts targets. The audit never calls `feature set`,
`kernel umount add`, `notify-module-mounted`, `insmod`, `umount`, or
`resetprop`.

KernelSU's supported features are **not automatically enabled**,
and kernel-only audit does not claim that the separate SUSFS hiding
operations work. Do not automatically generate or apply broad APEX
or hosts unmount rules based only on a manager feature check.

### LKM guard `/proc` interface (read-only discovery)

The current upstream `inforcqb/susfs4ksu-lkm` uses
`/proc/susfs_hide_mounts`, `/proc/susfs_hide_modules`,
`/proc/susfs_path`, `/proc/susfs_kstat`,
`/proc/susfs_open_redirect`, `/proc/susfs_avc_spoof`, and
`/proc/susfs_enable_log` when loaded with `expose_proc=1`.
Source: `PROC_INTERFACES.en.md` in the upstream repository.

`SusAF --lkm-proc-check` inventories **only the presence and
readability** of those seven nodes. It never prints stored rules
(which might expose personal paths) or issues an LKM control write.
Absent or partially available nodes cannot be used to authorize
automatic SUSFS policy application; backend feature ABI and compatibility
must first be independently validated on-device. The separate
`ksu_susfs show` tool is still required for the old policy runner.
An alternative proc-write adapter is **not** yet implemented.


### Verified correction: active root is YukiSU (not BakaSU)

STEP 79 was run on YukiSU, with `ksud version 1.7.0-5f85169d`:

- `ksud feature get kernel_umount` returned `Status: enabled`;
- `ksud feature get selinux_hide` returned `Status: enabled`;
- `ksud boot-info current-kmi` returned `android13-5.15`;
- `ksud susfs support/version/features` returned `unknown command 'susfs'`;
- `ksud kernel umount list` returned code **2**, with stderr not captured.

The unavailable list is **not evidence that the registry is empty**. The
code now fails closed instead of silently using an empty list and
re-registering unknown targets. Next, inspect `ksud --help`,
`ksud kernel umount --help`, and `ksud umount --help` on this exact
YukiSU build; choose a safe supported list query before implementing a
YukiSU-specific registry adapter.

Enabled KernelSU features still do not prove SUSFS operations exist.
