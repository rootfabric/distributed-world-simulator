# ENGINE48 R4 candidate cutover and rollback — 2026-10-24

**Status: RELEASE CANDIDATE ONLY, not yet merged in canonical main.**
Canonical main remains on the 4.7.1 baseline until final machine evidence and review.

## Exact provenance / release manifest

- Godot upstream: `4d10419cacd6d3009976e8f9fd3abd970fd58018` (4.8 beta1).
- Official source archive SHA256: `6d49c02e438935e49a12231d857b2b56131948b004d5b668bf295c9bc3b2281c`.
- Version: `4.8.beta1.double.custom_build.4d10419ca`, `precision=double`, `arch=x86_64`.
- Product feature marker: `project.godot`, `config/features=PackedStringArray("4.8", "Double Precision", "GL Compatibility")`. Do not migrate to Vulkan/Forward+ in the same change.
- Windows editor console exact SHA256: `f53f90f686a4eb05df076692c1b67a9e3d12d7c6c981cf86f1015d1ec36a2636`.
- Windows template_debug **console** SHA256: `fbb4dd72744cd0f03d2cea5379575ef6ebc094fd4466c9bcd031cce6f87d6997`.
- Windows template_release **console** SHA256: `bbcf50d7c4e5762188de7c56f559a67fb218b493523222aa4fecda43df3edcf3`.
- Linux editor exact SHA256 (outenemy build): `4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f`.
- Linux template_debug SHA256: `af1e29d1c53688786e0551c54b1d1105300955302180b02a7fdf5711d46ff897`.
- Linux template_release SHA256: `fffb8f53f85bda1757572638d88386e80f90a7e0abf1be61638544197f4506e7`.
- Older Linux work order SHA `25047b82...` is **not** the published outenemy binary; do not use it for the new canonical pin.

All files must be hashed **on the actual target machine** before runtime deployment. Native binaries built from the same source commit on a different machine are **not expected to have identical SHA256**; a different build needs separate exact identity acceptance.

## Cutover

1. Before any main merge confirm the latest exact main ref is an ancestor of final migration candidate; rerun Project Control. [R4 control PASS](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40063180492) proves only that snapshot, not future refs.
2. Require Windows latest-head exact GUI / 2 clients / persisted restart, Linux latest-head exact, ECO A10–A14 version-correct CI (and 4.8 normal portable smoke), independent Reviewer+Verifier and release approval.
3. After authorized merge, keep original Godot 4.7.1 editor/templates intact; store 4.8 editor/templates **in separate versioned directories**. Do not overwrite `C:\Godot\godot\bin` or `~/.local/opt/godot-double-4.7.1-a13da4f`.
4. Switch production launch scripts/workflows via a *pinned versioned path*, not an ambient executable called `godot`. Use `tools/engine48/select_exact_double_engine.ps1` or `.sh` for strict 4.8 vs 4.7.1 selection. Preserve separately the portable single-precision *smoke* tool, which is not a double editor/test.
5. In a fresh native clean checkout of the merged code, perform a cold import using 4.8, then start a dedicated server and two real clients. Validate authority convergence, inventory, digging, construction, reconnect/restart and persisted state. Capture machine SHA, version, full HEAD/TREE and logs.

## Rollback (if post-merge Godot 4.8 causes an actual regression)

- Stop only processes owned by the candidate test or deployment, preserve persistence records and evidence.
- Do **not** simply point 4.7.1 at a 4.8-imported `.godot` cache or the new tracked `*.import` metadata. That mutates tracked files and defeats exact evidence.
- Restore a **separate clean 4.7.1-compatible source checkout** at an accepted pre-migration Git commit, e.g. canonical pre-cutover main `aac301b9a9a89e027f6d99864437eb750a4202ca`, with its own `.godot` cache and isolated user-data roots. Re-verify its SHA-pinned 4.7.1 binaries.
- Verify persistence schema before any rollback replay; back up changed durable state, never assume 4.8 and 4.7.1 data formats are mutually writable.
- Do not rewrite main history. If a source rollback is needed, use a fresh reviewed forward-revert PR that preserves accepted main history; do not force-push.

## Evidence / release gates

- Windows 4.8 Core Exact R3 [SUCCESS 40039283756](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40039283756) on `e0c0dce...`, not final R4 head.
- Ubuntu R3 self-hosted [run 40054601194](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40054601194) still pending; an independently compiled native Ubuntu source-build fallback is [R4 hosted run 40064108185](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40064108185). Only exact run outcomes count.
- Project Control MAIN_DRIFT repaired via authentic main-ancestor merge [PR #843](https://github.com/rootfabric/distributed-world-simulator/pull/843); [PC0 run 40063180492](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40063180492) SUCCESS.
- ECO pinned 4.8/native 4.8 portable changes [PR #846](https://github.com/rootfabric/distributed-world-simulator/pull/846) await fresh machine exact and independent review.
- Windows 4.8 paired perf reported **RAM +18%**; baseline absolute footprint, GPU VRAM, and reproducibility must be documented. `NET-SMOOTH1` p99 25 ms is a separate network optimization goal.
- Linux M7 exit-0/failure finding and timeout [Issue #804](https://github.com/rootfabric/distributed-world-simulator/issues/804) tracked separately; no false pass, no blanket retries.

**Current release verdict: `PC0_R4_PASS / ECO_R4_PENDING / UBUNTU_EXACT_PENDING / MAIN_CUTOVER_NOT_EXECUTED`.**
