# V0 P7.4 — Verifier Environment Repair / READY Preflight

Role: **environment-preparation actor**, not runtime Implementer, Reviewer, or Verifier.

Purpose: physically place the exact Linux double Godot and exact frozen runtime checkout into an Ubuntu environment, prove that environment is ready, and stop **before** running any P7.4 gate.

Two Verifier rounds already ended correctly as `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT` with `execution_performed=false`. Do not dispatch R3 until this preflight is durably `READY`.

## Frozen runtime subject

```text
PR:
#396

branch:
feature/v0-p7-bounded-terrain-mutation

HEAD:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef
```

Do not change, rebase, repair, or merge this subject.

## Exact Godot artifact

The control surface has revalidated the exact project archive after R2:

```text
filename:
godot-4.7.1-linux-double-x86_64-a13da4f.tar.gz

archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92

binary inside archive:
tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

required --version:
4.7.1.stable.double.custom_build.a13da4feb
```

The archive must be **physically transferred into the chosen Ubuntu environment before any R3 verifier is created**.

Recommended destination:

```text
$HOME/Downloads/godot-4.7.1-linux-double-x86_64-a13da4f.tar.gz
```

## Acceptable Ubuntu environment

Either:

1. native Ubuntu x86_64 host; or
2. WSL2 Ubuntu x86_64, provided the Linux Godot binary executes inside Ubuntu and Git/worktree requirements below pass.

Windows Godot is forbidden.

No sudo is required.

## Install exact Godot

```bash
set -euo pipefail

ARCHIVE="$HOME/Downloads/godot-4.7.1-linux-double-x86_64-a13da4f.tar.gz"
ARCHIVE_SHA="d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92"
BIN_SHA="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
VERSION="4.7.1.stable.double.custom_build.a13da4feb"

test -f "$ARCHIVE"
test "$(sha256sum "$ARCHIVE" | awk '{print $1}')" = "$ARCHIVE_SHA"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$ARCHIVE" -C "$TMP"

SRC="$TMP/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64"
test -f "$SRC"
test "$(sha256sum "$SRC" | awk '{print $1}')" = "$BIN_SHA"

INSTALL="$HOME/.local/opt/godot-double-4.7.1-a13da4f"
mkdir -p "$INSTALL"
cp "$SRC" "$INSTALL/godot.linuxbsd.editor.double.x86_64"
chmod +x "$INSTALL/godot.linuxbsd.editor.double.x86_64"

GODOT_BIN="$INSTALL/godot.linuxbsd.editor.double.x86_64"
test "$(sha256sum "$GODOT_BIN" | awk '{print $1}')" = "$BIN_SHA"
test "$("$GODOT_BIN" --version 2>&1 | head -n1 | tr -d '\r')" = "$VERSION"
```

If any check fails, result is `NOT_READY`.

## Materialize exact Git subject

Use Git **inside Ubuntu**.

If no repository checkout exists:

```bash
mkdir -p "$HOME/projects"
cd "$HOME/projects"
git clone https://github.com/rootfabric/distributed-world-simulator.git dws-p7-4-env
cd dws-p7-4-env
```

Then:

```bash
git fetch origin --prune

VERIFY_DIR="$HOME/dws-p7-4-verifier-r3-ready"
git worktree remove --force "$VERIFY_DIR" 2>/dev/null || true
rm -rf "$VERIFY_DIR"

git worktree add --detach "$VERIFY_DIR" 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
cd "$VERIFY_DIR"

test "$(git rev-parse HEAD)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test "$(git rev-parse 'HEAD^{tree}')" = "1efad34a075af63169c48dd5055c2537c8d7e6ef"
test "$(git rev-parse origin/feature/v0-p7-bounded-terrain-mutation)" = "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
test -z "$(git status --porcelain --untracked-files=no)"
test -x ./RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.sh
```

## Critical stop boundary

Do **not** run:

```text
RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.sh
```

Do not run any of the 16 runtime stages.

The environment-preparation actor proves only that a fresh verifier **can** start.

## Required durable result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-4-VERIFIER-ENVIRONMENT-READY-001.v1.json
```

Schema:

```text
distributed_world_simulator.harness_environment_ready.v1
```

Required fields:

```text
status:
READY | NOT_READY

prepared_at_utc:
...

ubuntu_environment_type:
native | wsl2

ubuntu_release:
...

kernel:
...

archive_path:
...

archive_sha256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92

godot_path:
...

godot_sha256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

godot_version:
4.7.1.stable.double.custom_build.a13da4feb

repo_path:
...

detached_worktree_path:
...

runtime_head_sha:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

runtime_tree_sha:
1efad34a075af63169c48dd5055c2537c8d7e6ef

origin_runtime_branch_sha:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

tracked_clean:
true | false

runner_present:
true | false

runtime_gate_executed:
false
```

If `runtime_gate_executed=true`, this environment-preparation result is invalid.

## Result branch

Create from the exact final environment-repair dispatch HEAD:

```text
control/v0-p7-4-verifier-environment-ready-r1
```

Only the environment-ready JSON may be added.

Push it.

## Opening rule

Only:

```text
status = READY
AND exact archive SHA
AND exact Godot binary SHA/version
AND exact runtime HEAD/TREE
AND tracked clean
AND runner present
AND runtime_gate_executed = false
AND Project Control = SUCCESS
```

opens Fresh Ubuntu Verifier R3 dispatch.

Otherwise R3 stays blocked.
