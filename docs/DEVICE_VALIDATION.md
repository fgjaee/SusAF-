# Sus'AF reference device validation

This document records the sanitized result of a real Sus'AF configuration
export and Duck Detector report supplied on 2026-09-20. The raw archive and
detector report are not committed because they contain device-specific state.

This is a reference result, not a guarantee that the same policy is safe or
effective on another device.

## Test environment

| Item | Observed value |
|---|---|
| Device | Pixel 10 Pro Fold (`rango`) |
| Android | Android 17, SDK 37 |
| Kernel | `6.6.143-g7a74b80d` |
| Duck Detector | `2026.09.07-d3c2d5d3dd7d` (527) |
| Report time | 2026-09-20 06:31 EDT |
| Sus'AF data format | Backup schema 1, module ID `susaf` |

## Detector result

Duck Detector reported:

| Level | Count |
|---|---:|
| Danger | 0 |
| Warning | 1 |
| Ready/Clear | 15 |
| Pending | 0 |

The following cards were clear:

- Bootloader: locked and attested verified.
- Dangerous Apps: no known risky package visible across the detector's full
  package inventory.
- Kernel Check: no suspicious kernel marker; uname sources agreed.
- Memory: no hook-like memory signal.
- Mount: no suspicious mount-layer signal.
- Play Integrity Fix: no common residue surfaced.
- SU: no root indicator surfaced.
- TEE: local StrongBox/TEE attestation checks aligned.
- Zygisk: no runtime signal surfaced.

The single warning was the System Properties observation
`persist.sys.usb.config=adb`. The exported Sus'AF policy explicitly used
`ADB_MODE=unchanged`, so Sus'AF preserved the user's working USB-debugging
state rather than claiming it was disabled.

Custom ROM, LSPosed, Native Root, SELinux, and Virtualization were INFO results
with reduced, unavailable, or timed-out evidence paths. They were not positive
detections. Examples included an unavailable raw property-area scan, a timed
out app-zygote SELinux carrier, a seccomp-blocked sacrificial supercall helper,
and a timed-out isolated-process comparison.

## Mount and peer-group result

The Mount card reported:

- no suspicious mount, overlay, namespace, propagation, or root-managed
  filesystem artifact;
- 34 mount entries, 31 mountinfo entries, and 34 map lines examined;
- readable mounts, mountinfo, maps, and working `statx` support;
- 75% path coverage, with five permission-restricted checks; and
- clean mountinfo root-field, propagation, mount-ID, and namespace-consistency
  checks.

The previously observed `199949` peer-group finding did not appear anywhere in
this report. That is consistent with the gap disappearing from Duck Detector's
application view. It does not by itself prove which individual rule caused the
change, and the detector still reported only 75% mount-path coverage.

## Exported Sus'AF policy profile

The supplied backup contained:

| Policy list | Active entries |
|---|---:|
| `kernel_umount.txt` | 5 |
| `kstat_paths.txt` | 1 |
| `sus_maps.txt` | 2 |
| `sus_paths.txt` | 13 |
| `sus_paths_loop.txt` | 30 |

Core safe controls were enabled: early non-su mount filtering, SuSFS logging
off, AVC context spoofing, targeted KernelSU umount, automatic module-mount
discovery, boot Autopilot scanning, and automatic low-risk application.

This particular device had also explicitly enabled both high-risk compatibility
controls:

```ini
HIDE_SUS_MNTS_LATE=1
ALLOW_BROAD_KERNEL_UMOUNT=1
```

Its explicit umount list included broad system/debug targets as well as the
hosts and ART targets. These settings are evidence of the tested device state,
not universal recommendations. Sus'AF continues to default both controls off,
quarantines broad targets, and requires a risk warning before Autopilot enables
them.

The exported configuration kept:

```ini
ADB_MODE=unchanged
SELINUX_HIDE_MODE=unchanged
```

It also contained an existing uname file. Autopilot neither generated nor
edited that file; uname remains an independent user-controlled feature.

## Interpretation

This result demonstrates that Sus'AF is doing more than replaying a static
ReSuSFS configuration: it maintains its own policy model, boot audit, risk
gates, KernelSU integration, checkpoints, verification, and rollback. The
clean mount result and absent `199949` finding are meaningful device-test
evidence.

It is not accurate to describe the device as mathematically “100% stock”:

- Duck still recorded one ADB-related property warning.
- Several support probes had reduced coverage.
- Permission restrictions limited the Mount card to 75% path coverage.
- A detector result is a snapshot of one application process and one software
  version.

The proper release claim is: **zero Danger findings, the mount/peer-group gap
absent from this run, and only the deliberately preserved ADB property left as
a Warning.**
