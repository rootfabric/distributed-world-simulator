# ECO.EVO7 VIS5.2 — Noncanonical Ground-Cover Bridge EXACT VERIFIED CLOSED R1

Дата: 2026-09-03  
Статус: CLOSED  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Exact runtime subject

~~~text
HEAD:
e8ad5ad9f36eba45ff533918c2a97730d766aa17

TREE:
31d97747b097146b652a56ba6d5a36c73bdbe496
~~~

Source-export validation:

~~~text
validation branch:
validation/eco-vis5-2-source-export-r1

source-export run:
33749309612 = SUCCESS

source archive SHA-256:
2ec45746c245ab2048364d913096f191caa77bd149250a3c45a7868e4862ff61
~~~

Godot:

~~~text
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

## Exact runner result

~~~text
RUN_ECO_EVO7_VIS5_2_TESTS.sh

exit code:
0

full log SHA-256:
bba8434fe63beca01af5555bac92f4bde347fb21b596624016a9fc3f2ff9f817
~~~

Late-chain exact results:

~~~text
VIS4.7 Morphology Inspector                         PASS 106
VIS4.8 Diversity Evidence                          PASS 106
VIS4.9 Performance / LOD                           PASS 116
VIS5.0 Terrain / Ecosystem Composition Audit       PASS 87
VIS5.1 Terrain Surface Frame Adapter                PASS 70
VIS5.2 Noncanonical Ground-Cover Bridge             PASS 57
~~~

Earlier predecessor gates in the same runner were also GREEN, including:

~~~text
FFF2          56
PH2          107
VIS4.0       176
LS3.4         45
LS3.6        114
VIS4.1       598
VIS1          41
VIS2          69
VIS3         107
VIS4.2      1265
PH5          720
PH5-S2       387
PH5-S3        49
PH5-S3        61
PH5-S4      5026
PH5-S4       430
VIS4.3       752
PLAY0        103
VIS4.4        74
VIS4.5       491
VIS4.6       796
~~~

## Реализовано

VIS5.2 теперь является отдельной executable presentation boundary:

~~~text
canonical terrain
      |
      v
VIS5.1 surface frame
      |
      +-- canonical surface point
      +-- derived terrain normal
      +-- terrain_basis
      +-- geometric slope
      |
      v
VIS5.2 ground-cover bridge
      |
      +-- deterministic presentation seed
      +-- grass-density / water / snow / slope filters
      +-- weighted grass variants
      +-- terrain-following Transform3D
      +-- grass MultiMesh batching
      +-- grass mesh/material donor path
      +-- ground_cover LOD visibility
      +-- deterministic generation_hash
      |
      X procedural trees
      X ecology individuals
      X population/count semantics
      X fitness semantics
      X mutation semantics
      X Descriptor V2 writes
      X ecology_state_hash writes
~~~

Permanent truth marker:

~~~text
NONCANONICAL_SCENERY
~~~

Это важная архитектурная граница: плотная трава уже может визуально покрывать сложный terrain, но пока не притворяется биологической популяцией ECO.

## Найденные и исправленные дефекты

### 1. Terrain-normal orientation

Первый focused exact run выявил скрытый риск world-space yaw после ориентации Basis. Исправлено на локальную композицию:

~~~gdscript
terrain_basis
* Basis(Vector3.UP, yaw)
* Basis.from_scale(scale_value)
~~~

Проверяемый invariant:

~~~text
planned_transform.basis.y.normalized()
dot terrain_normal
>= 0.999999
~~~

Это критично для будущих пригорков, оврагов, склонов и WORLDGEN1 procedural matter terrain.

### 2. Linux runner portability

Обнаружено, что исторические VIS5.0/VIS4.9 shell runners tracked как mode 100644, хотя вызываются напрямую из predecessor chain.

VIS5.2 runner теперь временно делает только эти predecessor runners executable, восстанавливает их tracked mode через EXIT trap и вызывает VIS5.1 через bash. Это позволило exact source-export tree пройти полный regression chain без изменения закрытого runtime-кода predecessor checkpoints.

## Headless RenderingServer note

Dummy/headless RenderingServer не используется как authoritative readback instance-transform buffer после MultiMesh handoff.

Поэтому:

~~~text
orientation invariant
  -> проверяется на planned Transform3D ДО MultiMesh handoff

MultiMesh boundary
  -> отдельно проверяется instance_count / mesh / material / grouping / LOD
~~~

Это исключает ложные результаты от headless renderer readback.

## Fresh import diagnostics

Fresh import exact source завершился и runner вернул 0, но Godot напечатал три уже существующих parse diagnostics в старых EVO5 scene files:

~~~text
eco_evo5_probe2_tree_lab.tscn
eco_evo5_t51_creature_lab.tscn
eco_evo5_terrain_fly_lab.tscn
~~~

VIS5.2 эти файлы не меняет; все predecessor и VIS5 acceptance scripts, включая новые 57 assertions, завершились GREEN. Диагностики не скрываются и должны оставаться отдельным legacy-cleanup item, но не являются regression, внесённой VIS5.2.

## Closure

~~~text
VIS5.0 ✅
  |
VIS5.1 ✅
  |
VIS5.2 ✅ CLOSED
  |
  v
VIS5.3 ★ CURRENT ★
Mixed-Strata Composition Lab
~~~

Следующий практический смысл VIS5.3:

~~~text
real uneven terrain
+
VIS4 source-bound evolved PH5 macro plants
+
VIS5.2 dense noncanonical ground cover
+
terrain scenery
~~~

После этого линия сможет двигаться к:

~~~text
VIS5.4 Composition LOD / Streaming
VIS5.5 Visual Evidence / PLAY1 handoff
WORLDGEN1 WG1.7 ECO Surface Field Bridge
~~~
