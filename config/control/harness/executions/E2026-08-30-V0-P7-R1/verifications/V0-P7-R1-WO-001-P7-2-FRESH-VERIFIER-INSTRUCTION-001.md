# V0 P7.2 — Fresh Independent Verifier Instruction R1

Role: **fresh independent VERIFIER**, read-only with respect to runtime source.

You are verifying a CRITICAL-risk P7.2 exact runtime candidate after independent Reviewer R2 PASS.

Do not modify or repair runtime code. If any identity/test/log/cleanliness check fails, stop and return NOT_VERIFIED with the first exact failure.

## Exact subject

```text
repo: /home/yurig/distributed-world-simulator
runtime PR: #350
runtime branch: feature/v0-p7-bounded-terrain-mutation

HEAD:
0292e0a97d980d5c384b0118999429f1e6f13c3d

TREE:
dc39d42cf903b3dc7f56f6ba9cbb6fc82b258b36

current main:
d96ed71a917f7a28fb59856b1914eec0bdb89a42

required Godot:
4.7.1.stable.double.custom_build.a13da4feb
```

Independent Reviewer R2:

```text
review commit:
37b140f21395e0195826afc0ee0fd3787719dbb1

review:
V0-P7-R1-WO-001-P7-2-FINAL-REVIEW-002

verdict:
PASS

Reviewer Project Control:
33354295502 = SUCCESS
```

Immutable source evidence:

```text
validation PR: #361
export run: 33352617094 = SUCCESS
artifact ID: 9744115039
artifact ZIP SHA-256:
4259a92184a4e2d7d5fa7977f19879a70215f4cf3faa6105446872e93b293bef

source tar SHA-256:
1a7067ae17fded8c561ed358b8096bf8dab283481f7a624687ae7c8a79c44c93

reconstructed TREE:
dc39d42cf903b3dc7f56f6ba9cbb6fc82b258b36
```

## Required verifier procedure

1. Fetch exact refs.
2. Create a **fresh detached worktree** for `0292e0a97d980d5c384b0118999429f1e6f13c3d`; do not reuse Implementer or Reviewer worktrees.
3. Verify:
   - `git rev-parse HEAD == 0292e0a97d980d5c384b0118999429f1e6f13c3d`
   - `git rev-parse HEAD^{tree} == dc39d42cf903b3dc7f56f6ba9cbb6fc82b258b36`
   - `origin/feature/v0-p7-bounded-terrain-mutation == 0292e0a97d980d5c384b0118999429f1e6f13c3d`
   - tracked status clean.
4. Locate an executable Godot binary, but accept it only if:
   ```text
   <binary> --version
   == 4.7.1.stable.double.custom_build.a13da4feb
   ```
   If no exact binary exists: verdict NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT. Do not substitute standard Godot.
5. Run the canonical gate exactly:
   ```bash
   ./RUN_V0_P7_2_LUNAR_MATTER_BUBBLE_GATE.sh "$GODOT_BIN" "0292e0a97d980d5c384b0118999429f1e6f13c3d"
   ```
6. Require exit `0`.
7. Require PASS evidence for:
   - P7.2 bubble: 53 assertions / 0 failures
   - P7.2 seam: 50 assertions / 0 failures
   - P7.1 authority: 83 / 0
   - P7.1 Tool→MW4: 30 / 0
   - MW4: 187
   - MW5: 142
   - MW6: 130
8. Independently grep every generated log for:
   - `SCRIPT ERROR:`
   - `Parse Error:`
   - `Compile Error:`
   - `Failed to instantiate an autoload`
   - `Failed to load script`
   Any match is verifier failure even if a summary line exists.
9. Record SHA-256 of:
   - import.log
   - p7-2-bubble.log
   - p7-2-seam.log
   - p7-1-authority.log
   - p7-1-tool-to-mw4.log
   - mw4.log
   - mw5.log
   - mw6.log
10. Require tracked checkout clean after execution:
    ```bash
    git status --porcelain --untracked-files=no
    ```
    Untracked Godot `.gd.uid` import sidecars may exist and are not tracked mutation.
11. Verify runtime Project Control evidence for exact HEAD:
    ```text
    33352528718 = SUCCESS
    ```
12. Do not repair failures.

## Durable result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/verifications/
V0-P7-R1-WO-001-P7-2-VERIFICATION-001.v1.json
```

Use schema:

```text
distributed_world_simulator.harness_verification.v1
```

Required identity:

```text
work_order_id:
V0-P7-R1-WO-001

verified_head_sha:
0292e0a97d980d5c384b0118999429f1e6f13c3d

verified_tree_sha:
dc39d42cf903b3dc7f56f6ba9cbb6fc82b258b36

verifier:
INDEPENDENT_VERIFIER_P7_2_FRESH_EXACT_SOURCE_R1
```

Allowed verifier verdicts:
- `VERIFIED`
- `NOT_VERIFIED`

Record:
- verified_at_utc
- environment
- subject identity
- exact Godot version
- import result + log SHA
- each of seven stage results/assertion counts + log SHA
- canonical runner exit
- tracked-clean result
- Project Control exact-head result
- Reviewer R2 identity/verdict
- any verification findings.

A `VERIFIED` result opens only the human `RUNTIME_FEATURE_MERGE` gate. It does not itself authorize or perform merge.

## Result branch

Create result branch from this verifier-dispatch control HEAD (provided in the dispatch event/control branch), not from runtime HEAD.

Recommended branch:

```text
control/v0-p7-2-fresh-verifier-result-r1
```

Only the verification JSON may be added. Do not modify runtime files.

Push the branch. If `gh` is unavailable, pushed branch + commit SHA are sufficient durable evidence; do not block verification on PR creation.
