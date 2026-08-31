# ECO.EVO7 VIS4 — Evolved Plant Morphology / PLAY0.MORPH

Статус: ACTIVE PARALLEL DEVELOPMENT / VIS4.3 CLOSED / VIS4.4 R2 CLOSED / NEXT: VIS4.5  
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


---

## VIS4.1 implementation result — 2026-08-30

VIS4.1 закрыл publication gap, обнаруженный VIS4.0, без переноса biology в renderer.

Новая цепочка:

~~~text
LS3.4 existing phenotype pass
  |
  +-> PH2 realized_development_traits
  +-> exact GrowthGraph hash
  +-> FunctionalPhenotype morphology scalars
  |
  v
PlantMorphologyEvidence.v1
  |
  v
separate sealed presentation sidecar
  |
  v
Workbench.get_morphology_evidence()
  |
  v
VIS4 Morphology Descriptor V2
~~~

Ключевой инвариант: ecology snapshot schema/state_hash не расширялись morphology sidecar-ом. Evidence живёт отдельно и связывается с generation, precompetition population hash, competition hash и postcompetition population hash.

VIS4.1 публикует три явно разделённых слоя:

~~~text
GENETIC POTENTIAL
REALIZED PH2 TOPOLOGY
FUNCTIONAL MORPHOLOGY
~~~

и отдельно competition context.

Реализованные durable surfaces:

~~~text
scripts/research/ecology/plant_morphology_evidence_v1.gd
scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd
scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd
scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd
tests/ecology/eco_evo7_vis4_1_source_bound_morphology_evidence_acceptance.gd
RUN_ECO_EVO7_VIS4_1_TESTS.ps1
RUN_ECO_EVO7_VIS4_1_TESTS.sh
.github/workflows/evo7-vis4-1-source-bound-morphology.yml
~~~

VIS4.2 теперь может заниматься только diagnostic presentation mapping. Повторный вызов CoupledDevelopment/FunctionalPhenotype из presentation запрещён.


### VIS4.1 non-causal hardening

Implementation review выявил и закрыл дополнительный риск: derived morphology evidence не может быть обязательным условием успешного ecology generation.

~~~text
ecology / competition success
          |
          +-> optional complete morphology sidecar
                         |
                         v
                  presentation consumer

sidecar packaging failure
          |
          v
presentation unavailable / fail-closed
NOT ecology rollback
~~~

Это защищено focused source-gate: между MorphologyEvidence.build_record() и продолжением accepted competition path нет presentation-originated return/failure edge. Complete binding к survivor population проверяется уже на read side.


---

## VIS4.1 Windows R1 RED -> R2 repair

Fresh exact Windows verifier на SHA:

~~~text
782ceb53d4bd2cf35dd2664d5c05928322b1306c
~~~

получил RED:

~~~text
full runner RC=1
focused 121 assertions / 71 failures
~~~

Причина не в biology, а в неверном VIS4.1 identity assumption:

~~~text
bundle individual_seed
!=
SeedEnvelope / PH2 / GrowthGraph individual_seed
~~~

R2 разделяет:

~~~text
hereditary_individual_seed
development_individual_seed
~~~

и делает positive evidence non-vacuous обязательным acceptance condition.

Fresh Windows verifier получил GREEN на R2 exact-tested implementation:

~~~text
HEAD: c499a39ee3fa4c7b5ab871df7f89f7cb4b6ec436
TREE: 4427bada5367f9b06d4b642a6ab9e73670821c2e
Godot: 4.7.1.stable.double.custom_build.a13da4feb

VIS4.1 R2 focused: PASS (598 assertions)
living/evidence/descriptor: 61 / 61 / 61
full runner: PASS
RC=0
~~~

Formal closure:

~~~text
VIS4.1 R2
ACCEPTED
WINDOWS VERIFIED
CLOSED
~~~

Canonical next checkpoint:

