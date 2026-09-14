# MVP5 — exact implementation evidence and fresh Verifier handoff

## Frozen subject and current boundary

Repository `rootfabric/distributed-world-simulator`, PR #597 (DRAFT). Parent `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`, remains **IN_PROGRESS**, risk **CRITICAL**.

```text
product branch = feature/v0-mvp-playable-seamless-planet-r1
product HEAD   = e3dacd617ede4cca7402ff25c125fa85bd76283f
product TREE   = dfbef93c5b556499ab7edd3057ccf2900d52cb0f
MVP4 base      = d78760738e8032b97de2a433382fc7ddafa17fbf
main observed  = 9e10e640ffc53f82195f1fd930ebafbbc85e482f
```

This evidence-only carrier is **not the product candidate**. It does not move the feature ref, edit old events, merge to main or close a predicate. MVP1–MVP4 remain verified; MVP5 is implemented and targeted-tested, but a fresh independent runtime verdict and coordinator publication are still separate requirements.

Machine-readable map: `MVP5_EVIDENCE_E3DACD61_R1.v1.json` beside this document. All ZIP hashes in that map were computed from downloaded archive bytes; all runtime/control manifest members were rehashed. Use live GitHub metadata and independent byte checks rather than trusting these statements.

## Implemented behavior

One existing native Matter owner commits excavation. Existing P7 conversion and the canonical M4 Item Graph output/replay ledger issue the material. The MVP5 adapter reconstructs the original issuance receipt with pure owner reads, without calling delivery again just to obtain metadata. No second inventory, delivery ledger, receipt database, mutation owner or client-side carve was introduced.

The receipt distinguishes a replayed Matter commit from an Item Graph replay: following failure before output application, the retried Matter operation can still perform the first successful item issuance. Following a successful item write with lost acknowledgment, retry returns the same item id/quantity without another graph revision or tick. A late retry after another legitimate native operation also remains idempotent. Original issuance provenance is deliberately distinct from the item's later current location or remaining quantity.

Both actual graphical clients read the same bounded projection of the real canonical graph. The five-process scene executes one prepared dig three times, preserves native input and read-only terrain replicas, and confirms the actual terrain change outside the entire live UI rectangle. UI displays server-derived quantities without optimistic local increments. The prior MVP4 authority keeps its original default; only a small factory hook selects the MVP5 bridge in the new scene.

## Completed measurements on the frozen subject

| Check | Evidence | Result |
| --- | --- | --- |
| Exact MVP5 focused + graphical + unchanged MVP4/MVP3 | Run 34834494181, artifact 10343189749 | SUCCESS; 95/95 raw data members rehashed |
| Four actual canonical failure-window cases | `focused.json` and raw log | 270 assertions, zero failures |
| Independent consumer of raw native snapshots (not an independent role) | `native-accounting.json` | 47 checks, 10 deliberately corrupted evidence cases rejected |
| Real five-process graphical composition | `graphical/manifest.json` | 68 checks, 19 corrupted-evidence cases rejected, two HUD-only falsifiers rejected |
| Terrain visibility | Raw PNGs and unchanged pixel validator | A=198 and B=198 changed terrain pixels, threshold32 unchanged |
| Fresh exact static review | Codex result comment 5662755640 | No major issues on e3dacd617e; not a runtime-verifier verdict |
| Complete Harness discovery and both PC0 audits | Run 34834499763, artifact 10343234205 | 349 tests OK; CI SUCCESS; both reports YELLOW/non-RED |
| Exact branch-aware Status/Resume/Drive | Separate driver run 34835266121, artifact 10343634235 | All three `ok=true`, actual e3 product and named feature branch, clean checkout |

The graphical fixture produced one `item/ore` item with quantity19786 for A, quantity0 for B; two subsequent deliveries returned the same issuance. Revision remained7. Fractional residual `0.9909632145936484 kg` is explicit under the existing P7 floor-kilogram policy. This measured fixture quantity is not a gameplay balance recommendation.

Full world/core run34834494229 / job103945115991 was still **IN_PROGRESS** when this map was recorded. Neither its old predecessor PASS nor targeted validation is a substitute for its actual terminal result. A literal >=1800-second soak and `main_scene_cli_all` must be present in fresh raw output before PASS is claimed.

## Retained failures and bounded repairs

The first complete graphical candidate d5e23b42 failed. Adding a material HUD row enlarged the UI mask and covered the small visible hole; unchanged visible checks correctly rejected it. The repair reused the existing final HUD row without changing camera, brush, terrain fixture, UI exclusion or threshold. Raw audio/cache errors also revealed a log-consumer gap; isolated per-child profiles, Dummy audio and general ERROR rejection repaired that test environment without suppressing runtime failures.

