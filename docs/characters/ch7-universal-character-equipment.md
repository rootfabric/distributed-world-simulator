# CH7 — Universal Character Equipment

## Base checkpoint

CH7 starts directly from the accepted CH6 checkpoint:

```text
5d408029969ba8953011c559fc1376af357bca58
validation(ch6): accept jump crouch and shadow presentation
```

CH6 remains the presentation authority for character body visuals, first/third-person visibility, shadow preservation and model-specific crouch grounding. CH7 must not move `CharacterBody3D`, change collision, read input, add network RPCs or duplicate Item Graph state.

## Goal

Provide a character-independent equipment contract that can represent wearable, held and externally mounted items on humans, cyborgs, robots, animals, drones and future character types.

The equipment domain must not know:

- Quaternius asset paths;
- `Skeleton3D` bone names;
- `MeshInstance3D` or Godot presentation nodes;
- `LunarPlayer`;
- networking or prediction;
- persistence implementation;
- production Item Graph internals.

The presentation layer will later consume immutable equipment snapshots through a rig adapter and wearable presentation catalog.

## Core invariants

1. One physical item keeps one canonical identity. Equipping an item does not create a second gameplay item.
2. Equipment channels describe occupancy. Presentation anchors describe where a visual is attached. They are deliberately different concepts.
3. Channels and anchors use stable semantic string IDs rather than a fixed humanoid enum.
4. A single item may occupy multiple channels while remaining one item.
5. Character layouts advertise supported channels, anchors, tags and capabilities.
6. Compatibility failures are explicit and deterministic; unsupported equipment is a normal result, not a crash or fallback attachment to root.
7. Presentation receives derived snapshots and may not mutate equipment state.
8. Re-applying an identical snapshot must be idempotent.
9. CH7 laboratory state is temporary test state and must not masquerade as production Item Graph state.
10. CH6 view/shadow/crouch policies remain above equipment visuals so future equipment follows the same first-person and presentation-root behavior.

## Semantic topology

Humanoid examples:

```text
anchors:
  body.head
  body.root
  gear.back
  hand.left
  hand.right

channels:
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

Robot/drone layouts may expose different IDs, for example:

```text
module.head
module.torso
power.back
hardpoint.left
hardpoint.right
payload.center
```

Generic equipment code must not branch on `human`, `robot`, `drone` or any concrete character type. Differences belong in layout/adapter data.

## Domain objects

### `CharacterEquipmentLayout`

Declares:

- `layout_id`;
- character tags;
- capabilities;
- supported semantic channels;
- supported semantic anchors;
- supported semantic body regions.

### `CharacterEquipmentProfile`

Describes gameplay compatibility only:

- `profile_id`;
- `presentation_id`;
- required/forbidden character tags;
- required capabilities;
- preferred semantic anchor;
- occupied channels.

It must not contain mesh paths, bone names or node references.

### `CharacterEquipmentEntry`

Represents one equipped item in a derived snapshot:

- canonical `item_id`;
- equipment `profile_id`;
- `presentation_id`;
- resolved `anchor_id`;
- occupied channels.

### `CharacterEquipmentSnapshot`

Read-only presentation projection containing:

- owner entity ID;
- layout ID;
- revision;
- equipment entries.

Snapshot equality/fingerprinting is canonical and order-independent for equivalent state.

### `CharacterEquipmentCompatibility`

Pure validation service. It checks tags, capabilities, anchors, supported channels and channel occupancy without accessing a scene tree.

### `CharacterEquipmentSource`

Abstract source boundary for equipment snapshots.

CH7 initially provides:

```text
CharacterEquipmentSource
        ▲
        │
LabEquipmentSource
```

A later integration branch may add:

```text
CharacterEquipmentSource
        ▲
        │
ItemGraphEquipmentSource
```

without replacing the equipment presenter.

## Initial compatibility result codes

```text
OK
INVALID_LAYOUT
INVALID_PROFILE
INVALID_ITEM_ID
INCOMPATIBLE_CHARACTER_TAG
FORBIDDEN_CHARACTER_TAG
MISSING_CAPABILITY
UNSUPPORTED_ANCHOR
UNSUPPORTED_CHANNEL
EQUIPMENT_CHANNEL_OCCUPIED
ITEM_ALREADY_EQUIPPED
ITEM_NOT_EQUIPPED
```

No automatic replacement/swap is performed in the laboratory source. Production atomic replace belongs to a future Item Graph transaction.

## First laboratory profiles

The initial headless laboratory uses semantic profiles only:

```text
Helmet Mk1
  presentation_id: wearable.helmet.mk1
  anchor: body.head
  occupies: body.head.outer
  requires: equipment.headwear

Backpack Mk1
  presentation_id: wearable.backpack.mk1
  anchor: gear.back
  occupies: gear.back
  requires: equipment.backpack

EVA Suit Mk1
  presentation_id: wearable.eva_suit.mk1
  anchor: body.root
  occupies:
    body.torso.outer
    body.arms.outer
    body.legs.outer
  requires: equipment.clothing
```

The EVA suit is intentionally one item occupying multiple channels.

## CH7 implementation sequence

```text
CH7.0 Architecture Lock
  ↓
CH7.1 Headless Equipment Domain
  ↓
CH7.2 Deterministic LabEquipmentSource
  ↓
CH7.3 Generic Equipment Presenter
  ↓
CH7.4 Quaternius Rig Adapter
  ↓
CH7.5 Rigid Helmet + Backpack
  ↓
CH7.6 CH6 FP/TP/Shadow/Crouch Composition
  ↓
CH7.7 Second Rig Proof
  ↓
CH7.8 One Skinned Garment
  ↓
CH7.9 Lifecycle Stress
  ↓
CH7 Acceptance
```

Every later presentation checkpoint must continue to run the complete CH6 acceptance runner.

## Future production boundary

Production equip/unequip will be canonical Item Graph operations. CH7 does not implement them in this branch.

Target direction:

```text
Item Graph replica
      ↓
ItemGraphEquipmentSource
      ↓
CharacterEquipmentSnapshot
      ↓
CharacterEquipmentPresenter
      ↓
CharacterRigAdapter + WearablePresentationCatalog
```

Movement snapshots must not contain equipment state. Persistence must save canonical item relationships rather than visual flags.
