# V0 P7.4 — Fresh Independent Ubuntu Verifier R2

Role: **fresh independent VERIFIER R2**, read-only with respect to runtime source.

R1 ended correctly as `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT` without executing the gate. R2 exists only to repair the verifier environment and run a completely fresh campaign against the **same frozen runtime subject**.

If any identity, environment, import, stage, log, or cleanliness invariant fails, do not repair runtime source. Record `NOT_VERIFIED`.

## Frozen runtime subject

```text
runtime PR:
#396

runtime branch:
feature/v0-p7-bounded-terrain-mutation

HEAD:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef

P7.4 canonical base:
0ad8c41f04b1d115da7de4a24a1c0390761c3ae1

runtime Project Control:
33374295322 = SUCCESS
```

Do not rebase. Do not modify the runtime branch.

## Prior gates

Reviewer R1:

```text
commit:
abd753941f2bc4f9ff771e8501f261505b61c7de

verdict:
PASS

Project Control:
33388053145 = SUCCESS
```

Verifier R1:

```text
result commit:
38ddb506fed104ad419c1a94c9564a3ae6c654b4

result PR:
#412

Project Control:
33393399665 = SUCCESS

verdict:
NOT_VERIFIED

reason:
INSUFFICIENT_ENVIRONMENT

execution_performed:
false
```

**R1 contributes zero runtime execution evidence to R2.** No stage may be inherited from R1, Implementer, or Reviewer.

## Exact Linux double Godot — environment repair

The canonical project-provided archive has now been recovered and independently inspected by the control surface.

Required archive:

```text
godot-4.7.1-linux-double-x86_64-a13da4f.tar.gz
```

Required archive SHA-256:

```text
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

Archive payload:

```text
tools/godot/linux-x86_64/BUILD_INFO.json
tools/godot/linux-x86_64/SHA256SUMS
tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64
```

Required binary SHA-256:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Required version:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

BUILD_INFO identity:

```text
Godot: 4.7.1-stable
commit: a13da4feb8d8aefc283c3763d33a2f170a18d541
platform: linuxbsd
target: editor
arch: x86_64
precision: double
```

### Install without sudo

The archive does not require package installation or root privileges.

Assume the transferred archive is at `$HOME/Downloads/godot-4.7.1-linux-double-x86_64-a13da4f.tar.gz`:

```bash
set -euo pipefail

ARCHIVE="$HOME/Downloads/godot-4.7.1-linux-double-x86_64-a13da4f.tar.gz"
EXPECTED_ARCHIVE_SHA="d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92"
EXPECTED_BIN_SHA="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
EXPECTED_VERSION="4.7.1.stable.double.custom_build.a13da4feb"

test -f "$ARCHIVE"
test "$(sha256sum "$ARCHIVE" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$ARCHIVE" -C "$TMP"

SRC="$TMP/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64"
test -f "$SRC"
test "$(sha256sum "$SRC" | awk '{print $1}')" = "$EXPECTED_BIN_SHA"

INSTALL_DIR="$HOME/.local/opt/godot-double-4.7.1-a13da4f"
mkdir -p "$INSTALL_DIR"
cp "$SRC" "$INSTALL_DIR/godot.linuxbsd.editor.double.x86_64"
chmod +x "$INSTALL_DIR/godot.linuxbsd.editor.double.x86_64"

GODOT_BIN="$INSTALL_DIR/godot.linuxbsd.editor.double.x86_64"
test "$(sha256sum "$GODOT_BIN" | awk '{print $1}')" = "$EXPECTED_BIN_SHA"
test "$("$GODOT_BIN" --version 2>&1 | head -n1 | tr -d '\r')" = "$EXPECTED_VERSION"

printf 'GODOT_BIN=%s\n' "$GODOT_BIN"
```

If either SHA or version differs, stop with `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT`.

## Allowed Ubuntu environment

Preferred: a reachable native Ubuntu x86_64 host.

R2 may also use **WSL2 Ubuntu x86_64** as the repaired Ubuntu environment only when all of the following are true:

```text
/etc/os-release identifies Ubuntu
uname -s == Linux
uname -m == x86_64
the exact linuxbsd double Godot executes directly inside Ubuntu
Git inside Ubuntu can materialize a fresh detached exact worktree
the complete .sh canonical gate executes inside Ubuntu
all normal exact-head/log/cleanliness invariants pass
```

This does **not** permit Windows Godot. The Windows executable must not be used.

If the selected Ubuntu environment cannot satisfy all conditions, record `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT`.

## Fresh source materialization

Do not reuse an Implementer, Reviewer, or R1 verifier worktree.

If a canonical Ubuntu checkout already exists:

```bash
cd /home/yurig/distributed-world-simulator
git fetch origin --prune

