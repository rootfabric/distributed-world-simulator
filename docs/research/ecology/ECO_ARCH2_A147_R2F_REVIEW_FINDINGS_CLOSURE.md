# ECO ARCH2 A14.7 R2F — final review findings closure (2026-10-26)

**FROZEN PARENT:** A14.7 R2E3 [PR #856](https://github.com/rootfabric/distributed-world-simulator/pull/856) HEAD `d2ddebcdf5f6aecec85e7d85772f30a15ff3f748`, TREE `910833e082f376ea7d0ed0b14530edddd1503ef8`. Accepted main remains `aac301b9a9a89e027f6d99864437eb750a4202ca`. R2F is an independent stacked Draft and does NOT mutate the frozen accepted E3 head, rebase or merge any parent.

## P1 Controller integration fix
- Controller `run_staged_frame` accepts opt-in `r2f_worksets_per_resume=1`, `r2f_parallel_workers=1`. These do NOT change legacy `max_worksets` / soft wall scheduling.
- Both must remain 1/1 unless real LAB Controller runs opt-in R3 OffMain + E2 owned-source + E3 original global A4. Bounded [1,64] worksets/resume, [1,8] parallel workers. Invalid bounds and unauthorised combinations fail BEFORE any worker spawn or lease allocation.
- Host-private StagedSession independently checks the same constraints. It now forwards these two validated fields instead of hardcoded 1/1 to OffMain. OffMain already freezes both per generation and rejects policy changes while in flight. E3 still accepts only one true original Field.allocate_demands owner, with signed full A5 cursor and source digest, final FULL source/candidate `Runtime.validate`, Controller lease and A8 admission, no partial field/grants.
- The Workbench GUI, direct API and WORLD_COMPAT remain default OFF. No automatic activation.

## P1 exact proof and performance
`validation/ecology/evo_arch2_a14_7/test_a147_r2f_controller_composed.gd` compares **real Controller** E3 1/1 vs E3 batch16/nested4 against unchanged ORIGINAL A13 whole Runtime and serialized A8 at n4/32/96/256. It checks E2 and E3 genuinely activated, single global A4, source/candidate checks, one joined CPU task, no partial state and actual nested CPU threads at n96/256. A paired worker wall measurement is included and reported, not presupposed to improve.
`.github/workflows/eco-a147-r2f-review-closure-exact.yml` runs official portable and exact pinned Windows AND Linux Double: hashes Windows `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`, Linux `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`, with real original F64 state and A8 comparison.

## P2 multigeneration / error-frontier proof
`test_a147_r2f_multitick_exact.gd` runs:
- n32/96/256 original A13 vs E3 batch16/nested4, **2 committed ticks each**, mutation policy enabled; compare every complete field/grants/pop/feedback/outbox state and exact serialized A8 at EACH tick, plus owner/revision transitions and no partial publication.
- Reproductive n4 fixture with A13 Fidelity life-history policy maturity tick 2, genuine genome `module_parameter` mutation enabled, **4 ticks**, assert actual population growth and parity at each tick. This detects mutation, propagule and child-admission regressions rather than only one tick with disabled mutations.
- Fully dead-inert n4 source (zero A5 demands) plus n4 zero-stock field (nonempty demands but every granted amount zero); both must match accepted single ORIGINAL global A4 behavior. No skipped A4 barrier or forged grants.
- Main-thread/public Runtime malformed/stale source/checksum and first-error precedence further checked in dedicated fresh independent verifier before merge.
- `.github/workflows/eco-a147-r2f-multitick-exact.yml` enforces this on official Portable and both pinned native Double operating systems, with 5 independent Linux native A13 Fidelity repetitions retaining gdb/exit evidence on any SIGSEGV. A single 5/5 pass reduces but does NOT mathematically rule out intermittent SIGSEGV.

## Remaining human/release gates
- Real RTX4060 GPU GUI soak with E3 integrated fast flags and Stage B/C working, plus p99, RSS, tick backlog/overflow over 10 minutes, remains a distinct acceptance condition. A14.7 target full n256 canonical tick **under 1 second is NOT YET MET**. Do not merge/activate as a production-default performance path.
- Verify original 13 Draft dependencies #798→#805→#813→#819→#821→#824→#826→#827→#835→#842→#847→#849→#856, all exact frozen heads and merge conflicts, human-gated merge in order only. #860 diagnostic only, close without merge once preserved.
- Fresh independently authored verifier for R2F required; prior E3 independent results do not automatically approve new parameters. Existing PR #856 open review threads must not be marked resolved until independent R2F code/Windows/Linux proof and review confirm.

**Current status:** IMPLEMENTATION_CANDIDATE / CI_RUNNING / DEFAULT_OFF / NO_MERGE. This doc is not a final PASS declaration.
