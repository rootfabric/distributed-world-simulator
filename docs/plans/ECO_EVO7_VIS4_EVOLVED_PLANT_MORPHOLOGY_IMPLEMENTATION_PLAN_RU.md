# ECO.EVO7 VIS4 — Evolved Plant Morphology / PLAY0.MORPH

Статус: ACTIVE PARALLEL DEVELOPMENT / STREAM1 + VIS4 / ROADMAP SPLIT CONFIRMED  
Дата: 2026-08-30  
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1  
Exact base: PAR3 R3.2 — 8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf  
Sibling: feature/eco-evo7-stream1-bounded-generation-stream-r1

## Решение

VIS4 развивается параллельно STREAM1 от одного exact PAR3 R3.2 predecessor.

~~~text
                 PAR3 R3.2
                     |
          +----------+----------+
          |                     |
          v                     v
       STREAM1                 VIS4
 bounded generation     evolved morphology
          |                     |
          +----------+----------+
                     v
               PLAY1 / PERF2
~~~

STREAM1 отвечает за bounded orchestration поколения. VIS4 отвечает только за read-only presentation уже существующей ecology. VIS4 не должен становиться дочерней веткой STREAM1 и не меняет biology.

## Текущая parallel execution policy

На 2026-08-30 обе линии уже ведутся параллельно:

~~~text
STREAM1 HEAD:
4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4

VIS4 HEAD до этого roadmap amendment:
a6cedcd018a03740961c4b9d2798cba678f5009f
~~~

После принятия STREAM1 основная ECO-ветка НЕ ждёт завершения PLAY0.MORPH.

Правильная execution graph:

~~~text
                         PAR3 R3.2
                             |
                +------------+------------+
                |                         |
                v                         v
             STREAM1                    VIS4
                |                         |
                v                         v
           PERF2.SIM                PLAY0.MORPH
                |                         |
                +------------+------------+
                             |
                             v
                        PERF2.CONV
                             |
                             v
                    PLAY1 LIVING REGION
~~~

### PERF2.SIM

Разрешён сразу после независимой приёмки STREAM1, даже если VIS4/PLAY0.MORPH ещё не завершён.

Scope:

~~~text
PERF2.0 measurement contract
PERF2.1 STREAM1 generation profiling
PERF2.2 working-set / memory
PERF2.3 simulation scaling
PERF2.4 runtime optimization
~~~

Здесь измеряются generation throughput, CPU time по фазам, memory/working-set, allocator pressure, proposal/commit cost, scaling по cells/population и simulation bottlenecks.

### PERF2.CONV

Финальный integrated performance gate разрешён только после:

~~~text
STREAM1 ACCEPTED
+
VIS4 / PLAY0.MORPH ACCEPTED
~~~

Scope:

~~~text
PERF2.5 VIS4 materialization profiling
PERF2.6 PH5 LOD / cache tuning
PERF2.7 STREAM1 + VIS4 integrated load
PERF2.8 PLAY1 performance acceptance
~~~

Только PERF2.CONV подтверждает реальную стоимость будущего PLAY1, потому что в этот момент одновременно присутствуют bounded generation execution и реальный PH5 morphology workload.

Следовательно:

~~~text
STREAM1 done first
-> continue immediately into PERF2.SIM

PLAY0.MORPH still active
-> does not block PERF2.SIM

PLAY1 acceptance
-> blocked until PERF2.CONV GREEN
~~~

## Почему VIS4 нужен уже сейчас

Текущий 3D PLAY0 действительно использует один общий шаблон:

~~~text
BoxMesh -> stem
SphereMesh -> crown
~~~

Источник: scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd.

Высота берётся из realized_height_m, но crown radius сейчас выводится эвристикой из leaf_area_index_proxy. Уже существующие realized_crown_radius_m и realized_crown_density primary PLAY0 path не использует.

При этом EVO7 уже имеет morphology truth:

~~~text
max_height_m
crown_spread_m
apical_dominance
foliage_density
leaf_economics_proxy
structural_investment
root_spread_m
root_shoot_ratio

realized_height_m
realized_crown_radius_m
realized_crown_density
leaf_area_index_proxy
realized_root_depth_m
realized_root_spread_m
~~~

Значит первая цель — не придумать новые типы растений, а честно показать уже существующие phenotype differences.

## PH5 обязателен к переиспользованию

Accepted ECO.PH5 уже содержит цепочку:

~~~text
DevelopmentTraits
 -> GrowthGraph
 -> PlantRenderDescription
 -> RendererProfile
 -> ArrayMesh / MultiMesh
~~~

И tiers:

~~~text
TIER_0_FULL
TIER_1_REDUCED
TIER_2_CANOPY
TIER_3_IMPOSTOR
TIER_4_POPULATION_ONLY
~~~