~~~text
VIS4.2 — Honest Diagnostic Morphology
~~~

VIS4.2 теперь разблокирован. Он обязан читать только Descriptor V2 и не вызывать biology напрямую.

Durable closure evidence:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_1_WINDOWS_VERIFIED_CLOSED_R2_RU.md
~~~


---

## VIS4.2 implementation result — 2026-08-31

VIS4.2 Honest Diagnostic Morphology реализован как отдельная diagnostic-only presentation surface поверх accepted VIS4.1 Descriptor V2.

Новая цепочка:

~~~text
Workbench public read facade
 -> VIS4.1 Descriptor V2
 -> VIS4.2 DiagnosticMorphologyMapper
 -> VIS4.2 DiagnosticMorphologyOverlay
 -> diagnostic pixels
~~~

Критическое изменение presentation truth:

~~~text
OLD VIS2 diagnostic approximation:
leaf_area_index_proxy -> crown radius heuristic

VIS4.2 honest mapping:
realized_crown_radius_m -> crown width
realized_crown_density  -> crown visual density
realized_topology       -> branch silhouette
~~~

VIS4.2 также добавляет neutral-color mode, чтобы shape diversity была видна без lineage color.

Scope remains diagnostic:

~~~text
VIS4.2 does NOT replace PLAY0
VIS4.2 does NOT invoke biology
VIS4.2 does NOT add seed-driven individuality
VIS4.2 does NOT create taxonomy classes
~~~

VIS4.2 focused acceptance validates exact source seals, morphology pass-through, controlled monotonic visual mappings, live silhouette diversity, neutral-color invariance, tamper rejection and deterministic replay.

Durable checkpoint:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_2_HONEST_DIAGNOSTIC_MORPHOLOGY_R1_RU.md
~~~

Formal status:

~~~text
VIS4.2 IMPLEMENTED CANDIDATE
exact Windows verification required
VIS4.3 blocked until VIS4.2 GREEN
~~~


---

## VIS4.2 Windows R1 RED -> R2 repair — 2026-08-31

Fresh exact Windows verifier tested:

~~~text
HEAD: e74ffda554be177201542743f596b2c0bb272018
TREE: a7090261af65b3f4a3313aa0c0275e18850f2435
Godot: 4.7.1.stable.double.custom_build.a13da4feb
~~~

Result:

~~~text
VIS4.2 focused: FAIL
1263 assertions / 2 failures
full runner RC=1
~~~

All parent regressions and 1261 VIS4.2 assertions were GREEN.

Single root cause:

~~~text
typed Array[Dictionary] set_descriptors boundary
rejected untyped empty [] on generation-zero/fail-closed paths
~~~

R2 changes only the presentation input boundary:

~~~text
set_descriptors(Array)
-> validates every element
-> stores only Array[Dictionary]
~~~

Acceptance now explicitly proves:

~~~text
empty [] -> ACCEPT
malformed generic array -> REJECT
~~~

New exact runnable R2 boundary:

~~~text
HEAD: 3ecee0f0fe491a6f76145eb8f2da133c820ae793
TREE: 762806c32b43a1cc0740e7b5ab78be8e1cb108bd
~~~

Durable evidence:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_2_WINDOWS_VERIFICATION_RED_R1_RU.md
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_2_EMPTY_DESCRIPTOR_BOUNDARY_REPAIR_R2_RU.md
~~~

VIS4.3 runtime remains blocked until fresh exact Windows GREEN on R2.


---

## VIS4.2 R2 closure — 2026-08-31

Fresh exact Windows verification on:

~~~text
HEAD: 3ecee0f0fe491a6f76145eb8f2da133c820ae793
TREE: 762806c32b43a1cc0740e7b5ab78be8e1cb108bd
Godot: 4.7.1.stable.double.custom_build.a13da4feb
~~~

completed GREEN:

~~~text
VIS4.2 R2 focused: PASS (1265 assertions)
full runner: PASS
RC=0

