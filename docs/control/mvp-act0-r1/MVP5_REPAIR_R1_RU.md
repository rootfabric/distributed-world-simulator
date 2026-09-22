# MVP5 bounded repair R1 — UI occlusion and exact evidence

Parent `V0-MVP-R1-WO-001` remains `IN_PROGRESS`; risk remains CRITICAL. No owner/foundation authorization is expanded, old events remain immutable.

## Reproduced failed subject

HEAD `d5e23b42accdd6538fa89c584c83ef80ab0c86ac`, TREE `f8b2495a02e937134fcded9db08b3d0ef7a71ca0`; exact run `34833886119`, job `103943192308` = FAILURE. Artifact `10343711883`, ZIP SHA-256 `3e974541094851c3ae49780327c75e60d013aad22dfd532c5862b80f99308c9b`, downloaded and all 30 manifest members rehashed. This failed run is retained, not reclassified as PASS.

Focused real-engine tests passed 270 assertions / four cases. Five graphical processes exited zero and all material checks passed: one positive output, first execution plus two identical replay receipts, equal A/B canonical projection. Both terrain checks failed: zero changed pixels OUTSIDE UI. Raw before/after PNG inspection shows a real hole, but appending another HUD row enlarged the excluded live UI rectangle from height 237 to 267 and covered the visible hole. This is a UI layout regression, not permission to weaken the visible gate.

Raw client logs also show audio fallback and a shader-cache initialization error. The predecessor's broad marker list did not reject these lines. New MVP5 validation must reject general ERROR/SCRIPT ERROR/parse/compile markers rather than silently inherit that gap.

## Repair map

- RM-MVP5-01: replace the existing last status row with compact server-derived material values, instead of appending another row over terrain. Keep the complete derived UI mask, hide actual UI during captures, retain the unchanged terrain validator and its >=32 changed-pixel threshold. Before and after use the same row count. No camera, canonical brush or terrain fixture changes.
- RM-MVP5-02: give each owned child a separate temporary user-data/cache/config directory and use the explicit Dummy audio driver for this audio-free test. Delete only those temporary directories after owned child cleanup. Reject every general engine ERROR marker in new MVP5 process logs. No blanket suppression or invented clean-log PASS.
- RM-MVP5-03: independently derive selected material items/totals from already-recorded RAW native Item Graph snapshots, validate actual inventory membership and unchanged old items, revision/tick delta, both failure windows and stable replay receipts. Add ten evidence mutations which must be rejected. This strengthens the focused proof beyond comparing receipt/projection claims.
- RM-MVP5-04: the unchanged predecessor R13 cleanup exception must be backed by its actual exact-baseline command records and final successful summary; a command name alone cannot waive errors.

## Positive/negative controls and acceptance boundary

Re-run exact focused, native-accounting, five-process graphical, unchanged MVP4/MVP3 and Project Control on the repaired subject. Preserve material-output and HUD-only falsifiers; no threshold reduction or product-state stub. On historical focused artifact `10343760300`, the new native-accounting consumer passes 47 checks and rejects 10 deliberate corruptions; this local artifact-consumer check is not execution of repaired runtime.

Fresh review on a predecessor is historical after this change. A new exact-head review/verifier is required before predicate closure. Full world/core, manual keyboard input, persistence/restart, item-bearing seam, whole-MVP acceptance and main merge cannot be inferred from these repairs.
