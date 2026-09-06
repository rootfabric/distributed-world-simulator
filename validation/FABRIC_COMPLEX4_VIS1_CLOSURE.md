# FABRIC COMPLEX4-VIS1 — PLAYABLE PHYSICAL LAB — RESEARCH EXACT CLOSED

**Status:** `RESEARCH EXACT CLOSED` for the visual/playable observatory. This does not change canonical authority and is not a main product acceptance.

## Exact subject

- predecessor COMPLEX4 final: `4ef1a6f6e2ffdf7a6790661e00cd2e0bd32b9993`
- VIS1 runtime candidate: `d4dff1cfff985b73a44d6d47335369e7c16cb3b2`
- candidate tree: `03ece6879d976414eba2d9c0c175ef5ca495d512`
- scene: `res://scenes/labs/fabric/complex4_playable_physical_lab.tscn`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Godot SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

The candidate adds exactly six VIS1 paths. No COMPLEX4/BRIDGE-4/FABRIC1 predecessor runtime or test path is modified.

## What the user can see

The scene is a 3D observatory for the same canonical COMPLEX4 machine:

```text
REV0: two supported power paths -> ON / 36 W
  ↓ physical overload proposal
FULL, canonical revision still 0
  ↓ external canonical mutation
REV1: primary support BROKEN -> backup path survives -> ON / 36 W
  ↓ second physical overload proposal
FULL, canonical revision still 1
  ↓ external canonical mutation
REV2: both supports BROKEN -> zero active paths -> OFF / 0 W
  ↓ restart
REV2 remains OFF from authoritative canonical state
```

Visual encoding:

- green structural support = canonical `INTACT`;
- red/shrunk support = canonical `BROKEN`;
- yellow primary / cyan backup path = active derived functional path;
- red path = disabled because its canonical structural support is broken;
- emissive load + point light = machine `ON`;
- dark load = machine `OFF`;
- HUD shows canonical revision, FABRIC mode, active paths, power and `canonical writes = 0`.

## Exact acceptance

Two fresh published-byte replays:

```text
46 / 46 PASS × 2
COMPLEX4_VIS1_HASH=65951261f4bceb5b9e580d4ae6f85fc26c6ecf1170db1b96c7b98e4236917aef
```

The test explicitly proves that proposal stages enter `FULL` without advancing canonical revision, first canonical support failure keeps the machine `ON`, second support failure turns it `OFF`, and restart preserves authoritative revision 2.

Main-scene smoke using the real `.tscn`: exit `0`, fatal markers `0`.

Fresh predecessor boundary:

```text
COMPLEX4-BCD: 57 PASS
hash = 9dcd39048455f8cdb15ef4fb283fa91eb3fc0e7a6f56f24742a45348de88f300
```

## How to launch

From repository root:

```bash
GODOT_BIN=/path/to/godot ./RUN_FABRIC_COMPLEX4_VIS1_LAB.sh
```

or directly:

```bash
/path/to/godot --path . --scene res://scenes/labs/fabric/complex4_playable_physical_lab.tscn
```

Controls:

```text
SPACE  next proof step
1      break primary support immediately
2      break backup support immediately
N      restart derived runtime from current authoritative revision
R      reset to revision 0
```

For the full truth-boundary demonstration, use `SPACE`: it separates the `FULL` physical proposal stage from the later external canonical mutation.

## Project Control

```text
standard PC0 = RED
directional  = GREEN
```

Global RED is unrelated to VIS1 and remains attributed to G8/ECO/T1B/CH9.6/doctrine/NX/V0.

## Closure

`COMPLEX4-VIS1 / Playable Physical Lab = RESEARCH EXACT CLOSED`

```text
FABRIC_COMPLEX4_VIS1_CLOSURE_HASH=ba403c46263740af161bc69778b4abe58fa19fe6bb2983884e9f8dd19c325f16
```
