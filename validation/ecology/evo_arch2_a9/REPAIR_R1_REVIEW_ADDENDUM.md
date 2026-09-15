# A9 R1 independent-review addendum

Fresh whole-head review on 920a6f3a968be950559747be20ccf2f8b4e205c1 returned two findings on 2026-09-15.

## P1 4016102680 — durable packet limit

Owner: new A9 ecological_fidelity_v1.py.MAX_PACKET. Caller/siblings: constructor, from_snapshot, convert, restore, aggregate report and A8 SnapshotStore.commit. Canonical A8 store allows2MiB; A9 initially accepted4MiB. A valid raw A8 input can grow past2MiB when wrapped and JSON-escaped, so accepting it as persistable was incorrect.

Bounded fix: MAX_PACKET = MAX_RAW =2097152; do not raise or modify canonical A8 storage limits. The complete A9 packet, not merely its payload, must fit2MiB. An A8 source fitting its own raw limit is not automatically a fitting FULL envelope; oversize A9 envelopes reject explicitly and atomically. No silent clipping or automatic representation change.

Falsifier: an otherwise valid synthetic source with600000 quote characters fits the raw limit but its FULL envelope exceeds the store limit. Old A9 accepted it; repaired constructor must reject BYTE_BUDGET. Existing small positive roundtrip/persistence tests remain mandatory. Workflow must mechanically compare A9 MAX_PACKET against actual unchanged SnapshotStore.MAX_SNAPSHOT_BYTES. Update current design documentation from4MiB to2MiB.

## P2 4016102692 — specific stale-owner rejection

Owner: new A9 integration.py negative control. Already corrected in ceeae2509a63484d6b9285efdbea1b94bd85af26: unexpected FidelityError cannot satisfy owner fencing; require A8_STALE_OWNER. This must be independently reviewed on the final repaired HEAD, not accepted from the implementation reply.

## Same R1 post-build repair

c92c2e849d0ac8a9de08ac10185287bf945b81f0 records separate restore-recompression identity defect. Fix preserves exact acknowledged bytes after semantic admission. All issues are confined to new A9 runtime/test/docs; accepted A0–A8 files remain unchanged.

Next: publish size fix and boundary tests, pin new source HEAD/TREE, new exact execution and fresh whole-A9 review. Prior review/CI are historical; main merge and A10 remain unauthorized.
