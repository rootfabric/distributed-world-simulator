# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-A IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

Canonical North Star:

`docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine vision:

`config/ecology/eco-evolutionary-ecosystem-vision.v1.json`.

## 1. Что строит эта ветка

ECO — самостоятельный evolutionary-ecology mini-project внутри Distributed World Simulator.

Его конечная задача:

> взять ландшафт и initial ancestry, автономно вырастить на нём экологию без hardcoded biome/species placement, сохранить spatial/history state, а позднее позволить World Simulator материализовать и продолжить ту же экологию локально и в background.

Ветка не стремится напрямую к «красивым деревьям» или к раннему runtime integration.

## 2. Три слоя

```text
A. EVOLUTIONARY ECOSYSTEM
   standalone / headless / no player required
                ↓
B. SIMULATOR LIVING ECOLOGY
   import/query/activate/background continuation
                ↓
C. DERIVED PRESENTATION
   mesh / assets / animation / LOD
```

PH5 относится к слою C и уже дал достаточно representation foundation для текущего research stage. Основная работа теперь идёт в слой A.

## 3. Один ecological state, три режима исполнения

```text
INCUBATE_FAST
    accelerated long-horizon evolution

BACKGROUND_COARSE
    region/planet lives without observer

LOCAL_ACTIVE
    active local simulation and interaction
```

Ключевая инварианта:

`execution resolution != different ecology truth model`.

Offline evolution и runtime continuation не должны разойтись в две независимые системы правил.

## 4. Уже принято

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH4              ACCEPTED
ECO.PH5-S1..S4            ACCEPTED
ECO.PH representation     RESEARCH COMPLETE
ECO.CONV0-A               ACCEPTED DESIGN REQUIREMENTS
```

CONV0-A показал, что future simulator bridge должен использовать canonical `G/ENV/MAT/WQ/SD/TF/POP/LIFE/WB/NX/WT` foundations, а не ECO-private substitutes.

## 5. Центральный маршрут

```text
FOUNDATION ACCEPTED
P1 + PH0..PH5-S4
        │
        ▼
EVO0 — PLANT CAUSAL ECOLOGY
CAL1-A ← CURRENT CANONICAL GATE
        │
        ▼
CAL1-B/C/D/E/F
missing mechanisms → combined model → calibration
        │
        ▼
EVO1 — PLANT WORLD PROOF
P2 dispersal / recruitment / seed bank /
succession / disturbance / migration /
biogeography / lineage divergence
        │
        ▼
EVO2 — LONG-RUN EVOLUTIONARY LANDSCAPE
history / isolation / extinction-recolonization /
dynamic attractors / save-restart / ecology epochs
        │
        ▼
EVO3 — MULTI-TROPHIC ECOSYSTEM
organic matter + decomposers
        ↓
plant ↔ herbivore
        ↓
plant ↔ herbivore ↔ predator
        ↓
coevolution
        │
        ▼
EVO4 — AUTONOMOUS REGIONAL / PLANET ECOLOGY
headless runner
INCUBATE_FAST + BACKGROUND_COARSE
        │
        ▼
XFER0 — PORTABLE ECOLOGY ARCHIVE
state + lineage catalog + spatial atlas + history
        │
        ├──────────── wait canonical simulator foundations
        │
        ▼
XFER1 — WORLD GENERATION BRIDGE
G/MAT/ENV → ecology projection → local materialization
        │
        ▼
LIVE1 — LOCAL ACTIVE ECOLOGY
        │
        ▼
LIVE2 — BACKGROUND/OFFSCREEN CONTINUATION
+ coarse/fine convergence
        │
        ▼
LIVE3 — WORLD/PLAYER DISTURBANCE FEEDBACK
        │
        ▼
PRES1+ — richer derived visuals later
```

## 6. EVO0 / CAL1-A — текущая работа

Роль CAL1:

```text
CAL1 != цель ECO
CAL1 = hardening plant economics before autonomous ecosystem proof
```

### CAL1-A implementation

Implementation head:

`20e083d32d8dc9ff1f4a5f3f600a49a53f7a076e`.

Добавлены:

- `scripts/research/ecology/plant_morphology_economics_baseline_v1.gd`;
- `tests/research/ecology/eco_cal1_a_baseline_decomposition_acceptance.gd`;
- `tests/research/ecology/eco_cal1_a_restart_replay_probe.gd`;
- `RUN_ECO_CAL1_A_TESTS.ps1`.

Candidate checkpoint:

`docs/checkpoints/ECO_CAL1_A_BASELINE_DECOMPOSITION_CANDIDATE_RU.md`.

Validation:

`validation/ecology/eco-cal1-a-baseline-decomposition-validation.json`.

### Что измеряет CAL1-A

```text
REFERENCE / SHADE / SUN / DRY
            ×
BASE / HEIGHT_LOW / HEIGHT_HIGH /
CROWN_NARROW / CROWN_WIDE /
BRANCH_LOW / BRANCH_HIGH / GIANT_DENSE
```

Для каждой строки:

- same Genome;
- same PH3C IndividualSeed;
- realized morphology;
- accepted PH3 benefit/cost components;
- reconstructed selection score;
- deterministic full-pool rank/share;
- winner margin;
- leave-one-component-out rank sensitivity.

Environment summary объясняет winner-vs-runner и `HEIGHT_LOW-vs-HEIGHT_HIGH` через signed component deltas.

### Неподвижная граница

