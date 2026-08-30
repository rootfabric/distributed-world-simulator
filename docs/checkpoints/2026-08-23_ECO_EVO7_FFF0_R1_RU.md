# ECO.EVO7 FFF0 — Contract Mapping Checkpoint — CANDIDATE

**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1` (от `d4d5c309a2da772751cd53adf17554eea697dd19`)
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§19, этап FFF0)
**Аудит-документ:** `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md`

## Цель

Не продублировать ECO.PH: выполнить точный contract-mapping аудит перед любой новой генетикой EVO7 — инвентарь PH0 developmental traits, mutation authority, environment channels, freeze ownership boundaries, минимальный список действительно новых contract-полей.

## Что сделано

1. **Аудит существующих поверхностей** (все факты проверены чтением исходников и зафиксированы машинно):
   - mutation authority единственная: `plant_mutation_lineage_kernel_v1 :: MUTABLE_TRAITS` = ровно 5 экологических полей генома; **морфологические PH0-триты вне эволюционного контура** — главный доказанный semantic gap (FFF0-A);
   - reuse-цепочки подтверждены: stature (`height_m` + `max_height_m` + graph metrics), crown spread/apical dominance (6 PH0-тритов), root depth (уже эволюционирует и работает в water fitness);
   - новые оси доказаны кодовыми gap'ами: crown density / leaf economics / structural investment / root spread / root-shoot allocation (последний — placeholder 0.5, никем не читается);
   - environment: в `environment_sample_v1` нет soil texture / litter / transpiration / understory light каналов; вода и тень сегодня только потребляются растениями — публикацию эффектов достраивает `plant_environment_effect.v1` (ТЗ §7);
   - feedback surfaces к переиспользованию: CAL1-B vertical light competition, CAL1-C spatial crown/root competition (caller-supplied `canopy_overlap`/`local_density` — точка инъекции cell-полей), P3.6 succession, resource model costs.
2. **Документ маппинга** `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md`: таблица 8 осей ТЗ → accepted surface → verdict (REUSE ×4 / NEW-additive ×5), инвентари, ownership boundary freeze (6 правил), минимальный список новых полей для FFF1, открытые вопросы → FFF1 design brief.
3. **Машинная фиксация**: `tests/research/ecology/eco_evo7_fff0_contract_mapping_acceptance.gd` — гейты M1–M10 (genome v1 frozen exact-count; single mutation authority + morphology outside kernel; PH0 traits intact; plasticity realize exists; environment channel gaps; bridge delegates kernel без собственного trait set (G13 preview); structural cost без наследуемой оси; allocation placeholder не наследуется; render pipeline derived-only (G15 preview); determinism smoke).

## Focused evidence

Проверено на:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`, Windows, headless

```powershell
.\RUN_ECO_EVO7_FFF0_TESTS.ps1
```

Результат (после repair R1; до repair — 168 assertions c 56 дублями в M3, см. секцию Review):

```text
ECO.EVO7 FFF0 Contract Mapping: PASS (112 assertions)
ECO.P1A-S1 Environment Baseline: PASS (109 assertions)  # hash b862c4fc… совпал с принятым baseline
ECO.P1A-S2 Single-Plant Resource Model: PASS (235 assertions)
ECO.P1C-S4 Aggregate Contract: PASS (15 assertions)     # failure matrix: все PASS
ECO.PH0 Development Trait Contract: PASS (63 assertions) # development_traits_hash 9d812950… совпал
```

Регрессия EVO6-WATER (G14):

```powershell
.\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Результат:

```text
ECO.EVO6-WATER strong water rules + evolutionary divergence + visual adapter: PASS
ECO.EVO6-WATER fitness: PASS (5 assertions)
ECO.EVO6-WATER evolution: PASS (24 assertions)
ECO.EVO6-WATER-VIS: PASS plants=72 pref_span=0.657 root_span=0.700
result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e
  (одинаковый в evolution и visual observatory)
dry: mean water_preference 0.58 -> 0.343, mean root_depth_m 0.85 -> 2.164
  (воспроизведены значения принятого EVO6-WATER R1)
```

## Review & Verification

### Independent review — PASS

Свежая изолированная роль reviewer'а на exact head `6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f`.

- Отчёт: `docs/evidence/2026-08-23_ECO_EVO7_FFF0_FINAL_REVIEW_RU.md`.
- Re-run evidence воспроизведён ревьюером лично; ключевые заявления аудита подтверждены по коду (`MUTABLE_TRAITS` ровно 5 экологических полей, делегация моста, все REUSE/gap-факты).
- BLOCKER/MAJOR: нет. MINOR-1: в M3 `check_bounds_keys` вызывался внутри цикла → 56 дублей-assertions (168 вместо честных 112). MINOR-2: в mapping doc §7 параметры `canopy_overlap`/`local_density` были приписаны CAL1-C, тогда как в коде это параметры `VerticalLight.create_context` (CAL1-B).
- **Repair R1 (этот коммит):** дубли M3 удалены (тест теперь 112 assertions), атрибуция CAL1-B/CAL1-C исправлена в `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md` §7. Гейты M1–M10 и все зафиксированные хэши не менялись; после repair FFF0 gate повторно прогнан локально: `PASS (112 assertions)`.

### Clean-checkout verification — VERIFIED

Независимая роль верификатора воспроизвела весь evidence на чистом detached worktree той же exact head (без `.godot`, fresh-worktree import правило отработано).

- Отчёт: `docs/evidence/2026-08-23_ECO_EVO7_FFF0_VERIFICATION_RU.md`.
- Все хэши совпали: environment `b862c4fc…`, simulation `618ec5c1…`, aggregate `0ca70eab…`, traits `9d812950…`, EVO6-WATER `result_hash 7010e307…` (идентичен в evolution и visual observatory); dry root_depth_m 0.85 → 2.16355.
- Неблокирующее замечание верификатора: parse-ошибки импорта трёх legacy-сцен `eco_evo5_*_lab.tscn` существуют на этой голове независимо от FFF0 и на гейты не влияют.

## Exit FFF0 по ТЗ §19

- mapping таблица `EVO7 semantic axis -> accepted PH field` — готова, машинно зафиксирована;
- инвентарь mutation authority и environment channels — готов;
- ownership boundaries заморожены (6 правил, включая `environment != genome writer`);
- список действительно новых contract-полей минимален: ровно 5 additive полей development traits + derived functional phenotype + effect record + soil texture input channel.

## Что этот checkpoint НЕ делает

- не вводит ни одного нового поля/контракта (это FFF1+);
- не меняет schema v1 genome или PH0 traits (только фиксирует их frozen-статус тестом);
- не добавляет feedback-логику, визуал лабы или evolution extension;
- не претендует на canonical acceptance до независимого review/verification.

## Следующий шаг

FFF1 — PlantFunctionalPhenotype R1: derived read-only representation, компилятор из принятых поверхностей, G1–G3. Стартует отдельным work order'ом на design brief из §11 audit-документа.
