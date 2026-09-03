# V0 P7.6 — Fresh Independent Linux Verifier R1

Role: `FRESH_INDEPENDENT_VERIFIER_P7_6_R1`.

This actor is NOT the Implementer, NOT the Reviewer, and must not inherit PASS from prior Ubuntu runtime validation or Reviewer smoke execution.

## Control parent / Reviewer gate

Canonical Reviewer R2 result:

- result commit: `033866ea8e077727aeabc87ba6f40b7b9e983f0c`
- result tree: `aeefbe89306719416c588e07bfbb16a59b52d18f`
- reviewer dispatch HEAD: `9177602c543ffdb48f43f80ca92c37fbcc6fd3c8`
- reviewer: `FRESH_INDEPENDENT_REVIEWER_P7_6_R2`
- verdict: `PASS`
- required_fixes: `[]`
- Reviewer result Project Control: `33706513500 = SUCCESS`
- Reviewer dispatch Project Control: `33703587212 = SUCCESS`
- runtime Project Control: `33696913965 = SUCCESS`

The verifier must independently confirm these identities before runtime execution.

## Frozen runtime subject

- branch: `feature/v0-p7-bounded-terrain-mutation`
- runtime PR: `#466`
- HEAD: `c2e056980eed4ae20849154b1dacc71af0ce8bdf`
- TREE: `2df40d13610b5a93cd1549d8c1bc89205026e1f5`
- activation base: `aca907022bf3a3239ae53ae0583c6aff8004da98`
- exact runtime delta: 4 commits, exactly 4 files, +847/-13

Do not execute a later runtime branch head. Do not rebase, repair, cherry-pick, amend, or merge runtime.

If `origin/feature/v0-p7-bounded-terrain-mutation` no longer equals the frozen HEAD, stop with `NOT_VERIFIED / SUBJECT_IDENTITY_MISMATCH`; do not silently test a different subject.

## Platform

Required:

- Linux
- x86_64
- Ubuntu userspace

Record:

```bash
cat /etc/os-release
uname -s
uname -m
git --version
```

## Exact Godot

Use only the canonical Linux double binary:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Recommended path:

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
```

Verify before execution:

```bash
"$GODOT_BIN" --version
sha256sum "$GODOT_BIN"
```

Do not use system Godot, single precision, Windows/Wine, or another custom build.

If archive provenance is recorded, canonical archive SHA256 is:

```text
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

## Fresh detached worktree

Create a brand-new verifier worktree. Do NOT reuse:

- Implementer worktree
- P7.6 repair validation worktree
- Reviewer worktree
- prior P7.5 Verifier worktree
- any other P7.6 execution worktree

Suggested:

```bash
cd "$HOME/distributed-world-simulator"

git fetch origin --prune

WT="$HOME/dws-p7-6-verifier-r1"

git worktree remove --force "$WT" 2>/dev/null || true
rm -rf "$WT"

git worktree add --detach   "$WT"   c2e056980eed4ae20849154b1dacc71af0ce8bdf

cd "$WT"
```

Before execution:

```bash
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
git rev-parse origin/feature/v0-p7-bounded-terrain-mutation
git status --porcelain --untracked-files=no
git diff --exit-code
git diff --cached --exit-code
```

Required:

```text
HEAD:
c2e056980eed4ae20849154b1dacc71af0ce8bdf

TREE:
2df40d13610b5a93cd1549d8c1bc89205026e1f5

origin runtime ref:
c2e056980eed4ae20849154b1dacc71af0ce8bdf

tracked status:
empty
```

Any mismatch means do not run the gate.

## Execution independence

The Verifier must execute all stages fresh.

Do not copy PASS from:

- `V0-P7-R1-P7-6-REPAIR-R1-LINUX-EXACT-RUNTIME-VALIDATION-002.v1.json`
- Reviewer R2 optional smoke
- earlier subject `5e3ecef5...`
- GitHub queued/previous runtime validation

Those are context only.

No new runtime runner may be added after review. The frozen runtime already contains the repository-owned focused tests and SM1/MW8/MW9/MW10 runners that define this P7.6 exact verifier sequence.

## Log directory

Use a fresh directory:

```bash
LOGDIR="/tmp/p76-verifier-r1"
rm -rf "$LOGDIR"
mkdir -p "$LOGDIR"
```

The required verifier evidence set is exactly 8 top-level logs:

1. `import.log`
2. `p7-1.log`
3. `p7-6.log`
4. `sm1.log`
5. `mw8.log`
6. `mw9-durable.log`
7. `mw9-race.log`
8. `mw10.log`

## Stage 1 — import

Run without a top-level external timeout:

```bash
"$GODOT_BIN"   --headless   --editor   --path "$WT"   --quit   > "$LOGDIR/import.log" 2>&1

IMPORT_EXIT=$?
echo "IMPORT_EXIT=$IMPORT_EXIT"
```

