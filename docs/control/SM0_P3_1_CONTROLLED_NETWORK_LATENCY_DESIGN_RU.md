# SM0-P3.1 — controlled network latency/jitter lab

Status: **DESIGN / BRANCH-LOCAL EXPERIMENT ONLY**.

P3.1 extends the already measured healthy localhost path. It does not alter the canonical authority/handoff decision algorithm and does not promote `SERVER_HANDOFF` into V0-S1.

## Question

Can the same single-client A <-> B healthy handoff remain identity-safe and visually continuous when every SM0 UDP egress leg is subjected to deterministic WAN-like one-way latency and jitter?

P3 measured localhost end-to-end handoff at 12..25 ms. P3.1 deliberately adds transport delay so the cost and subjective hitch become measurable instead of conflating normal handoff with the earlier crash/restart recovery laboratories.

## Scope

Initial profile:

- profile id: `p31-controlled-latency-v1`;
- default artificial one-way latency: `30 ms`;
- default jitter: `+/- 5 ms`;
- packet loss: `0`;
- duplication: `0`;
- explicit reordering: `0`;
- deterministic seed: `431`;
- both authority server egress and graphical client egress are shaped;
- ordinary movement packets and handoff protocol packets use the same egress shaper.

The shaper is laboratory-only. It is selected explicitly by runner arguments; the existing healthy P1/P3 path remains unchanged when the profile is absent.

## Transport semantics

Delay is applied to message delivery, not to Godot frames, process sleeps, authority mutation, persistence, or visual interpolation.

Each queued egress message receives a deterministic delay derived from profile seed plus sender identity, message type, request id and destination. Per-channel FIFO delivery is retained so P3.1 measures latency/jitter without silently becoming a packet-reordering test.

No packet is intentionally dropped. Loss/duplicate/reorder belong to a later checkpoint.

## Instrumentation

Each participating process emits `SM0_NET_PROFILE_ENABLED` with profile parameters.

Handoff-relevant queued deliveries emit `SM0_NET_DELAY_SCHEDULED` with sender role, channel, message type, request id, requested delay and actual FIFO-constrained scheduled delay. This provides evidence that the runtime measurement did not merely pass profile flags without shaping packets.

Existing client events remain the latency source of truth:

- `SM0_CLIENT_HANDOFF_LATENCY_TRIGGER`;
- `SM0_CLIENT_HANDOFF_LATENCY_REDIRECT`;
- `SM0_CLIENT_HANDOFF_LATENCY_MEASURED`.

## Acceptance invariants

A default P3.1 run is acceptable as branch-local runtime evidence only when:

1. exact Godot is `4.7.1.stable.double.custom_build.a13da4feb`;
2. one graphical client completes at least the requested number of alternating handoffs;
3. both authorities and the client report the exact same P3.1 profile parameters;
4. handoff-relevant delay scheduling evidence exists on both authority and client paths;
5. every measured crossing keeps `player/a`, `identity_changes=0`, and `|v|=0.25`;
6. route continuity A -> B -> A is preserved;
7. no authority process is deliberately killed or recovered;
8. no `SM0_INVARIANT_VIOLATION` is present;
9. runner writes a profile-bearing machine-readable latency summary.

There is intentionally no hard production latency budget in P3.1. The first run establishes the empirical cost curve and visual feel under a known deterministic delay profile.

## Follow-up

After DEFAULT is green, a later FINAL/matrix run may compare several profiles (for example low-latency regional, ordinary WAN, and long-distance WAN). Packet loss/reorder should be a distinct checkpoint so latency conclusions remain attributable.
