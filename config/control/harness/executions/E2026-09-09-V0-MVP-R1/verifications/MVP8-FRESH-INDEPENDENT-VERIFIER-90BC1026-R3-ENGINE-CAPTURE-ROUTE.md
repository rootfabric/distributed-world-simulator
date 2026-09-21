# MVP8 Fresh Independent Verifier R3 — Exact Engine Capture Route

Role: **FRESH INDEPENDENT VERIFIER R3**. This file defines an evidence transport route only. It does not change product source, acceptance criteria, or the required Windows Godot identity.

## Frozen product

- HEAD: `90bc1026f0f5749492107191233330f87c8c70df`
- TREE: `4b6f2d48f7ef8d9c441ae89d2cbb02c730ef7f71`
- freeze: `freeze/v0-mvp8-review-90bc1026-r1`
- Reviewer PASS: `b8daebf27e11938a3c4432a127f384290e3255dc`
- R1 verifier: `502f5ea8d12f97b89577bc28d57f473918fe8f16`, verdict `EVIDENCE_GAP`

## Why this route exists

The repository self-hosted Windows executor is not currently accepting queued jobs reliably and the prior verifier documented host-level multi-process interference.

A source rebuild on GitHub-hosted Windows is not equivalent evidence: the Windows Server 2022 probe built the exact Godot source commit and exact version string, but produced console SHA-256 `7608b77a798a66f3ff6a89e8a0e8001aa044fca162a324676215b3294b21d891`, not the canonical required SHA.

Therefore R3 must transport the already-installed canonical binary; it must not substitute a rebuilt binary.

## Canonical Windows Godot

Required console executable:

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Required identity:

- version: `4.7.1.stable.double.custom_build.a13da4feb`
- SHA-256: `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`

## Stage A — minimal self-hosted capture

On the self-hosted Windows runner:

1. Do not run MVP8, world/core, VMs, LLMs, or other simulation workloads.
2. Verify the installed console executable version and SHA above.
3. Pair it with `godot.windows.editor.double.x86_64.exe`.
4. Copy the pair to a clean staging directory.
5. Re-run `--version` from the staged console executable.
6. Re-hash both staged files.
7. Write a capture manifest binding source path, version, console SHA, editor SHA, byte sizes, runner name, run id and attempt.
8. Upload only the staged canonical pair + manifest as a same-run Actions artifact.

If the console SHA is not exact, stop with `EVIDENCE_GAP`. Do not rebuild or replace it.

## Stage B — clean hosted Windows closure

On a GitHub-hosted Windows runner in the same workflow run:

1. Download the Stage A artifact.
2. Re-hash the console and editor executables.
3. Require console SHA exactly `3633c3e6...`.
4. Require captured editor SHA to match the downloaded editor SHA.
5. Checkout the frozen product HEAD/TREE exactly and require tracked source clean.
6. Run `tests/integration/test_v0_mvp_8_bounded_workload.py` using the downloaded canonical console executable.
7. Immediately snapshot and hash all raw MVP8 output, including all 11 per-role JSON files and manifest.
8. Require manifest PASS, 20/20 positive checks, 14/14 negative controls, no fatal logs, exact subject.
9. Run `RUN_WORLD_REGRESSION_TESTS.ps1` with bounded MVP7 produce roots exactly as specified by R2.
10. Require exit 0, summary PASS, declared == discovered, every step green.
11. Preserve logs, raw files, summary and hashes.
12. Require tracked source clean after.

## Verdict rules

`VERIFIED` is permitted only if:

- exact frozen product identity is unchanged;
- Reviewer PASS remains exact/fresh for the frozen subject;
- Stage A canonical console SHA is exact;
- Stage B downloaded console SHA is the same exact canonical SHA;
- Stage B Windows MVP8 exact runtime PASS;
- Stage B Windows full world/core PASS;
- existing Linux full world/core PASS is corroborated: run `35515256366`, job `106089996971`, artifact `10607661947`;
- existing PC0 standard/directional are non-RED: run `35513137221`;
- source is tracked-clean before/after;
- no blocking evidence gap remains.

If Stage A cannot execute because the self-hosted runner remains offline, verdict stays `EVIDENCE_GAP`.

If Stage A runs but the installed canonical hash is wrong, verdict stays `EVIDENCE_GAP`.

If Stage B shows a reproducible frozen-product failure with the exact captured canonical binary on a clean hosted host, use `FIX_REQUIRED`.

## Durable verifier result

Write only verifier evidence to:

`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP8-INDEPENDENT-VERIFICATION-90BC1026-R3.v1.json`

Suggested branch:

`verify/v0-mvp8-90bc1026-r3`

Do not publish `MVP_BOUNDED_INTERACTIVE_WORKLOAD=PREDICATE_VERIFIED`; Director closes the leaf after the fresh verifier result.
