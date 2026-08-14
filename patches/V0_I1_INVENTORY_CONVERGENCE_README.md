# V0-I1 Inventory Convergence — delivery manifest

Branch:

```text
agent/v0-s1-inventory-convergence
```

Source base for the cumulative delivery:

```text
feature/v0-s1-networked-planetary-outpost-mvp
6c4931f9c44db374b4eb3ab08b51fe1268dce569
```

## Files

### Incremental delivery

```text
patches/v0-i1-inventory-convergence.patch
SHA-256 78a679fc41b54b0b061498cc871084cc81711beecf83ad9fb5977f53afc40c0e
```

Apply this only when the previously validated V0 Tab/spawn/spectator patch is
already present in the working tree.

It changes only:

```text
scripts/app/earth_mvp_app.gd
```

and replaces the temporary text-only MVP inventory with the existing network
inventory stack:

```text
M5NetworkedInventoryShell
-> M5InventoryUiBridge
-> canonical server M4 Item Graph
```

### Cumulative delivery

```text
patches/v0-s1-inventory-convergence-cumulative.patch.gz
compressed SHA-256 f9ad9d1ae30701f66ca4914c2e5424ae21d6ccfab2341d0364545cb4d2b74665
uncompressed patch SHA-256 090ace9b6a9e644a4a1956980a80becb03186e1f1edb0b27250e452f3ebab6b8
```

Use this for a clean checkout at/compatible with `6c4931f9...`.

It includes the previously validated baseline changes plus V0-I1:

```text
scripts/app/earth_mvp_app.gd
scripts/app/simulator_app.gd
scripts/runtime/networked_gameplay/networked_gameplay_service.gd
```

Baseline behavior preserved by the cumulative patch:

```text
Tab physical-key fallback
A/B spawn separation = 10 m
F3 detached spectator with parked local body visual
neutral movement when UI/spectator takes control
```

V0-I1 behavior added:

```text
M5 graphical network inventory shell in Earth MVP
canonical server-owned M4 Item Graph remains sole item truth
hotbar visible during gameplay
Tab opens/closes graphical inventory
hotbar selection is 1..8 (canonical M5 hotbar capacity)
G drops selected canonical hotbar item
movement input is suppressed while inventory is open
V0-I1 convergence report is exposed by Earth MVP
```

## Validation performed

Godot binary:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Results:

```text
V0_I1_EARTH_MVP_PARSE_PASS
V0_I1_INVENTORY_CONVERGENCE_FAKE_RUNTIME_PASS
incremental git apply --check PASS
cumulative Earth git apply --check PASS
git diff --check PASS
```

The fake runtime validation covered:

```text
network client attach
M5 inventory shell setup
initial inventory hidden state
Tab open/close
movement suppression while inventory is visible
hotbar slot 2 accepted
hotbar slot 9 rejected
G/drop resolves selected hotbar item and uses canonical item.drop command
```

Full graphical dedicated-server + two-client acceptance remains a human runtime
check on the target machine.

## Apply — current working tree with previous MVP patch already present

Git Bash:

```bash
git fetch origin
git show origin/agent/v0-s1-inventory-convergence:patches/v0-i1-inventory-convergence.patch > v0-i1.patch
git apply --check v0-i1.patch
git apply v0-i1.patch
git diff --check
```

## Apply — clean/fresh feature branch

Git Bash:

```bash
git fetch origin
git switch feature/v0-s1-networked-planetary-outpost-mvp

git show origin/agent/v0-s1-inventory-convergence:patches/v0-s1-inventory-convergence-cumulative.patch.gz \
  | gzip -dc > v0-s1-inventory-convergence-cumulative.patch

sha256sum v0-s1-inventory-convergence-cumulative.patch
git apply --check v0-s1-inventory-convergence-cumulative.patch
git apply v0-s1-inventory-convergence-cumulative.patch
git diff --check
```

Expected uncompressed SHA-256:

```text
090ace9b6a9e644a4a1956980a80becb03186e1f1edb0b27250e452f3ebab6b8
```

If the feature branch has moved, do not reset it to the historical base. Run
`git apply --check` first and treat a failure as a rebase/convergence requirement.

## Manual V0-I1 graphical acceptance

Start the server and both Earth clients exactly as for the current V0-S1 test.
Then verify on both clients:

```text
hotbar is visible with inventory closed
Tab opens the M5 graphical inventory
Tab closes it and gameplay mouse/input returns
inventory cells represent the canonical network projection
cursor/drag interactions operate through the M5 bridge
keys 1..8 select hotbar slots
G drops the selected item into canonical world state
second client receives resulting Item Graph changes where applicable
F3 baseline spectator still behaves as before
A/B remain approximately 10 m apart at initial spawn
```

Network movement/presentation jitter is intentionally not addressed by V0-I1 and
remains the separate `V0-NET-001` follow-up owned by the network/NX track.
