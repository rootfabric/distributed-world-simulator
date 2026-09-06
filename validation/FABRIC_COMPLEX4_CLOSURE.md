# FABRIC COMPLEX4 — REAL WORLD MACHINE LAB — RESEARCH EXACT CLOSED

**Status:** `RESEARCH EXACT CLOSED` for the bounded real-world canonical machine lab. This is not a `main` product-checkpoint acceptance.

## Exact subject

- Branch: `research/fabric-complex4-real-world-machine-lab-r1`
- BRIDGE-4 predecessor: `e5df247a79546400a98ffcd123d221b28d567908`
- Runtime candidate: `2c45695a19f214ce0fde5d0606697492a13b5a8f`
- Runtime tree: `61fc0d18190fe799233c1c8d84ef793c863a2a27`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Godot SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`
- Fresh import: exit `0`, fatal markers `0`

Git compare from the closed BRIDGE-4 head to the COMPLEX4 runtime candidate contains only seven new COMPLEX4 paths. No predecessor FABRIC1/BRIDGE-4 runtime or test path was modified.

## Canonical machine

COMPLEX4 creates one real `ConstructionConstructStore` machine:

- 164 canonical Construction parts;
- 167 canonical bonds;
- 164 kg matching `MatterMaterialBatch`;
- material composition: 72% steel, 18% copper, 10% ceramic;
- two structural support bonds;
- two redundant canonical `POWER_LINK` bonds;
- one derived power source/load plane compiled from the same canonical snapshot.

The structural and functional views do not create a second truth. The power links remain canonically `INTACT`; whether they execute is derived from the state of their canonical structural support bonds.

## Functional sequence

```text
revision 0
2 supported power paths
machine ON / 36 W
        ↓
physical overload on primary support
        ↓
noncanonical failure proposal only
        ↓
EXTERNAL ConstructionConstructMutation
revision 1
primary support BROKEN
1 supported power path
machine still ON / 36 W
        ↓
physical overload on backup support
        ↓
EXTERNAL ConstructionConstructMutation
revision 2
backup support BROKEN
0 supported power paths
machine OFF / 0 W
        ↓
REBAKE
        ↓
derived restart capsule
        ↓
restart from authoritative revision 2
machine remains OFF
```

Both canonical power bonds are still `INTACT` at revision 2. The OFF state is therefore a derived functional consequence of canonical structural topology loss, not a hidden canonical write by FABRIC.

## C4-A — canonical machine contract

Three fresh processes on byte-identical runtime/test files:

```text
27 / 27 PASS
COMPLEX4_A_HASH=3c299a0bca586666779659d8616372025d62f98bae634d4b77ab9ff346125c4e
```

Observed power:

```text
initial       36 W / ON / 2 active paths
after primary 36 W / ON / 1 active path
after backup   0 W / OFF / 0 active paths
```

An otherwise canonical-valid machine whose power link names an unknown structural support fails closed with `COMPLEX4_FUNCTIONAL_SUPPORT_UNKNOWN`.

## C4-B/C/D — end-to-end damage, consequence, rebake, restart

Three fresh processes on the published bytes:

```text
57 / 57 PASS
COMPLEX4_BCD_HASH=9dcd39048455f8cdb15ef4fb283fa91eb3fc0e7a6f56f24742a45348de88f300
```

The acceptance proves:

- subcritical load cannot mutate the canonical store;
- overload creates only a noncanonical, non-write-authorized proposal;
- both support failures are applied only by external `ConstructionConstructMutation(OP_UPDATE)`;
- Construction revisions advance exactly `0 → 1 → 2`;
- stale physical representations are fenced by BRIDGE-4;
- first support loss is masked by redundancy (`ON → ON`);
- second support loss produces a real functional consequence (`ON → OFF`);
- both successor states can execute FULL and return to BAKED;
- COMPLEX4 records `canonical_writes = 0`;
- restart accepts only authoritative revision 2 and reproduces `OFF / 0 W`;
- revision 1 cannot accept the revision-2 derived capsule.

## Remote byte identity

```text
projection  f75376ef81d3a5b40059d5cd0cc4c1292ccbd19d
fixture     9718b45d11707838f5a686ffd2851f00b8c1694b
A test      3b5136ee54e7a9f08686370961635fdffebcb018
A runner    45097639de7980d15ad2c672a0945f05abde61b2
runtime     c3eb2e9bf3f4f0ad72e0e31d15354636ca05e4d5
BCD test    a292388beff44d20e67271485e284e94fad3d844
BCD runner  caff391f1b8eaaf933572b87c0fcde210b936e59
```

## Fresh predecessor boundaries

```text
BRIDGE-4:      49 PASS
hash = c7daed6263058ce016a32b9813ee9a5d8da1798be96cb01e641818bd323458bf

FABRIC1-SYNC1: 30 PASS
hash = 9fa0138b88d63d8584afdc08972954a6aa86e3e8e32b8a413644c73112559d18

FABRIC1 core:  50 PASS
hash = 0dd739404c2ed0b352abc08e7c93d9100213e7479dd2cd96da8a51f1f9509444
```

## Bounded claim

COMPLEX4 proves that a real canonical DWS machine can couple structural and functional derived physics, preserve redundant function across one structural failure, lose function after the second canonical support failure, rebake, and survive restart without FABRIC acquiring canonical authority.

The functional plane is still the existing passive steady `electrical_like` conservation family. COMPLEX4 does not yet claim arbitrary electrical devices, nonlinear dynamics, thermal/hydraulic coupling, or distributed cross-authority execution.

## Project Control attribution

```text
standard PC0 = RED
directional  = GREEN
```

The global RED is attributed to unrelated active product lines: G8, ECO, T1B, CH9.6, doctrine, NX and V0. COMPLEX4 does not claim product/main acceptance.

## Activation after COMPLEX4

Highest-priority next stage:

```text
COMPLEX4-VIS1 — PLAYABLE PHYSICAL LAB
```

Now also architecturally unblocked:

```text
FABRIC1.1 — MULTI-DOMAIN GENERALIZATION
```

Nonlinear/dynamic, distributed physical execution, and FABRIC2 definition remain downstream.

## Closure hash

```text
FABRIC_COMPLEX4_CLOSURE_HASH=496327621c6080803f3e0e0ee19de2ee4e221311046533291bd2cdd60fc5cc7d
```
