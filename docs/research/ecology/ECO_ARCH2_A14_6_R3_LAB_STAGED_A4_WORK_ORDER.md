# ECO ARCH2 A14.6 R3 — Opt-in live LAB staged global A4

STATUS: PRODUCT CANDIDATE / NOT INDEPENDENTLY VERIFIED / NO MERGE.
BASE: main aac301b9a9a89e027f6d99864437eb750a4202ca
(R1 #788 and R2 #793 accepted).
BRANCH: feature/eco-arch2-a14-6-r3-lab-allocator-integration-r1.

## Product execution

R2 proved a detached resumable global A4 primary + residual pro-rata
allocation, but it was NOT connected to a LAB frame loop. R3 integrates
the SAME R2 primitive in the actual accepted LAB orchestration:

Workbench._process [LAB only]
  -> Controller.run_staged_frame (enforces LAB authority)
  -> host-private StagedFrameSession
  -> Runtime.begin_staged_global_tick(use_r3_allocator=true)
  -> A5 staged_begin, new nonpersistent R3 schema
  -> all PREPARE worksets join into ONE global demand frontier
  -> A4 R2 staged begin + NORMALIZE / BUILD_CLAIMS /
     PRIMARY / RESIDUAL across host frames
  -> R2 FINALIZE recomputes ORIGINAL Field.allocate_demands on
     the unchanged source and compares full field/grants/revision/hash
  -> all A5 ADVANCE worksets, propagule admission, A6 feedback
  -> ONE canonical Runtime.tick publish after COMPLETE only

The nested A4 cursor, partial grants, wall clock and scheduler debt are
noncanonical. No partial resource/biology is returned to Controller,
Checkpoint, network, Region/Matter owner, or UI. A5/A6 formulas and
the canonical field ledger/owner/revision are unchanged.

## Explicit switch / backward compatibility

The historical A14.5 legacy staged A5 path and v1 inner lifecycle cursor
remain defaults for callers without the new trailing parameters.
To opt in on an actual LAB Workbench, call:

    configure_staged_live(true, soft_budget_us, resumes_per_frame,
        worksets_per_resume, max_members, cursor_cap_bytes,
        true, allocator_items_per_call)

The last bool enables R3 (default false); item quota 1..4096. Host cursor
cap 1024..16777216 encoded bytes bounds the FULL nested A5+R2 scratch,
not process RSS. The Runtime outer v2 sealed envelope binds the nested
checksum and canonical source/options. Unknown schemas fail closed.

Controller.run_staged_frame refuses WORLD_COMPAT with the previously
accepted CONTROLLER_STAGED_WORLD_AUTHORITY_UNPROVEN rule. Existing
WORLD_COMPAT per-tick authority admission remains untouched. No
live field mutation, competing legacy run, replay or world-owner change
may race a pending staged cursor.

## Rollback and phase telemetry

PAUSE, reset, successful trusted load_state, LAB mode opt-out and host
change of in-flight allocator mode/quota discard BOTH R3 and R2 transient
cursors. Previously uncommitted tick debt remains in the UI; no
canonical Field, organism, ledger, checkpoint or RNG is changed by
a pending frame. Failed R2 stages and failed final proof return no
published grants/state and make the caller fail closed.

Host-only telemetry measures BEGIN, PREPARE/ALLOCATE/ADVANCE, and nested
R2 BEGIN/NORMALIZE/BUILD_CLAIMS/PRIMARY/RESIDUAL/FINALIZE samples.
The LAB status bar displays the subphase only if R3 is enabled.
No clocks or samples are persisted or influence biology decisions.

## Acceptance matrix

- Real shipped LAB manifest, Controller and true Workbench._process:
  R2 advances through its six subphases across frames, exactly one
  committed global tick at the end, no halfway A8 state.
- Explicit option change/cancel/pause/restore/memory refusal must
  discard the nested speculative cursor and leave trusted state
  intact; replay from original reference exact.
- For populations 4/32/96/256 measure accepted serial/parallel baseline,
  historical A14.5 staged, and R3 global R2 staging. Compare complete
  Runtime bytes/hash and full A8 Checkpoint bytes, and keep state/RNG
  unmodified on every pending frame. Four JSONL profiles.
- Re-run R2 A4 768-request pro-rata, residual, tamper and source
  falsifiers; R1 fine profiler, all accepted A14.5 R1–R3,
  A14.4/A14.3/A14.2/A13 exact, Project Control and clean tracked state.
- Official portable Godot 4.7.1 and pinned Linux/Windows double exact:
  Linux bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
  Windows 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
  plus independent frozen exact verifier on separate source child commit.

## Prohibited claims

R3 stages item counts, NOT guaranteed wall milliseconds. A4 R2 FINALIZE
still invokes the original monolithic A4 allocator; full cursor copy /
checksum, a large claim bucket and final A5 admission/A6 feedback
are also indivisible. Therefore throughput can REGRESS compared with
legacy staging. There is no hard 30 ms guarantee or accepted speedup
until repeated cross-host cold/warm measurements confirm actual benefit.
No Earth/WORLD_COMPAT activation, >256 canonical population, or
independent regional resources are introduced.

A14.7 should test GUI frame/input smoothness, backlog, native
process RSS and decide whether an exact, singly-computed global
allocation or off-main-thread work is warranted for performance.