VIS4 не создаёт второй procedural tree renderer. Используются существующие plant_growth_graph_skeleton_v1.gd, plant_render_description_v1.gd, plant_3d_materializer_v1.gd и multiscale PH5 stack.

## Инвариант

~~~text
ecology truth
 != morphology presentation
 != LOD
 != deterministic visual individuality
~~~

Data flow только наружу:

~~~text
LS3.6 immutable snapshot
 -> morphology descriptor
 -> derived PH5 render input
 -> GrowthGraph
 -> render materialization
 -> pixels
~~~

Renderer не меняет genome, phenotype, fitness, population, generation, persistence или network state.

Обязательный gate:

~~~text
renderer OFF ecology_state_hash
==
renderer ON ecology_state_hash
~~~

## Implementation ladder

### VIS4.0 — Truth / Contract Audit

Зафиксировать источник каждого visual field: realized height/crown/density, hereditary branching traits, foliage strategy, structural investment, roots и individual_seed.

Exit: ни одно visual field не требует второго biology implementation.

### VIS4.1 — Morphology Descriptor V2

Добавить в source-bound read model:

~~~text
individual_seed
realized_crown_radius_m
realized_crown_density
structural_investment
apical_dominance
internode_length_m
branch_probability
branch_angle_deg
branch_length_ratio
branching_depth
crown_spread_m
foliage_density
leaf_economics_proxy
~~~

Hereditary fields читаются только из validated bundle, realized fields — только из accepted live phenotype evidence. Missing source -> fail-closed.

### VIS4.2 — Honest diagnostic morphology

Исправить VIS2/VIS3 presentation так, чтобы crown width исходила из realized_crown_radius_m, density — из realized_crown_density, silhouette — из branching traits.

Добавить neutral-color mode. Различия должны быть видны формой, а не только lineage color.

### VIS4.3 — Live Phenotype -> PH5 Bridge

PH5 DevelopmentTraits задают potential, live phenotype зависит от environment/history. Поэтому нужен presentation-only bridge:

~~~text
hereditary topology
+
realized height/crown envelope
+
individual_seed
+
source hashes
 -> accepted PH5 GrowthGraph
~~~

Один source plant + seed + tier обязан давать тот же geometry hash после restart.

### VIS4.4 — PLAY0.MORPH

Primary near-plant path меняется:

~~~text
BoxMesh + SphereMesh
        |
        v
PH5 GrowthGraph
 -> tapered branch mesh
 -> foliage MultiMesh
 -> canopy/impostor LOD
~~~

Игрок должен иметь возможность подойти к растениям на реальной поверхности планеты и увидеть разные формы.

### VIS4.5 — Deterministic individuality

individual_seed может детерминированно менять branch azimuth, bounded angle jitter, foliage placement и небольшую asymmetry. Он не создаёт ecology advantage.

### VIS4.6 — Grid appearance boundary

VIS2 уже имеет stable deterministic jitter. VIS4 может переиспользовать его семантику для небольшого presentation offset.

Но:

~~~text
visual offset != ecological position
~~~

32x32 Spatial Cohort Lattice остаётся truth. Настоящие continuous plant positions — отдельный будущий ECO.SPATIAL1.

### VIS4.7 — Morphology Inspector

Предлагаемая клавиша F6. Для выбранного растения показывать lineage, generation, individual_seed, height, crown radius/density, LAI, branching traits, foliage density, structural investment, roots, water/light/resource balance и source/render hashes.

### VIS4.8 — Diversity Evidence

Разделить два gate:

1. Renderer fidelity — controlled fixtures показывают tall/low, narrow/wide, vertical/bushy, sparse/dense и разные branch angles.
2. Live diversity — реальная population измеряется по morphology variance/clusters.

Если renderer корректен, но population схлопнулась:

~~~text
RENDERER_PASS
LIVE_DIVERSITY_INSUFFICIENT
~~~

Запрещено маскировать это random TREE/BUSH/GRASS формами.

### VIS4.9 — Performance / LOD

Собирать visible plant/tier counts, graph build ms, materialization ms, cache hits, branch primitives, foliage instances, draw calls, FPS/frame time.

Этот checkpoint даёт VIS4-local performance evidence, но НЕ заменяет PERF2.CONV. VIS4 может самостоятельно оптимизировать PH5 materialization и LOD, однако итоговая PLAY1 performance acceptance выполняется только на композиции STREAM1 + VIS4.

## Acceptance PLAY0.MORPH R1

