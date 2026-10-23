# ENGINE48 Windows R2 — bounded CI identity and hash repair

**Статус:** IMPLEMENTED_CANDIDATE / NOT_EXECUTED_ON_WINDOWS / FRESH_VERIFIER_REQUIRED / NO_MERGE.
**Parent:** `fecc13c5c90cc70c68521fdc016e836b48fe3a7b` (Windows R1 PR #806).
**Migration root:** `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9` (PR #794).
**Source engine:** Godot `4.8.beta1.double.custom_build.4d10419ca` (`precision=double`, `x86_64`).

## Why repair is required

1. R1 verification workflow checked `git rev-parse HEAD == a936412c...` even when running after the migration candidate advanced to R1 Windows commit `fecc13c5...`. An exact-head run on the accepted R1 branch would be rejected before tests.
2. R1 workflow exposed `godot48_console_sha256` but did not actually use `Get-FileHash` to enforce this identity. A matching `--version` alone is insufficient.
3. R1 local PowerShell runner allowed empty `ExpectedSha256` and silently skipped byte-level identity when omitted.
4. R1 had no artifact-upload step and failed to check cold-import native exit code; a single crash-on-exit could have been misreported as an import PASS.

## Narrow repair

- `.github/workflows/engine48-windows-r1-verify.yml` checks exact event subject (PR head or explicit `subject_sha`) and migration ancestor; no false fixed R1 head requirement.
- The verified console SHA256 is fixed to `f53f90f686a4eb05df076692c1b67a9e3d12d7c6c981cf86f1015d1ec36a2636` (confirmed Windows R1 binary). Dispatch-supplied SHA must equal this immutable pin.
- Build identity check compares the actual executable SHA256 **and** exact `--version`.
- Self-hosted executable path comes from runner `ENGINE48_GODOT_CONSOLE` or an optional, data-only workflow_dispatch path. Inputs are passed through environment variables rather than interpolated into PowerShell source.
- Cold import returns nonzero => FAIL; GDScript parse errors, missing class cache, and tracked changes => FAIL.
- Headless regression suite, MVP5, M7 and postflight remain separate gates; exact logs uploaded as GitHub Actions artifacts even on failure.
- `RUN_ENGINE48_WINDOWS_R1.ps1` also enforces the trusted binary SHA by default; passing an arbitrary hash to bypass the pin is no longer possible.
- Canonical Godot 4.7.1 workflows, `main`, authoritative gameplay kernels and imported resources are untouched.

## Separate project control issue (NOT a Godot regression)

[PR #806 Project Control run 39603470834](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39603470834) exited 3 due to `CANDIDATE_MAIN_DRIFT`:

```text
observed_main = 3d7672cba293d8e7bd72427b803f73fc8fcee5da
canonical_main = aac301b9a9a89e027f6d99864437eb750a4202ca
```

This is a **product-blocking project control finding**. The CI repair MUST NOT suppress candidate consistency checks. Integrator must refresh/reconcile main-derived control state through the supported Harness procedures and rerun the independent PC0 review on the integration candidate. This requires treating the migrated state as an explicit new candidate and resolving main drift before a final merge.

## R2 acceptance requirements

1. Fresh Windows agent runs this repair on a clean exact candidate checkout and verifies the expected binary, then reruns headless suite and MVP5/M7; retains `*.log`, `preflight.json`, `verified-binary.json` and `postflight.json`.
2. Prove negative controls: wrong SHA256 fails before import; wrong `subject_sha` fails before tests; missing binary path fails closed; known import nonzero fails; modified tracked files fail postflight.
3. Independent verifier examines final HEAD/TREE and the new workflow. Previous PR #806 comment reviewed commit `17e72f7566ae5153beb218d8903d9bf4dba2756d`; the later `fecc13c5...` was documentation-only but R2 is a new code subject requiring fresh verification.
4. No merge of Windows R2, Windows R1 or ENGINE48 migration into canonical `main` until Linux repair branch and exact-head cross-platform evidence are available.
5. NET-SMOOTH1 server p99 <=25 ms is a separate open performance goal; M7 baseline metrics do not prove it. Ubuntu WSLg/llvmpipe GUI != native real-GPU evidence.

## Operational trigger (once the workflow is present on a valid trigger ref)

Provide full product SHA and the **pinned** console SHA when dispatching manually. The runner must have access to the binary or the `godot_console_path` input. For PR events, a runner-local `ENGINE48_GODOT_CONSOLE` path is required.

Do not describe a created workflow as an executed workflow. Evidence begins only after an actual GitHub Actions run on an immutable subject.
