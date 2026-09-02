# V0 P7.5 — Windows Exact Runtime Validation R1

Role: local Windows execution agent. This is execution evidence only; it is not an independent Reviewer or Verifier verdict and does not authorize merge.

## Frozen runtime subject

- branch: `feature/v0-p7-bounded-terrain-mutation`
- HEAD: `ba8210a8d3cddf084a573f2e862982d3f76c37c9`
- TREE: `f35e3a1acbe587de6a8f9bb9cef1f3949d5eea53`
- runtime PR: #435
- exact Project Control: `33523992483 = SUCCESS`

Do not modify, rebase, repair, cherry-pick, or merge the runtime subject during this execution.

## Required Godot

Use only `4.7.1.stable.double.custom_build.a13da4feb`.
Canonical Windows console binary: `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`.
Expected SHA-256: `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`.
Verify both `--version` and SHA-256 before execution.

## Fresh checkout

Create a brand-new detached worktree at the frozen HEAD, suggested path `C:\dws-p7-5-runtime-validation-r1`.
Do not reuse Implementer, Reviewer, P7.4 verifier, or earlier P7.5 worktrees.
Before execution prove exact HEAD, exact TREE, and tracked-clean.
Untracked Godot-generated `.gd.uid` sidecars after import are allowed; tracked mutation is not.

## Canonical command

From the fresh detached worktree run this exact PowerShell command:

`& .\RUN_V0_P7_5_TWO_CLIENT_CONVERGENCE_GATE.ps1 -GodotExe "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" -ExpectedHead "ba8210a8d3cddf084a573f2e862982d3f76c37c9"`

Do not impose an external timeout. P7.4 restart phases and transitive regressions must finish naturally.

## Required stages

The gate must freshly complete all 16 stage checks: P7.5 two-client convergence; M7 aggregate replica compatibility; P7.4 seed; P7.4 recover-deliver; P7.4 recover-replay; P7.3 material delivery; P7.2 lunar Matter bubble; P7.2 lunar surface seam; P7.1 authority gate; P7.1 Tool→MW4; P5 two-client replication/reconnect; P5 mining tool; MW6; MW7; RL2; RL3.

Expected evidence set: import log + 16 stage logs = 17 logs total.
Expected focused marker: `V0-P7.5 two-client convergence: PASS (85 assertions, 0 failures)`.
The new M7 aggregate replica regression must also PASS.

## Fatal scan

Scan all 17 logs for: `SCRIPT ERROR:`, `Parse Error:`, `Compile Error:`, `Failed to instantiate an autoload`, `Failed to load script`.
Any occurrence means RED even if PASS text exists elsewhere. Record SHA-256 for every log.

## Required final banner

`V0-P7.5 TWO CLIENT CONVERGENCE GATE GREEN`
`EXACT_HEAD=ba8210a8d3cddf084a573f2e862982d3f76c37c9`
`GODOT=4.7.1.stable.double.custom_build.a13da4feb`

## Diagnostic context only

Do not inherit this as execution proof: exact Linux source/Godot identity was verified; focused P7.5 passed 85/85; M7 aggregate replica regression passed; Linux full gate exceeded the container execution window while entering inherited P7.4 seed. Windows R1 must execute all stages itself.

## Result

Return actual HEAD/TREE, Godot version/SHA, gate exit code, final banner, all 16 stage PASS summaries, fatal scan result, SHA-256 manifest for all 17 logs, tracked-clean before/after, and exact failing log/stage if RED.

Do not merge PR #435. Do not declare P7.5 COMPLETE_MERGED. Do not start P7.6.
