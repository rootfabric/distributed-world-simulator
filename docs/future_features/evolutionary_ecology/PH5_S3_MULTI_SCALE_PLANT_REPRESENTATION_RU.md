# ECO.PH5-S3 — Multi-Scale Plant Representation

Статус: **RESEARCH ONLY / ACCEPTANCE READY, NOT PROMOTED**.

## Архитектурная граница

S3 добавляет только derived presentation layer:

```text
GrowthGraph
    ↓
PlantRenderDescription
    ↓
PlantMultiScaleRepresentation
    ├─ FULL
    ├─ REDUCED
    ├─ CANOPY
    ├─ IMPOSTOR
    └─ POPULATION_ONLY
```

Обратного пути из representation в GrowthGraph, genome, resource state, lifecycle, selection или reproduction state нет. Individual projector получает `PlantRenderDescription`, renderer profile, tier, immutable `source_ecology_identity` и deterministic seed. Биологический state в API projector не передаётся.

## Tier contracts

`FULL` повторно использует принятый PH5-S2 `plant_3d_materializer_v1.gd`: tapered branch mesh + instanced foliage. Source `PlantRenderDescription` не меняется.

`REDUCED` создаёт временную derived projection-description: main axis схлопывается в один envelope segment, lateral chains — в один segment на chain, foliage детерминированно прореживается. Исходные bounds и source hashes сохраняются в artifact. Accepted renderer profile остаётся неизменным.

`CANOPY` строится только из canopy/bounds/foliage/branch envelope исходного render description. Artifact содержит canopy center, radius, height, density, foliage mass projection и branch envelope.

`IMPOSTOR` хранит billboard width/height/resolution и `source_shape_identity`, связанный с тем же source graph/render description. Presentation identity отличается от FULL/CANOPY, source ecology identity — нет.

`POPULATION_ONLY` принимает aggregate population projection source. Он не принимает массив individual GrowthGraphs и не проходит циклом по canonical organisms. Количество visual samples ограничено 128, `materialized_growth_graph_count = 0`, а `canonical_organism_count` только копируется в derived artifact.

## Determinism и provenance

Каждый artifact несёт:

```text
source_ecology_identity
source_graph_hash        # individual tiers
render_description_hash  # individual tiers
profile_id
profile_hash
tier
renderer_version
deterministic_seed
deterministic_input_identity
representation_hash
presentation_identity
```

`representation_hash` вычисляется только из deterministic projection data. Runtime/performance timing в hash не входит.

## Acceptance transitions

Focused acceptance проверяет:

```text
FULL → REDUCED
REDUCED → CANOPY
CANOPY → IMPOSTOR
IMPOSTOR → FULL
```

После каждого switch полностью сравнивается immutable truth snapshot, включающий GrowthGraph, genome, resource state, lifecycle state, selection-relevant phenotype hash и reproduction/seed envelope.

Population proof использует patch с `1,000,000` canonical organisms и доказывает far-view с `0` materialized GrowthGraphs и максимум `128` visual samples без изменения canonical count.

## Graphical lab

Scene:

```text
res://scenes/labs/ecology/eco_ph5_s3_multi_scale_representation_lab.tscn
```

Управление:

```text
1 = FULL
2 = REDUCED
3 = CANOPY
4 = IMPOSTOR
5 = POPULATION_ONLY
A/D или ←/→ = предыдущий/следующий tier
```

Lab показывает source ecology identity, GrowthGraph hash, representation hash, renderer version и bounded metrics. Для первых четырёх tier используется один и тот же reference plant truth. `POPULATION_ONLY` переключает lab на aggregate population truth и явно показывает `materialized_growth_graphs=0`.

Для ручной graphical проверки на Windows double build из корня checkout:

```powershell
godot.windows.editor.double.x86_64.exe --path . res://scenes/labs/ecology/eco_ph5_s3_multi_scale_representation_lab.tscn
```

Graphical PASS можно фиксировать только после фактического наблюдения всех пяти presentation tier и подтверждения, что displayed source GrowthGraph hash не меняется при 1→2→3→4→1 roundtrip.

## Не закрывает

PH5-S3 не исправляет и не маскирует `FULL_POOL_COMPACT / HEIGHT_LOW dominance`. Это остаётся отдельной задачей CAL1. S3 не запускает CONV0, не создаёт production adapter и не меняет production runtime.
