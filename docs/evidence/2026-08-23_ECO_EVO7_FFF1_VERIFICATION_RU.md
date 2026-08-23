# ECO.EVO7 FFF1 — Независимая верификация воспроизводимости — VERIFIED

**Дата верификации:** 2026-08-23
**Роль:** независимый верификатор (изолированная свежая роль, этап FFF1)
**Вердикт:** **VERIFIED**

## Точная голова

- **HEAD (проверено `git rev-parse HEAD` в чистом worktree):** `a8958d7dcfa6e96b52923f53395b966d382a3eec`
- **Ветка-источник:** `feature/eco-evo7-fff-r1` (в source-репозитории `C:\distributed-world-simulator\worktrees\eco-water-r1` HEAD совпадает с тем же SHA)
- **Worktree:** `C:\distributed-world-simulator\worktrees\eco-evo7-fff1-verify`, создан командой `git worktree add ... --detach` (detached HEAD); после создания `git status --short` пуст (рабочее дерево чистое).

## Факт чистого чекаута

- Worktree создан заново из source-репозитория на точном SHA; `git rev-parse HEAD` вернул `a8958d7dcfa6e96b52923f53395b966d382a3eec` — совпадение подтверждено.
- Каталог `.godot` **отсутствовал** на момент сразу после создания worktree (`Test-Path .godot` = False) — правило fresh-worktree import соблюдено; `.godot` создан только префлайтом самого раннера (`godot --headless --import` внутри `RUN_ECO_EVO7_FFF1_TESTS.ps1`, т.к. `.godot\uid_cache.bin` отсутствовал). Первый запуск с импортом занял несколько минут.
- Никакие существующие файлы не изменялись; коммитов и push не было. Единственный созданный файл — настоящий отчёт.

## Ожидаемое vs наблюдаемое

### Этап 2 — `RUN_ECO_EVO7_FFF1_TESTS.ps1` (exit code 0)

| Проверка | Ожидаемое | Наблюдаемое | Совпадение |
|---|---|---|---|
| Итоговая строка | `ECO.EVO7 FFF1 PlantFunctionalPhenotype candidate: PASS` | `ECO.EVO7 FFF1 PlantFunctionalPhenotype candidate: PASS` | ✅ |
| FFF1 | PASS (107) | `ECO.EVO7 FFF1 PlantFunctionalPhenotype: PASS (107 assertions)` | ✅ |
| FFF0 | PASS (112) | `ECO.EVO7 FFF0 Contract Mapping: PASS (112 assertions)` | ✅ |
| PH2 | PASS (107) | `ECO.PH2 Environment-Coupled Development: PASS (107 assertions)` | ✅ |
| P1A-S1 | PASS (109), `environment_hash` = `b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` | PASS (109 assertions), `environment_hash=b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` | ✅ |
| P1A-S2 | PASS (235), `simulation_hash` = `618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c` | PASS (235 assertions), `simulation_hash=618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c` | ✅ |
| P1C-S4 | PASS (15), aggregate = `0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112` | PASS (15 assertions), `aggregate=0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112`; failure matrix: все 6 позиций PASS (`GLOBAL_TAKEOVER`, `DIVERSITY_COLLAPSE`, `CLUSTER_COLLAPSE`, `FALSE_NICHE_UNIFORM`, `RUNAWAY_TRAIT` = PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS, `REPLAY_DIVERGENCE` = PASS_EXACT_HASH_CONTRACT) | ✅ |
| PH0 | PASS (63), `development_traits_hash` = `9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` | PASS (63 assertions), `development_traits_hash=9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` | ✅ |

### Этап 3 — `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline` (exit code 0)

| Проверка | Ожидаемое | Наблюдаемое | Совпадение |
|---|---|---|---|
| Evolution | PASS (24 assertions) | `ECO.EVO6-WATER evolution: PASS (24 assertions)` | ✅ |
| `result_hash` (evolution) | `7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` | `ECO.EVO6-WATER result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` | ✅ |
| `result_hash` (visual observatory) | идентичен evolution | `ECO.EVO6-WATER-VIS: READY plants=72 result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` — побайтно идентичен | ✅ |
| dry mean `root_depth_m` | 0.85 → ~2.1636 | initial `mean_root_depth_m` = 0.85 → final = 2.16355290968219 (~2.1636) | ✅ |
| Итоговая строка | strong water rules + divergence + visual adapter PASS | `ECO.EVO6-WATER strong water rules + evolutionary divergence + visual adapter: PASS` | ✅ |

