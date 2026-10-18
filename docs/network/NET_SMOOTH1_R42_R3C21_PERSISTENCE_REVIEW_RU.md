# NET-SMOOTH1 R4.2 R3C21-R2 — Fresh persistence projection review exact matrix

## Scope and ancestry
- Frozen implementation PR #779 HEAD: `1205996dbf3e17295b88e7c4142bb209d1ca7320`.
- Review branch: `review/net-smooth1-r42-r3c21-persistence-exact-r1`, stacked **on** that exact HEAD; no production script changes.
- PR #779 retargeted to implementation predecessor PR #778 (`f034794ebe71d887ed020cfa4aac879e514a2280`) so its diff contains only the three persistence-repair source files.
- Canonical main as of review: `f369858c9bf7d6247785898537d7c8841b08b7bd`; fetch freshly before any later decision.

## What this independent CI adds
1. Trigger Windows, Linux and Python source exact on the review branch with full ancestry fences.
2. Make `tests/runtime/test_net_smooth1_r42_r3c21_same_revision_tick_mirror.gd` **mandatory on both Windows and Linux pinned Godot 4.7.1 double**.
3. Add Python source checks against accidental projection removal of canonical ownership player rows or ownership.revision; retain exact fail-closed progression error.
4. Retain all existing R2/R1/CHAR/M6 tests, SHA identity and no-waiver timeouts.

**Status boundaries:** The real two-client GUI frame measurements and five slow-ITEM canaries were performed on `1205996dbf3e17295b88e7c4142bb209d1ca7320` and reported by the Windows operator in PR #778; do not represent them as an independently reproduced GUI measurement from this CI-only child. Source contracts and headless native checks do not prove GUI continuity.

## Reviewer evidence and required follow-ups
- Parent #777 native CI RED was test parser type inference, child #778 Windows/Linux exact PASS ([run 39076121531](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39076121531)).
- Parent #779 server M6 projection repair is a separately scoped code change. Its own native regression was omitted from the triggered workflow, so green #778 cannot be inherited as direct #779 validation.
- Project Control GitHub check for #779 is still RED due candidate registry snapshot `CANDIDATE_MAIN_DRIFT`; on-host fresh fetch confirms live main SHA but **does not itself mean the CI control check passed**. Resolve/record this under canonical control owner, not by disabling gates.
- Baseline/client repair frame thresholds: A p99 23.2ms / p999 31.2ms / max 72.2ms, B 23.2/30.8/73.7ms. Server authoritative 20Hz; loop >=59Hz. All remain operator-reported evidence.
- Scripted reconnect continuity fails in baseline and candidate, and 100–220ms durable drain stalls remain. These are separate end-to-end/release blockers, not evidence this projection guard is wrong.
- Retain nested ownership checksum validation/integrity concern for independent recovery-owner review: semantic projection ignores derived checksum by design, but schema validity must still be checked on export/import; do not remove player-row/revision checks.
- Do **not** merge or perform 4h soak until fresh independent verification, release-specific continuity decision and Project Control provenance acceptance.

## Final decision
Expect `REVIEW_CI_EXACT_PENDING` immediately after publishing branch. Only exact native success may upgrade this to `NARROW_PERSISTENCE_REPAIR_VERIFIED`; full game release remains a separate gate.
