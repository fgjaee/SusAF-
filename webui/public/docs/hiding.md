# Hiding behavior

Sus'AF uses targeted rules instead of broad filesystem scans.

- KernelSU `kernel_umount` receives validated live KSU/module-backed mountpoints
  and explicit mounted targets. Existing global entries are preserved. Broad
  roots such as `/system_ext` are retained in configuration but quarantined by
  default because per-process unmounting can expose two mount views.
- SUS_PATH and SUS_PATH_LOOP apply only configured paths. PTY nodes are never
  enumerated automatically.
- SUS_MAP applies only entries in `sus_maps.txt`; it does not add every module
  library or every `.so` file.
- Kstat is intended only for paths whose stat identity genuinely changes after
  a bind mount or overlay.
- Verified-boot sanitation removes `verifiedbooterror` and `verifyerrorpart`;
  it does not rewrite build, product, lock-state, Developer Options, or ADB
  properties.

The broad `hide_sus_mnts_for_non_su_procs` guard is enabled only during early
boot by default, then disabled at boot completion. Targeted KernelSU umount and
Sus path rules remain active. Keeping the broad filter enabled after boot is a
compatibility option because it can make app and isolated-process mount tables
diverge.

Set `ALLOW_BROAD_KERNEL_UMOUNT=1` only for compatibility with a setup that
genuinely mounts an entire Android partition root. It is off by default and
requires a reboot after changing so the kernel list starts cleanly.

More rules are not automatically better. Broad or contradictory spoofing can
create inconsistencies that are easier to detect and harder to diagnose.
