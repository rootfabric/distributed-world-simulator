#!/usr/bin/env bash
# ENGINE48 transfer: locate the EXISTING Ubuntu 7-commit Git branch, do not synthesize it.
set -euo pipefail

base="a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9"
expected_tree="3c0a04c78eca918717e8e836b1c1bf2836cb5596"
branch="repair/engine48-linux-runner-guards-r1"
outdir="/mnt/c/DWS-Transfers"
bundle="$outdir/engine48-linux-r1.bundle"
expected_prefix="7aaa7fa9e"

if [[ ! -d /mnt/c ]]; then
  echo "ENGINE48_WINDOWS_DRIVE_NOT_MOUNTED" >&2
  exit 21
fi

repo=""
# Both ordinary clones and linked worktrees may contain a .git directory or file.
while IFS= read -r -d '' gitlink; do
  candidate="${gitlink%/.git}"
  case "$candidate" in *distributed-world-simulator*) ;; *) continue ;; esac
  if ! git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then continue; fi
  if ! git -C "$candidate" cat-file -e "$base^{commit}" 2>/dev/null; then continue; fi
  if ! git -C "$candidate" show-ref --quiet --verify "refs/heads/$branch"; then continue; fi
  repo="$candidate"
  break
done < <(find /home /root -maxdepth 8 \
  \( -name .cache -o -name node_modules -o -name .local -o -name .venv \) -prune -o \
  -name .git -print0 2>/dev/null)

if [[ -z "$repo" ]]; then
  echo "ENGINE48_LINUX_LOCAL_BRANCH_NOT_VISIBLE_IN_THIS_WSL_DISTRO" >&2
  exit 22
fi

if [[ "$(git -C "$repo" rev-parse "$base^{tree}")" != "$expected_tree" ]]; then
  echo "ENGINE48_LINUX_BASE_TREE_MISMATCH" >&2
  exit 23
fi

tip="$(git -C "$repo" rev-parse "refs/heads/$branch")"
if [[ "${tip:0:10}" != "$expected_prefix" ]]; then
  echo "ENGINE48_LINUX_LOCAL_TIP_MISMATCH:$tip" >&2
  exit 24
fi
if ! git -C "$repo" merge-base --is-ancestor "$base" "$tip"; then
  echo "ENGINE48_LINUX_NOT_DESCENDANT_OF_MIGRATION_BASE" >&2
  exit 25
fi

count="$(git -C "$repo" rev-list --count "$base..$tip")"
if [[ "$count" != "7" ]]; then
  echo "ENGINE48_LINUX_COMMIT_COUNT_MISMATCH:$count" >&2
  exit 26
fi

# Do not mutate or clean this source worktree. The branch ref can be accessed from any linked checkout.
mkdir -p "$outdir"
git -C "$repo" bundle create "$bundle" "refs/heads/$branch" "^$base"
git -C "$repo" bundle verify "$bundle" >&2
sha="$(sha256sum "$bundle" | awk '{print $1}')"
tree="$(git -C "$repo" rev-parse "$tip^{tree}")"
bytes="$(stat -c '%s' "$bundle")"

echo "ENGINE48_LINUX_BUNDLE_READY"
echo "ENGINE48_LINUX_SOURCE_WORKTREE=$repo"
echo "ENGINE48_LINUX_TIP_SHA=$tip"
echo "ENGINE48_LINUX_TIP_TREE=$tree"
echo "ENGINE48_LINUX_COMMIT_COUNT=$count"
echo "ENGINE48_LINUX_BUNDLE_SHA256=$sha"
echo "ENGINE48_LINUX_BUNDLE_BYTES=$bytes"
echo "ENGINE48_LINUX_BUNDLE_WINDOWS_PATH=C:\\DWS-Transfers\\engine48-linux-r1.bundle"
git -C "$repo" rev-list --reverse "$base..$tip" | sed 's/^/ENGINE48_LINUX_COMMIT=/'
