# ECO — Evolutionary Ecosystem North Star

Статус: `CANONICAL BRANCH VISION / RESEARCH MINI-PROJECT / 2026-08-12`.

Этот документ уточняет конечную цель ветки `feature/eco-evolutionary-ecology` и имеет приоритет над слишком узким прочтением текущих CAL1/P2/CONV задач.

Исходный замысел `ECOLOGY_EVOLUTION_PROGRAM_RU.md` сохраняется: ECO должен быть самостоятельным эволюционно-экологическим мини-проектом, который умеет взять ландшафт, самостоятельно вырастить на нём жизнь, сохранить результат и позднее передать его в основной World Simulator.

## 1. Конечная цель

На входе есть не список `FOREST -> Oak/Pine`, а физический/географический ландшафт и история условий:

```text
landscape topology
+ climate / sunlight / moisture / substrate
+ gravity / atmosphere / seasonal forcing
+ initial ancestry / seed pool
+ disturbance history
                 ↓
        EVOLUTIONARY ECOLOGY
                 ↓
organisms + lineages + populations + niches
+ succession + migration + extinction
+ later trophic webs / coevolution
                 ↓
        living ecosystem state
```

Система должна отвечать не на вопрос «какие ассеты поставить здесь?», а на вопрос:

> какие формы жизни смогли бы здесь возникнуть, выжить, конкурировать, распространиться и продолжать жить с учётом истории этого места?

Первый полноценный результат ветки — не красивое дерево и не runtime adapter. Это **автономная растущая экосистема**, которую можно запустить headless без игрока и наблюдать как отдельный эксперимент.

## 2. Три слоя продукта

### Слой A — Evolutionary Ecosystem

Самостоятельное ядро ECO.

Оно владеет экологической семантикой:

- наследование / mutation / selection;
- morphology и resource economics;
- reproduction;
- population/cohort state;
- competition;
- dispersal / recruitment;
- succession;
- disturbance / recovery;
- extinction / recolonization;
- lineage divergence / speciation diagnostics;
- позже herbivory / predation / decomposition / trophic interactions / coevolution.

Этот слой **не требует игрока и не требует графического клиента**.

Его можно использовать как Evolution Incubator: дать ландшафт, ускорить время и получить выросшую экологическую историю.

### Слой B — Simulator Living Ecology

Мост в основной Distributed World Simulator.

Он не создаёт новую экологическую модель. Он берёт состояние, выращенное слоем A, и позволяет основной симуляции:

- запросить экологию конкретного участка;
- материализовать локальные растения/животных в правдоподобных местах;
- активировать участок для взаимодействия;
- продолжить те же процессы роста, питания, размножения, смерти и миграции;
- вернуть последствия локальных событий в population/patch state;
- снова дематериализовать участок;
- продолжать регион/планету в background даже без игрока.

### Слой C — Derived Presentation

Отдельный слой визуального качества.

```text
ecological truth
      ↓
phenotype / local projection
      ↓
mesh / asset / animation / LOD / shader
```

PH5 уже доказал первый кусок этого принципа для растений. В дальнейшем красота изображения не должна определять архитектуру ecology kernel.

## 3. Один EcologyKernel, а не offline-model + runtime-model

Критический принцип новой программы:

> offline evolution и runtime ecology используют одну экологическую семантику состояния и переходов.

Нужны разные **режимы исполнения**, а не разные truth models.

### `INCUBATE_FAST`

Ускоренная автономная эволюция:

- большие временные горизонты;
- population/cohort resolution;
- тысячи поколений;
- поиск lineage divergence, succession и dynamic attractors;
- игрок не нужен.

### `BACKGROUND_COARSE`

Живущая планета/регион без наблюдателя:

- coarse patch updates;
- низкая частота;
- migration / birth / death / disturbance / succession продолжаются;
- индивидуальные Node3D не нужны.

### `LOCAL_ACTIVE`

Активный участок мира:

- более высокая spatial/time resolution;
- локальные cohorts/individual promotion;
- взаимодействие с игроком, животными и world events;
- результаты агрегируются обратно в patch/population state.

Целевая инварианта:

```text
INCUBATE_FAST
BACKGROUND_COARSE
LOCAL_ACTIVE
       ↓
share one ecology state meaning
```

Приближения и resolution различаются; экологические причины не должны становиться тремя несовместимыми наборами правил.

## 4. Что является переносимым результатом эволюции

Одного `SpeciesCatalog` недостаточно. Для реального переноса нужна история и пространственная структура экосистемы.

Концептуальные артефакты, имена пока не являются frozen production API:

### `LandscapeEcologyInput`

- patch/landscape topology;
- environmental fields;
- substrate projection;
- climate/history forcing;
- initial ancestry / colonization source;
- disturbances;
- deterministic seed;
- ecology ruleset revision.

### `EcologyWorldState`

- ecology time / epoch;
- lineage catalog;
- population/cohort state по patch;
- biomass / density / age structure;
- seed bank / recruitment state;
- resource/interaction summaries;
- migration flux;
- disturbance/history state;
- provenance/revisions.

### `EcologyArchive`

Portable restartable snapshot:

```text
EcologyWorldState
+ lineage/species-candidate catalog
+ spatial ecology atlas
+ ruleset/provenance
+ deterministic replay metadata
```

Это может быть результатом длительного bake/evolution run для конкретной планеты.

### `EcologyLocalProjection`

То, что требуется конкретному региону симулятора:

- присутствующие lineages/species candidates;
- density / biomass / cover;
- age/size/phenotype distributions;
- seed/recruitment state;
- interaction/promotion relevance;
- deterministic placement/materialization hints.

## 5. Как ECO входит в генерацию поверхности

Целевая схема:

```text
G / MAT / ENV
terrain + substrate + environment truth
                 ↓
       ecology state/archive query
                 ↓
        EcologyLocalProjection
                 ↓
local deterministic materialization
                 ↓
grass / bushes / trees / colonies /
herds / nests / other organic presence
```

ECO отвечает за **экологическое присутствие и распределение**, но не забирает ownership поверхности.

Например:

- где вероятна высокая древесная biomass — ECO;
- какой lineage там существует и почему — ECO;
- плотность/возраст/phenotype distribution — ECO;
- конкретный terrain height, canonical river, rock/material truth — G/MAT/ENV;
- окончательный mesh/asset — presentation.

Камни могут находиться рядом с растениями на финальном surface, но geology/rocks не являются частью ecology truth.

## 6. Как участок продолжает жить после materialization

```text
EcologyPatchState
      ↓ activate
LocalEcologyState
      ↓
plants / animals / promoted individuals
      ↓
growth / feeding / reproduction / damage /
harvesting / disturbance / player effects
      ↓
aggregate ecological consequences
      ↓
EcologyPatchState
      ↓ demote
BACKGROUND_COARSE
```

Активный участок — не новая маленькая экосистема. Это более подробное представление того же ecological state.

## 7. Планета без игрока

Отсутствие игрока не должно останавливать экологию.

Допустимы два сценария:

1. **до запуска мира** — отдельный Evolution Incubator ускоренно выращивает экологию и выпускает `EcologyArchive`;
2. **в живом мире** — authoritative ecology state продолжает `BACKGROUND_COARSE` независимо от присутствия игрока.

Запрещён сценарий, где параллельно существуют две независимые версии одной и той же canonical ecology planet state: одна «offline», вторая «runtime».

## 8. Что должно эволюционировать

### Сначала растения

Потому что они дают дешёвый и хорошо контролируемый proof:

```text
environment
→ resource acquisition
→ growth form
→ competition
→ reproduction
→ dispersal
→ succession
→ lineage divergence
```

Текущий CAL1 нужен именно для того, чтобы этот фундамент не был построен на искусственном `HEIGHT_LOW` bias.

### Затем пространственная plant ecology

После CAL1 важнее не добавлять новые ветки к дереву, а получить самостоятельный landscape experiment:

- patch topology;
- dispersal;
- establishment;
- local competition;
- seed bank;
- succession;
- disturbance;
- isolation;
- migration;
- long-horizon biogeography.

### Затем multi-trophic ecology

Добавлять не `Rabbit eats Grass01`, а причинные свойства:

- edible biomass / chemistry / digestibility;
- metabolism;
- feeding strategy;
- mobility;
- reproduction;
- defense/toxicity;
- predation risk;
- territory/social behavior.

Последовательность proof может быть:

```text
organic matter / decomposer loop
        ↓
plant ↔ herbivore
        ↓
plant ↔ herbivore ↔ predator
        ↓
coevolution / dynamic food web
```

Детальная animal mesh/animation к этому proof не относится.

## 9. Новая большая дорожная карта

```text
FOUNDATION
P1 + PH0..PH5-S4 ACCEPTED
        ↓
EVO0 — Plant causal economics
CAL1 ← CURRENT
        ↓
EVO1 — Autonomous spatial plant ecosystem
P2 dispersal / recruitment / succession /
disturbance / biogeography
        ↓
EVO2 — Long-run evolutionary landscape
isolation / migration / lineage divergence /
dynamic attractors / speciation diagnostics
        ↓
EVO3 — Multi-trophic ecosystem
herbivores / decomposers / predators /
food web / coevolution
        ↓
EVO4 — Autonomous regional/planet ecology
headless runner / accelerated + background modes /
pause-save-restart / long-horizon stability
        ↓
XFER0 — Portable EcologyArchive
state + lineage catalog + spatial atlas + provenance
        ↓
             ┌──────────────────────┐
             │ canonical simulator  │
             │ foundations ready    │
             └──────────┬───────────┘
                        ↓
XFER1 — World generation bridge
G/MAT/ENV → ecology projection → local materialization
                        ↓
LIVE1 — Local active ecology continuation
                        ↓
LIVE2 — Background/offscreen ecology
+ coarse/fine convergence
                        ↓
LIVE3 — bidirectional world/player disturbance
                        ↓
PRES1+ — richer derived visual presentation
```

`EVO` можно и нужно развивать как автономный мини-проект до готовности production foundations основного симулятора.

## 10. Ближайшая практическая цель

Текущий `CAL1-A` сохраняется.

Но его новая роль:

```text
CAL1
!= цель ветки

CAL1
= последний hardening plant economics
  перед первым autonomous ecosystem proof
```

После CAL1 следующий крупный milestone должен звучать не «ещё одна selection matrix», а:

> **ECO.EVO1 PLANT WORLD PROOF** — на небольшом детерминированном неоднородном ландшафте из общего ancestral pool без biome/species placement tables самостоятельно формируются несколько устойчивых растительных сообществ, succession и пространственная структура, которые сохраняются/restart-ятся и объясняются условиями и историей.

## 11. Acceptance North Star

Ветка достигнет исходной цели первого порядка, когда можно будет:

1. дать ей небольшой произвольный landscape;
2. задать физические/environmental conditions и общий ancestral life seed;
3. запустить без игрока;
4. получить через длительное время несколько различающихся ecological niches/lineages и их пространственное распределение;
5. сохранить `EcologyArchive`;
6. открыть произвольный local patch и воспроизводимо получить правдоподобные растения/организмы именно из этого состояния;
7. продолжить этот patch локально;
8. вернуть его изменения в population ecology;
9. снова оставить планету жить без игрока;
10. менять visual quality независимо от ecology truth.

Это и есть основная North Star ECO.
