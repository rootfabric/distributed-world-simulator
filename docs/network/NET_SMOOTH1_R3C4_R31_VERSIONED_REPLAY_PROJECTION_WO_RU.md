# NET-SMOOTH1 R3C.4 R3.1a — Versioned Replay Projection (first incremental slice)

## Identity and scope

Parent: R3.0 attribution [PR #795](https://github.com/rootfabric/distributed-world-simulator/pull/795),
HEAD `da3e23b59ddb621aa97cf975f71602b975ed1434`;
its parent is frozen R2 `f64fed2430f1292773d1561f881e5c8a4cc89075`.
Separate slow-ITEM admission tool [PR #796](https://github.com/rootfabric/distributed-world-simulator/pull/796)
is **not** combined. No main changes, no automatic merge.

R3.0 Windows 3×120s Earth GUI evidence
([#795 comment 6307019763](https://github.com/rootfabric/distributed-world-simulator/pull/795#issuecomment-6307019763))
identified capture p50 ~28ms = gameplay durable authority export ~11.8ms +
replay outbox export ~16.4ms + handoff ~0.14ms. Replay decomposes to
service replay export ~10.7ms + canonical checksum-detach ~5.5ms.
Writer duplicate(true) itself ~0.13ms; moving it off-thread cannot fix p99.

**R3.1a optimizes ONLY unchanged-replay periodic captures**.
The expensive gameplay durable export remains unchanged (~12ms p50).
This is a bounded first component of a future shared authority + replay
immutable projection, not a claim of full R3.1 or cap_capture p99 <=5ms.

## Actual implementation

- Server-only `DWS_NET_R3C4_R31_REPLAY_PROJECTION=1` /
  `--r3c4r31-replay-projection`. Requires R2 and R1 flags, defaults OFF,
  invalid env rejected, incompatible with R3.0 uncached stage-attribution.
- The *authoritative* service, ownership, M4 Item Graph and P5 ResourceMining
  replay journals each have monotonic mutation generations, independent of
  the 60Hz fixed-movement revision. The product seam fence also includes
  transfer serial and coordinator count, and requires seam quiescence.
- The existing M6 outbox stays the **single replay source of truth**.
  `to_dict_r31_versioned()` builds the **unchanged** `to_dict()` canonical
  snapshot/checksum only when source generation or outbox generation changes;
  on exact matching epoch/source fence, returns a deep-detached copy of the
  cached canonical data. Invalidation on outbox stage/delivery attempts,
  delivery, load/restore; stage transitions and nested Item Graph/resource
  ledger changes invalidate through source generation.
- Safe fallback to canonical legacy `to_dict()` if the source fence cannot
  be proven or cache exceeds its 256-outbox-record / 4MiB budget. This is a
  **cache bypass**, not persistence failure or a performance success.
- Cache is private, discarded on mutation; every caller receives detached
  values, and the existing checkpoint writer **still performs** deep copy
  before signalling its semaphore. No live Node, Resource, Dictionary owned
  by gameplay, or second mutable authority state enters the worker. No
  checkpoint schema / checksum / M6 ACK / generation changes.
- Trace adds `checkpoint_capture.r31_cache_hit`, `r31_cache_bypassed`,
  `r31_projection_generation`; existing normative metrics unchanged.

## Mandatory native exact / falsifiers

Pinned Linux/Windows Exact and source CI must cover:
1. Default OFF and invalid/unsupported mode rejection; never blend R3.0 with
   R3.1a instrumentation and mislabel costs.
2. `to_dict_r31_versioned().value == to_dict()` exact M6 replay DTO and
   disk checksum/bytes on first miss and all warm cache hits.
3. Caller nested alias poisoning cannot mutate cache or writer checkpoint.
4. 60Hz fixed ticks without replay changes **do not** invalidate; real M4
   ITEM, ownership/Join, resource changes, outbox stage/delivery/replay
   restore and product seam handoffs **must** invalidate.
5. Invalid projection fence / over-budget state can never return stale data.
6. Full M6 real command, durable-before-ACK, slow ITEM 1800ms, hard kill,
   restart, idempotence, two client authority roundtrip unchanged.

## Independent Windows experiment

Fresh clean worktree pinned to this PR's exact HEAD/TREE, original
Quaternius visual assets (no fallback), one binary for all paired GUI tests.

Use production `tools/net_smooth1/run_net_smooth1.py` and unchanged
`tools/net_smooth1/analyze_net_smooth1.py`, 3 paired **OFF vs ON**
120s measured 2-client Earth+Quaternius `r31-reconnect-roundtrip`,
20s warmup, OpenGL3 900x600, VSync off, 60 FPS, profile LOCAL.
Common flags:

`--r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased --r3c3-staged-earth --r3c21-frame-paced-presentation --r3c4-periodic-frame-pacing --r3c4r2-worker-envelope`

Only ON adds `--r3c4r31-replay-projection`. OFF and ON must run on same
**new R3.1a HEAD** (NOT historic #795 or #787 HEAD). Alternate order.
Separate each output root and preserve all manifest, report.json, trace,
raw screenshots and asset hashes.

After the unmodified normative analyzer, run for **each R3.1a ON**
measured server trace:

`python tools/net_smooth1/analyze_r3c4_r31_cache.py <OutputRoot>/server/trace.jsonl --output <OutputRoot>/r31_cache.json`

The dedicated read-only diagnostic fails closed for missing stage samples,
source flags, unknown bypasses, invalid generation, <10 captures,
<90% replay cache hit rate or a generation reversal. In an R31 moving
phase with ~78 checkpoints and no new replay commands, expect one cache
materialization then mostly hits. The diagnostic's PASS is **not** the
normative GUI PERF_PASS, nor an M6 correctness acceptance.
Preserve legacy and candidate per-run reports even on negative results. Compare per checkpoint replay_ms,
authority_ms, capture_ms, cache hits/misses, bypass error codes,
server/client frame p99/p999/max and loop Hz. Evidence is invalid if
a cache-bypass occurs in an accepted fast-path run without explanation.
A cache benefit alone is not a passing acceptance if p99 >25ms.

**Godot provenance:** pinned Windows console wrapper SHA256
`3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`;
earlier Windows source review reports the main engine `6464da35...`.
Version string equality or wrapper-only SHA is **insufficient** to prove
the main engine exact identity. Report both hashes, use same engine for
all pairs, classify unpinned engines `NON_PINNED_ENVIRONMENT` even when
comparisons are internally valid. Separate native CI self-hosted runners
may still be missing; never claim queued jobs PASS.

**Acceptance bars unchanged:** server AND client p99<=25ms, p99.9<=50ms,
frame max<=100ms, server loop >=59Hz, 0 durability/checksum/replay/ACK or
lost-trace violations; source/native independent review, Project Control
canonical rotation #783, SEAM-E2E separate. All PRs remain Draft and
`NO_MERGE` until every required gate passes.

## Follow-up R3.1b / 3.2

The remaining ~12ms gameplay durable `export_durable_state()` is
still a full traversal, with changing tick/player rows. Never cache a
whole fixed-tick gameplay state using replay-only source generations.
Implement **per-domain** versioned snapshot chunks and mutation fencing,
then combine consistent authority/replay high-watermarks at one
quiescent boundary. Preserve old format and rollback canary. Prove
byte parity, multi-client seam transfer under concurrent ITEM,
worst-case memory and CPU, deterministic crash replay before pursuing
a full capture p99 <=5ms target.
