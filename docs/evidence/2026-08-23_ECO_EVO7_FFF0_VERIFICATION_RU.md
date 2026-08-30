# ECO.EVO7 FFF0 — Независимая верификация воспроизводимости — VERIFIED

**Дата:** 2026-08-23
**Роль:** независимый Verifier (изолированная свежая роль, вне контекста имплементации)
**Вердикт:** **VERIFIED**

## Проверенная голова

```
6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f
```

- ветка источника: `feature/eco-evo7-fff-r1` (в `C:\distributed-world-simulator\worktrees\eco-water-r1`);
- коммит: `test(eco): fixate EVO7 FFF0 contract mapping with machine gates` (2026-08-23 16:15:30 +1000);
- проверка выполнялась на **отдельном detached-чекауте** этой точной головы, а не в рабочем дереве имплементатора.

## Факт чистого чекаута

1. Создан временный worktree вне исходного дерева:

   ```
   git -C C:\distributed-world-simulator\worktrees\eco-water-r1 worktree add C:\distributed-world-simulator\worktrees\eco-evo7-fff0-verify 6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f --detach
   ```

2. `git rev-parse HEAD` во временном worktree вернул ровно `6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f`; `git status --porcelain` пуст.
3. Каталог `.godot` в свежем чекауте **отсутствовал** (`Test-Path .godot` → `False`) до первого прогона — тем самым документированное правило fresh-worktree import было реально отработано: раннер `RUN_ECO_EVO7_FFF0_TESTS.ps1` сам выполнил preflight `godot --headless --path <root> --import` (создан `.godot/uid_cache.bin`), после чего запустил пять тестовых скриптов.
4. Импорт Godot создал только новые untracked служебные файлы (`.godot/*` и сгенерированные Godot `*.uid`-сайдкары); **ни один tracked-файл не был изменён** (проверка: из 243 записей `git status --porcelain` записей с модификацией tracked-файлов — 0).
5. По завершении тестов временный worktree удалён:

   ```
   git -C C:\distributed-world-simulator\worktrees\eco-water-r1 worktree remove C:\distributed-world-simulator\worktrees\eco-evo7-fff0-verify --force
   ```

   Каталог отсутствует, в `git worktree list` записи нет.

## Команды запуска (как записано)

```powershell
powershell -Command ".\RUN_ECO_EVO7_FFF0_TESTS.ps1"
powershell -Command ".\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline"
```

Обе выполнены в корне чистого чекаута `C:\distributed-world-simulator\worktrees\eco-evo7-fff0-verify`, обе завершились с exit code 0.

## Ожидаемое vs наблюдаемое

### Прогон 1 — RUN_ECO_EVO7_FFF0_TESTS.ps1

| Проверка | Ожидаемое | Наблюдаемое | Совпадение |
|---|---|---|---|
| Терминальная строка | `ECO.EVO7 FFF0 Contract Mapping candidate: PASS` | `ECO.EVO7 FFF0 Contract Mapping candidate: PASS` | ✅ |
| FFF0 gate | PASS (168 assertions) | `ECO.EVO7 FFF0 Contract Mapping: PASS (168 assertions)` | ✅ |
| P1A-S1 environment_hash | `b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` (accepted baseline) | `ECO.P1A-S1 environment_hash=b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` | ✅ |
| P1A-S1 assertions | PASS (109 assertions) | `ECO.P1A-S1 Environment Baseline: PASS (109 assertions)` | ✅ |
| P1A-S2 simulation_hash | `618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c` | `ECO.P1A-S2 simulation_hash=618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c` | ✅ |
| P1A-S2 assertions | PASS (235 assertions) | `ECO.P1A-S2 Single-Plant Resource Model: PASS (235 assertions)` | ✅ |
| P1C-S4 aggregate | `0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112` | `ECO.P1C-S4 Aggregate Contract: PASS (15 assertions) aggregate=0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112` | ✅ |
| P1C-S4 assertions / failure matrix | PASS (15 assertions), failure matrix все PASS | 15 assertions; failure_matrix: GLOBAL_TAKEOVER=PASS, DIVERSITY_COLLAPSE=PASS, CLUSTER_COLLAPSE=PASS, FALSE_NICHE_UNIFORM=PASS, RUNAWAY_TRAIT=PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS, REPLAY_DIVERGENCE=PASS_EXACT_HASH_CONTRACT | ✅ |
| PH0 development_traits_hash | `9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` | `ECO.PH0 development_traits_hash=9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` (individual_seed=959597643576420676) | ✅ |
| PH0 assertions | PASS (63 assertions) | `ECO.PH0 Development Trait Contract: PASS (63 assertions)` | ✅ |

