# EVO ARCH2 A7 — Integration Repair R6

Дата: 2026-09-13. Parent Work Order: `EVO-ARCH2-A7-MAIN-INTEGRATION-20260913-R1`. Risk: HIGH.

## Evidence and recovery anchor

Fresh independent review on HEAD `9a4c96a7eba19e25cc262161d2811e2f671537f7`, TREE `9527a919a7ff5ce0d858f61991a499f4a2742ea7`, found P1 `3999322861` and `3999322864`. R5 fixed the dependency and complete-history defects, but is NOT integration-accepted. Project Control `34750314289` succeeded with 325 Harness tests and explicit YELLOW audits; the separate exact execution `34750348246` remains evidence only for that historical R5 subject. Neither result overrides these review findings.

The closure finding repeats historical comments `3998402438` and `3998418167`; this repair must close the underlying family rather than respond only to the latest comment.

Main/base remains `7dfc68ab5a1e90254a1b7039807f275b5da04eef`. Accepted A7 remains `8eccf6304078bec3a3ccaa5860c5aab6ee311209` / `24e876b7377cb3e1e521f08ff9766331fe4e895a`.

## Repair Map and design

### R6-01 — frozen resource closure

Owner: integration verifier. Entry: production exact CLI before Godot import. Callers/siblings: transferred source enumeration, recursive res:// dependencies, main-owned dependencies, reused executor filesystem, generated output exceptions.

Root cause: `Path.exists()` established filesystem presence, not membership or byte identity in the frozen Git tree. Ignoring untracked paths in source cleanliness made that insufficient. Initial enumeration from filesystem glob had the same authority error.

Fix: start with the actual Git-derived transfer additions and follow resource dependencies recursively. For each input, resolve an exact literal path in the frozen HEAD tree; require a regular blob rather than a tree or symlink, reject noncanonical/traversal paths, require a regular on-disk file with no symlink components, and compare unfiltered working bytes with its frozen blob. Missing objects and Git errors fail closed. Untracked or staged-only files cannot establish closure. Resource source enumeration must not depend on extra executor files.

Generated exceptions are restricted to the named Observatory PNG/report outputs, not arbitrary scripts under an artifacts prefix. Outputs referenced this way must actually be produced by the runtime tests. Accepted source bytes and all runtime tests remain unchanged.

Negative controls: absent/untracked/staged-only input; altered tracked bytes; Git command error; non-blob/symlink/path traversal; untracked transitive dependency; a generated-looking script. Positive controls: exact regular blob, recursive closure, dependency cycle termination, explicitly classified report output. Tests invoke the production helper on disposable real Git repositories.

### R6-02 — mandatory focused test completeness

Owner: production verifier, not the external workflow wrapper. Root cause: standalone R5 verifier accepted >=20 discovered tests despite the mandatory 27-test contract. R6 requires EXACTLY 27 R5 tests, no skips/errors, and an unambiguous successful unittest footer. New R6 tests are a separate suite with EXACTLY 21 required tests; they do not replace any R5 tests or full Harness tests.

Negative controls: counts 0/20/26/28, skipped test, failure/error, absent/ambiguous footer. Positive control: exact 27-test successful footer. The exact CI wrapper repeats these requirements but is not their sole authority.

## Scope and post-build check

Allowed edits: existing integration verifier; new `test_repair_r6.py`; this repair map; existing integration Work Order. Validation orchestration remains separate on `validation/eco-arch2-a7-main-integration-r1`.

Preserve canonical jsonschema 4.22.0, complete ancestry guard, direct accepted byte comparison, approved Godot, all A0–A7 and A5 repair suites, restart/repeats, actual graphics, complete 325+ Harness tests, explicit GREEN/YELLOW controls, and final exact clean seal. No accepted runtime, production, network, architecture, scheduler or additional main-owned file modification. The existing scene-guard repair stays pinned to its accepted integration blob.

Post-build critique must check that closure reads frozen input bytes, that no artifact prefix becomes an executable-source exemption, and that standalone CLI enforces the entire test contract. New evidence is appended on the validation branch after the new source freeze; R5 evidence is not rewritten.

## Continuation

Last durable predicate: R5 implementation/preflight/Project Control complete; fresh review FIX_REQUIRED. Next: implement R6, freeze new source HEAD/TREE, run focused + full exact Linux R7, obtain a fresh independent whole-integration review, inspect artifact bytes and record actual closure diagnostics. Main merge, A8 dispatch and production promotion remain separate human gates. No independent self-accept or MISSION_COMPLETE is claimed.
