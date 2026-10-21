# ECO ARCH2 A14.6 R3.2 — Optional Off-Main CPU LAB Global A4

Status: DRAFT EXPERIMENTAL CANDIDATE / NOT FINAL VERIFIED / NO MERGE.
Parent: A14.6 R3 PR #798 product HEAD 080fdbef2102fed0b61b7cde14e21c3b7720c588.
Accepted BASE_MAIN aac301b9a9a89e027f6d99864437eb750a4202ca.
Branch feature/eco-arch2-a14-6-r3-2-offmain-lab-r1.

## Purpose

R3.1 proved real LAB global A4 R2 staged execution but is about 3× slower
than A14.5 at 256 canonical organisms, without improvement to the worst
main-thread frame stall. R3.2 experimentally computes the SAME complete,
indivisible, globally causal R3 A4/A5/A6 tick in a CPU-only worker instead
of blocking the UI thread. It does NOT promise faster throughput,
a 30ms hard frame deadline or any new biology/Region authority.

## Explicit LAB opt-in

Workbench.configure_staged_live(enabled, soft_budget_us,
resumes_per_frame, worksets_per_resume, max_members, cursor_cap_bytes,
use_r3_allocator=true, allocator_items_per_call, use_off_main_r3=true).

Both flags remain OFF by default. WORLD_COMPAT, Earth and player-driven
production authority are explicitly excluded.

The trusted LAB controller owns a private immutable canonical source
frontier. The main thread binds only a shallow outer read-only dictionary
and the options/source hash. No external mutable nested-state alias is
permitted during the background operation. The worker NEVER writes to
the input state. Its only CPU APIs are accepted Runtime, Lifecycle and
R2 staged A4: whole-world PREPARE, one original globally verified A4
allocator (two pro-rata passes), ADVANCE, propagule admission and A6
feedback.

The UI polls WorkerThreadPool.is_task_completed without waiting for an
unfinished task, joins an already completed task exactly once, then
verifies original source hash/tick/options and Runtime.validate(source)
before publishing ONE full canonical tick. A pending task never returns
a partial field/grant/organism/checkpoint.

Cancellation is cooperative at step boundaries; a currently running
monolithic A4 FINALIZE or A5 workset may not be interrupted.
PAUSE/restore/opt-out irrevocably marks the worker result abandoned
before allowing the prior canonical frontier to move. A canceled worker
may continue on its old immutable reference for a short time but cannot
commit stale output. Abandoned tasks are reaped non-blockingly, even
while the GUI is paused. A second worker cannot start until it is
drained. This is trusted LAB ownership, not untrusted client security.

Cursor integrity, input epoch and encoded byte limits remain in R3.
The memory cap is encoded bytes, not process RSS. No new canonical data,
RNG seed, scheduler wall clock or state serialization is added.
Historical A14.5 and R3.1 paths are unmodified except extra opt-in
routing and a very small abandoned-worker cleanup poll.

## Exact falsifier and performance evidence

New tests:
validation/ecology/evo_arch2_a14_staged/test_r32_off_main_lab.gd

They check direct CPU worker state vs original real controller, actual
Workbench._process across pending frames, A8 canonical checkpoint byte
equality, PAUSE/cancel, legacy-command guard, cancellation cleanup/join,
trusted external restore, and two noncanonical timing JSON rows.

Require Godot 4.7.1 official portable + pinned Windows/Linux double:
Windows SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
Linux SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.

Before acceptance: independently reproduce frozen product HEAD/TREE,
all R3/R2/R1 and A14.5–A13 exact suites, native Windows/Linux
real GUI input/frame-time and backlog soak at 4/32/96/256 with enough
samples and process RSS measurements to separate main-thread responsiveness
from throughput. New verifier branch and independent source review must
cover cancellation, worker lifetime, source ownership, race/failure cases,
and A4 single-global-grants integrity. Any failure => no merge.

This R3.2 PR depends on R3 #798 and MUST NOT be merged into main while
R3 is still pending. Keep it Draft if performance or concurrency
safety is unproven.
