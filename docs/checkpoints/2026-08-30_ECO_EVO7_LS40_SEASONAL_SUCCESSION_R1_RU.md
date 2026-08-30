# ECO.EVO7 LS4.0 R1 — Deterministic Seasonal Forcing / Succession Response

Статус: **CODE COMPLETE / EXACT-WINDOWS VERIFICATION REQUIRED**.

Это branch-local research checkpoint линии ECO.EVO7. Он **не меняет** main-owned
`config/control/project-program-registry.v1.json`, не объявляет себя текущим
каноническим ECO checkpoint проекта и не заменяет основную ECO.CONV0/CAL1
линию.

## Base

STREAM1 acceptance control head:

```text
5beb603ebdae2e89ad8f66f469e7ecc12312c29e
```

STREAM1 frozen verified target:

```text
HEAD: 4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4
TREE: 68389ef9a491fc2f1e13efb92058029c9536f870
```

LS4 branch:

```text
feature/eco-evo7-ls40-seasonal-succession-r1
```

Freeze anchors before exact-Windows verification:

```text
runtime_code_head:
fa63b7b680cac6bc25889d30ff99df86fc841df3

verification_harness_head:
4328583fd5f01f7a22304cd4d354ca54a59ac4aa
```

## Зачем нужен LS4

LS3 доказал причинную цепочку:

```text
frozen physical environment
→ reproduction
→ dispersal
→ recruitment
→ local competition
→ post-hoc emergent biome observation
```

Но physical environment оставался неизменным на протяжении всего run.

Это означает, что система уже могла адаптироваться **к пространственной
неоднородности**, но ещё не имела настоящего временного экологического
давления.

LS4.0 добавляет минимальный temporal ecology слой:

```text
immutable LS3.1 base field
        ↓
deterministic generation phase
        ↓
LS4 seasonal forcing proposal
        ↓
strict LS3.1-compatible field validation
        ↓
LS3.3 recruitment
        ↓
LS3.4 competition
        ↓
population / hereditary response
        ↓
LS3.5 + Observatory post-hoc observation
```

Главный смысл checkpoint: один и тот же founder pool должен проходить через
изменяющиеся физические условия, причём forcing остаётся детерминированным,
проверяемым и не получает никакой скрытой ecology/world authority.

## Это НЕ Time Fabric

`CYCLE_GENERATIONS = 12` — это **внутренний research phase index**, а не
календарь, год, месяц или canonical simulator time.

LS4 не владеет `TIME_FABRIC` и не создаёт его альтернативу.

```text
generation 1..12
→ abstract deterministic forcing phases
→ generation 13 exactly wraps to phase 1
```

Будущая production интеграция с canonical Time Fabric должна быть отдельным
consumer adapter после соответствующего project gate.

## Forcing profiles

R1 содержит три профиля:

```text
STATIC_CONTROL
TEMPERATE_SEASONAL
MONSOON_SEASONAL
```

### STATIC_CONTROL

Identity control.

Для любого generation возвращает byte-semantic duplicate исходного LS3.1
field с тем же:

```text
field_hash
cell_hashes
physical values
```

Это доказывает, что сам новый orchestration seam не меняет старую экологию.

### TEMPERATE_SEASONAL

Меняет только допустимые dynamic research inputs:

```text
temperature_c
incident_light
rainfall_forcing
soil_moisture
```

### MONSOON_SEASONAL

Использует более сильную rainfall/moisture амплитуду и cloud dimming, сохраняя
тот же immutable физический базис.

## Что LS4 не может менять

Следующие значения являются frozen static identity и проверяются до causal use:

```text
index / x / y
east_m / north_m
land_mask
surface_water_fraction
soil_texture_sand
soil_texture_clay
soil_texture_loam
soil_water_retention
elevation_m
local_relief_m
drainage_index
```

То есть LS4 **не производит**:

- terrain truth;
- river/lake/ocean truth;
- material/substrate ontology;
- world-query truth.

Даже если злоумышленник изменит elevation и полностью пересчитает
`cell_hash` + `field_hash`, LS3.3 отклонит поле из-за static-identity fence.

## Single hash implementation

LS4 не вводит собственную альтернативную схему EnvironmentField.

Derived field остаётся:

```text
distributed_world_simulator.ecology.evo7_environment_field.v1
ECO.EVO7-LS3.1.2
```

Cell и field hashes пересчитываются через существующие LS3.1:

```text
EnvironmentField._cell_hash
EnvironmentField._field_hash
```

Таким образом LS4 не создаёт второй источник физической идентичности.

## Authority model

### LS4 SeasonalForcing

Может:

- прочитать immutable копию base EnvironmentField;
- выбрать deterministic phase по generation;
- вычислить четыре dynamic значения;
- вернуть LS3.1-compatible proposal;
- публиковать noncanonical forcing telemetry.

Не может:

- вызвать `step_generation`;
- менять records/population;
- менять genome;
- строить mutation/dispersal identity;
- менять terrain/surface-water/substrate;
- писать persistence/network;
- писать production world state.

### LS3.3

Добавлен bounded public seam:

```text
set_environment_field(environment_field)
```

Он:

1. проверяет exact LS3.1 schema/version/revision;
2. проверяет exact field/cell key sets;
3. проверяет source patch / recipe / seed / grid / cell size;
4. проверяет canonical cell coordinates;
5. проверяет все LS3.1 cell hashes;
6. проверяет LS3.1 field hash;
7. проверяет static physical identity против текущего accepted field;
8. только после полной проверки меняет:
   - `environment_field_hash`;
   - `environment_cells`.