### Прогон 2 — RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline

| Проверка | Ожидаемое | Наблюдаемое | Совпадение |
|---|---|---|---|
| Evolution gate | PASS (24 assertions) | `ECO.EVO6-WATER evolution: PASS (24 assertions)` | ✅ |
| result_hash | `7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e`, идентичен в evolution и visual observatory | evolution: `result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e`; visual: `ECO.EVO6-WATER-VIS: READY plants=72 result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` — идентичны | ✅ |
| dry: mean root_depth_m | рост с 0.85 к ~2.1636 | initial 0.85 → final `2.16355290968219`; mean water_preference 0.58 → `0.34297809420071` | ✅ |
| Visual observatory | plants=72 pref_span=0.657 root_span=0.700 | `ECO.EVO6-WATER-VIS: PASS plants=72 pref_span=0.657 root_span=0.700` | ✅ |
| Итоговая строка | полный PASS | `ECO.EVO6-WATER strong water rules + evolutionary divergence + visual adapter: PASS` (+ fitness PASS (5 assertions), Python acceptance PASS) | ✅ |

## Сверка с checkpoint-заявлениями

Все значения сверены также с `docs/checkpoints/2026-08-23_ECO_EVO7_FFF0_R1_RU.md` (ветка `feature/eco-evo7-fff-r1`): 168/109/235/15/63 assertions, baseline-hash `b862c4fc…`, `development_traits_hash 9d812950…`, `result_hash=7010e307…` (одинаковый в evolution и visual observatory), `dry: mean water_preference 0.58 -> 0.343, mean root_depth_m 0.85 -> 2.164` (наблюдаемое 0.3430 / 2.16355 — согласуется с округлением до 2.164), `plants=72 pref_span=0.657 root_span=0.700`. Расхождений между checkpoint-документом, ожиданиями верификации и фактическим прогоном не обнаружено.

## Замечания (не блокирующие)

- Во время headless-импорта Godot печатал parse-ошибки для трёх legacy-лабораторных сцен (`res://scenes/labs/ecology/eco_evo5_probe2_tree_lab.tscn`, `eco_evo5_t51_creature_lab.tscn`, `eco_evo5_terrain_fly_lab.tscn`: `Parse Error: Expected '['`). Это существующее состояние данной головы, не связано с ECO-гейтами: все пять тестов и обе итоговые строки PASS, exit code 0. Зафиксировано как факт окружения.
- Импорт создал untracked `*.uid`-сайдкары и `.godot/uid_cache.bin`; tracked-файлы не изменялись; всё уничтожено вместе с временным worktree.

## Окружение

- OS: Microsoft Windows 10 Pro, 64-разрядная, 10.0.19045 (Microsoft Windows NT 10.0.19045.0)
- Godot: `Godot Engine v4.7.1.stable.double.custom_build.a13da4feb (2026-07-13 21:00:28 UTC)`; `--version` → `4.7.1.stable.double.custom_build.a13da4feb`
- Бинарник: `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`, режим headless

## Заявление о независимости

Верификация выполнена изолированной ролью Verifier, не участвовавшей в имплементации ECO.EVO7 FFF0 R1. Код не правился, существующие файлы не изменялись, ничего не коммитилось и не публиковалось. Прогон выполнен на независимом чистом чекауте точной головы `6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f` без доступа к артефактам предыдущих прогонов; все хэши получены заново из фактического запуска. Все ожидаемые значения совпали с наблюдаемыми; единственный зафиксированный отчёт — настоящий файл.
