# A9 Repair R1 — preserve the acknowledged representation on restore

Work Order: EVO-ARCH2-A9-20260915-R1. Risk HIGH. Implementer post-build inspection, not independent acceptance.

Source: 920a6f3a968be950559747be20ccf2f8b4e205c1 / 8a68a33206270b15d3f7cd24ced0c26b0f50ec35. Base main: 675c04bb213bbb68b8cdb500d540d57ce1490318. Current independent review request 5680887802 and exact run34974736747 are historical once the repair moves source.

## Root cause and owner

NativeA8.restore() admitted the exact historical payload by calling refine(), then returned a freshly converted packet. A valid REDUCED packet is allowed to contain a zlib stream from a different compression level/version, so recompression at level9 changes acknowledged packet bytes/hash despite no ecological or fidelity transition.

Reproduced through the real Python NativeA8.restore method with only its native-admission boundary replaced by the existing explicitly synthetic fixture service. A level1 packet's hash was 6db9bcf43a7539bc626e74d61bdcefe9b133751ed661923cef3954598c391b84; returned hash was 17a7ebc6f1b25208f14c6b9ac2de1276e300d057c756492f830f0b7959405884. This is a contract counterexample, not a biological execution claim.

Canonical fix location: scripts/research/ecology/v2/fidelity_runtime_v1.py, NativeA8.restore. Keep full native semantic/projection admission, but return the original immutable acknowledged record instead of re-encoding. Conversion remains a separate explicit operation.

Callers/siblings: FULL/REDUCED restore, external packet anchors, fresh Python restart, A8 SnapshotStore persistence; explicit convert/refine semantics remain unchanged. No main-owned A8 store or biological/authority code changes.

## Tests

Extend existing test_packet_restore_external_anchors with compression levels0/1/6/9. Run actual NativeA8.restore method against synthetic admission boundary and require byte/hash identity for each. Preserve 32 mandatory unit methods; normal Python and python -O both must pass. Full native integration remains mandatory on the repaired source.

## Adjacent evidence fixes

Integration's stale-owner negative control must require A8_STALE_OWNER instead of accepting any FidelityError (e.g. unrelated process failure). Integration must set verdict PASS only after final mandatory-check-count validation. These are bounded evidence-strength corrections, not changes to biology or acceptance thresholds.

## Continuation

Publish scoped runtime/test/helper repair; verify Git bytes against tested local code; freeze new HEAD/TREE; rebind read-only exact workflow; fresh whole-head review. Preserve old evidence as historical. Use shared workflow concurrency to retire only superseded A9 exact attempts, never another research family. No main merge or A10 activation.