1. EVO7 biology unchanged.
2. VIS4 остаётся sibling STREAM1.
3. PH5 reused; второго procedural renderer нет.
4. BoxMesh/SphereMesh не primary near-plant form.
5. Source morphology реально управляет height/crown/branch/foliage silhouette.
6. individual_seed deterministic.
7. Нет canonical TREE/BUSH/GRASS classes.
8. Neutral-color mode доказывает shape differences.
9. Renderer ON/OFF сохраняет ecology_state_hash.
10. LOD сохраняет ecology truth/source hash.
11. Restart сохраняет descriptor/graph/geometry hashes.
12. Presentation scatter явно noncanonical.
13. F6 inspector связывает форму с source traits.
14. Controlled fixtures проходят.
15. Live campaign сообщает реальную diversity количественно.
16. Insufficient diversity не маскируется random decoration.
17. PLAY0 остаётся интерактивным.
18. Existing VIS2/VIS3/PLAY0 authority guards зелёные.
19. Нет новых ecology/persistence/network write authority.
20. Exact double-Godot + graphical evidence обязательны до ACCEPTED.

## Convergence

Convergence теперь двухуровневый.

~~~text
STREAM1 ACCEPTED
      |
      v
  PERF2.SIM ------------------+
                              |
VIS4 -> PLAY0.MORPH ACCEPTED  |
      |                       |
      +-----------+-----------+
                  |
                  v
             PERF2.CONV
                  |
                  v
         PLAY1 LIVING REGION
~~~

PERF2.SIM может начаться раньше завершения VIS4.

PERF2.CONV и PLAY1 не могут быть приняты раньше завершения обеих линий.

VIS4 читает только fully published generation. Partial STREAM1 work никогда не становится presentation source. Renderer/materialization workload добавляется в performance acceptance только на PERF2.CONV.

## Следующие самостоятельные этапы

MORPH1 — расширение свободно эволюционирующей архитектуры: internode length, branch probability, angle, length ratio, branching depth. Только после benefit/cost audit и через единую lineage/mutation authority.

ECO.SPATIAL1 — настоящая continuous physical position растения внутри cell. Не смешивать с presentation scatter.

## Обновлённая ECO-roadmap

~~~text
                         PAR3 R3.2
                             |
                +------------+------------+
                |                         |
                v                         v
             STREAM1                    VIS4
                |                         |
                v                         v
           PERF2.SIM                PLAY0.MORPH
                |                         |
                |                    VIS4.5-4.9
                |                         |
                +------------+------------+
                             |
                             v
                        PERF2.CONV
                             |
                             v
                    PLAY1 LIVING REGION
                             |
                             v
                           MORPH1
                             |
                             v
                        ECO.SPATIAL1
                             |
                             v
                            LS4
~~~

Execution rule:

~~~text
STREAM1 accepted earlier -> immediately continue PERF2.SIM.
VIS4 continues independently.
No waiting between STREAM1 and PERF2.SIM.
Final PERF2.CONV waits for both lines.
PLAY1 opens only after PERF2.CONV GREEN.
~~~

Текущая программа уже работает в parallel mode; этот roadmap amendment фиксирует это как каноническое execution rule для ECO track.

Первый рабочий пункт VIS4-ветки: VIS4.0 Truth / Contract Audit.


---

## VIS4.0 implementation result — 2026-08-30

Truth / Contract Audit уточнил первоначальный roadmap.

1. Exact live branch topology должен предпочитать PH2 realized_development_traits, а не raw hereditary dev_traits: PH2 реально изменяет internode, apical dominance, branch probability/angle/length и crown spread под environment plasticity.
2. LS3.4 публикует height/LAI/root/resource evidence, но теряет realized crown radius/density, structural/leaf strategy seals и exact PH2 topology.
3. VIS4.1 поэтому обязан делать source-bound pass-through/sidecar из уже вычисленного LS3.4/PH2 pass. Renderer-side biology recomputation запрещён.
4. В EVO7 R1 генетически mutable из PH0 только max_height_m, crown_spread_m и apical_dominance; internode_length_m, branch_probability, branch_angle_deg, branch_length_ratio и branching_depth наследуются, но пока не входят в morphology mutation AXES. Это остаётся областью MORPH1.
5. PH5 переиспользуется, но его current render description имеет fixed branch base radii и fixed foliage anchors per segment. structural_investment, realized_crown_density и leaf strategy требуют тонкой source-bound VIS4 presentation mapping поверх accepted PH5, а не второго tree renderer.

Durable audit sources:

~~~text
docs/plans/ECO_EVO7_VIS4_0_TRUTH_CONTRACT_AUDIT_RU.md
config/ecology/eco-evo7-vis4-truth-contract-audit.v1.json
tests/ecology/eco_evo7_vis4_0_truth_contract_audit_acceptance.gd
~~~
