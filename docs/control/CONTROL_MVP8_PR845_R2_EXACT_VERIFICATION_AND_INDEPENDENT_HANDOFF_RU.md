# CONTROL MVP8 — reviewer finding R1 FAIL, narrow R2 repair: final implementer exact evidence

**Original failing reviewer subject** PR #839
`a2a8e93f065f9cee8fc8a39eb03df29be322c786` / TREE `e4622f57ec1b86d9193f0675c96f8e67cd9c1d97`.
**Current narrow repair subject** [Draft PR #845](https://github.com/rootfabric/distributed-world-simulator/pull/845):
`3a8f858f85c5ff018676557650f34179d6d5f86b` / TREE `f03f89297f1cb97ed4df9b4b8ecedfc1fef2aec3`.
Stacked lineage: canonical main `aac301b9a9a89e027f6d99864437eb750a4202ca` → Draft #834 schema repair `a5ef36a17...` → Draft #839 Reviewer witness R1 `a2a8e93...` → Draft #845 R2 `3a8f858...`. None merged.

## Independent adversarial original RED (Reviewer FAIL)

[Review-only GitHub Actions run 40063151255](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40063151255),
[durable report on PR #839](https://github.com/rootfabric/distributed-world-simulator/pull/839#issuecomment-6379959426):
- In disposable **named** Git worktree, original `external-role-event-witness.v1.json` is removed from actual local HEAD by a disposable commit and restored ONLY as an ignored untracked file.
- `git cat-file -e HEAD:<witness>` fails; `git status --porcelain -- <witness>` is empty.
- Unmodified old Harness `-Status` incorrectly returned **EXIT=0, OK=True**, admitting a non-ancestor Reviewer event using non-Git-backed local bytes.
- Expected fail-closed test correctly failed 1 assertion. This establishes a **blocking violation of GIT IS DURABLE MEMORY**, not a spurious expired worktree/runner failure.

## R2 repair — strict, no broad ancestry relaxation

Four-path diff vs frozen PR #839:
1. `scripts/harness/state_builder.py`: before decoding the privileged witness, require `git --no-replace-objects rev-parse HEAD:<manifest>` (valid committed object), `git --no-replace-objects hash-object --no-filters -- <path>` to match the live exact bytes, and single initial-add commit with no rewrite. Existing status, unchanged reviewer/event Git SHA and one-direct-child checks remain.
2. Normative four-case test: authentic committed witness positive, ignored-untracked negative, modified `assume-unchanged` live bytes negative, committed rewrite negative.
3. Additive scoped Linux/Windows exact workflow.
4. Bounded Repair Map.

**No edits** to original historic reviewer/event/manifest, Evidence Map or canonical transition table, Godot/physics, FABRIC, root main, or global architecture.

## Canonical published-head CI and source evidence

[GitHub Actions run 40063985232](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40063985232): **scope / windows / linux = 3/3 SUCCESS**.
- On **Windows**, R2 new **4/4 PASS** (expected precise errors: ignored untracked `EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_COMMITTED`, altered `assume-unchanged` `EXTERNAL_REVIEW_WITNESS_MANIFEST_DIRTY`, rewritten persisted record `EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_IMMUTABLE`); inherited original Reviewer-witness **6/6 PASS**; exact native `CONTROL_DEVELOPMENT.ps1 -Status` exit 0/ok=true, `-CheckConsistency -Candidate` exit 0/ok=true.
- On **Linux**, R2 new **4/4 PASS**, inherited **6/6 + 5/5 PASS**, entire Harness **397/397 PASS**; exact CLI `status` exit 0/ok=true, `check-consistency --candidate` exit 0/ok=true. No source edits in acceptance executors.
- CI scope asserts exact original parent and only four changed paths. `git diff --check`, Python parse and original event/receipt/witness blob preservation PASS.
- Linux PC0 standard: exit 0, **overall YELLOW**. Directional PC0: exit 0, **overall YELLOW** (non-RED). Existing global critical directional V0→NX hit was accepted under its specific clearance `V0-MVP6-NX-POSTMERGE-CRITICAL-WATCH-CLEARANCE-005`; other YELLOW watch findings remain. Some advisory research programs may individually report RED while *blocking global overall* remains YELLOW. The audits were invoked with documented `--no-fail-on-red` for diagnostic capture, so the truth comes from JSON `overall_health`, not tool exit code alone.
- `-CheckConsistency` reported `ok=true` and three findings in product overview, none triggered product-blocking error. This is not a blank/green-everywhere project health guarantee.
- Both PC0 and CheckConsistency results are machine diagnostics on the frozen **control candidate**, not separate PC0 role signatures or a human main merge approval.

[Actions raw artifact 12548449034](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40063985232/artifacts/12548449034), SHA256 `7cb5c393a04a2429bd5a0ff007b8a407a7cc7a0572239d09edd9841bad18a399` independently downloaded and matched. It contains `check-consistency.jsonl`, standard+directional PC0 raw logs and JSON reports. Internal `reviewer-evidence/SHA256SUMS` **3/3** hashes independently recomputed MATCH.

## Review state and remaining hard gates

**OLD R1 exact `REVIEW_FAIL`** (documented); **R2 implementer exact `PASS_WITH_FINDINGS`** for security/provenance boundary. This assistant session executed R2 repair and verification, so it **cannot independently sign off its own repair** as separate-actor Reviewer/Verifier under the Harness separation rule.

Require fresh independent reviewer challenge on **new** `3a8f858...` (Git replacement refs, head staging, EOL conversions, immutable-manifest policy; attack on forged event/receipt), a separate verifier source+Windows/Linux evidence audit, and post-integration canonical-main and PC0 checks. Parent #834/#839 remain Draft; human merge gate required. **MERGE_READY=false; no main change.**

Next work order: fresh Reviewer and separate Verifier on exact repair HEAD/TREE; do not replay old PASS/signoffs from PR #839.
