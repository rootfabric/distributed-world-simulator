# MVP3 — Seamless authority A → B → A

## Durable continuation anchor

Parent: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`, state `IN_PROGRESS`.
Role: IMPLEMENTER; independent_context=false. No Reviewer/Verifier verdict is issued here.
Active runtime branch: `feature/v0-mvp-playable-seamless-planet-r1` (PR #597).
MVP2 frozen runtime: `287df80c69840fea7ae9ac0ea69a07581f192d34`, tree `e591dc6c5346139bc1b4659915c54bf80603713e`.
Continuation base: `0b297f6afe2ca6e97efaddb0e6cd4278108d8936`, tree `05b95d79cdc70de0b6ab1cba69f4ae4606171f2e`.
The latter is a verified descendant of the frozen runtime, adding control/evidence only. Historical event 0008 is retained byte-for-byte. PR #613 and the MVP2 freeze ref must not be modified or merged to main.

## Findings that constrain implementation

The accepted SM1 process workers expose a real two-authority freeze → warm-load → retire → activate handoff and a stable gateway connection. They are not an implementation of MVP2's two independently controlled M3 players: client `a` controls a single SM1 carrying domain; client `b` is an observer. The old smoke also sends ±11 m moves. The historical manual client at `b0445e08c56e090279ab21a210169df01ff3bd73` is not present in this runtime base. Merely replaying either smoke cannot close integrated MVP3.

## Bounded implementation slices

1. Add a reusable, fail-closed continuity observer under `scripts/runtime/networked_gameplay/mvp/`. It validates immutable session/player/entity/spawn/gateway identity, monotonic epoch/revision, route changes and checksums before presentation changes. It is not an authority owner.
2. Add an interactive graphical seam adapter and process launcher reusing the existing SM1 workers without modifying them. Manual and automated validation must use the same bounded input path; rendered player/camera instances survive handoff. A→B→A requires movement on B and movement after returning to A, not only a final route label.
3. Add exact-process evidence with two graphical clients, per-process identity, actual connection/disconnection observations, route/revision/state agreement, screenshots, and falsification tests. Preserve the MVP2 runtime and its tests.
4. Assess the remaining M3 two-player composition boundary explicitly. A successful single-domain operator/observer subgate is **not** integrated MVP3 acceptance and cannot emit `PREDICATE_VERIFIED`. Closing the parent leaf additionally requires both independently controlled MVP2 players to retain identity, presentation and control in the one shared scene across the real authority transition.

## Ownership and safety

No changes to SM1/P7/M4/network kernels, architecture ownership, project.godot, acceptance registry, or main. No new canonical player/Matter/Item authority. No sidecar claiming a handoff while M3 remains the real player owner. No importing unrelated runtime branches. One runtime implementation worker only. GitHub connector is the authoritative read/write route; do not clone through an unavailable container network. CI is execution/evidence only, never a Git transport or independent human verdict.

## Acceptance gates

Focused contract tests, negative controls (stale epoch/revision, identity/spawn change, route/epoch mismatch, corrupt checksum, disconnect, synthetic connection counts, missing post-seam movement), actual process gate, MVP1/MVP2 nonregression, exact Harness/standard PC0/directional PC0. Fresh independent Reviewer and Verifier must examine exact HEAD/TREE and the two-player integration boundary. Full world/core and human acceptance remain parent obligations.

## State

MVP1=VERIFIED; MVP2=VERIFIED; MVP3=IMPLEMENTATION_IN_PROGRESS.
whole_mvp_acceptance=false; predicate_verified=false; runtime_merge=false; main_merge=false.
Next action: implement the bounded continuity observer and executable adapter, publish exact test evidence, and report any remaining integrated-scene gap without upgrading a subgate to whole MVP3 acceptance.