VERIFY_DIR=/home/yurig/dws-p7-4-verifier-r2
git worktree remove --force "$VERIFY_DIR" 2>/dev/null || true
rm -rf "$VERIFY_DIR"
git worktree add --detach "$VERIFY_DIR" 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
cd "$VERIFY_DIR"
```

If no Ubuntu checkout exists, clone with Ubuntu Git first, then create the detached worktree. No sudo is required for cloning.

Required proofs:

```bash
test "$(git rev-parse HEAD)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test "$(git rev-parse 'HEAD^{tree}')" = "1efad34a075af63169c48dd5055c2537c8d7e6ef"
test "$(git rev-parse origin/feature/v0-p7-bounded-terrain-mutation)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test -z "$(git status --porcelain --untracked-files=no)"
```

Any mismatch = `NOT_VERIFIED`. Never rebase to fix identity.

## Canonical R2 execution

No external 180-second timeout is allowed.

Run exactly:

```bash
./RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.sh \
  "$GODOT_BIN" \
  "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
```

Required final exit:

```text
0
```

Required final banner:

```text
V0-P7.4 PERSISTENCE RESTART COMPOSITION GATE GREEN
EXACT_HEAD=9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
GODOT=4.7.1.stable.double.custom_build.a13da4feb
```

## Required 16 fresh stages

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

Especially close freshly:

```text
P7.2 bubble
MW4
MW5
MW6
M6 recovery processes
```

A timeout is not PASS.

## Required 17 logs

Require exactly:

```text
1 import log
3 P7.4 restart phase logs
13 regression-stage logs
17 total
```

Independently scan all campaign logs for:

```text
SCRIPT ERROR:
Parse Error:
Compile Error:
Failed to instantiate an autoload
Failed to load script
```

Any match = `NOT_VERIFIED`.

Record SHA-256 for every log.

## Final exact-head and cleanliness fence

After execution:

```bash
test "$(git rev-parse HEAD)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test "$(git rev-parse 'HEAD^{tree}')" = "1efad34a075af63169c48dd5055c2537c8d7e6ef"
git diff --exit-code
git diff --cached --exit-code
test -z "$(git status --porcelain --untracked-files=no)"
```

Untracked Godot-generated sidecars may be listed but must not be committed.

## Control checks

Confirm independently:

```text
runtime PR #396 is open and exact
runtime PC 33374295322 = SUCCESS
Reviewer R1 commit abd753941f... = PASS
Reviewer PC 33388053145 = SUCCESS
Verifier R1 commit 38ddb506fed1... = NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT
Verifier R1 PC 33393399665 = SUCCESS
immutable export 33374385318 = SUCCESS
carrier PC 33374385340 = SUCCESS
```

R1's NOT_VERIFIED result is historical control evidence only, never runtime execution evidence.

## Durable R2 result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/verifications/
V0-P7-R1-WO-001-P7-4-VERIFICATION-002.v1.json
```

Required identity:

```text
schema:
distributed_world_simulator.harness_verification.v1

verification_id:
V0-P7-R1-WO-001-P7-4-VERIFICATION-002

work_order_id:
V0-P7-R1-WO-001

verified_head_sha:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

verified_tree_sha:
1efad34a075af63169c48dd5055c2537c8d7e6ef

verifier:
INDEPENDENT_VERIFIER_P7_4_FRESH_UBUNTU_EXACT_SOURCE_R2
```

Allowed verdicts:

```text
VERIFIED
NOT_VERIFIED
```

Record:
- environment type (native Ubuntu or WSL2 Ubuntu);
- exact Ubuntu release and kernel;
- exact Godot path/version/binary SHA;
- archive SHA if bootstrap archive was used;
- exact HEAD/TREE/origin branch;
- fresh import;
- all 16 fresh stage counts;
- canonical runner exit/banner;
- all 17 log SHA-256 values;
- fatal-log scan;
- tracked-clean before/after;
- all control identities above;
- findings.

## R2 result branch

Create the result branch from the **exact final R2 dispatch control HEAD**, never from runtime HEAD or main:

```text
control/v0-p7-4-fresh-verifier-result-r2
```

Only `V0-P7-R1-WO-001-P7-4-VERIFICATION-002.v1.json` may be added.

## Success boundary

`VERIFIED` opens only the Human `RUNTIME_FEATURE_MERGE` gate for exact PR #396.

No merge is performed by the verifier.

At VERIFIED finish exactly:

```text
P7.4 Fresh Ubuntu Verifier R2 VERIFIED opens Human RUNTIME_FEATURE_MERGE only.
No merge performed.
```

At NOT_VERIFIED, state the exact blocker/failing stage and the next repair or rerun required.
