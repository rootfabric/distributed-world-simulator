# V0 P7.4 — Fresh Independent Ubuntu Verifier R1

Role: **fresh independent VERIFIER**, read-only with respect to runtime source.

You are verifying CRITICAL-risk P7.4 after Fresh Independent Reviewer R1 PASS.

If exact identity, exact Godot, fresh import, any stage, fatal-log scan, tracked-clean fence, or required execution evidence fails, do **not** repair runtime source. Record `NOT_VERIFIED`.

## Exact subject

```text
repository:
rootfabric/distributed-world-simulator

runtime PR:
#396

runtime branch:
feature/v0-p7-bounded-terrain-mutation

HEAD:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef

canonical P7.4 base:
0ad8c41f04b1d115da7de4a24a1c0390761c3ae1

runtime Project Control:
33374295322 = SUCCESS

required Godot:
4.7.1.stable.double.custom_build.a13da4feb
```

The runtime candidate is frozen. Do not rebase or modify it even if unrelated `main` work moves.

## Reviewer gate

```text
review:
V0-P7-R1-WO-001-P7-4-FINAL-REVIEW-001

reviewer:
INDEPENDENT_REVIEWER_P7_4_FRESH_EXACT_SOURCE_R1

review result branch:
control/v0-p7-4-fresh-reviewer-result-r1

review result commit:
abd753941f2bc4f9ff771e8501f261505b61c7de

review carrier PR:
#404

review result Project Control:
33388053145 = SUCCESS

verdict:
PASS

reviewed HEAD:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

reviewed TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef
```

Reviewer accepted:
- no new P7 durable owner;
- MW5 remains Matter persistence owner;
- M6/V0 remains gameplay persistence owner;
- MW4 receiver/journal remains Matter replay/provenance owner;
- canonical Item Graph remains spendable inventory and exactly-once owner;
- NetworkedGameplayService remains aggregate revision owner;
- `_advance()` exactly once on successful non-replay canonical output;
- failed output and canonical replay do not advance aggregate revision;
- first restart delivery is exactly-once;
- second restart is byte-stable replay;
- the contract-built committed MW5 seed fixture is acceptable for P7.4.

Reviewer PASS is **not** execution evidence for the full gate.

## Immutable exact source

```text
validation PR:
#397

validation branch:
validation/v0-p7-4-exact-source-r1

carrier HEAD:
8e5520db6cae05a816740b00b387f273e757096b

export run:
33374385318 = SUCCESS

carrier Project Control:
33374385340 = SUCCESS

artifact:
9751287742

artifact ZIP SHA-256:
71a833cb3b7f99133d81e309d2e22b329704fd4e5d3dbb2ee409b1ab94a99e9a

source tar SHA-256:
b422f8ba9dec229d53ea3e63325355d286bf96bb248376703047492cffbc147e

reconstructed TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef

Reviewer byte-exact comparison:
5095 files identical
```

## Required fresh materialization

Use a brand-new Ubuntu worktree/check-out. Do not reuse Implementer or Reviewer worktrees.

Example:

```bash
cd /home/yurig/distributed-world-simulator
git fetch origin --prune

VERIFY_DIR=/home/yurig/dws-p7-4-verifier-r1
git worktree remove --force "$VERIFY_DIR" 2>/dev/null || true
rm -rf "$VERIFY_DIR"
git worktree add --detach "$VERIFY_DIR" 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
cd "$VERIFY_DIR"
```

Prove exact identity:

```bash
test "$(git rev-parse HEAD)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test "$(git rev-parse 'HEAD^{tree}')" = "1efad34a075af63169c48dd5055c2537c8d7e6ef"
test "$(git rev-parse origin/feature/v0-p7-bounded-terrain-mutation)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test -z "$(git status --porcelain --untracked-files=no)"
```

If any identity check fails: `NOT_VERIFIED`. Do not rebase.

## Exact Godot

Use only a binary whose first `--version` line is exactly:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Known canonical path may be:

```text
/home/yurig/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64
```

but verify the binary; do not trust the path.

Example:

```bash
GODOT_BIN=/home/yurig/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64
test -x "$GODOT_BIN"
test "$("$GODOT_BIN" --version 2>&1 | head -n1 | tr -d '\r')" = "4.7.1.stable.double.custom_build.a13da4feb"
```

If exact double Godot is unavailable: `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT`.

## Important execution rule

Do **not** impose the Implementer container's 180-second outer execution cap.

In particular, `M6 dedicated recovery processes` must be allowed to complete naturally. A timeout/truncation is not PASS.

The canonical runner already fails closed. Run it as one complete verification campaign.

## Fresh import

The canonical runner performs its own import, but independently materialize/check the project first if your environment requires it.

No parse/compile/autoload/load errors may be ignored.

## Canonical execution

Run exactly from the detached runtime worktree:

```bash
./RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.sh \
  "$GODOT_BIN" \
  "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
```

Required final exit code:

```text
0
```

Required final banner:

```text
V0-P7.4 PERSISTENCE RESTART COMPOSITION GATE GREEN
EXACT_HEAD=9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
GODOT=4.7.1.stable.double.custom_build.a13da4feb
```

## Required 16 stages

All must freshly complete in this Verifier campaign.

