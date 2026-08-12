# FPE-R2 S6 ACCEPTED → S7 RESOURCE-BACKED HAND VISUAL PROVIDER

Дата: 2026-08-12

Ветка: `research/first-person-embodiment-prototype`

Frozen parent: `feature/ch9-6-playable-network-equipment-lab @ e547ba52a440e72cc02c6bbe449edaf160bae7ab`

## S6 acceptance

Operator rerun на `6d10e42a10468da585a3d042c44831b3332b2a47` завершён чисто:

- `FirstPersonEmbodiment contract: PASS (23 assertions)`
- hotbar network/presentation/local gates PASS
- equipment result policy PASS
- S1 shared held-item state PASS
- S2 catalog/profile gates PASS
- S3 pose/rig/posed-viewmodel gates PASS
- S4 two-hand gates PASS
- S5 secondary-world-hand gates PASS
- `FPE R2 S6 hand visual provider boundary: PASS (33 assertions)`
- sandbox owner-collision isolation PASS
- performance gate PASS
- graphical scene-load PASS (23 assertions)
- final `FirstPersonEmbodiment focused tests: PASS`

Operator additionally подтвердил, что graphical runtime работает нормально после вставки provider boundary. Default visual provider остаётся `PROCEDURAL_SEGMENTS`, поэтому S6 не выдаёт procedural geometry за production hand asset.

Решение: **FPE-R2 S6 RESEARCH ACCEPTED**.

## S7 objective

S7 переводит абстрактную S6 substitution boundary в настоящий resource-backed путь:

```text
res://hand_visual.tscn
        ↓
ResourceBackedFirstPersonHandVisualProvider
        ↓
validated FPE hand asset schema
        ↓
BoneAttachment3D targets
        ↓
canonical 17-bone hand Skeleton3D
        ↓
existing pose / grip / two-hand logic
```

S7 НЕ меняет Item Graph, network authority, gameplay transform ownership или accepted CH9.6.

## S7 asset contract v1

PackedScene root обязан быть `Node3D` и иметь metadata:

- `fpe_hand_visual_schema = planet_simulator.fpe_hand_visual_asset.v1`
- `fpe_compatible_skeleton_schema = planet_simulator.fpe_hand_skeleton.v1`
- `fpe_hand = both|left|right`
- optional `fpe_provider_id`

Прямые дети root для S7 v1 — `BoneAttachment3D`. Каждый attachment обязан ссылаться на существующую bone canonical hand skeleton. Mesh descendants переводятся только на viewmodel render layer и не создают physics bodies.

Это bounded authored-segment resource contract. Production skinned mesh import/retargeting является следующим визуальным этапом, а не claim S7.

## Implemented S7 surface

- `scripts/characters/presentation/resource_backed_first_person_hand_visual_provider.gd`
- `scripts/characters/presentation/resource_configurable_two_hand_first_person_embodiment.gd`
- `scripts/characters/lab/quaternius_first_person_embodiment_fix15.gd`
- `tests/fixtures/fpe_s7_authored_hand_visual.tscn`
- `tests/characters/test_fpe_r2_s7_resource_backed_hand_visual_provider.gd`
- graphical scene advanced to Fix15
- focused runner includes S7 gate
- PLAY runner accepts `-HandVisualScene <res:// PackedScene>`

Default PLAY without `-HandVisualScene` preserves S6 procedural visuals. Explicit resource configuration is fail-closed on missing/incompatible asset schema.

## S7 operator gates

1. Full focused suite must remain clean.
2. New gate must report:

```text
FPE R2 S7 resource-backed hand visual provider: PASS
```

3. Default graphical run must preserve all S2-S6 behavior and HUD should report S7 `DEFAULT` with S6 procedural providers.
4. Adapter graphical run:

```powershell
.\PLAY_FPE_RESEARCH.ps1 -GodotPath $Godot -ResetState -HandVisualScene "res://tests/fixtures/fpe_s7_authored_hand_visual.tscn"
```

must report:

```text
S7 resource hand: REQUESTED
L:RESOURCE_BONE_ATTACHMENTS
R:RESOURCE_BONE_ATTACHMENTS
```

The fixture is deliberately crude and exists only to prove the real resource loading/binding route. It is not a production art candidate.

## Authority boundary

S7 remains presentation-only:

- `owns_item_state = false`
- `owns_network_state = false`
- `owns_gameplay_transform = false`
- no collision/physics body is created by the hand visual provider
- canonical world `hand.grab` authority remains fail-closed and outside S7

## Next after S7

After clean focused + graphical resource-adapter evidence, proceed to a production-quality authored/skinned first-person hand provider/retargeting stage without changing the already accepted grip/pose/two-hand contracts.
