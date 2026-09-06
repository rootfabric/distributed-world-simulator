# PROJECT-FOCUS POST-MERGE REPAIR — VERIFIER HANDOFF

Role requested: **FRESH INDEPENDENT VERIFIER**

This branch is evidence-only. It MUST NOT modify source or merge PR #575.

Frozen subject:

- HEAD `ba2679c2e342e2e5ccabee1c7f8cdd4fc202d968`
- TREE `04679a6e67fc86ec156d4341140fd5b0225d6085`
- base/main `ce782cfff4293b4b6d88bdb237e7bdf99cf9688c`
- source PR `#575`

Exact machine evidence:

- Project Control run `34033113340`
- result `SUCCESS`
- full Harness `266 tests / 0 failures / 0 errors`
- standard PC0 `YELLOW`, no blocking RED
- directional PC0 `YELLOW`, no RED
- artifact id `9989281539`
- uploaded ZIP SHA-256 `158336aa99799e7f87ca387461f77d946dcf7b128a9f2d80601e05bed9b8f7a9`

Fresh Reviewer on exact subject completed with no major findings (`Codex Review: Didn't find any major issues. Nice work!`, reviewed `ba2679c2e3`). Reviewer evidence is NOT a Verifier verdict.

Verifier must independently establish:

1. a branch HEAD already contained in `origin/main` is excluded only from concurrent overlap while historical/source scope remains visible;
2. two genuinely unmerged branches sharing runtime/contract scope still become RED;
3. if a previously merged branch advances, it immediately re-enters overlap;
4. inherited old `coordination.observed_main` is tolerated only when Git topology proves current canonical main is an ancestor of candidate HEAD;
5. main advancing after candidate still yields blocking `CANDIDATE_MAIN_DRIFT`; unresolved ancestry fails closed;
6. the live proposed-R3 standard/directional regression is non-red on the exact subject;
7. PR #575 changes no runtime/scenes/P7 execution/evidence/acceptance semantics.

The current verifier reuse policy permits a fresh Verifier to consume digest-bound exact machine evidence. Re-execute only checks needed to establish missing mandatory predicates.

Required durable result in PR conversation:

```text
PROJECT-FOCUS POST-MERGE INDEPENDENT VERIFIER
verdict: PASS / FAIL / INSUFFICIENT_EVIDENCE
subject_head: ba2679c2e342e2e5ccabee1c7f8cdd4fc202d968
subject_tree: 04679a6e67fc86ec156d4341140fd5b0225d6085
ci_run: 34033113340
artifact: 9989281539
artifact_sha256: 158336aa99799e7f87ca387461f77d946dcf7b128a9f2d80601e05bed9b8f7a9
findings: ...
checks_inspected_or_reexecuted: ...
checks_not_run: ...
```

A PASS authorizes only the next human merge gate for PR #575. It does NOT declare P7 accepted or activate MVP.
