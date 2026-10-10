# FABRIC R5.5 R1 — cached successor / scratch isolation

Base: R5.4 merged commit `56ab06936b902e8c752be06eafa2e4d16465cc82`.

## Implemented
- Additive R5.5 adapter; closed R5.4 and previous physical kernels remain byte-for-byte unchanged.
- Precompute canonical 100k broken-bond successor **once at initialization** and verify the original R5.1 successor binding.
- Reuse deep-copied canonical successor in each local staging attempt. No `create_subject(100000, true)` on the attempt path.
- Make a **one-time** deep copy of the R5.1 packed prefix index for staging, avoiding live-index aliasing.
- Fail closed on cached source tampering and identity drift.
- Count full successor builds separately from event attempts and count only committed cached events.
- Add parity acceptance against original R5.4 (baseline/local/global machine hash), counters, index ownership, and tamper rejection.

## Explicit limits
This is an initial research slice, **not** a universal incremental digest algorithm. The canonical fixture has a known one-bond successor; the full digest cost has moved to initialization rather than disappeared. Index isolation is by ownership; GDScript still permits mutation inside a scratch-owned dictionary. Stage index is reused between attempts and must be treated read-only. This does not yet establish deep immutable ROM boundaries for recursive capsules, multi-event generality, or production performance.

Windows exact adversarial evidence (2026-10-10, canonical Godot `a13da4feb`): a targeted prefix-array mutation of the scratch stage index is **not detected** — the staged transaction commits silently and `machine_hash` stays canonical because corruption is confined to derived residual descriptors. Prepared-successor field tampers (spec/frontier/authority) do fail closed with `R5_5_SUCCESSOR_CACHE_MUTATED` and leave live state untouched; capsule tamper fails closed at restore (`COMPLEX3_CAPSULE_INVALID`); live range-index tamper cannot leak into the staged event. Scratch-index integrity is therefore trust-based: prevention by ownership, no per-attempt detection (O(1) checks cannot detect intermediate prefix deltas, and O(N) re-verification would defeat the purpose).

## Validation
The acceptance script is added but **not executed** in this environment; canonical Godot binary is present, but the complete repository checkout is not. Requires fresh Linux canonical and Windows exact, baseline R5.4 regressions, collector and independent review. Keep PR draft and do not merge.
