# Sus'AF upstream review — 2026-10-28

Scope: review architecture and recent changes before more audit-engine development. No upstream module should be installed alongside Sus'AF during comparison. Do not merge vendor scripts or switch kernel binaries automatically.

## Repositories and versions checked

- Our project: `fgjaee/SusAF-`, `capability-routing`, last checked head `486bf311`; compared with `susaf-dev`: 65 commits ahead, 1 behind, with only `.github/workflows/keep-latest-build.yml` on the other side.
- ReSuSFS: <https://github.com/ahmed-alnassif/ReSuSFS>, released `v26.10.23`. `dev` is 3 commits ahead of that release, consisting chiefly of WebUI dependencies/localization.
- BRENE: <https://github.com/rrr333nnn333/BRENE>, released `v0.0.69`. `main` is 42 commits ahead and changes its boot scripts and WebUI; review source at `main`, not only the release summary.
- LKM: <https://github.com/inforcqb/susfs4ksu-lkm>, stable release `v2.3.0-r18.4` (2026-10-20); GitHub reports subsequent mainline commits. Validate KMI/ABI before considering any LKM upgrade.
- Universal helper: <https://github.com/sidex15/susfs4ksu-binaries>, Sus'AF currently pins `26958b7c3dca487c17227b62a6dd7cf11645b49a`. Comparison to `universal-binary` showed only a LICENSE addition. No automatic helper sync needed from that branch.
- Original kernel-patched SuSFS upstream: <https://gitlab.com/simonpunk/susfs4ksu>. Its default `master` is frozen at v1.3.8; track the kernel-specific branches (v2.3.0), not `master`.

## ReSuSFS findings

Source: `module/utils.sh`, `module/post-fs-data.sh`, `module/customize.sh`, `module/configs/scripts`, README.

- Supports built-in SUSFS and downloads a KMI-selected `susfs_guard_lkm` plus `susfs_insmod` for LKM devices. Loads in `post-fs-data.sh` before applying early-stage rules.
- Uses separate static versus loop path lists, configurable built-in scripts, and UserHub schedules.
- Current `load_susfs_lkm` calls `rmmod susfs_guard_lkm` before attempting a new `ksud insmod`, then a fallback loader. **Do not copy this into Sus'AF**: existing live LKM/kernel-root state should not be unloaded by a policy manager.
- Its BusyBox wget downloader uses `--no-check-certificate`; retain Sus'AF's digest-pinned updater and do not replace it.
- Its curated scripts are policy presets, not an independent per-app exposure verification engine.

## BRENE findings

Source: `module/boot-completed.sh` lines ~299–342, `module/utils.sh`, `module/post-fs-data.sh`.

- When enabled, BRENE iterates `/data/local/tmp/*` and submits each path to `add_sus_path_loop`. This explains how it would consider temporary-root binaries/sockets that Sus'AF's smaller curated list missed.
- It also has targeted lists for recovery/storage paths, custom ROM markers, fonts/Zygisk-related mapped files, and a property-spoofing UI.
- This is **broad rule application**, not a reliable proof that a finding is detectable by an unprivileged app. Glob enumeration may include benign debugging files and essential runtime files.
- BRENE assumes a working `/data/adb/ksu/bin/susfs` helper and is not a drop-in replacement for Sus'AF's `/proc/susfs_*` LKM routing.
- BRENE's code is AGPL-3.0; Sus'AF is GPL-3.0. Prefer independently written functionality with clear attribution instead of copying code into this repository.

## Sus'AF concrete gaps

Source: `module/lib/coverage.sh` and `module/lib/susfs-capabilities.sh` on `capability-routing`.

1. Curated list omits `/data/local/tmp/ksud`, `/data/local/tmp/temp_su.sock`, and `/apex/com.android.virt/bin/su`, so these are never reported by that detection path.
2. Process-map discovery is restricted to selected `/data/adb` roots, so it is not a general search for temporary-root artifacts.
3. Audit candidates are derived from accessible root-side data and known presets. The current `result=ok` means the scan completed, **not** a detector's app-side visibility is clean.
4. Applying a candidate is restricted to curated paths and capability-specific actions; unknown paths are not automatically remediated.
5. LKM procfs `add /path` and patched-kernel `add_sus_path_loop /path` have different semantics. Do not label static path registration as loop registration, or claim app-side verification when only kernel-side rules were listed.
6. Boot-stage timing remains a concern if another component loads LKM after Sus'AF's post-fs-data script.

## First implementation milestone: audit reliability (no broad auto-hide)

- Add **read-only** discovery of exact files/sockets under narrowly scoped temporary-root locations, bounded and configurable; label path evidence with existence, type, observer, and timestamp. Include the three known GhostLock paths in test fixtures without assuming they always exist.
- Report per finding: `detected`, `backend_supported`, `configured`, `operation_result`, `app_visibility`, and `verification_method` with unknown/not-run values rather than claiming verified clean.
- Keep detection **separate** from applying policy. New/uncertain or live-root paths require review and a rollback plan; do not automatically hide everything in `/data/local/tmp`.
- Preserve the active LKM; use an adapter only when its documented command/control interface is proven active, and distinguish static/loop implementations.
- Tests: fixture paths including socket and symlink, bounded traversal, missing entries, missing helper with live LKM, different backends, and report schema; ensure existing Sus'AF tests and WebUI build pass.
- On device, verify both root and a fresh unprivileged app process independently; avoid declaring Play Integrity outcomes from a filesystem audit.

## Update policy

- **Do now:** audit-engine improvements, read-only evidence collection, accurate statuses; fix any verified boot-order issue.
- **Review selectively:** ReSuSFS boot orchestration and backup UX; BRENE's path categories and property checks; upstream LKM control protocol; changed upstream helper capabilities.
- **Do not wholesale sync:** competing module boot scripts, `rmmod`/double-load logic, aggressive wildcard hiding, unverified binary downloaders, or kernel patch branches onto both phones.
- Keep `capability-routing` separate and do not merge draft PR #1 until device testing.
