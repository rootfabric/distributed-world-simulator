# ECO ARCH2 A14.5 R3 — Live Staged Global Tick / Bounded Cancellation

Base main: 0d1173303fb6b84e6aa046423ab7c49600176492
(A14.5 R1 #768 and R2 #776 merged).
Feature: feature/eco-arch2-a14-5-r3-live-staged-session-r1.

## Product scope

A14.5 R1/R2 implemented exact, abortable global tick stages but did not
integrate them in the living LAB frame loop. R3 connects the accepted
Runtime staged API to the SAME canonical ExperimentController and
EcologyWorkbench._process. Host StagedFrameSession holds the speculative
cursor privately across frames; one canonical state is published ONLY after
A5 PREPARE / once-per-world ALLOCATE / ADVANCE / propagule admission /
A6 feedback have all completed successfully.

LAB may opt in with configure_staged_live. The opt-in is initially disabled
so accepted A14.4/default behavior is preserved. Generation and condition
goals stay serial for exact predicate checks, WORLD_COMPAT stays on its
per-tick world-authority admission path.

Each staged frame runs a bounded number of resume calls and worksets per
resume; a soft wall budget may stop work between whole stage calls. Completed
canonical ticks consume precisely one logical cadence interval from
EcologyWorkbench. Uncommitted debt remains across frame boundaries.
Speculative cursor, wall time, metrics and scheduler debt never enter
Runtime state, RNG seeds, manifest or A8 checkpoint bytes.

## Cancellation and memory

- PAUSE discards the speculative cursor but never changes canonical truth.
- RESET and successful externally anchored load_state discard the cursor.
- Legacy run/step, A14.3 budgeted replay and live field mutations reject
  operations while speculative staging is pending. UI manual mode-switch
  commands explicitly cancel speculation before legacy work.
- Opt-out discards a pending cursor but retains unconsumed logical time.
- Every cursor must encode canonically and fit a configured transient
  UTF-8 byte cap (default 8 MiB; hard configuration ceiling 16 MiB).
  Oversized cursors fail closed with NO partial biological publication.
- Source/options hashes and deep nested A5 checksum are checked on EVERY
  resume. They are host-integrity checks and NOT malicious-client signatures.

## Diagnostics

The session reports per-phase p95/peak for BEGIN, PREPARE, ALLOCATE and
ADVANCE; bounded sample history; overall wall-time and peak call time;
cursor peak bytes; cancellation count; memory refusal count; fully committed
ticks. The LAB status line can show current phase, transient KiB and
allocation p95. No timing measurement changes canonical state or RNG.

## Non-claims and remaining irreducible hot spots

No hard millisecond / CPU-time execution deadline. Time.get_ticks_usec is
monotonic wall time rather than measured per-process CPU time. One expensive
workset, global A5 allocator, deep cursor validation and final admission /
feedback are still indivisible. They may exceed the soft wall budget.
R3 accepts true opt-in LAB staged integration, NOT Earth/WORLD_COMPAT
activation, hard preemption or 1M organisms. Canonical maximum is 256.
Whole-tick acceleration is not claimed from a small cursor hash gain.

## Falsifier matrix and required gates

F1: actual LAB ExperimentController and host manifest; canonical state and
A8 checkpoint remain unchanged on pending frames, legacy run blocked, exact
checkpoint bytes/hash after completion for consecutive staged ticks.
F2: 1024-byte speculative cursor cap rejects and rolls back; fresh attempt
safe; pending PAUSE cancels without mutation.
F3: externally anchored restore drops cursor/metrics; memory diagnostics
remain noncanonical, source state never changes from speculative work.
F4: real EcologyWorkbench._process drains four owed ticks over multiple
frames while each frame publishes no more than one complete canonical tick.
F5: 4/32/96/256 scale exact parity with canonical Parallel Advance and A8,
per-phase latency and peak transient bytes, no fabricated speedup.
F6: existing A14.5 R2 (205/0), staged R1 (173/0), A14.4, A14.3, A14.2,
A13 regressions and Project Control all remain PASS.

Use official portable Godot 4.7.1, Linux double exact and Windows double
exact on ONE frozen product HEAD/TREE; fresh source review and a separate
independent verifier. Do not merge on failed or pending gates.
