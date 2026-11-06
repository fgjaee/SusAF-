# Sus'AF roadmap

**Last updated:** 2026-09-26

The roadmap prioritizes proven device behavior over feature count. A feature is
not complete merely because a helper command returned success. The target is:

```text
capability detected
      -> configuration validated
      -> controller applied
      -> runtime state observed
      -> cross-surface consistency verified
```

## P0 — Convert proven tests into product behavior

### Keep Android 17 mount filtering active

- Change the shipped Android 17 validation policy so late non-superuser SuSFS
  mount filtering is not turned back off after boot.
- Update diagnostics to distinguish the configured early/late policy from the
  observed runtime backend state.
- Add regression coverage for the `zygote_next` case that exposed BindHosts
  and Zygisk Vector mounts when the late filter was disabled.
- Preserve targeted KernelSU `kernel_umount`; the two mechanisms solve
  different visibility paths and should not be treated as substitutes.

### Remove the high-ID Autopilot decision rule

- Keep mount, peer, master, and propagation IDs as diagnostics.
- Never generate `HIDE_SUS_MNTS_LATE=1` solely because an ID is numerically
  large.
- Compare actual namespace topology, mountpoint, root/source, filesystem,
  options, propagation, and provenance instead.

### Fix coverage-scan output

- `SusAF --coverage-scan` must print the same completed report it writes to
  `state/coverage.report.txt`.
- Add a regression test that rejects a successful scan with empty stdout.

### Finish product-identity separation

- Remove legacy project branding, banners, active credits, and sync language
  from Sus'AF product-facing surfaces.
- Keep legacy names only where technically required to import/migrate existing
  user data during the compatibility window.
- Remove the temporary legacy CLI alias once migration no longer needs it.
- Keep historical ancestry in Git history instead of presenting it as current
  product identity.

## P1 — Runtime verification layer

Every capability shown in the WebUI should expose three independent states:

```text
Supported    kernel/helper can provide it
Configured   Sus'AF has requested it
Verified     runtime observation matches the requested state
```

Initial verification targets:

- `SUS_PATH`
- `SUS_PATH_LOOP`
- `SUS_MOUNT` / non-superuser mount filtering
- KernelSU `kernel_umount`
- `SUS_MAP`
- uname/kernel identity
- cmdline/bootconfig sanitation

A successful helper exit code is application evidence, not runtime proof.

## P2 — Autopilot 2.0: discovery and provenance

Replace static-suspicion behavior with an evidence graph.

### Mount discovery

For each candidate mount, capture:

- namespace and process context;
- mount ID and parent ID as metadata only;
- mountpoint;
- root;
- source/device;
- filesystem;
- propagation fields;
- owning module/root source when derivable;
- whether the mount exists in init, normal app, and isolated/`zygote_next`
  views.

### Classify source separately from recommendation

Use explicit classes such as:

- `android_system`
- `apex_system`
- `module_backed`
- `module_runtime_bind`
- `known_artifact`
- `user_configured`
- `unknown`

A curated signature can help identify provenance, but existence alone must not
become a recommendation.

### Settled/late runtime mounts

Modules can create mounts after Sus'AF's first boot-complete scan. Add bounded
settling rescans:

1. initial boot-complete scan;
2. short follow-up scan;
3. register newly appeared validated module-backed mounts;
4. stop after the mount set stabilizes or the bounded retry budget expires.

Do not poll indefinitely.

## P3 — Coherent kernel identity profiles

Current SuSFS `set_uname` changes UTS release/version but can leave other
observable kernel identity surfaces unchanged. Sus'AF should offer profiles
rather than a raw two-field spoof pretending to be complete.

### Profiles

- **Default** — expose the real kernel identity.
- **Coherent** — apply one identity consistently across every supported
  observable surface.
- **Custom** — advanced user-supplied release/version/date, subject to the same
  consistency checks.

### Apply before Zygote

A coherent profile must be established early enough that the value cached by
Zygote agrees with later live reads.

### Kernel-side provider

Where the running kernel exposes only the standard SuSFS uname hook, Sus'AF
should report a partial capability. A future optional kernel extension can
provide the remaining identity surface(s), including `/proc/version`, from the
same profile rather than using a brittle bind mount or fake text file.

### Verification

Compare at minimum:

- live `uname -r`;
- live `uname -v`;
- `/proc/version`;
- readable proc/sysctl kernel identity surfaces;
- early/Zygote-visible `os.version`.

Report **Verified**, **Partial**, or **Mismatch**.

## P4 — WebUI performance and status UX

- Profile the remaining SuSFS-page opening lag instead of adding speculative
  caching.
- Avoid serial shell subprocesses for status-only data.
- Cache immutable capability discovery for the page lifetime and invalidate it
  only when the helper/kernel source changes.
- Show runtime verification next to capability support instead of burying it in
  diagnostics.
- Replace legacy banner/assets with Sus'AF-owned visual identity.

## P5 — Release hardening

Before the first stable release:

- all shell and WebUI tests green;
- new regression tests for the Android 17 late mount-filter behavior;
- coverage-scan stdout regression test;
- Autopilot no longer generates candidates from raw high IDs;
- migration tested without destroying existing user configuration;
- no conflicting policy engine enabled during reference validation;
- clean install and upgrade tested across two reboots;
- reproducible release ZIP verified;
- smoke-test documentation updated from measured behavior;
- known detector findings documented as observations, not promises that every
  detector must return green.

## Non-goals

Sus'AF should not:

- blindly copy another module's suspicious-path list;
- hide a real user artifact merely to satisfy one detector;
- claim a feature is effective because a command returned zero;
- silently rewrite build identity, ADB, or unrelated user configuration;
- make raw mount-ID magnitude a security verdict;
- promise universal detector bypass.

The differentiator is stronger orchestration and verification: discover what
the kernel can do, apply only evidence-backed policy, and prove the resulting
runtime state is coherent.