The legacy control-drive job103945116141 failed on e3 because exact-SHA checkout left detached HEAD. A separate read-only carrier `control/v0-mvp5-exact-driver-r1` at150cd379 checks out unchanged e3 and locally attaches the actual Work Order branch name. It proves both HEAD and TREE before/after control execution and records driver provenance separately. No remote ref reset or product commit was made. The failed original job stays failed; later driver success is not retroactive rewriting of that run.

The PC reports are **YELLOW/non-RED**, not uniformly GREEN. Canonical V0 passport tested-head declarations remain pending, and unrelated directional WATCH_HIT entries remain visible. Successful control commands do not mean whole-checkpoint acceptance or unrestricted runtime authorization.

## Post-build critique — Implementer

The main correctness risk was a split effect: Matter mutation can commit before Item Graph delivery finishes. Reusing canonical replay ownership is safer than a compensating second carve, local balance or new replay table. The test proxy injects failures around the REAL output port and recorded raw native snapshots prove the two sides of the write boundary.

A receipt/projection comparison alone could be a shared false positive. The added native-accounting consumer therefore verifies actual raw item additions, unchanged pre-existing items, inventory membership, native revision/tick and both failure windows, and must reject ten corruptions. Graphical terrain proof independently retains the prior HUD-only falsification.

Remaining boundaries are explicit: injected port failures are not process-crash or disk-durability tests; this does not close MVP7 restart/reconnect. The material view has strict fixed-scene budgets, not a generalized unbounded inventory API. The automated observable scene does not prove physical-keyboard/manual gameplay acceptance, item-bearing seam or multi-region excavation. Static review is not independent runtime verification. No stronger claims should be made from this implementation.

## Fresh independent Verifier task

Act as a **new read-only VERIFIER**, not Implementer or the static Reviewer. Do not edit source, push to feature/main, merge, rewrite history or old events, start a second runtime worker, or publish PREDICATE_VERIFIED.

1. Live-check PR#597 HEAD/TREE and named feature ref against the frozen subject. Read `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, the parent Work Order and existing review/evidence contracts. If subject drifted, do not silently retarget or accept historical evidence.
2. Read the bounded MVP5 diff from d7876073 and the design/repair documents. Verify unchanged canonical Matter/M4/P7/SM1 ownership and old MVP1–MVP4 events, the bounded workflow authorization, and the absence of a second inventory or replay owner.
3. Independently download artifact10343189749; match ZIP digest and every manifest member against GitHub and recomputed bytes. Bind head, tree, actual engine hash and clean checkout. Re-evaluate raw native snapshots and receipts, not only `passed:true`, using the evidence consumers plus independent spot checks.
4. Check the real output-port failure windows, authentic actor/session/frozen-source rejection, altered replay fingerprint, late replay after another native operation, conserved mass with explicit residual, and no extra item/revision/tick/Matter change on retry. Inspect raw client logs, actual PNGs, full UI mask/HUD falsifiers, five unique real processes and shared canonical material values. Compare inherited MVP4/MVP3 execution and exact historical cleanup-baseline classification.
5. Independently consume artifact10343234205 and the 349-test job log. Verify non-RED, not imagined all-GREEN; record actual YELLOW findings. Independently consume corrected driver artifact10343634235, checking e3 product vs150cd driver provenance, local named branch, all three `ok=true`, immutable old events and no premature MVP5 closure. Preserve the legacy failed driver as a distinct failure.
6. Read the live full-world-core job103945115991 in run34834494229. When terminal, download its raw artifact, rehash all declared files, and require exact e3/dfbe/pinned engine, no failed/nonzero steps, literal soak>=1800 seconds and `main_scene_cli_all` PASS. If still running or unavailable, record that gate as pending; never infer it passed.
7. Return `VERIFIED` only when the required evidence is actually consumed and all scope gates are met; otherwise return precise `FIX_REQUIRED` or `NOT_VERIFIED` with missing evidence. A tool access failure is not a runtime defect. Report concrete file/line and reproducible failures separately from optional improvements. Independently executed commands must be distinguished from consumption of existing raw CI artifacts. Store a verdict on a separate verifier/evidence carrier or in the PR discussion; product remains frozen.

After a qualifying independent verdict and fresh required control checks, Coordinator may publish a **leaf** MVP5 PREDICATE_VERIFIED event using the repository's exact-subject rules. Parent stays IN_PROGRESS; this does not authorize main merge or whole-MVP acceptance. Do not mutate feature merely to store preliminary evidence and recreate the earlier stale-HEAD incident.

## Visible local launch

From the feature checkout with the repository-pinned double Godot available:

```powershell
.\RUN_V0_MVP_MATERIAL_OUTPUT.ps1 -GodotBin $env:GODOT_BIN
```

This opens the automated observable two-client scenario and preserves its evidence. It is not a manual-input acceptance claim. Linux graphical CI uses Xvfb, the same pinned double engine and the Python integration runner. Exact subject/clean checkout checks are intentional.
