# V0 P7.3 — Fresh Independent Verifier R1

Role: **fresh independent VERIFIER**, read-only with respect to runtime source.

You are verifying CRITICAL-risk P7.3 after fresh independent Reviewer R1 PASS.

If identity, exact Godot, import, any stage, fatal-log scan, or tracked-clean check fails, do not repair runtime source. Record `NOT_VERIFIED`.

## Exact subject

```text
repo:
/home/yurig/distributed-world-simulator

runtime PR:
#373

runtime branch:
feature/v0-p7-bounded-terrain-mutation

HEAD:
b4b11a69ef921c59b28208685cf26509c3b81907

TREE:
99dea175fda7bacce936b15d30d9e25fa9e4af00

canonical main at verifier dispatch:
718a9767da8b2bda986e1cadee3f7bc6d729f0d4

runtime Project Control:
33360078991 = SUCCESS

required Godot:
4.7.1.stable.double.custom_build.a13da4feb
```

The runtime candidate is intentionally frozen even though unrelated canonical main work may move. Do **not** rebase or modify the runtime branch; doing so invalidates Reviewer freshness.

## Reviewer gate

```text
review:
V0-P7-R1-WO-001-P7-3-FINAL-REVIEW-001

reviewer:
INDEPENDENT_REVIEWER_P7_3_FRESH_EXACT_SOURCE_R1

review result commit:
b9c638b1721edfe24537e264bd562e96ca224116

review result PR:
#380

review result Project Control:
33365405527 = SUCCESS

verdict:
PASS

reviewed HEAD:
b4b11a69ef921c59b28208685cf26509c3b81907

reviewed TREE:
99dea175fda7bacce936b15d30d9e25fa9e4af00
```

Reviewer accepted:
- canonical ownership;
- explicit 1 kg -> item/ore V0 policy;
- mass conservation/residual accounting;
- unsupported-material fail-closed behavior;
- canonical Item Graph-only exactly-once ownership;
- full immutable batch-checksum replay binding;
- cross-player/content-changed replay conflicts;
- committed-Matter failure/retry behavior;
- staged P7.3 boundary.

Reviewer left one execution gap intentionally for Verifier: the full canonical gate, including fresh standalone P7.2 bubble.

## Immutable exact source

```text
validation PR:
#375

export run:
33363652803 = SUCCESS

artifact:
9747515061

artifact name:
p7-3-review-source-b4b11a69ef92

artifact ZIP SHA-256:
b6f2be94c8dbe371468ccfbee0064dcf354007b8ae0b4db6ac1176b37e008853

source tar SHA-256:
f5cb57e6d953b6f9dcf3d4cc0014e2c3759e9b461d5bcf638a2dcc0681ed1f98

reconstructed TREE:
99dea175fda7bacce936b15d30d9e25fa9e4af00
```

## Required execution

1. Fetch exact refs.
2. Create a **fresh detached worktree** at `b4b11a69ef921c59b28208685cf26509c3b81907`. Do not reuse Implementer or Reviewer worktrees.
3. Prove:
   - `git rev-parse HEAD == b4b11a69ef921c59b28208685cf26509c3b81907`;
   - `git rev-parse HEAD^{tree} == 99dea175fda7bacce936b15d30d9e25fa9e4af00`;
   - `origin/feature/v0-p7-bounded-terrain-mutation == b4b11a69ef921c59b28208685cf26509c3b81907`;
   - tracked status clean before execution.
4. Locate Godot, but accept only a binary whose exact `--version` output is:
   `4.7.1.stable.double.custom_build.a13da4feb`.
   If unavailable: `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT`. Never substitute standard Godot.
5. Run an independent import.
6. Run exactly:
   ```bash
   ./RUN_V0_P7_3_MATERIAL_BATCH_ITEM_GRAPH_GATE.sh "$GODOT_BIN" "b4b11a69ef921c59b28208685cf26509c3b81907"
   ```
7. Require exit `0` and banner:
   ```text
   V0-P7.3 MATERIAL BATCH TO ITEM GRAPH GATE GREEN
   ```
8. Require all ten stages:
   - P7.3 material delivery — 116 / 0;
   - P7.2 bubble — 53 / 0;
   - P7.2 seam — 50 / 0;
   - P7.1 authority — 83 / 0;
   - P7.1 Tool→MW4 — 30 / 0;
   - P5 mining tool — 36 / 0;
   - P3 resource domain — 79 / 0;
   - MW4 — 187 / 0;
   - MW5 — 142 / 0;
   - MW6 — 130 / 0.
9. Independently scan **all 11 logs** (import + ten stages) for:
   - `SCRIPT ERROR:`
   - `Parse Error:`
   - `Compile Error:`
   - `Failed to instantiate an autoload`
   - `Failed to load script`
   Any match = `NOT_VERIFIED`, even if PASS text exists.
10. Record SHA-256 for all 11 logs.
11. Require tracked checkout clean after execution:
   ```bash
   git status --porcelain --untracked-files=no
   ```
   Untracked Godot `.gd.uid` sidecars are allowed; tracked mutation is not.
12. Confirm runtime Project Control `33360078991 = SUCCESS` and Reviewer result identity/Project Control.
13. Do not repair failures.

## Durable verification result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/verifications/
V0-P7-R1-WO-001-P7-3-VERIFICATION-001.v1.json
```

Required schema:

```text
distributed_world_simulator.harness_verification.v1
```

Required identity:

```text
verification_id:
V0-P7-R1-WO-001-P7-3-VERIFICATION-001

work_order_id:
V0-P7-R1-WO-001

verified_head_sha:
b4b11a69ef921c59b28208685cf26509c3b81907

verified_tree_sha:
99dea175fda7bacce936b15d30d9e25fa9e4af00

verifier:
INDEPENDENT_VERIFIER_P7_3_FRESH_EXACT_SOURCE_R1
```

Allowed verdicts:

```text
VERIFIED
NOT_VERIFIED
```

Record:
- verified_at_utc;
- Ubuntu/environment/worktree;
- exact Godot path/version;
- exact HEAD/TREE/branch identity;
- import result and SHA-256;
- ten stage results/counts/log SHA-256;
- canonical runner exit/banner;
- independent fatal-log scan across all 11 logs;
- tracked clean before/after;
- runtime Project Control;
- Reviewer R1 result identity/verdict/Project Control;
- any findings.

A `VERIFIED` result opens **only** the Human `RUNTIME_FEATURE_MERGE` gate. Do not merge PR #373.

## Result branch

Create the result branch from the exact verifier-dispatch control HEAD, not from runtime HEAD.

Recommended:

```text
control/v0-p7-3-fresh-verifier-result-r1
```

Only the verification JSON may be added.

Push it. `gh` is not required; pushed branch + commit SHA are sufficient durable evidence.