Descriptor V2 / diagnostic / overlay:
61 / 61 / 61
~~~

Former VIS4.2-WIN-001 generation-zero and replay initialization paths are GREEN.

Formal status:

~~~text
VIS4.2 R2
ACCEPTED
WINDOWS VERIFIED
CLOSED
~~~

Durable closure:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_2_WINDOWS_VERIFIED_CLOSED_R2_RU.md
~~~

VIS4.3 exact PH5 bridge is now unblocked.


---

## VIS4.3 implementation result — 2026-08-31

VIS4.3 exact Live Phenotype -> PH5 bridge is implemented.

Exact runtime/test subject:

~~~text
HEAD: b8e8c2ffea260eea40ae3a451ec0c63d81028f76
~~~

Runtime architecture:

~~~text
same LS3.4 PH2 pass
 -> exact reconstruction sidecar
 -> validated realized DevelopmentTraits + development seed
 -> accepted PlantGrowthGraphSkeleton.build()
 -> exact graph_hash equality gate
 -> accepted PlantRenderDescription
 -> accepted PH5 multiscale representation/materializer
~~~

The bridge does not rerun CoupledDevelopment or FunctionalPhenotype and does not copy the GrowthGraph algorithm.

Focused acceptance requires exact reconstruction for all 61 generation-one survivors, all PH5 tiers, rehashed traits_id/development-seed rejection, and deterministic replay.

VIS4.3 verification is platform-neutral for this checkpoint; the exact Ubuntu double-Godot PASS below is the canonical closure evidence. VIS4.4 is unblocked.


VIS4.3 final pre-verification hardening also binds reconstruction evidence to the exact Descriptor V2 competition seal.

Final runtime/test subject:

~~~text
HEAD: b8e8c2ffea260eea40ae3a451ec0c63d81028f76
TREE: 920454da5bb41959680e3309c690f4ef399f3e6d
~~~

VIS4.4 preflight is documented in:

~~~text
docs/plans/ECO_EVO7_VIS4_4_PLAY0_MORPH_PREFLIGHT_RU.md
~~~

VIS4.4 runtime is unblocked by the accepted exact Ubuntu double-Godot verification.


## VIS4.3 Ubuntu exact pre-verification — GREEN

Frozen executable subject:

~~~text
HEAD: b8e8c2ffea260eea40ae3a451ec0c63d81028f76
TREE: 920454da5bb41959680e3309c690f4ef399f3e6d
~~~

Ubuntu exact pre-verification passed with the canonical double Godot
`4.7.1.stable.double.custom_build.a13da4feb` and the verified Linux binary
SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

All canonical VIS4.2 -> PH5 -> VIS4.3 regressions passed; the final VIS4.3 focused
acceptance reported 752 assertions and the canonical PASS marker. HEAD and TREE
remained unchanged and tracked status remained clean.

Closure qualification:

~~~text
VIS4.3 EXACT UBUNTU DOUBLE-GODOT VERIFICATION GREEN
EXACT SUBJECT VERIFIED
EXACT TREE VERIFIED
CANONICAL VIS4.2 -> PH5 -> VIS4.3 CHAIN GREEN
TRACKED STATUS CLEAN
VIS4.3 CLOSED
VIS4.4 PLAY0.MORPH RUNTIME UNBLOCKED
~~~

Owner acceptance rule for this checkpoint: VIS4.3 contains no platform-specific
runtime branch, native extension, OS-specific API or path-dependent computation.
Therefore a second Windows execution is optional cross-platform regression
evidence, not a closure prerequisite. The exact double-Godot Ubuntu run is
sufficient canonical verification for VIS4.3.


## VIS4.4 PLAY0.MORPH implementation result — 2026-08-31

VIS4.4 runtime integration is implemented on exact executable candidate:

~~~text
HEAD: ac9a0bf7ea7e794b4c3d6c884fc59e812516d17a
TREE: 7d13219874d3d02c2c84b4f278db2c385ba252fd
~~~