CAL1-A **не импортирует** `plant_morphology_resource_profile_v1.gd` и не создаёт tuned profile. Никакие accepted PH3/PH3C sources не изменялись.

### Локальная interface validation

На Godot `4.7.1 stable double a13da4feb` новый surface прошёл API-compatible synthetic validation:

- acceptance `1094 PASS`;
- fresh process probe `5 PASS × 2`;
- exact synthetic replay.

Эти числа и synthetic hashes не являются canonical ecology evidence.

### Current gate

На exact Windows checkout выполнить:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_A_TESTS.ps1 -GodotPath $Godot
```

Runner повторяет accepted PH3/PH3C regressions, затем CAL1-A и два fresh processes.

До этого:

```text
CAL1-A = IMPLEMENTED_CANDIDATE
CAL1-A != ACCEPTED
CAL1-B = BLOCKED
```

## 7. CAL1-B..F

После CAL1-A acceptance:

- CAL1-B relative vertical light competition;
- CAL1-C crown/root competition;
- CAL1-D lifetime/reproduction/dispersal/disturbance payoffs;
- CAL1-E combined mechanisms;
- CAL1-F calibration/full-pool robustness.

Принцип:

```text
observe missing mechanism
        ↓
causal experiment
        ↓
accept mechanism
        ↓
combine
        ↓
only then calibrate
```

После CAL1 не продолжать morphology tuning ради tuning.

## 8. EVO1 — следующий главный milestone

Target:

`ECO.EVO1_PLANT_WORLD_PROOF`.

Нужно взять небольшой детерминированный неоднородный landscape, общий ancestral pool и доказать:

- никакой biome->species placement table;
- seed dispersal создаёт spatial propagation;
- establishment зависит от local conditions;
- competition меняет состав сообщества;
- seed bank и recruitment дают continuity;
- succession возникает из механики, не state machine;
- disturbance меняет trajectory;
- isolation/migration создают различия между patches;
- long run не runaway-collapse/explosion;
- save/restart сохраняет ecology history;
- lineages занимают разные ecological niches.

P2 является execution plan внутри EVO1, а не мостом к production ради самого production.

## 9. EVO2 — история и эволюция ландшафта

После plant-world proof:

- ecology epoch/time;
- connected/isolated regions;
- migration flux;
- local extinction/recolonization;
- historical contingency;
- lineage tracking;
- dynamic attractors;
- speciation candidate diagnostics;
- deterministic replay/provenance.

Цель: одинаковая среда с разной историей может иметь разную экологию.

## 10. EVO3 — животные и прочая органика

Животные добавляются только после устойчивого plant substrate.

Не вводить hardcoded `Rabbit eats Grass01`.

Пищевые связи должны следовать из свойств:

```text
food biomass / chemistry / digestibility
consumer metabolism / diet / mobility / defense
reproduction / predation / territory
```

Порядок:

1. decomposition / organic-matter loop;
2. herbivore population;
3. predator population;
4. multi-trophic robustness;
5. coevolution experiments.

Detailed fauna meshes/animation не являются acceptance requirement.

## 11. EVO4 — автономный Ecology Runner

ECO должен реально запускаться отдельно от игрового клиента.

Обязательные режимы:

- `INCUBATE_FAST`;
- `BACKGROUND_COARSE`;
- pause/save/restart;
- deterministic seeded run;
- bounded population/cohort representation;
- research diagnostics/dashboard.

## 12. XFER0 — EcologyArchive

Переносимый результат включает:

```text
EcologyWorldState snapshot
+ lineage catalog
+ spatial population atlas
+ biomass/density/age distributions
+ seed/recruitment state
+ disturbance/history state
+ ruleset/provenance/replay metadata
```

## 13. XFER1 — bridge в G / world generation

Только после готовности canonical simulator foundations:

```text
G / MAT / ENV
terrain + substrate + environment
           ↓
EcologyArchive / EcologyWorldState
           ↓
EcologyLocalProjection
           ↓
local placement/materialization
```

ECO определяет ecological occupancy/distribution; G/MAT/ENV владеют terrain/geology/material/environment truth.

## 14. LIVE — продолжение той же экосистемы

```text
EcologyPatchState
      ↓
LocalEcologyState
      ↓
promoted organisms when necessary
      ↓
interaction / growth / feeding / reproduction / damage
      ↓
aggregate result
      ↓
EcologyPatchState
```

При уходе игрока patch возвращается в background/coarse execution. Нельзя иметь unrelated offline ecology и runtime ecology для одной planet state.

## 15. Presentation

Текущего PH5 достаточно как proof derived representation. До EVO major proofs не приоритизировать photorealistic vegetation, final animal animation или final art pipeline.

## 16. Глобальные gates

Standalone `EVO0..EVO4` можно развивать независимо от runtime critical path основного проекта.

`XFER1/LIVE` ждут canonical foundations и Harness-controlled runtime frontier.

CONV0-A findings остаются действующими:

- `ECO` = Evolutionary Ecology; future economy = `ECON`;
- generic production population fabric = `POP`-owned;
- ECO не создаёт private WQ/SD/TF/MAT/LIFE/WB/NX/WT/persistence/authority foundations.

## 17. Операционный resolver

При команде «продолжай ECO»:

1. прочитать North Star;
2. прочитать machine roadmap;
3. выполнить `current_step`;
4. не перескакивать через acceptance gates;
5. проверять, приближает ли работа к автономной экосистеме.

Сейчас resolver однозначен:

`RUN CAL1-A EXACT WINDOWS CANONICAL BASELINE GATE`.
