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
