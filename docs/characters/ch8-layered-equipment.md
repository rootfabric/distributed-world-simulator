# CH8 — Layered Equipment

## Goal

Move from one whole-body prototype outfit to a canonical layered equipment model that can represent independent inner clothing, outer clothing, armor, trousers, footwear and whole-body suits without coupling the equipment domain to any particular character rig or asset pack.

CH8 starts from the accepted CH7.8 checkpoint. CH7.8 already proves one real skinned `Male_Peasant` outfit, fused-base-body suppression, rigid helmet/backpack composition, first-person/shadow integration and unchanged gameplay body/capsule.

## Core rule

Layering is canonical state, not presentation state.

```text
Item / profile
    |
    v
semantic occupied channels
    |
    +-- compatible channels -> coexist
    |
    +-- overlapping channels -> explicit conflict plan
                                  |
                                  +-- plain equip: reject
                                  +-- explicit replace: atomic replacement
```

No mesh, Skeleton3D, Quaternius file name, camera state or network packet participates in conflict resolution.

## Semantic layer channels

The accepted humanoid layout already exposes the required vocabulary:

```text
body.head.inner
body.head.outer

body.torso.inner
body.torso.outer
body.torso.armor

body.arms.inner
body.arms.outer
body.hands

body.legs.inner
body.legs.outer
body.feet

gear.back
gear.waist
hand.left
hand.right
```

CH8A deliberately reuses these channels instead of inventing another slot system.

Example compatible set:

```text
undersuit -> torso.inner + arms.inner + legs.inner
jacket    -> torso.outer + arms.outer
trousers  -> legs.outer
boots     -> feet
armor     -> torso.armor
```

All five items may coexist because none owns the same canonical channel.

Example whole EVA suit:

```text
EVA -> torso.outer + torso.armor + arms.outer + legs.outer + feet
```

The EVA suit conflicts with jacket, trousers, boots and armor but does not conflict with the inner undersuit.

## CH8A — deterministic conflict planning

`CharacterEquipmentLayering.plan_equip()` is additive to the accepted CH7 domain.

It preserves `CharacterEquipmentDomain.validate_equip()` as the strict legacy gate. If the only rejection is occupied channels, CH8 returns a deterministic complete conflict plan containing:

- requested channels;
- every conflicting channel;
- every conflicting item ID;
- the conflicting profile IDs;
- whether direct equip is possible;
- whether explicit replacement is required.

Conflict rows and item IDs are sorted. The plan must be independent of the current snapshot entry order.

Planning is read-only and must not increment the canonical revision.

## Explicit replacement only

Plain `equip()` remains strict and **does not auto-swap**.

This is intentional. Server-authoritative Item Graph integration must never remove valuable equipment merely because a client attempted to equip another item.

CH8A adds an explicit lab mutation:

```text
equip_replacing_conflicts(item_id, profile_id)
```

The operation:

1. computes the full conflict plan;
2. rejects structural/tag/capability/anchor/channel errors before mutation;
3. removes exactly the conflicting canonical entries;
4. inserts the requested item;
5. increments revision exactly once.

Thus:

```text
before revision 5:
  undersuit + jacket + trousers + boots + armor

one explicit replacement transaction

revision 6:
  undersuit + EVA
```

There is no canonical intermediate revision containing only a partially unequipped character.

A future ItemGraph-backed source may implement the same semantic transaction with its own ledger/base-revision/authority checks. CH8A does not make the lab source production authority.

## Presentation diff

`CharacterEquipmentPresenter` remains snapshot-driven and does not receive a new layering policy.

For the example above it should observe only two canonical snapshots:

```text
snapshot A: 5 visuals
snapshot B: undersuit + EVA
```

Expected diff:

```text
created: 1  (EVA)
removed: 4  (jacket, trousers, boots, armor)
reused:  1  (undersuit)
```

This avoids visual flicker from four separate unequip mutations followed by one equip mutation.

## CH8B — real Quaternius part discovery

The next step is asset-driven, not filename-driven.

`probe_ch8_quaternius_layered_parts.gd` inspects every Standard Godot-Unreal outfit scene and prints:

- scene file;
- skeleton count and bone counts;
- every `MeshInstance3D` name;
- skinned status;
- surface/material names;
- AABB;
- a best-effort semantic category (`UPPER`, `LOWER`, `FEET`, `ARMS_HANDS`, `ACCESSORY`, `UNKNOWN`).

This will tell us whether the advertised modular parts are separate mesh nodes inside each outfit glTF and which real nodes are suitable for the first independent upper/lower/feet items.

Do not hard-code a Quaternius part name before this probe is run on the installed pack.

## CH8C — real layered skinned presentation

After CH8B identifies real mesh parts, add the smallest selector/filter mechanism to instantiate only the requested garment nodes from an otherwise compatible exact-rig outfit scene.

Target first visual composition:

```text
base head / eyes / eyebrows
+ independent upper garment
+ independent lower garment
+ independent footwear
+ optional helmet / backpack
```

The canonical items remain independent even if several presentation parts originate from the same external glTF resource.

## Body suppression challenge

The accepted Quaternius base has one fused `SuperHero_Male` head+body surface. CH7.8's simple head clip is sufficient for a whole-body outfit but is intentionally **not** assumed to solve partial upper/lower clothing.

For CH8 layered clothing, region-specific suppression must be derived only after the real garment-part probe. Candidate directions include presentation-only bone/region-aware masking or a preprocessed modular base presentation, but CH8A does not commit to either prematurely.

Never solve this by modifying `CharacterBody3D`, collision, Item Graph identity or network state.

## Acceptance ladder

### CH8A1 — layer coexistence and deterministic conflict plan

Pending Windows rerun.

Must prove:

- inner/outer/armor/lower/feet channels coexist independently;
- a multi-channel EVA plan reports all conflicts deterministically;
- planning does not mutate revision;
- legacy `equip()` still rejects a conflict;
- explicit replacement removes only conflicts;
- compatible inner layer survives;
- one replacement transaction advances exactly one revision;
- duplicate item rejection remains unchanged.

### CH8A2 — atomic presentation diff

Pending Windows rerun.

Must prove five visuals become two through one snapshot diff with `created=1`, `removed=4`, `reused=1`, and idempotent reapply remains unchanged.

### CH8B — real part probe

Pending local asset probe. Informational for CH8A; required before selecting the first real layered presentation.

### CH8C — real layered garment composition

Not started. Depends on CH8B findings.

## Deferred

- production ItemGraphEquipmentSource transaction/ledger integration;
- network replication of equipment mutations;
- persistence;
- arbitrary unrelated-rig retargeting;
- cloth physics;
- body morph fitting;
- wardrobe UI;
- auto-equip policy;
- durability/stat modifiers;
- thermal/pressure gameplay effects of EVA layers;
- large-NPC presentation optimization.