The primary live-plant path for generation > 0 is now:

~~~text
Workbench completed generation
 -> VIS4.1 Descriptor V2
 -> VIS4.3 exact reconstruction / PH5 bridge
 -> VIS4.4 PH5 renderer
 -> branch MeshInstance3D
 + foliage MultiMeshInstance3D
 + accepted PH5 far tiers
~~~

Generation-zero founders keep the legacy BoxMesh/SphereMesh fallback because no
realized PH2 morphology exists yet. Once a live generation activates PH5, legacy
stem/crown MultiMesh instances are emptied and hidden.

The integration keeps the existing physical placement and render-origin
contracts:

~~~text
cell direction -> ProceduralEarthWorld.get_surface_point(direction)
render-origin change -> transform update only
camera/view movement -> PH5 tier selection only
~~~

No second GrowthGraph, branch generator, foliage placer, ecology authority,
persistence owner or network authority is introduced.

Atomic failure behavior:

~~~text
complete VIS4.1 + VIS4.3 source -> PH5 publish
missing/tampered/incomplete source -> reject publish
                                  -> keep last completed presentation
~~~

Focused verification covers exact source hashes, TIER0/2/3/4 behavior,
population-only no-node semantics, neutral-color geometry invariance,
render-origin no-rebuild, tamper fail-closed, legacy instance retirement and the
existing PLAY0 regression.

Canonical candidate runner:

~~~text
RUN_ECO_EVO7_VIS4_4_TESTS.sh
~~~

R1 was RED in the focused acceptance parser only. R2 changed only explicit
local type annotations in the acceptance script; runtime production files were
unchanged.

Canonical verified R2:

~~~text
HEAD: 6ec628ad125114c1588f543d877ec83b1dfc81ed
TREE: 2f2cfd8c1893f0c9b76f8e98b936253a92d8bd18
Godot: 4.7.1.stable.double.custom_build.a13da4feb

VIS4.3 predecessor: PASS / 752 assertions
PLAY0 regression: PASS / 103 assertions
VIS4.4 focused: PASS / 74 assertions
final marker: PRESENT
tracked worktree: clean
~~~

Current qualification:

~~~text
VIS4.4 EXACT UBUNTU GREEN
VIS4.4 R2 CLOSED
NEXT: VIS4.5 DETERMINISTIC INDIVIDUALITY
~~~


## VIS4.4 R2 durable closure

The original R1 candidate `ac9a0bf7ea260eea40ae3a451ec0c63d81028f76`
was not accepted because Godot 4.7.1 double reported 12 parse errors in the new
focused acceptance test. The runtime implementation itself had already passed
the VIS4.3 predecessor and existing PLAY0 regression.

The test-only repair:

~~~text
6ec628ad125114c1588f543d877ec83b1dfc81ed
fix(eco): explicit type annotations in VIS4.4 PLAY0.MORPH acceptance script
~~~

adds explicit `Dictionary`, `Vector3` and `String` annotations for values
returned through untyped references. No runtime production path changed.

Exact R2 verification:

~~~text
HEAD: 6ec628ad125114c1588f543d877ec83b1dfc81ed
TREE: 2f2cfd8c1893f0c9b76f8e98b936253a92d8bd18

VIS4.3 predecessor PASS
PLAY0 regression PASS / 103 assertions
VIS4.4 focused PASS / 74 assertions
canonical VIS4.4 marker PRESENT
HEAD/TREE unchanged
tracked worktree clean
~~~

The durable morphology branch was fast-forwarded directly from its former tip
`6f982f1d...` to the exact tested R2 commit. Therefore the tested commit SHA is
preserved as the canonical executable boundary.

Closure checkpoint:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_4_PLAY0_MORPH_UBUNTU_VERIFIED_CLOSED_R2_RU.md
~~~

VIS4.4 is CLOSED. The morphology track may continue with VIS4.5.