```text
P7.4 seed                         21 / 0
P7.4 recover-deliver              25 / 0
P7.4 recover-replay               17 / 0

P7.3 material delivery           116 / 0
P7.2 bubble                       53 / 0
P7.2 seam                         50 / 0
P7.1 authority                    83 / 0
P7.1 Tool→MW4                     30 / 0
P5 mining tool                    36 / 0
P3 resource domain                79 / 0
P3 aggregate recovery             33 / 0
M6 recovery contracts            126 / 0
M6 recovery processes            128 / 0
MW4                               187 / 0
MW5                               142 / 0
MW6                               130 / 0
```

Do not inherit any of these from Implementer or Reviewer execution.

The specific gaps that **must** be freshly closed here are:

```text
P7.2 bubble
MW4
MW5
MW6
M6 recovery processes
```

## Log integrity

The runner produces:

```text
1 import log
3 P7.4 restart phase logs
13 regression-stage logs
-------------------------
17 logs total
```

Independently scan all 17 logs for:

```text
SCRIPT ERROR:
Parse Error:
Compile Error:
Failed to instantiate an autoload
Failed to load script
```

Any occurrence is `NOT_VERIFIED`, even if a PASS line is present.

Record SHA-256 for all 17 logs.

A robust example:

```bash
ARTIFACT_ROOT="$PWD/artifacts/runtime/v0-p7-4-persistence-restart"

find "$ARTIFACT_ROOT" -maxdepth 1 -type f -name '*.log' -print0 \
  | sort -z \
  | xargs -0 sha256sum

if grep -R -F \
  -e "SCRIPT ERROR:" \
  -e "Parse Error:" \
  -e "Compile Error:" \
  -e "Failed to instantiate an autoload" \
  -e "Failed to load script" \
  "$ARTIFACT_ROOT"/*.log; then
  echo "FATAL_LOG_MARKER_FOUND"
  exit 1
fi
```

Verify there are exactly 17 `*.log` files belonging to this fresh campaign.

## Freshness and tracked-clean fence

After all execution:

```bash
test "$(git rev-parse HEAD)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test "$(git rev-parse 'HEAD^{tree}')" = "1efad34a075af63169c48dd5055c2537c8d7e6ef"

git diff --exit-code
git diff --cached --exit-code
test -z "$(git status --porcelain --untracked-files=no)"
```

Untracked Godot-generated `.gd.uid` or ignored artifacts may exist; list them if present, but do not commit them.

Tracked mutation invalidates verification.

## Control evidence checks

Confirm:
- runtime PR #396 still points at exact runtime HEAD;
- runtime Project Control `33374295322 = SUCCESS`;
- Reviewer result commit is exact `abd753941f2bc4f9ff771e8501f261505b61c7de`;
- Reviewer record verdict is `PASS`;
- Reviewer reviewed exact runtime HEAD/TREE;
- Reviewer Project Control `33388053145 = SUCCESS`;
- source-export run `33374385318 = SUCCESS`;
- source-carrier Project Control `33374385340 = SUCCESS`.

Do not require unrelated later `main` movement to equal the frozen runtime base.

## Preserve Reviewer INFO findings

Do not turn these into scope-expanding repairs unless actual fresh execution fails because of them:

1. `P7.4-R1-F001` — unchanged P3 resource-mining direct Item Graph output seam is outside P7.4 and nonblocking.
2. `P7.4-R1-F002` — hypothetical post-delivery Matter provenance fence failure remains replay-safe.
3. `P7.4-R1-F003` — contract-built committed MW5 seed fixture is accepted for this stage.

Verifier verifies; Verifier does not redesign.

## Durable verification result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/verifications/
V0-P7-R1-WO-001-P7-4-VERIFICATION-001.v1.json
```

Required schema:

```text
distributed_world_simulator.harness_verification.v1
```

Required identity:

```text
verification_id:
V0-P7-R1-WO-001-P7-4-VERIFICATION-001

work_order_id:
V0-P7-R1-WO-001

verified_head_sha:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

verified_tree_sha:
1efad34a075af63169c48dd5055c2537c8d7e6ef

verifier:
INDEPENDENT_VERIFIER_P7_4_FRESH_UBUNTU_EXACT_SOURCE_R1
```

Allowed verdicts:

```text
VERIFIED
NOT_VERIFIED
```

Record at minimum:
- `verified_at_utc`;
- Ubuntu host/worktree;
- exact Godot path and version;
- exact HEAD/TREE/origin runtime branch identity;
- fresh import result;
- all 16 stage results/assertion counts;
- canonical runner exit/banner;
- SHA-256 for all 17 logs;
- independent fatal-log scan result;
- tracked-clean before and after;
- runtime Project Control;
- Reviewer identity/verdict/Project Control;
- immutable-source/export identity;
- findings, if any;
- forbidden conclusions respected.

## Result branch

Create the result branch from the **exact final verifier-dispatch control HEAD**, not from runtime HEAD and not from main.

Recommended:

```text
control/v0-p7-4-fresh-verifier-result-r1
```

Only the verification JSON may be added.

Push the branch.

## Success boundary

A `VERIFIED` result opens **only**:

```text
HUMAN RUNTIME_FEATURE_MERGE gate
for exact PR #396 subject
```

It does not:
- merge PR #396;
- authorize itself to merge;
- declare `P7.4 COMPLETE_MERGED`;
- accept whole P7;
- start P7.5.

At VERIFIED, finish exactly:

```text
P7.4 Fresh Ubuntu Verifier R1 VERIFIED opens Human RUNTIME_FEATURE_MERGE only.
No merge performed.
```

At NOT_VERIFIED, finish with the exact failing stage/evidence and what must be repaired or rerun next.
