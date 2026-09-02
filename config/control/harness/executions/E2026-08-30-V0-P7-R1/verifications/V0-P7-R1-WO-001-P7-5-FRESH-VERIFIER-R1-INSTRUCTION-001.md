# V0 P7.5 — Fresh Independent Linux Verifier R1

Role: `FRESH_INDEPENDENT_VERIFIER_P7_5_R1`.

This actor is NOT the Implementer, NOT the Reviewer, and must not inherit execution PASS from either prior Linux execution evidence or Reviewer corroboration.

## Control parent / Reviewer gate

- verifier dispatch branch parent: exact canonical Reviewer R2 result commit
- reviewer result commit: `d4c1b36556140e8338482c251442fd8d12806022`
- reviewer semantic PASS source commit: `572134032e824c4c03806dca3056da252b461cdd`
- reviewer dispatch HEAD: `3e4e945d1984219b0b83dcd95b2a753a42cae29b`
- reviewer verdict: `PASS`
- reviewer required_fixes: `[]`
- reviewer result Project Control: `33618553668 = SUCCESS`
- runtime Project Control: `33523992483 = SUCCESS`

The verifier must verify these identities before execution. The `d4c1...` commit differs from `572134...` only by normalizing the review_type to the canonical Harness vocabulary; review semantics, verdict, reviewed HEAD/TREE and findings are unchanged.

## Frozen runtime subject

- branch: `feature/v0-p7-bounded-terrain-mutation`
- runtime PR: `#435`
- HEAD: `ba8210a8d3cddf084a573f2e862982d3f76c37c9`
- TREE: `f35e3a1acbe587de6a8f9bb9cef1f3949d5eea53`
- activation base: `1107eb81c4ff28a7ba4dda768312847ef345a448`
- exact runtime delta: 15 commits, 6 files, +1272/-4

Do not review or execute any later runtime branch head. Do not rebase, repair, cherry-pick, amend, or merge the runtime subject.

## Platform

Required platform: fresh Linux x86_64 / Ubuntu userspace.

Verify:

- `uname -s` = `Linux`
- `uname -m` = `x86_64`
- `/etc/os-release` recorded in result

## Exact Godot

Use only:

`4.7.1.stable.double.custom_build.a13da4feb`

Canonical Linux binary SHA-256:

`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

Recommended path:

`$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64`

Before runtime execution verify both:

- exact `--version`
- exact SHA-256

Do not use system Godot, single precision, Windows/Wine, another custom build, or another Godot version.

## Fresh detached worktree

Create a brand-new detached worktree at the exact frozen runtime HEAD. Do not reuse:

- Implementer worktree
- prior Linux runtime validation worktree
- Reviewer worktree
- P7.4 Verifier worktree
- any prior P7.5 worktree

Suggested path:

`$HOME/dws-p7-5-verifier-r1`

Example:

```bash
cd $HOME/distributed-world-simulator
git fetch origin --prune
git worktree add --detach $HOME/dws-p7-5-verifier-r1 ba8210a8d3cddf084a573f2e862982d3f76c37c9
cd $HOME/dws-p7-5-verifier-r1
```

Before execution prove:

- `git rev-parse HEAD` == frozen HEAD
- `git rev-parse 'HEAD^{tree}'` == frozen TREE
- `origin/feature/v0-p7-bounded-terrain-mutation` == frozen HEAD
- `git status --porcelain --untracked-files=no` empty

If any identity differs: verdict is NOT_VERIFIED / SUBJECT_IDENTITY_MISMATCH and runtime gate must not be run.

## Canonical gate

Run exactly:

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
bash RUN_V0_P7_5_TWO_CLIENT_CONVERGENCE_GATE.sh "$GODOT_BIN" "ba8210a8d3cddf084a573f2e862982d3f76c37c9"
```

Do not impose any external timeout. Let all inherited P7.4 restart and transitive regression stages finish naturally.

Do not replace the canonical gate with manual subsets if the repository-owned runner can execute.

## Required fresh stage execution

All 16 stage checks must execute fresh in this Verifier session:

1. P7.5 two-client convergence — expected `PASS (85 assertions, 0 failures)`
2. M7 aggregate replica compatibility — expected `PASS (5 assertions, 0 failures)`
3. P7.4 seed — expected 21/0
4. P7.4 recover-deliver — expected 25/0
5. P7.4 recover-replay — expected 17/0
6. P7.3 material batch to Item Graph — expected 116/0
7. P7.2 lunar Matter bubble — expected 53/0
8. P7.2 lunar surface seam — expected 50/0
9. P7.1 authority gate — expected 83/0
10. P7.1 Tool→MW4 integration — expected 30/0
11. P5 two-client replication/reconnect — PASS
12. P5 mining tool — expected 36/0
13. MW6 matter network authority — expected 130/0
14. MW7 matter interest replication — expected 114/0
15. RL2 Matter multiresolution meshing — expected 153 assertions
16. RL3 representation-aware network streaming — expected 175 assertions

No stage may be inherited from the Implementer, the previous Linux runtime execution agent, the Reviewer, or any P7.4 verifier.

## Logs / fatal scan

Expected evidence set:

- 1 import log
- 16 stage logs
- total = 17 logs

Scan every one of the 17 logs for all five exact fatal markers:

- `SCRIPT ERROR:`
- `Parse Error:`
- `Compile Error:`
- `Failed to instantiate an autoload`
- `Failed to load script`

Required fatal matches: `0`.

Compute SHA-256 for every log and include a 17-entry manifest in the durable verification result.

## Required runner result

Runner exit code must be `0` and output must contain all three lines:

```text
V0-P7.5 TWO CLIENT CONVERGENCE GATE GREEN
EXACT_HEAD=ba8210a8d3cddf084a573f2e862982d3f76c37c9
GODOT=4.7.1.stable.double.custom_build.a13da4feb
```

## Cleanliness after execution

After the complete gate, verify again:

- HEAD exact
- TREE exact
- tracked status clean

Untracked Godot `.gd.uid` sidecars or runtime artifacts are allowed only if no tracked mutation/staging occurs.

## Required independent checks

In addition to executing the gate, independently confirm:

1. Reviewer R2 PASS result exists at exact canonical result commit `d4c1b365...` and required_fixes is empty.
2. Runtime PR #435 remains open/unmerged and head is exact frozen runtime HEAD.
3. Runtime Project Control `33523992483` is SUCCESS on exact runtime HEAD.
4. Reviewer result Project Control `33618553668` is SUCCESS on exact canonical reviewer result commit.
5. P7.5 M7 repair amendment authorizes exactly the M7 adapter + M7 regression test and no broader M7 surface.
6. No P7.5 Human RUNTIME_FEATURE_MERGE approval exists yet.

## Verdict semantics

Allowed final verdicts:

- `VERIFIED` — only if full canonical gate fresh-executes GREEN, identities exact, fatal scan zero, and tracked-clean before/after.
- `NOT_VERIFIED` — environment/identity/execution could not be completed without a runtime correctness RED.
- `FAIL` — an actual exact runtime/gate invariant fails.

Do not convert environment failure into runtime FAIL.

## Durable result branch

Create:

`control/v0-p7-5-fresh-verifier-result-r1`

Create it from the exact verifier dispatch HEAD produced by this branch after Project Control is GREEN. Do not create the result branch from main or runtime.

Add exactly one file:

`config/control/harness/executions/E2026-08-30-V0-P7-R1/verifications/V0-P7-R1-WO-001-P7-5-VERIFICATION-001.v1.json`

The result JSON must use schema:

`distributed_world_simulator.harness_verification.v1`

It must record at minimum:

- exact dispatch branch/head
- exact verified HEAD/TREE
- verifier identity
- verdict + reason
- execution_performed
- host/platform
- Godot path/version/SHA256
- fresh detached worktree path
- gate command
- gate exit code
- 16 stage results/assertion counts
- 17 log hashes
- fatal scan result
- tracked-clean before/after
- inherited_execution_evidence=false
- runtime branch/PR unchanged
- merge performed=false

## Boundary

Do NOT:

- edit runtime
- repair runtime
- merge PR #435
- create Human approval
- declare P7.5 COMPLETE_MERGED
- start P7.6

If VERIFIED, the only thing opened is Human `RUNTIME_FEATURE_MERGE` decision for exact PR #435.
