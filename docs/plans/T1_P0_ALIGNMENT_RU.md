# T / Construction — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-10-R2`  
**Branch family:** `T / Construction`  
**Active frontier:** `feature/t1a4-interactive-fixture-binding`  
**Current stage:** `T1A.4 — Interactive Fixture Binding`  
**Parallel planned track:** `TS0 — Large Structural Visual Lab`  
**Local role:** Construction composition + construction scale/visual validation

## 1. Назначение

T проверяет Construction как canonical gameplay domain поверх Item, utilities, runtime representation, network и recovery.

T может развивать локальные composition/scale experiments, но не может переопределять P0 owners:

```text
Spatial Domain Fabric
Unified Material Ontology
Cross-Domain World Transaction Model
Authority foundation
NX8 shared interest/budget
Persistence/recovery foundation
future World Work / Budget Fabric
```

## 2. Текущая точка

Принятая база для текущего T frontier:

```text
T1A.3 SOURCE_ACCEPTED
commit 5e051f67bf6987a354de5b565da1448be6b0b4db
        ↓
T1A.4 Interactive Fixture Binding — CURRENT
```

T1A.4 связывает шесть interactive Item identities с C5/C15/Container contracts. Binding/runtime artifacts не становятся полями canonical `ConstructSnapshot`.

## 3. R2: две параллельные линии T

После принятого T1A.3 развитие разрешено параллельно:

```text
                         T1A.3 ACCEPTED
                              │
               ┌──────────────┴──────────────┐
               │                             │
               ▼                             ▼
         T COMPOSITION                    TS SCALE/VISUAL
               │                             │
         T1A.4 Binding                   TS0.0 fixtures
               │                             │
         T1A.5 Runtime                   TS0.1 10k
               │                             │
         T1A.6 Inspector                 TS0.2 100k
               │                             │
         T1B Failure/Recovery            TS0.3 mutation
               │                             │
               │                         TS0.4 1M probe
               │                             │
               └──────────────┬──────────────┘
                              ▼
                            T2.0+
```

Правило:

```text
T1A.4 does not depend on TS0
TS0 does not depend on T1A.4
```

TS0 не должен стартовать от незавершённого T1A.4 candidate. Его preferred base — accepted T1A.3 + synchronized P0 R2 change-set.

## 4. Spatial boundary

Construction сохраняет construct/local scopes и local frames.

```text
ConstructionScope != WorldAddress
Construction section != WorldAddress
HLOD section != InterestRegionId
HLOD section != AuthorityRegionId
```

Будущий Spatial Domain Fabric маппит Construction наружу; T не создаёт собственную глобальную world addressing system.

## 5. Material boundary

```text
presentation material_family != MaterialDefinitionId
render material               != canonical material definition
```

TS0 может использовать простой визуальный материал блока. Он остаётся presentation-only и не становится физической/material truth.

## 6. Transaction boundary

Cross-domain операции:

```text
consume item -> place part
remove part -> salvage
construction damage -> debris/material
```

не должны становиться best-effort RPC chain.

T1A.4 продолжает использовать существующие C2B/M0/C5/C15 boundaries. Будущий T5-like cross-domain acceptance подключается к общему `WorldOperation / WorldTransactionPlan`.

TS0 не требует Item consumption или salvage semantics: fixture создаётся как deterministic scale lab и может работать без новых cross-domain mutations.

## 7. Network / authority boundary

```text
T != Network owner
T != authority registry owner
TS0 != Interest Management owner
TS0 != replication budget owner
```

NX7 задаёт physics authority policy; NX8 — общий interest/replication budget contract.

TS0 может измерять distance/HLOD и локальные budgets, но эти значения не получают canonical/global identity.

## 8. Representation boundary

```text
Construct canonical graph
    != C22 artifact
    != C24 ArrayMesh
    != HLOD selection
    != PartVisualProfile
    != TS0 debug mode
```

Presentation artifact можно полностью удалить и rebuild-нуть из canonical state.

TS0 обязан переиспользовать C21/C22/C24 там, где они покрывают задачу. Создавать параллельный `TSMeshSystem`/`TSHlodSystem` как новый owner запрещено.

## 9. Work / budget boundary

Для 10k/100k/1M experiments будут нужны ограничения работы за frame.

Разрешены локальные lab knobs:

```text
max_builds_per_frame
max_upload_bytes_per_frame
max_active_sections
```

Но:

```text
lab knob != global scheduler contract
```

Будущий `World Work / Budget Fabric` остаётся P1 owner и позже сможет заменить/адаптировать эти knobs.

## 10. Локально разрешённые задачи

Без нового P0 gate разрешены:

- T1A.4 binding C5/C15/Container semantics;
- T1A.5 interactive runtime execution;
- T1A.6 runtime inspector/telemetry;
- D0/D1 gameplay composition;
- C22/C24 near/mid/far representation;
- TS0 cube/pyramid deterministic fixtures;
- TS0 10k/100k visual scale tests;
- TS0 dirty-section rebuild measurements;
- TS0 1M research ceiling probe;
- visual debug overlays;
- runtime-node/draw-call/mesh/GPU telemetry.

## 11. TS0 explicit P0 gate

Перед новым TS0 contract проверить:

```text
[ ] fixture identity не зависит от camera/LOD
[ ] section ID не является global world address
[ ] authority owner не кодируется в part identity
[ ] visual block material не является MaterialDefinitionId
[ ] HLOD artifact не входит в canonical checksum
[ ] lab scheduling knobs не становятся global Work Budget owner
[ ] headless canonical fixture может существовать без renderer assets
[ ] C21/C22/C24 reuse проверен до создания нового backend
```

## 12. Stop conditions

T/TS должен остановить локальную реализацию и вынести вопрос в P0, если потребуется:

- отдельный Construction authority registry;
- отдельный global material namespace;
- Construction/TS section как permanent WorldAddress;
- private interest/replication identity;
- private global work scheduler;
- HLOD/proxy как canonical state;
- собственный persistence model;
- correctness через порядок RPC;
- server route внутри permanent construct/part identity.

## 13. T2 handoff

TS0 даёт synthetic scale evidence, но не закрывает T2.0.

```text
TS0 10k/100k cube+pyramid proof
        ↓
T2.0 real large construct
```

T2.0 должен доказать масштаб уже на реальной сложной базе/станции с неоднородной semantic composition.

## 14. Merge gate

Перед formal acceptance активного T head:

```text
[PASS] GLOBAL-P0-2026-08-10-R2 или более новая синхронная revision
[PASS] global config byte-equivalent main
[PASS] global roadmap byte-equivalent main
[PASS] local T P0 alignment current
[PASS] no duplicate P0 ownership
[PASS] SOURCE_ACCEPTED / MAIN_INTEGRATED / COMPOSITION_VERIFIED / PRODUCTION_READY раздельны
[PASS] focused tests
[PASS] required world/core regression
```

Для TS0 дополнительно:

```text
[PASS] accepted T1A.3 ancestry
[PASS] no dependency on unfinished T1A.4 semantics
[PASS] 100k visual gate telemetry captured
[PASS] 1M classified RESEARCH only
```

Канонический общий план: `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
