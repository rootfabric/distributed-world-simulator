# G0 Geo Contracts — cleanup1: чистый acceptance output

**Дата:** 2026-08-08
**Ветка:** `feature/g0-geo-contracts`
**G0 implementation candidate:** `6bc49940fa6d762690d0e5a4ea4261a72c24310b`
**Cleanup1 evidence head:** `388c680085d4cb30c75020906790c9c0d642fb0a`
**Decision:** `ACCEPTED`
**Scope:** только test/acceptance infrastructure; GeoKernel, procedural contracts и production runtime не изменены.

---

## 1. Основание

Пользователь выполнил полный `RUN_G0_FULL_ACCEPTANCE.ps1` на реальном Windows checkout G0.

Подтверждено:

```text
focused G0:                         PASS — 209 assertions
world/core regression:              PASS
Breakpoint runtime :9081 noise:     0
functional regression failures:     0
```

Полный regression ранее подтверждал:

```text
world-regression-summary.json
passed:                 true
declared_test_count:    201
discovered_test_count:  201
steps:                  204
failed steps:           0
```

В новом clean-wrapper прогоне все функциональные suites снова дошли до PASS, включая persistence, inventory, NX5/NX6, MW0–MW10 и RL0–RL3.

---

## 2. Что исправлял cleanup1

До cleanup в multi-process logs было:

```text
17 occurrences
ERROR: [breakpoint_runtime] could not listen on 127.0.0.1:9081 (error 22)
```

Причина: несколько child Godot processes одновременно поднимали Breakpoint runtime autoload на одном fixed port.

Сам addon уже поддерживает штатный switch:

```text
BREAKPOINT_RUNTIME_DISABLED=1
```

Поэтому production addon/runtime не изменялся.

---

## 3. Cleanup1 implementation

### RUN_G0_GEO_CONTRACTS_TESTS.ps1

Runner:

1. временно устанавливает `BREAKPOINT_RUNTIME_DISABLED=1`;
2. выполняет headless editor import;
3. запускает G0 focused acceptance;
4. восстанавливает исходное значение environment variable.

### RUN_G0_GEO_CONTRACTS_TESTS.sh

Linux runner имеет ту же семантику.

### RUN_G0_FULL_ACCEPTANCE.ps1

Единый Windows gate выполняет:

```text
G0 focused
→ full existing world/core regression
→ current-run :9081 noise audit
→ git diff --check
```

Подтверждённый результат текущего прогона:

```text
All world/core regression tests ... passed.
Breakpoint runtime :9081 collision noise: 0
```

Первый проход `git diff --check` обнаружил только trailing whitespace в четырёх markdown-файлах. Никаких code/runtime defects за этим failure не стояло. Эти строки исправлены отдельным documentation-only patch после прогона.

---

## 4. Expected negative-path output

В regression output присутствуют сообщения вида:

```text
World manifest identity mismatch (...)
CONFLICTING_REMOTE_SNAPSHOT_TICK
STALE_REMOTE_AUTHORITY_EPOCH
```

Они возникают внутри тестов, которые намеренно проверяют rejection/error paths. Соответствующие suites завершаются `PASS`, поэтому эти строки не являются regression failures.

Отдельно MW7 сообщает ObjectDB/ResourceCache exit warnings. Suite также завершился `PASS`; это уже существующий cleanup/performance debt и не относится к G0 cleanup1.

---

## 5. Что не изменено

Cleanup1 не меняет:

```text
GeoKernel
PlanetDefinition / PlanetRecipe
provider graph
FlatSurfaceProvider
Moon / Earth runtime
Matter
network protocol
player/items/construction
Breakpoint MCP behavior в обычном editor/game запуске
```

Runtime bridge выключается только внутри G0 automated acceptance process tree.

---

## 6. Решение

```text
G0 CORE:       ACCEPTED
CLEANUP1:      ACCEPTED
:9081 NOISE:   0
REGRESSION:    PASS
NEXT:          G1 — Geodesy + Body Shape
```

После documentation whitespace fix повторный полный 201-test regression не требуется: изменены только Markdown-файлы. Для локального зеркала достаточно подтянуть branch и выполнить `git diff --check` либо полный wrapper при желании.
