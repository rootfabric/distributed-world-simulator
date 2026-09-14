# MVP5 control-driver repair R2 — separate read-only carrier

## Exact product remains frozen

Product branch `feature/v0-mvp-playable-seamless-planet-r1` remains at HEAD `e3dacd617ede4cca7402ff25c125fa85bd76283f`, TREE `dfbef93c5b556499ab7edd3057ccf2900d52cb0f`. Parent `V0-MVP-R1-WO-001` remains IN_PROGRESS. This document/workflow is on a separate control carrier, not a new product candidate, runtime worker or acceptance record.

Carrier branch: `control/v0-mvp5-exact-driver-r1`, based on the exact product subject. It changes only the already authorized named read-only MVP5 workflow and this documentation. It does not add a new workflow wildcard, canonical owner or remote ref reset. The workflow is not intended to be merged into the product: it checks out the pinned product commit, not the carrier commit, and records BOTH product HEAD/TREE and driver HEAD/branch.

## Retained failure

Legacy control-drive job `103945116141` / run `34834494229` on product e3dacd61 failed before Resume/Drive. Raw status.log: `GIT_STATE_INVALID / GIT_BRANCH_UNAVAILABLE`. Checkout used a commit SHA and left detached HEAD; Harness requires a named execution branch. Artifact `10343453332`, ZIP SHA-256 `a0277dc6fb4cbf41d10aae84ee4dbcf5472d20fc0677f8ef99a2d46c88c9cef7`, was downloaded and inspected. This remains a failed driver execution; it is not reclassified as product success.

## Bounded correction

Inside the disposable CI checkout only, bind the actual Work Order branch name to the already-pinned product HEAD. First verify live origin/feature still equals that HEAD, then assert symbolic branch name, exact HEAD and exact TREE before and after Status/Resume/Drive. The carrier workflow has read-only contents/actions permissions and checkout does not retain credentials. No remote branches or old execution events are rewritten. No Harness gate, assertion or contract is relaxed.

Product runtime, tests and workflow source bytes stay unchanged at e3dacd61. The failed legacy control job can coexist with a later successful corrected driver on the SAME exact product subject; evidence must distinguish their provenance and verdicts.

## Already consumed runtime evidence

MVP5 exact run `34834494181`, job `103945115676`: SUCCESS. Artifact `10343189749`, ZIP SHA-256 `3f2989ad00bd116b6141f3ed45218071a38e0814825e4eaf85d6f2f84d5d2798`, downloaded and all 95 manifest members rehashed (96 ZIP members including manifest). Focused real-engine tests: 270 assertions, four cases, no failures. Native-accounting consumer: 47 checks, ten corruptions rejected. Five-process graphical evidence: 68 checks, 19 corruptions rejected, both HUD-only falsifiers rejected; each client has 198 changed terrain pixels outside actual UI, threshold32 unchanged. General engine ERROR markers absent from new graphical child logs. Unchanged MVP4/MVP3 validator and its exact baseline cleanup comparison PASS.

Measured graphical output: A=19786 item/ore units, B=0; residual 0.9909632145936484 kg follows the existing policy. One fresh issuance followed by two identical replay receipts; Item Graph revision stays7. Both clients display the same server-derived result.

This is Implementer/CI evidence, not an independent verdict. Full world/core is separately running on e3dacd61 and is not yet claimed here. Fresh Reviewer/Verifier, exact Project Control and coordinator leaf publication remain separate gates; whole-MVP acceptance and main merge are not authorized.