Он **не меняет**:

```text
generation
records
population_hash
hereditary_pool_hash
candidate/dispersal identity
```

## LS3.4 composition

LS3.4 имеет один pass-through:

```text
set_environment_field(...)
```

Сначала поле принимает LS3.3, и только после успеха LS3.4 заменяет локальный
competition input.

Поэтому recruitment и competition используют один и тот же exact derived field.

## Workbench transaction

Rule Workbench владеет только экспериментальной orchestration:

```text
base_environment_field
+
optional forcing provider
```

Перед каждым поколением:

```text
provider proposes field for generation N
→ LS3.3/LS3.4 validate + accept
→ ecology.step_generation()
```

Если forcing proposal невалиден, generation вообще не запускается.

Если generation fail-closed до commit, Workbench пытается вернуть exact previous
environment field.

Без provider старый LS3.6 path не изменяется.

## Observatory repair

Старый Spatial Observatory намеренно фиксировал один
`spatial_environment_hash` на весь run.

Это было корректно для LS3, но несовместимо с настоящим LS4.

R1 заменяет это на более сильную per-generation source binding:

```text
environment_field.field_hash
==
ecology_snapshot.environment_field_hash
==
classification.source_environment_field_hash
```

Observatory по-прежнему read-only и не создаёт physical truth.

При статическом environment старое поведение остаётся тем же.

## Determinism

Runtime trigonometry для seasonal phase не используется.

R1 содержит explicit 12-value lookup tables для thermal/wet forcing, поэтому
одинаковые:

```text
base field
+
profile
+
generation
```

должны дать exact одинаковый derived field.

Generation 13 повторяет phase generation 1 byte-for-byte.

## STREAM1 compatibility

LS4 применяется **до** STREAM1 proposal generation.

STREAM1 получает уже принятый immutable environment context и не знает о
seasonal scheduler.

Это сохраняет существующую границу:

```text
LS4 field proposal
→ LS3.3 accepts environment
→ STREAM1 computes full-generation proposal
→ LS3.3 validates
→ ONE generation commit
```

Chunk shape по-прежнему не является ecology identity.

## Focused acceptance

Добавлен:

```text
tests/ecology/eco_evo7_ls40_seasonal_succession_acceptance.gd
```

Он проверяет:

1. exact `STATIC_CONTROL`;
2. 12 deterministic forcing phases;
3. generation 13 == generation 1;
4. derived field остаётся LS3.1-valid;
5. frozen terrain/substrate identity;
6. deterministic replay одного seasonal profile;
7. одинаковый founder hereditary pool для counterfactual profiles;
8. causal divergence через recruitment/competition/population/heredity evidence;
9. serial ↔ STREAM1 exact parity с seasonal forcing;
10. malformed environment proposal fail-closed;
11. rehashed terrain/static tamper rejection;
12. valid environment replacement не меняет generation/population/heredity;
13. source authority guards.

Expected focused marker после Windows verification:

```text
LS4.0 STREAM1 seasonal exact comparisons: 6/6
ECO.EVO7 LS4.0 Seasonal Forcing / Succession: PASS
```

## Transitive gate

Добавлен:

```text
RUN_ECO_EVO7_LS40_TESTS.ps1
```

Он требует exact:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

и запускает 14 suites:

```text
LS3.3
LS3.4
LS3.5
LS3.6
PERF1
PAR0
PAR0.2
PAR1
PAR2
PAR3
STREAM1
LS4.0
VIS3
PLAY0
```

Expected final marker:

```text
ECO.EVO7 LS4.0 transitive acceptance: PASS
```

## Non-goals R1

LS4.0 не реализует:

- canonical calendar/time;
- production Environment Simulation;
- weather solver;
- climate model;
- hydrological state machine;
- soil material ontology;
- disturbances/fire/disease;
- multi-trophic food web;
- explicit biome state machine;
- persistence;
- networking;
- production world integration.

Это минимальный temporal causal layer поверх уже принятой EVO7 ecology.

## Relation to canonical ECO program

На момент создания этого checkpoint main-owned project control ведёт
канонический ECO research frontier по другой, более новой линии
(ECO.CONV0/CAL1 и связанные этапы).

Поэтому:

```text
ECO.EVO7/LS4.0
=
branch-local research evidence
!=
canonical main ECO project state
```

Ни этот runtime, ни branch-local roadmap не должны самостоятельно менять
main registry/checkpoint catalog.

Если результаты LS4 окажутся полезны для основной ECO линии, перенос должен
проходить отдельным convergence decision.

## Acceptance condition

Implementer не может self-accept этот checkpoint.

R1 может быть предложен к acceptance только после fresh exact-Windows
verification на frozen branch HEAD:

```text
exact Godot build
+
clean import
+
focused LS4 PASS
+
STREAM1 seasonal exact 6/6
+
14/14 transitive gate
+
source guards PASS
+
immutable HEAD/TREE
+
tracked worktree clean
```

До этого итоговый статус:

```text
LS4.0 R1 CODE COMPLETE
AWAITING EXACT WINDOWS VERIFICATION
NOT ACCEPTED
```


## Fresh Windows mission

Для независимого закрытия R1 использовать:

`docs/checkpoints/2026-08-30_ECO_EVO7_LS40_R1_WINDOWS_VERIFICATION_MISSION_RU.md`

Mission динамически резолвит текущий origin tip ветки, но отдельно требует,
чтобы frozen runtime/harness anchors оставались его ancestors. Verification
worktree является read-only evidence environment: при первом FAIL никаких
repair-коммитов в нём делать нельзя.