### Этап 4 — сверка с `docs/checkpoints/2026-08-23_ECO_EVO7_FFF1_R1_RU.md`

Все заявленные в чекпоинте значения подтверждены наблюдениями без расхождений: FFF1 107 / FFF0 112 / PH2 107 / P1A-S1 109 + `b862c4fc…` / P1A-S2 235 + `618ec5c1…` / P1C-S4 15 + failure matrix все PASS / PH0 63 + `9d812950…` / EVO6-WATER `-SkipBaseline` PASS + `result_hash 7010e307…`; заявленное окружение `Godot 4.7.1.stable.double.custom_build.a13da4feb`, Windows headless — совпадает с фактически использованным. Расхождений не обнаружено; рационализации не потребовались.

## Выполненные команды

```powershell
# 1. Чистый detached-чекаут
git -C C:\distributed-world-simulator\worktrees\eco-water-r1 worktree add C:\distributed-world-simulator\worktrees\eco-evo7-fff1-verify a8958d7dcfa6e96b52923f53395b966d382a3eec --detach
git -C C:\distributed-world-simulator\worktrees\eco-evo7-fff1-verify rev-parse HEAD   # == a8958d7dcfa6e96b52923f53395b966d382a3eec
# (Test-Path .godot == False сразу после создания)

# 2. Цепочка FFF1 (cwd = C:\distributed-world-simulator\worktrees\eco-evo7-fff1-verify)
powershell -Command ".\RUN_ECO_EVO7_FFF1_TESTS.ps1"

# 3. Детерминизм-регрессия (тот же чистый worktree)
powershell -Command ".\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline"

# 5. Очистка
git -C C:\distributed-world-simulator\worktrees\eco-water-r1 worktree remove C:\distributed-world-simulator\worktrees\eco-evo7-fff1-verify --force
# Test-Path ...eco-evo7-fff1-verify == False; путь удалён, подтверждено `git worktree list`
```

## Окружение

- **Godot:** `Godot Engine v4.7.1.stable.double.custom_build.a13da4feb (2026-07-13 21:00:28 UTC)` (4.7.1 stable, double), бинарник `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`; все прогоны headless.
- **ОС:** Microsoft Windows NT 10.0.19045.0 (Windows 10 x64).
- Оба скрипта завершены с exit code 0.

## Наблюдения, не влияющие на вердикт

- Во время импортного сканирования префлайта в stderr фиксировались parse-ошибки трёх старых лабораторных сцен (`res://scenes/labs/ecology/eco_evo5_probe2_tree_lab.tscn`, `eco_evo5_t51_creature_lab.tscn`, `eco_evo5_terrain_fly_lab.tscn`, «Parse Error: Expected '['»). Эти сцены не входят в цепочку FFF1/EVO6; exit code 0, все тесты пройдены, хэши совпали. Зафиксировано как факт состояния репозитория на данной голове, не как сбой верификации.
- Дополнительный вывод PH2 (`phenotype_hashes`, `realized_metrics`) получен как побочный продукт прогона; на вердикт не влияет.

## Заявление о независимости

Верификация выполнена изолированной свежей ролью верификатора, не участвовавшей в реализации этапа FFF1. Прогоны выполнены на новом detached-чекауте точного коммита `a8958d7dcfa6e96b52923f53395b966d382a3eec` без переиспользования артефактов предыдущих запусков (`.godot` отсутствовал до старта и создан префлайтом раннера). Все наблюдаемые значения сняты непосредственно из вывода команд; сверка с ожидаемыми значениями и чекпоинт-документом выполнена дословно, без подгонки. Реализующие роли не имели доступа к процессу верификации; существующие файлы не изменялись, коммитов и push не выполнялось. Создан единственный файл — настоящий отчёт.
