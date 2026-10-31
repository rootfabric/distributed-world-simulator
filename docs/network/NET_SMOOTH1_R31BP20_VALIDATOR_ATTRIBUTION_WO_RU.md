# NET-SMOOTH1 R31b P2.0 — native per-validator attribution (diagnostics only)

## Lineage and prior evidence

Parent frozen #809 HEAD 4e6840e23c6add8b61ecc818c023d19edd0d468e, TREE d85566bca754c6af86da82a7d94dbc3247efee68. Ancestor #803 HEAD 6cdb0f0ce0f8550ece723194d67826afc6b81348; direct parent of #809 is 34f094c34b995ebd289c0d5a5da84cbd55064870. No merge/force/main change.

Windows [PR #809 comment 6317818361](https://github.com/rootfabric/distributed-world-simulator/pull/809#issuecomment-6317818361) verified B1 Win64 signed instance ID, B3 strict Godot process isolation and 3-role measurement-end ACK. On idle CPU 0–16%, server frame p99 across OFF/ON 26.4–29.5ms in every accepted arm (>25), clients pass, sim >=59.9Hz, P1 M4/Resource 100% cache-hit and 0 bypass. ONE first pair3-ON attempt had a pre-measure PAYLOAD_CHECKSUM_MISMATCH on BOTH clients; exact retry functional PASS, but incident remains explicitly unclosed. Clean ON max 40–44ms versus OFF 127/276ms in pair1/2; correlation is not proof of causation. No known P2.0 performance fix.

BINARY PROVENANCE WARNING: #809 published report gives console wrapper SHA256 457de51624b0b7ef06943abfcb6c8f0fcbf9cdeabd3f965bf7a5503b11c1d2e1, whereas old pinned wrapper SHA was 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5. Main EXE SHA observed 6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4. Verify exact binaries separately; don't pool uncertain environments or claim Windows exact on wrapper-only provenance.

## Implementation: P2.0 observer, NOT validation optimization

Opt-in DWS_NET_R31BP20_VALIDATOR_ATTRIBUTION=1 and --r31bp20-validator-attribution. Server-only, default OFF, requires full R31a replay + R31b P0 + P1 cache + R2 worker + persistent USER1 ProductSeam. Missing/invalid prerequisites fail closed.

At the SAME quiescent authoritative frame, the existing SINGLE validate_durable_state(durable) call is timed internally: envelope/schema, outer checksum verification, PlayerRegistry, Ownership, SharedItem, M4 validator setup and actual M4 validator.validate_durable_state, cross-domain inventory/owner consistency, final JSON safety canonicalization, P3 ResourceMining validation and authority match. Original error codes and validation order preserved; no second validation, no disabling any checks, no new disk schema or M6 writer/ACK changes.

Nested traces: checkpoint_capture.r31b_durable_stages.r31bp20_validation_stages. Active-seam checkpoints include per-stage metrics; fallback seam-unbound checkpoints explicitly separated. This is a diagnostic only, NOT P2.1 cached validation proofs.

## Exact source / native gates

Fresh exact HEAD/TREE; tracked clean, real Quaternius CC0 provider, Godot double, both hashes. Cold import and real Godot suite tests/runtime/test_net_smooth1_r31bp20_validator_attribution.gd. Tests exact validation Dictionary and nested error-code/cause parity for valid source, bad schema, bad outer checksum, missing players, bad ItemGraph checksum and bad ResourceMining checksum. Direct M6 adapter export must match profiled periodic frozen envelope; server rejects malformed canary / missing P1/P0/R31a/R2. All existing native M6/disk/ACK/USER1/replay tests inherited, and tests/tools/test_net_smooth1_r31bp20_validator_attribution.py plus Python synthetic trace negatives. No native PASS claims from CI queued/unknown.

## Independent Windows three paired 120s real GUI source attribution

Use SAME fresh new P2.0 HEAD, real server and 2 graphical Earth+Quaternius clients, OpenGL3 900x600 VSync off, LOCAL, scenario r31-reconnect-roundtrip, warmup20 + measured120. Alternate OFF/ON, ON/OFF, OFF/ON, separate run roots.

Common BOTH arms:
--r3c-async-admission
--r3c2-avatar-prewarm
--r3c2-server-phased
--r3c3-staged-earth
--r3c21-frame-paced-presentation
--r3c4-periodic-frame-pacing
--r3c4r2-worker-envelope
--r3c4r31-replay-projection
--r3c4r31b-durable-attribution
--r31bp1-durable-chunks

ON only adds --r31bp20-validator-attribution. Thus OFF is already R31a+P1 enabled, NOT an old legacy engine.

For each ON server trace run:
python tools/net_smooth1/analyze_r31bp20_validator_stages.py <ON_ROOT>/server/trace.jsonl --output <ON_ROOT>/p20_validator_stages.json

The strict reducer requires 10+ active measured ProductSeam captures, finite stage times, full R2/P1/R31a opt-in, coherent timing and legitimate seam-unbound fallback accounting; reports p50/p95/p99/max for every stage. NEVER sum individual p99 values to infer total p99. Compare per-stage and outer validator p99 with regular normative analyze_net_smooth1.py OFF/ON report, and analyze_r31bp1_durable_chunks.py for measured P1 hit-deltas. Preserve all raw trace/manifest/report.json and every failed first attempt. Observer overhead is not a cache benefit. Never adjust p99 threshold or retroactively filter >100ms gaps.

## Product release / P2.1 gate

Unchanged server AND client frame p99 <=25ms, p99.9 <=50ms, max <=100ms, sim >=59Hz, zero M6/replay/ACK/authority violations; explicit separate first-join checksum mismatch reproduction or disproval by repeated negative tests, real ITEM 1800ms, hard-kill/restart, A->B->A authority handoff, independently pinned main+wrapper EXEs, Project Control/SEAM-E2E and known base-equal P7.4 port collision. No merge.

Only after measured P2.0 results, design separate version-fenced prevalidated immutable M4/Resource checks (P2.1). Never skip whole validate_durable_state(); retain outer checksum, live player+ownership and cross-domain checks on every tick. No shadow authoritative state or mutable graph on worker.

VERDICT: P2.0 DIAGNOSTIC CANDIDATE / NATIVE_GUI_PENDING / PERF_NOT_FIXED / NO_MERGE.
