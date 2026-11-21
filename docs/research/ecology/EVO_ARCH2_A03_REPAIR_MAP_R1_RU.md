# EVO ARCH2 A0–A3 — Repair Map R1

Дата: 2026-09-06.  
Fresh Reviewer: Codex PR review on `83da390463ff1c8dfcdcb4af62ee2bacc85ee4a8`.  
Frozen pre-repair A0–A3 source: `096723ec6162892b49c11839e07f8824d0d2c45d`.

## Reviewer verdict

`FIX_REQUIRED` — три P1 blocking findings. До исправления A0–A3 нельзя считать принятыми.

## RM-01 — cold-import BOM repair вне write fence

**Affected module:** branch execution scope / three legacy lab scenes.  
**Canonical owner:** legacy scene files remain legacy presentation fixtures; EVO ARCH2 does not claim their semantics.  
**Finding:** original Work Order allows only `evo_morphology_lab_v2*` scenes, while three `eco_evo5_*` scene BOM removals were included in the implementation subject without a durable repair Work Order.  
**Root cause:** cold-checkout parse failure was found after the initial Work Order was issued; the byte-only repair was performed but repair authorization was recorded only in prose delivery evidence, not as an executable/durable scoped Work Order.  
**Canonical fix:** add a dedicated bounded `EVO-ARCH2-A03-REPAIR-COLD-IMPORT-R2` Work Order authorizing exactly those three files and only leading UTF-8 BOM removal. No other semantic scene edits are allowed.  
**Sibling check:** no other legacy scene change is permitted. Verify exact diff/byte relation against research base.  
**Why not symptom patching:** this repairs the scope/governance defect; the scene bytes themselves were already the minimal parse fix.

## RM-02 — Morphology Lab conflates `BUDGET_BLOCKED` with `TICK_COMPLETE`

**Affected module:** `scripts/labs/ecology/evo_morphology_lab_v2_model.gd`.  
**Canonical owner:** A2 interpreter owns development status semantics; Lab model is a consumer/adapter.  
**Entry points:** `step()`, `environment_preview()`, `generate()`.  
**Sibling paths:** any helper that loops over `K.advance()`, UI status display, tests for capacity resume.  
**Finding:** code treated any status other than `RUNNING` as successful completion. `K.advance()` may return `BUDGET_BLOCKED` with an open frame. The next `begin_tick()` can then fail with `TICK_ALREADY_OPEN`, and preview/gallery can compile a phenotype from an incomplete tick without truth-labeling the block.  
**Root cause:** adapter collapsed a three-state protocol (`RUNNING`, `TICK_COMPLETE`, `BUDGET_BLOCKED`) into boolean done/not-done. Interpreter semantics are not the root cause.  
**Canonical fix:** introduce explicit tick-finalization helper. Only `TICK_COMPLETE` is success. `BUDGET_BLOCKED` preserves state/frame, surfaces the reason, and returns non-success to caller. Add explicit `resize_capacity()`/resume path; do not start a new tick while a frame is open. Preview/generation reject or truth-label blocked candidates instead of treating them as completed.  
**Tests:** force module capacity block, assert open frame + model failure/status, resize, resume same tick, assert completion and no `TICK_ALREADY_OPEN`; gallery/preview must not accept blocked final tick.  
**Why not symptom patching:** status semantics are fixed at the Lab consumer boundary shared by all three call paths.

## RM-03 — import genome preserves unrelated lineage/family/gallery

**Affected module:** `evo_morphology_lab_v2_model.gd` and UI family label.  
**Canonical owner:** Lab model owns diagnostic session provenance only; genome biological identity remains in `OrganismGenomeV2`.  
**Finding:** successful `import_genome()` replaced genome/body state but kept `generation`, `lineage`, `family`, and `gallery`, causing later mutations and display to claim ancestry/results from the old source.  
**Root cause:** import was implemented as state replacement but not modeled as a new diagnostic root.  
**Canonical fix:** import creates a fresh session root: `generation=0`, lineage contains only imported biological hash and import source marker, gallery cleared, fixture family cleared/marked `IMPORTED`, organism state rebuilt from imported genome.  
**Tests:** mutate + generate before import; import a different genome; assert generation zero, lineage size one/hash matches imported genome, gallery empty, family not an authored fixture; next mutation descends from imported hash.

## RM-04 — validation workflows must not live inside implementation write fence

**Self-found during review response.** Original Work Order explicitly forbids `.github/workflows/**`. The two exact-verifier workflows were added only after source freeze to obtain independent evidence, but leaving them on the implementation branch violates the branch-local implementation fence even though they are validation-only.

**Canonical fix:** delete both workflow files from the implementation branch. After source repair is complete and frozen, cut a separate `validation/eco-arch2-a03-exact-head-r1` branch with its own narrow Verifier Work Order. Only that validation branch may contain the read-only exact workflows. No Actions workflow may author/push/reconstruct source.

## Repair order

```text
Repair Map durable
  ↓
Cold-import repair Work Order durable
  ↓
remove verifier workflows from implementation branch
  ↓
fix Lab status + import provenance
  ↓
expand exact acceptance tests for RM-02/RM-03 + scope guard
  ↓
local exact regression
  ↓
freeze repaired source HEAD
  ↓
cut isolated validation branch + verifier Work Order/workflows
  ↓
independent exact verifier
  ↓
fresh Codex re-review of repaired source HEAD
```

No A4 work, no production ownership, no main mutation, no merge.
