# G0 Geo Contracts — cleanup1: чистый acceptance output

**Дата:** 2026-08-08  
**Ветка:** `feature/g0-geo-contracts`  
**G0 implementation candidate:** `6bc49940fa6d762690d0e5a4ea4261a72c24310b`  
**Cleanup1 head:** `ae58d9116d5d037262a6c50f326734c179bed77d`  
**Scope:** только test/acceptance infrastructure; GeoKernel, procedural contracts и production runtime не изменены.

---

## 1. Основание

Пользователь выполнил полный `RUN_WORLD_REGRESSION_TESTS.ps1` на реальном Windows checkout G0.
Перед cleanup подтверждено:

```text
world-regression-summary.json
passed:                 true
declared_test_count:    201
discovered_test_count:  201
steps:                  204
failed steps:           0
```

Focused G0 ранее также прошёл:

```text
G0 Geo contracts: PASS (209 assertions)
```

Функциональных regression failures не обнаружено.

При анализе приложенного `test-results.zip` найден test-infrastructure noise:

```text
17 occurrences
ERROR: [breakpoint_runtime] could not listen on 127.0.0.1:9081 (error 22)
```

Ошибки были распределены по multi-process M2/M3/M4/M6/N2 child logs. Они не влияли на итоговый verdict, но засоряли output и могли скрывать будущие настоящие engine errors.

---

## 2. Причина

`BreakpointRuntimeBridge` является autoload и по умолчанию открывает фиксированный loopback port `127.0.0.1:9081`.

Addon уже содержит штатный test/process switch:

```text
BREAKPOINT_RUNTIME_DISABLED=1
```

При его установке runtime bridge не открывает socket и не меняет gameplay composition.

Поэтому addon и production behavior менять не требуется.

---

## 3. Cleanup1

### RUN_G0_GEO_CONTRACTS_TESTS.ps1

Runner теперь:

1. временно устанавливает `BREAKPOINT_RUNTIME_DISABLED=1`;
2. выполняет headless editor import;
3. запускает G0 focused acceptance;
4. восстанавливает исходное значение environment variable.

Headless editor import закрывает второй источник лишнего шума: совершенно новый git worktree ещё не имеет `.godot` UID cache, поэтому прямой `--script` мог сначала вывести ошибки разрешения UID-backed autoload.

### RUN_G0_GEO_CONTRACTS_TESTS.sh

Linux runner получил ту же семантику:

```text
cold editor import
+ temporary runtime bridge disable
+ focused G0
+ environment restore
```

### RUN_G0_FULL_ACCEPTANCE.ps1

Добавлен единый Windows gate:

```text
G0 focused
→ full existing world/core regression
→ current-run :9081 noise audit
→ git diff --check
```

World regression запускается в отдельном PowerShell child process с унаследованным:

```text
BREAKPOINT_RUNTIME_DISABLED=1
```

После regression wrapper сканирует только `.log` файлы, записанные текущим запуском. Исторические artifacts не участвуют в проверке.

Acceptance condition:

```text
Breakpoint runtime :9081 collision noise: 0
G0 full acceptance gate: PASS
```

---

## 4. Что не изменено

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

## 5. Проверка cleanup1

На Windows worktree:

```powershell
git fetch origin --prune
git pull --ff-only

.\RUN_G0_FULL_ACCEPTANCE.ps1
```

Ожидаемый финал:

```text
G0 Geo contracts: PASS (209 assertions)
...
All world/core regression tests ... passed.
Breakpoint runtime :9081 collision noise: 0
G0 full acceptance gate: PASS
```

Если full wrapper проходит, cleanup1 можно считать `ACCEPTED` и использовать его head как чистую базу G1.

---

## 6. Решение

G0 core получил полный внешний regression evidence до cleanup:

```text
201 / 201 discovered tests
204 / 204 steps PASS
0 failed steps
```

Cleanup1 является non-functional test-infrastructure patch.

Текущий статус:

```text
G0 CORE:       ACCEPTED BY FULL REGRESSION EVIDENCE
CLEANUP1:      CANDIDATE — one clean full-wrapper rerun required
NEXT:          G1 Geodesy + Body Shape after cleanup1 PASS
```
