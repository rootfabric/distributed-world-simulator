# FABRIC BRIDGE-4 — CANONICAL WORLD ↔ FABRIC1

Status: **RESEARCH EXACT CLOSED**.

BRIDGE-4 is the first frozen-FABRIC1 integration that reads real DWS canonical Construction/Matter contracts and observes a real `ConstructionConstructStore` successor instead of a research-only canonical stand-in.

## Frozen architecture boundary

```text
Construction / Matter = authoritative world truth
           ↓
BRIDGE-4 canonical adapter
           ↓
FABRIC1 derived graph/execution
           ↓
physical overload → proposal only
           ↓
external ConstructionConstructMutation
           ↓
source revision / checksum changes
           ↓
stale FABRIC execution forbidden
           ↓
FULL successor → REBAKE → restart
```

BRIDGE-4 has no canonical write authority. `Construction` is bound as mutable canonical source; `Matter` is bound read-only. A derived capsule is discardable and can restore only when the authoritative successor still matches.

## Exact frozen subject

- SYNC1 predecessor: `336fa62d48f0c9659623b320948a2304989baf84`
- runtime candidate: `bb86d0b9f97b52727560bff88afc03df0a021668`
- runtime tree: `95bb1a501f14e205d19336c36a374399cf1a63fb`
- exact replay: `49 PASS × 2`
- replay hash: `c7daed6263058ce016a32b9813ee9a5d8da1798be96cb01e641818bd323458bf`

## Next activation

`COMPLEX4 — REAL WORLD MACHINE LAB` is now authorized. It should build a richer real canonical object from Construction/Matter and prove structural + functional downstream consequences in an end-to-end lab. The playable visual lab remains the next consumer after COMPLEX4.