Required: exit 0.

Godot import may generate untracked `.uid` sidecars. Before any repository runner that checks checkout cleanliness, remove only generated untracked `.uid` files:

```bash
git ls-files --others --exclude-standard -z -- '*.uid'   | xargs -0 -r rm -f
```

Do not remove or alter tracked `.uid` files.

Do not `chmod` tracked runner scripts; invoke them through `bash`.

## Stage 2 — P7.1 authority gate

```bash
"$GODOT_BIN"   --headless   --path "$WT"   --script res://tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd   > "$LOGDIR/p7-1.log" 2>&1

P71_EXIT=$?
echo "P71_EXIT=$P71_EXIT"
```

Required:

```text
V0-P7.1 authority gate: PASS (88 assertions, 0 failures)
exit 0
```

## Stage 3 — P7.6 focused composition

```bash
"$GODOT_BIN"   --headless   --path "$WT"   --script res://tests/runtime/test_v0_p7_6_seam_multi_region_composition.gd   > "$LOGDIR/p7-6.log" 2>&1

P76_EXIT=$?
echo "P76_EXIT=$P76_EXIT"
```

Required:

```text
V0-P7.6 seam + multi-region composition: PASS (106 assertions, 0 failures)
exit 0
```

This fresh execution must include the repaired R1 negative coverage:

- Dictionary without `success` fails closed
- null executor fails closed
- Array executor fails closed
- null resolver fails closed
- Array resolver fails closed
- empty resolver fails closed
- MW10 body mismatch rejected
- invalid plans/results do not reach inappropriate MW10/single execution

After focused tests, remove only untracked generated `.uid` sidecars again if present.

## Stage 4 — SM1 handoff composition

```bash
GODOT_BIN="$GODOT_BIN" bash ./RUN_V0_SM1_WORLD_MUTATIONS_AROUND_HANDOFF.sh   > "$LOGDIR/sm1.log" 2>&1

SM1_EXIT=$?
echo "SM1_EXIT=$SM1_EXIT"
```

Required:

```text
SM1_7_11_WORLD_MUTATIONS_AROUND_HANDOFF_PASS
145 assertions / 0 failures
exit 0
```

If the runner reports checkout not clean solely because the fresh import generated untracked `.uid` files, remove only those generated untracked files and rerun this stage fresh. Record the first environmental cleanliness stop and the successful rerun; do not hide it.

## Stage 5 — MW8

Use the repository-owned timeout parameter only; do not wrap the whole verifier in an external timeout.

```bash
GODOT_BIN="$GODOT_BIN" MW8_TIMEOUT_SECONDS=900 bash ./RUN_MW8_MATTER_HANDOFF_TESTS.sh   > "$LOGDIR/mw8.log" 2>&1

MW8_EXIT=$?
echo "MW8_EXIT=$MW8_EXIT"
```

Required:

- contracts-freeze-abort DONE
- successful-handoff-reconnect DONE
- split-brain-cross-region DONE
- `MW8 regional authority handoff: PASS (98 assertions ...)`
- exit 0

## Stage 6 — MW9 durable

```bash
GODOT_BIN="$GODOT_BIN" MW9_TIMEOUT_SECONDS=900 bash ./RUN_MW9_DURABLE_HANDOFF_RECOVERY_TESTS.sh   > "$LOGDIR/mw9-durable.log" 2>&1

MW9_DURABLE_EXIT=$?
echo "MW9_DURABLE_EXIT=$MW9_DURABLE_EXIT"
```

Required fresh PASS:

- durable handoff recovery: 203 assertions
- lock release retry: 12 assertions
- durable handoff processes: 225 assertions
- exit 0

## Stage 7 — MW9 race stress

```bash
GODOT_BIN="$GODOT_BIN" MW9_RACE_ITERATIONS=100 MW9_RACE_BATCH_SIZE=8 MW9_RACE_BATCH_TIMEOUT_SECONDS=600 bash ./RUN_MW9_RACE_STRESS_TESTS.sh   > "$LOGDIR/mw9-race.log" 2>&1

MW9_RACE_EXIT=$?
echo "MW9_RACE_EXIT=$MW9_RACE_EXIT"
```

Required:

```text
MW9 race stress runner: PASS (100 rounds in 13 batches)
exit 0
```

No reduced iteration count is allowed.

## Stage 8 — MW10

```bash
GODOT_BIN="$GODOT_BIN" MW10_TIMEOUT_SECONDS=900 bash ./RUN_MW10_CROSS_REGION_MATTER_TRANSACTIONS_TESTS.sh   > "$LOGDIR/mw10.log" 2>&1

MW10_EXIT=$?
echo "MW10_EXIT=$MW10_EXIT"
```

Required:

```text
MW10 cross-region Matter transactions: PASS (184 assertions)
MW10 cross-region Matter processes: PASS (51 assertions)
MW10 runner: PASS (2/2 suites)
exit 0
```

