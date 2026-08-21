# NX -> V0-P4 directional dependency revalidation R1

## Purpose

This is a narrow control dependency revalidation for the current main-owned NX routing repair.

It answers only this question:

> Does the exact implemented H0.2/NX.C1 source delta invalidate V0-P4's canonical `SERVER_PREDICTED` baseline or mutate a gameplay/domain foundation owned outside NX?

It is **not** an H0.2 post-build runtime acceptance, **not** `H0_2_PASS`, **not** `NX SOURCE_ACCEPTED`, **not** a runtime-tested-head claim, and **not** authorization to merge NX runtime or V0-P4.

The reviewer performing this dependency inspection did not implement the NX.C1 runtime or the V0-P4 runtime. The same agent is implementing the surrounding main-owned routing repair, so this document also does **not** satisfy the separate fresh independent review required for that control PR.

## Exact producer

Program: `NX`

Branch: `feature/h0-2-nx-c1-owner-authority-r3`

Exact source implementation head reviewed for dependency semantics:

`1814ca72c9569ea2aa7e3d1dd4a69eb790888908`

Current lifecycle head:

`d1a4466775a6e08192179dfc9af397eafbf574c0`

Project Control on exact source implementation head:

`31690226579 — SUCCESS`

That workflow is bound to exact `1814ca72c9569ea2aa7e3d1dd4a69eb790888908` and passed architecture/ownership compatibility, H0.2 machine checkpoint regression, standard PC0 and directional PC0.

The diff from exact implementation head `1814ca72...` to current lifecycle head `d1a44667...` contains only H0.2 control/passport/work-order/plan changes. None of the runtime files fenced below changed after the exact implementation head.

## Exact consumer identity used only by Directional Watch

Program: `V0`

Branch: `feature/v0-p4-construction-real-resources`

Current branch head used by the Directional Watch identity fence:

`da1c8825429af53095240943de663ada9a6549fc`

Consumer passport:

`config/control/branches/feature__v0-p4-construction-real-resources.v1.json`

Consumer passport blob:

`c1f1f2367bedb53ff73b373c93937996f34f4a41`

**This does not canonize `da1c8825...` as P4 implementation or closure truth.** That branch head is the quarantined malformed closure-ledger carrier and remains forbidden for review/merge as P4 closure truth. The exact independently reviewed P4 implementation/evidence target remains:

`2a6721cdf02fa1134c59d1ab98bb7b597c66821d`

The valid closure control path remains the recovery/repair carrier. Here `da1c8825...` is recorded only because the current Directional Watch algorithm fail-closes a clearance to the exact registered consumer branch head/passport identity.

## Observed NX -> V0-P4 hit set

V0-P4 intentionally watches network/runtime dependencies. The current NX.C1 producer therefore creates one critical and two ordinary watched hits:

Critical:

- `scripts/network/authority/movement_authority_profile.gd`

Ordinary watched:

- `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd`
- `scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd`

No protocol manifest, M4 canonical Item Graph service, Construction authority, persistence owner, Item ownership, or cross-server authority file is changed by the exact NX.C1 source implementation.

## Exact reviewed blob fence

At `1814ca72c9569ea2aa7e3d1dd4a69eb790888908`:

- `scripts/network/authority/movement_authority_profile.gd` -> `5b3804f9d90fcd91cfad4e6202ed3e710f0f2257`
- `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd` -> `8377db769e1c18b35d1919cbfb41d5cf32e986b9`
- `scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd` -> `0c5b1c51e70ccb10b6076f5921582d83d0d82c8e`

The current NX lifecycle head retains those exact runtime blobs because all commits after `1814ca72...` are control/docs/passport lifecycle changes only.

## Semantic inspection

`movement_authority_profile.gd` defines both:

- `SERVER_PREDICTED`
- `OWNER_AUTHORITATIVE_VALIDATED`

and explicitly limits the choice to realtime locomotion authorship. Its contract keeps entity ownership, spawn/despawn, items, economy, persistence and durable gameplay mutation server/domain authoritative in both modes.

`networked_gameplay_service_owner_movement.gd` is a leaf extending the existing canonical gameplay service. It accepts an owner-authored pose only after existing ownership/session/epoch/input-sequence checks and the existing movement validator accepts speed/displacement state. It does not move Item Graph, Construction, persistence or economy authority into NX.

The current NX passport likewise constrains its ownership claim to `NETWORK_REPLICATION_POLICY` for realtime locomotion/snapshot/presentation behavior and explicitly forbids ownership of Item Graph, Construction, Matter, persistence, authority foundation, world transaction, spatial/material/work-budget/query foundations.

## Decision

`DEPENDENCY_REVALIDATED_NO_FOUNDATION_MUTATION`

For the exact fenced source implementation, the NX -> V0-P4 critical watch represents an opt-in locomotion-authority extension inside the already-declared NX realtime replication policy. It does not mutate the V0-P4 canonical Item/Construction/economy/persistence truth and does not force V0-P4 off its canonical `SERVER_PREDICTED` baseline.

The dependency finding must remain visible. An accepted main-owned clearance may downgrade only this exact fenced hit from raw critical RED to ordinary watched YELLOW while all producer ancestry, consumer identity, complete hit-set and blob fences remain exact. Any drift must fail closed back to RED.

## Evidence identities

Dependency review id:

`NX-V0-P4-DIRECTIONAL-REVALIDATION-001`

Machine verification id:

`PROJECT_CONTROL_RUN_31690226579`

These identities support only this dependency clearance. They do not satisfy NX post-build Reviewer/Verifier gates and do not satisfy the fresh independent review required before merging the routing repair.
