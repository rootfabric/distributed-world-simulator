# ECO.EVO7 LS4.1 — Multi-Species Ecology / LS4-VIS1

Дата: 2026-09-05

Статус:

```text
LS4 SCOPE CONTRACT                  ✅ ACCEPTED
LS4.1 Multi-Species Ecology         🟡 IMPLEMENTED / EXACT RUNTIME PENDING
LS4-VIS1 Species Observatory        🟡 IMPLEMENTED / EXACT RUNTIME PENDING
LS4.2 Interaction Graph             BLOCKED UNTIL LS4.1 ACCEPTED
```

## Accepted predecessor

```text
LS4 scope exact verified HEAD
26ff38e3385a794d7f519f2be9fa8bb9f4ce08de

TREE
06d4d7aaeafce3a66b04ff66dfb99f9c23ba6876

canonical Windows double Godot
4.7.1.stable.double.custom_build.a13da4feb

scope verification
PASS — 120 assertions

scope accepted control tip
0624b7146c86ca727666ecd05c41e81bbd3559a8
```

## Что реализовано

LS4.1 добавляет три функционально различные species-populations поверх одного и того же физического PlanetPatch и EnvironmentField.

Каждый species использует уже принятую причинную цепочку LS3:

```text
founder heredity
  ↓
reproduction / mutation
  ↓
dispersal
  ↓
recruitment
  ↓
LS3.4 local competition
```

Принятые LS3.3/LS3.4/PERF2 runtime-файлы не модифицируются.

Три species:

- `riparian_pioneer`
- `xeric_anchor`
- `shade_weaver`

Каталог содержит frozen functional axes:

- growth strategy
- water demand
- light demand
- nutrient demand
- stress tolerance
- reproduction strategy

На LS4.1 эти axes входят в immutable `species_hash` и детерминированно порождают разные founder / placement / evolution identities. Прямая семантика общего распределения WATER/LIGHT/NUTRIENTS/SPACE намеренно не добавлена раньше LS4.3.

## Почему populations пока отдельные

LS4.1 доказывает, что несколько species могут одновременно существовать и эволюционировать на одной physical environment chain без scripted biome placement.

Но LS4.1 ещё НЕ вводит межвидовые причинные связи.

Поэтому:

```text
LS4.1: multiple species on same world
LS4.2: typed inter-species interaction graph
LS4.3: explicit shared-resource allocation
```

Это не позволяет скрыто реализовать будущие stages раньше их собственных contracts.

## Aggregate publication / fail-closed

Все species должны завершить один и тот же generation number до публикации aggregate snapshot.

Если один species-core не завершает generation после того, как другой уже продвинулся, wrapper становится `poisoned` и больше не публикует aggregate state до explicit reset/rebuild.

Таким образом частично собранное multi-species поколение не становится наблюдаемой LS4 truth.

## Bounded workload

Frozen LS4.1 workload:

```text
species cores                 3
grid                          32x32
projection cells              1024
initial records/species       24
max records/species           4096
max aggregate records         12288
retained generation history   0
new unbounded cache           NO
new unbounded history         NO
```

PERF2.CONV остаётся immutable accepted baseline и не перебенчмаркивается этим capability gate.

## LS4-VIS1

Добавлена сцена:

```text
res://scenes/labs/ecology/eco_evo7_ls41_multi_species_lab.tscn
```

Она показывает:

- dominant species по каждой из 1024 cells;
- локальную population density;
- species richness;
- точный состав выбранной клетки;
- generation;
- environment recipe/hash;
- species catalog identity;
- переключение environment recipe как physical counterfactual.

Белая внутренняя рамка означает, что в derived overlay клетка содержит более одного species.

VIS1 является presentation-only и не имеет ecology/WORLD authority.

## Exact acceptance

Windows:

```powershell
.\RUN_ECO_EVO7_LS41_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Runner выполняет:

1. LS4 Scope Contract regression.
2. LS4.1 Multi-Species acceptance.
3. LS4-VIS1 derived-only acceptance.

Ключевые falsifiers:

- меньше 3 species;
- duplicate functional species identity;
- species получают разные patch/environment truth;
- catalog содержит biome/cell placement;
- same-input replay расходится;
- physical environment counterfactual не меняет species distribution;
- VIS1 observation мутирует ecology;
- LS4.1 получает WORLD/LS4.2/LS4.3 authority;
- старый LS3.6 больше не исполняется независимо;
- появляется unbounded history/cache.

## После PASS

```text
LS4.1 ACCEPTED
      ↓
LS4.2 Interaction Graph AUTHORIZED
```

LS4.2 должен впервые ввести typed deterministic causal edges между уже существующими species, но не shared resource allocation — оно остаётся LS4.3.