## Fatal scan

Scan all eight logs for all five fatal classes:

```bash
FATAL_RE='SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to instantiate an autoload|Failed to load'

for f in "$LOGDIR"/*.log; do
  echo "===== $f ====="
  grep -E "$FATAL_RE" "$f" || true
done
```

Required fatal matches: 0.

A benign `breakpoint_mcp` failure to listen on `127.0.0.1:9081` may be recorded as nonfatal only if:

- it occurs outside these fatal classes,
- the stage exits 0,
- required PASS marker/assertions are present.

Do not silently discard other errors.

## Log hash manifest

Record SHA-256 for all exactly eight logs:

```bash
sha256sum   "$LOGDIR/import.log"   "$LOGDIR/p7-1.log"   "$LOGDIR/p7-6.log"   "$LOGDIR/sm1.log"   "$LOGDIR/mw8.log"   "$LOGDIR/mw9-durable.log"   "$LOGDIR/mw9-race.log"   "$LOGDIR/mw10.log"
```

Include the full eight-entry manifest in the durable verification result.

## Final tracked cleanliness

After all stages:

```bash
git ls-files --others --exclude-standard -z -- '*.uid'   | xargs -0 -r rm -f

git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
git status --porcelain --untracked-files=no
git diff --exit-code
git diff --cached --exit-code
```

Required:

```text
HEAD:
c2e056980eed4ae20849154b1dacc71af0ce8bdf

TREE:
2df40d13610b5a93cd1549d8c1bc89205026e1f5

tracked clean:
true
```

## Required independent control checks

Before verdict, independently confirm:

1. Reviewer R2 result exists at commit `033866ea8e077727aeabc87ba6f40b7b9e983f0c`.
2. Reviewer result schema is `distributed_world_simulator.harness_review_result.v1`.
3. Reviewer `review_type` is exactly `POST_BUILD_EXACT_HEAD_REVIEW`.
4. Reviewer verdict is `PASS`.
5. Reviewer `required_fixes` is empty.
6. Both R1 findings are recorded as `FIX_VERIFIED`.
7. Reviewer result Project Control `33706513500` is SUCCESS at the exact result commit.
8. Reviewer dispatch Project Control `33703587212` is SUCCESS.
9. Runtime Project Control `33696913965` is SUCCESS at exact runtime HEAD.
10. Runtime PR #466 is still open/unmerged and its head remains exactly `c2e056980eed4ae20849154b1dacc71af0ce8bdf`.
11. No P7.6 Human `RUNTIME_FEATURE_MERGE` approval has been created.
12. P7.6 is not declared COMPLETE/MERGED.

## Verdict semantics

Allowed:

- `VERIFIED` — all exact identities, all 8 stages freshly execute PASS, 8/8 logs present, fatal scan is zero, log hash manifest complete, and tracked-clean before/after.
- `NOT_VERIFIED` — environment/identity/execution could not be completed without proving a runtime correctness failure.
- `FAIL` — actual exact runtime/gate invariant fails.

Do not convert an environment issue into runtime FAIL.

Do not inherit PASS from prior execution evidence.

## Durable verifier result

Only after this verifier dispatch branch itself has Project Control SUCCESS:

Create:

```text
control/v0-p7-6-fresh-verifier-result-r1
```

Create it from the exact verifier-dispatch HEAD, not from main, Reviewer result, or runtime.

Add exactly one file:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/verifications/
V0-P7-R1-WO-001-P7-6-VERIFICATION-001.v1.json
```

Schema:

```text
distributed_world_simulator.harness_verification.v1
```

Minimum result content:

- verification_id
- work_order_id
- project_epoch
- program
- checkpoint
- verifier
- verifier_role_is_not_implementer_not_reviewer=true
- verdict and verdict_reason
- verified_at_utc
- execution_performed=true
- inherited_execution_evidence=false
- is_runtime_fail
- dispatch branch/head/PR + dispatch Project Control
- Reviewer result identity and Project Control
- exact runtime branch/PR/HEAD/TREE and runtime Project Control
- host/platform
- exact Godot path/version/SHA256
- fresh verifier worktree path
- all 8 stage results
- all 8 log SHA256 hashes
- fatal scan result
- tracked-clean before/after
- runtime PR unchanged/unmerged
- merge_performed=false
- human approval created=false

For `VERIFIED`, explicitly state that the only newly opened gate is the Human `RUNTIME_FEATURE_MERGE` decision for exact runtime PR #466.

## Boundary

Do NOT:

- edit or repair runtime
- create a new runtime runner
- rebase runtime
- merge PR #466
- create Human approval
- declare P7.6 COMPLETE_MERGED
- begin the next P7 runtime substep

A successful Fresh Independent Linux Verifier opens only the Human merge decision for exact PR #466.
