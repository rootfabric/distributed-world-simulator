# V0→NX — Repair Map R2: stale same-revision prediction projection

Parent Work Order: V0-NX-MVP6-DIRECTIONAL-20260916-R1.
Bounded repair: V0-NX-PREDICTION-PROJECTION-R2. Risk HIGH. State IMPLEMENTING.
This amendment adds exactly one existing implementation path to the parent scope:
`scripts/network/prediction/predicted_item_interaction_journal.gd`, plus a focused regression under the existing validation directory. No merge authority, foundation/ownership change, V0/NX active-branch edit or policy weakening is granted.

## Falsifier

- exact main 6982a563dd0c88c81449566131852c601ae89868;
- comparison run 35089776382, artifact 10443244313;
- ZIP SHA256 5ed10e753f321e7f52a680df09b29e8e67df2c77ec86dfab9ea3b796e0316d81;
- current-main + explicitly type-adapted NX BASELINE (before importing the V0 facade): owner movement 44 PASS, single-writer 31 PASS, item rollback 37 assertions / 3 failures;
- failed behaviors: pickup rejection leaves projected item in inventory; drop rejection leaves decremented quantity and temporary predicted spawn.
- This is a pre-existing NX/current-main composition defect, not an A9 or V0 facade regression. It must not be hidden behind an accepted clearance.

## Canonical owner, entry points and cause

Owner: the existing NX prediction journal; this is derived client presentation, never canonical item truth.
Entry points: resolve_prediction → pending removal → adopt_authoritative; duplicate-authority callers project_authoritative/adopt_authoritative; timeout path expire/_expire_predictions.
Cause: duplicate revision+checksum fast path only expires predictions. When resolve_prediction already removed an entry, expiry changes nothing, so the cached presentation still contains that removed prediction. The method returns success without rebuilding from canonical authority and surviving predictions.
Canonical fix location: same-revision/same-checksum branch of adopt_authoritative. Rebuild derived projection with authoritative_changed=false. This does not advance revision, rewrite checksum, confirm unrelated predictions by snapshot or mutate authoritative data.
Sibling controls: independent pending predictions survive, repeated acknowledgement is idempotent, duplicate snapshot expiry clears overlays, higher-revision rebase remains valid, conflicting/stale snapshots remain rejected. Keep existing NX5/NX6 assertions and exact V0 native tests.

## Acceptance and boundaries

The original failing baseline must stay in evidence. Both post-fix comparison roots use the exact same proposed journal bytes; their sole differential remains the V0 M4 facade. Record journal original/fixed hashes separately from the explicit type-only NX composition adapters. Raw frozen NX compilation is still NOT declared passing or accepted.

The repair changes one existing implementation, not a new FIX layer, subclass, authority, manager or alternate journal. It requires independent review of the real source diff and the evidence. Clearance proposal remains PROPOSED until independent dependency review; canonical global closure additionally requires human merge and post-merge Project Control SUCCESS.

Resume: implement journal duplicate-authority rebuild; run negative pre-fix and positive post-fix focused controls, full paired NX/V0 compatibility and fail-closed control projection. Then freeze clean repair candidate and request fresh independent review.
