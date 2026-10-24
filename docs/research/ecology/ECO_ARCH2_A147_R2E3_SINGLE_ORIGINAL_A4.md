# ECO ARCH2 A14.7 R2 Stage E3 — ONE original global A4

Status: Draft experimental / default OFF / no merge. Direct frozen parent Stage E2 PR #849 at b718b6150e0e4a2e28045cf2d96f15086a466a81, TREE 765c08fa36f2249ac6415662eca796d6efd908f2. Accepted main aac301b9a9a89e027f6d99864437eb750a4202ca unchanged.

## Motivation

R1 native RTX4060 GUI p99 ~6.3–7.3ms, but CPU ecology tick for n256 ~17.6 sec and backlog grows. E2 owned-worker source saved ~33% worker wall on one Portable headless pair; n256 E2 still ~22.1sec in that run. The existing R3 staged A4 computes a full speculative R2 NORMALIZE/BUILD_CLAIMS/PRIMARY/RESIDUAL state and subsequently reruns ORIGINAL Field.allocate_demands as an exact reference. This experimental E3 executes that SAME ORIGINAL globally coupled allocator ONCE rather than replaying the original and the speculative proof.

## Safety constraints and implementation

1. New opt-in trailing boolean r2e3_original_a4=false on real LAB Controller / host-private StagedSession / OffMain. Only available with E2 deep-owned CPU source, genuine R3.2.2 exclusive LAB Controller lease and R3 OffMain. All default production, GUI and WORLD_COMPAT code keeps E3 false. No parallel or per-tile resource authority.
2. Deep-owned worker source (created by OffMain inside WorkerThreadPool) grants one phase-specific CPU-only context at the already fully joined A5 ALLOCATE frontier; checks exact R3 schema, source_field/population Dictionary/Array identity, the already fully validated A5 source fingerprint, owner generation and an EMPTY nested R2 A4 scratch cursor. Main-thread, untrusted, wrong phase, stale source, fake object and mid-task policy changes are rejected before any A4 operation.
3. A5.staged_resume validates complete original incoming sealed cursor checksum, field+population digest, current owner/epoch/revision, phase and quota BEFORE this branch. At this one barrier E3 calls EXISTING _allocate_population_demands, which runs the ORIGINAL Field.allocate_demands as a single global validated authoritative operation; this returns original field, grants and intake for unchanged ADVANCE. No new allocator, no change to rounding, grant precedence, ledger, reserve, RNG, biology or A8.
4. Runtime resumes with full original checks for null owned context. On E3 owner context it still checks signed outer cursor and full A5 digest; only original E2's trusted-worker repeated FULL Runtime.validate shortcut is used. Final CPU worker again FULLY validates source and final candidate and signs the receipt, Controller rechecks original LAB lease and only then adopts ONE complete canonical tick. Public direct/untrusted/off-main E3 request fails closed. No partial grants/state delivered from CPU worker.
5. CPU worker requires exactly one E3 single-original-A4 barrier; 0 or 2 is fatal before candidate validation/adoption. Default older R2 staged speculative path reports zero E3 barriers. All transient profiling fields are not in canonical cursor/checkpoint.

## Acceptance

- Product test: real LAB Controller on n4/32/96/256 with identical historical frozen population and options, E2 original speculative+reference versus E3 one original A4. BOTH must byte-match accepted Runtime.step_spatial_parallel_advance global state, frozen canonical first-tick hash and entire serialized A8 checkpoint. One global A4, no incomplete state, exact CPU task/lease, complete source+candidate FULL final validation, no source mutation. OffMain E3 without E2 lease and public Runtime E3 without owner must reject BEFORE spawning/stepping.
- Native Godot 4.7.1 Double Windows SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5 and official Portable perform all n4/32/96/256 in fresh processes, retaining raw logs/profiles. Product run comparison MUST include original E2 baseline on identical run, not just a new faster absolute number.
- Fresh independent verifier must test malicious public owner impostors, wrong source/cursor, invalid unfinished A4 frontier, late cancellation/restart/restore with no invalid grants and full original A13 state exactness. Independent native Windows verification and inherited A13/A14.5/A14.6 regressions required. Treat arbitrary script execution within the trusted worker as outside the owner threat model, not cryptographic authentication.
- Pinned Windows paired ABBA repeated n256 CPU timing, RSS and real LAB GPU p99/backlog are separate performance gates. Do not claim less than one second per tick without real native repeated receipts. Subsecond target remains open.

READY_FOR_MERGE=false, NO_PRODUCTION_DEFAULT=true.
