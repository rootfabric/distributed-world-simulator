# ECO ARCH2 A13 Parallel Prepare — Fresh Independent Verifier R1

Role: FRESH_INDEPENDENT_VERIFIER. Do not act as Implementer, Reviewer, Director, or merge approver.

## Frozen product subject

- PR: #737
- branch: `feature/eco-arch2-a13-parallel-prepare-r1`
- HEAD: `cfb10f700202e8054fddc7c802491601b6e455d4`
- TREE: `db6250cbf38cdbf63872738aaa3d72a49459ba63`
- base main: `1f8a9debc4f8838569f818faa43bdadc0f23f965`
- freeze: `freeze/eco-arch2-a13-parallel-prepare-cfb10f70-exact-r1`

Do not verify a later product HEAD.

## Reviewer gate

Fresh Reviewer R1 must be PASS on the same exact HEAD/TREE with:
- required_fixes = []
- blocking findings = 0
- review result commit = `b264ccf831d9ebf8de363895df749772806f76ef`
- GitHub review id = `5406845797`

## Required machine evidence

Workflow:
`ECO ARCH2 A13 Parallel Prepare Exact`

Run:
`37210363778`

The verifier must require BOTH matrix jobs to complete SUCCESS on the frozen HEAD.

Expected stage counts on each platform:
- Parallel Prepare = 93 / 0
- Activity = 122 / 0
- Spatial = 108 / 0
- A13 Exact Worksets = 58 / 0
- A12 = 38 / 0
- A11 = 171 / 0
- tracked checkout clean after execution

Windows evidence already available:
- job = `111460134210`
- runner = `desktop-qnagsti-eco-runner`
- artifact = `11306517587`
- artifact SHA256 = `9c3378bfc3cd476c92d02a56f440556828074f7b681f4a43ee29726d1f29ad27`

Linux evidence is mandatory before VERIFIED and must come from the Linux matrix job of the same run.

## Required control evidence

- Project Control run `37210363845` = SUCCESS on exact HEAD
- includes full Harness regression, PC0 and directional audit
- A10.5 Windows exact run `37210363818` = SUCCESS
- final main drift must be checked after Linux completion

## Verification questions

1. Are Windows and Linux jobs bound to exact product HEAD `cfb10f70...`?
2. Do both use canonical Godot 4.7.1 double binaries with expected SHA256?
3. Does Parallel Prepare report 93 checks / 0 failures on both platforms?
4. Does the test prove worksets execute off main thread for worker bounds 1/2/4/8?
5. Are serial and parallel field/population/propagule bytes and hashes exact?
6. Is repeated threaded execution deterministic?
7. Is population input permutation invariant?
8. Do invalid worker bounds and stale spatial plans fail closed?
9. Is 8-tick reproduction+mutation runtime byte/hash exact to serial execution?
10. Are checkpoint bytes identical and scheduler/thread metadata absent from canonical Runtime/checkpoints?
11. Does Activity cadence catch-up remain exact through the parallel-prepare path?
12. Do Activity/Spatial/A13/A12/A11 regressions all pass on both platforms?
13. Is tracked source clean after both jobs?
14. Is Fresh Reviewer PASS still exact-head fresh?
15. Is Project Control SUCCESS on the same product HEAD?
16. Has main drifted since the product freeze?

## Verdict contract

Only publish:
- `VERIFIED` if all mandatory evidence is complete and exact;
- otherwise `NOT_VERIFIED` or `INSUFFICIENT_EVIDENCE`.

Do not infer Linux success from Windows evidence.
Do not merge PR #737.
