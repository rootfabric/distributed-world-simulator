# ECO.EVO7 — Мульти-seed acceptance, волна 2 (независимый research-probe)

**Дата:** 2026-08-23
**Вердикт:** **PASS** — `ECO.EVO7 multiseed wave2: PASS (15 assertions)`, код выхода 0.
**Роль:** независимый research-probe линии EVO7, волна 2 мульти-seed проверки (изоляированная делегированная сессия).
**Ограничение роли:** созданы ровно 2 новых файла; ни один существующий файл не изменён и не закоммичен.

## 1. Точная голова

- Worktree: `C:\distributed-world-simulator\worktrees\eco-water-r1`, ветка `feature/eco-evo7-fff-r1`.
- `git rev-parse HEAD`: `d129b0ba3fff1ae303216a47628d2a4a7f49a904` — начинается с `d129b0ba`, совпадает с ожидаемой.
- На момент старта пробы `git status --porcelain` содержал только ранее существовавшие untracked-файлы (`.uid`-сайдкары, `scripts/research/ecology/__pycache__/`, `docs/evidence/2026-08-23_ECO_EVO7_FFF6_VERIFICATION_RU.md` параллельной работы); изменённых tracked-файлов не было.

## 2. Что проверяется

Волна 2 воспроизводит детерминированные мосты ECO.EVO7 на СВЕЖИХ lineage-seeds `[20260824, 20260825, 20260826]` (seed 20260823 исключён: это уже доказанная базовая линия одино-seed acceptances и wave-1 пробы `2026-08-23_ECO_EVO7_MULTISEED_ROBUSTNESS_RU.md`). Утверждаются НАПРАВЛЕНИЯ и причинность, не точные хеши; требование к каждой направленной семье — **3 из 3 seeds** (эффекты сильные):

- **WATER** `evo7_water_feedback_bridge_v1.run_all(seed)` (FFF4, 16 поколений):
  - направленная устойчивость на feedback ON по каждому seed: `dry_sand` mean `leaf_area_index_proxy` < `mesic_loam`; `dry_sand` mean `realized_root_depth_m` > `mesic_loam`; `dry_sand` mean `mean_cell_moisture` < `mesic_loam`;
  - причинность по каждому seed: `feedback_on.final_population_hash` != `feedback_off` в ОБОИХ сценариях (`dry_sand`, `mesic_loam`);
  - детерминизм: строгий двойной прогон seed 20260824 → идентичный `result_hash`.
- **LITTER** `evo7_litter_feedback_bridge_v1.run_all(seed)` (FFF5, Experiment D):
  - популяции modified-vs-pristine различаются по каждому seed (`divergence.populations_differ_modified_vs_pristine`);
  - направление накопления органики по каждому seed: legacy-фаза строит органическую память выше исходного девственного состояния (стартовая карта органики пуста ⇒ среднее 0; факт: `legacy_phase.mean_cell_organic` > 0) И modified-пул удерживает больше органики, чем pristine (`divergence.organic_modified_minus_pristine` > 0);
  - детерминизм: строгий двойной прогон seed 20260824 → идентичный `result_hash`.
- **SUCCESSION** `evo7_succession_simulation_v1.run_all(seed)` (FFF6, шесть зон):
  - расхождение ON/OFF ≥ 5/6 зон на каждый seed; число зон пересчитано независимо по хешам `zones[zone].feedback_on/off.final_population_hash` и сверено с `comparison.on_off_divergent_zones` (совпадение подтверждено на каждом seed);
  - конечность/ограниченность средних во ВСЕХ зонах и ОБОИХ режимах: `mean_understory_light`, `mean_cell_moisture`, `mean_cell_organic` ∈ [0..1] (+1e-9), все `mean_features` конечны и неотрицательны (нет NaN), `max_bound_pinning_fraction` ∈ [0..1];
  - детерминизм: строгий двойной прогон seed 20260824 → идентичный `result_hash`.

Код мостов и модуля не изменялся и не ослаблялся; пороговые требования не пересматривались.

## 3. Таблица seed × check (наблюдаемое)

Источник: `tests/research/ecology/eco_evo7_multiseed_wave2_acceptance.gd`, прогон от 2026-08-23 на HEAD `d129b0ba`.

| Проверка (требование 3/3) | 20260824 | 20260825 | 20260826 | Rate |
|---|---|---|---|---|
| WATER lai: dry_sand < mesic_loam (feedback_on) | pass | pass | pass | **3/3** |
| WATER root_depth: dry_sand > mesic_loam (feedback_on) | pass | pass | pass | **3/3** |
| WATER cell_moisture: dry_sand < mesic_loam (feedback_on) | pass | pass | pass | **3/3** |
| WATER причинность: on != off population hash (dry_sand) | pass | pass | pass | **3/3** |
| WATER причинность: on != off population hash (mesic_loam) | pass | pass | pass | **3/3** |
| LITTER Experiment D: populations differ modified vs pristine | pass | pass | pass | **3/3** |
| LITTER organic direction: legacy > initial и modified > pristine | pass | pass | pass | **3/3** |
| SUCCESSION on/off divergence >= 5/6 zones | pass | pass | pass | **3/3** |
| SUCCESSION finite + bounded means (все зоны, оба режима) | pass | pass | pass | **3/3** |

Дополнительно (внутренние утверждения теста, не матричные): три строгих двойных прогона seed 20260824 → идентичные `result_hash` (WATER/LITTER/SUCCESSION — все `twice_identical=true`); независимый пересчёт расходящихся зон совпал с `comparison.on_off_divergent_zones` на всех трёх seeds. Итого **15 assertions**, отказов нет.

## 4. Наблюдаемые значения

### WATER (FFF4, feedback ON)

| Seed | LAI dry | LAI mesic | root dry, м | root mesic, м | влага dry | влага mesic | on!=off dry/mesic | result_hash (16) |
|---|---|---|---|---|---|---|---|---|
| 20260824 | 0.296 | 0.436 | 1.66 | 1.01 | 0.014 | 0.422 | да / да | `dd754a1f985c7a8c` |
| 20260825 | 0.305 | 0.455 | 2.16 | 0.86 | 0.011 | 0.435 | да / да | `bfb34d5e32172423` |
| 20260826 | 0.325 | 0.412 | 1.80 | 1.23 | 0.010 | 0.421 | да / да | `12cb1826c76725f7` |

Согласование с базовой линией seed 20260823 (LAI 0.27 dry vs 0.40 mesic; корни 2.29 vs 0.90): направления и порядки величин воспроизводятся на всех свежих seeds без ослабления контраста.

### LITTER (FFF5, Experiment D)

| Seed | legacy organic (final) | organic mod−pristine | establishment mod−pristine | влага mod−pristine | пулы идентичны | pop differ | result_hash (16) |
|---|---|---|---|---|---|---|---|
| 20260824 | 0.1741 | +0.0835 | +0.00246 | −0.0021 | да | да | `26f51fb25c6e3e01` |
| 20260825 | 0.1720 | +0.0826 | +0.00235 | −0.0017 | да | да | `fa4c202313f879ba` |
| 20260826 | 0.1537 | +0.0867 | +0.00230 | −0.0026 | да | да | `32005f014e6b2f37` |

Согласование с базовой линией seed 20260823 (organic ≈ +0.083, establishment ≈ +0.0022): обе заявленные дельты воспроизводятся узким corridor'ом (+0.083…+0.087 и +0.0023…+0.0025) — эффект стабилен между seeds.

Честная наблюдаемая (не гейт): `moisture_modified_minus_pristine` слегка отрицателен на всех трёх seeds (−0.0017…−0.0026). Этот показатель НЕ входит в заявленное направление пробы: мост явно помечает cross-evaluation/популяционную влагу как observability-only с не гарантированным знаком (PH2-пластичность пере-реализует морфологию под изменённую влажность); структурно гарантируемые факты — различие популяций, накопление органики и положительный establishment-компонент — подтверждены на 3/3 seeds.

### SUCCESSION (FFF6, шесть зон)

| Seed | Расхождение ON/OFF | Зоны | finite+bounded | result_hash (16) |
|---|---|---|---|---|
| 20260824 | **6/6** (порог ≥5/6) | FLOODED\|RIPARIAN|MESIC_LOAM\|DRY_SAND\|UNDER_CANOPY\|CANOPY_GAP | да | `28414a1831f26475` |
| 20260825 | **6/6** | все шесть | да | `876ecd4f96e258a2` |
| 20260826 | **6/6** | все шесть | да | `c047378faadb898f` |

Расхождение ON/OFF превысило требование: во всех зонах на всех seeds (как и на базовой линии 20260823, где зафиксирован `result_hash=52995cf4bcd03578…` при 6/6 зон). Конечность/ограниченность средних соблюдена везде: ни одного NaN, нормированные средние внутри [0..1], pinning-доли валидны. `result_hash` закономерно различаются между seeds (зависимость от seed) и побитово совпадают при повторном прогоне того же seed (детерминизм).

## 5. Честные заметки об отклонениях

Отклонений семейств НЕТ: каждая направленная/причинная семья выполнена на 3/3 seeds, все двойные прогоны детерминистичны. Два наблюдения для полноты картины:

1. LITTER-влага «modified − pristine» отрицательна малого масштаба (~−0.002) на всех seeds — см. раздел LITTER выше; не является заявленным гейтом и не влияет на вердикт.
2. SUCCESSION-порог «≥ 5/6» фактически выполняется с запасом (6/6 везде); порог оставлен как заявлен, не «подгонялся» под результат.

## 6. Runtime

| Фаза | Состав | Время |
|---|---|---|
| WATER | 3 прогона run_all (9.6–9.9 c) + строгий двойной прогон | 38.8 c |
| LITTER | 3 прогона run_all (5.2–5.4 c) + строгий двойной прогон | 21.3 c |
| SUCCESSION | 3 прогона run_all (19.4–20.4 c) + строгий двойной прогон | 77.7 c |
| **Всего** | | **137.8 c (~2 мин 18 c)** |

Уложилось в бюджет ~6 минут с запасом; прогресс печатался построчно по каждому seed, так что частичный прогресс был виден во время прогона.

## 7. Итоговый вывод теста

```text
=== ECO.EVO7 multiseed wave2: check x seed (every family required >= 3/3) ===
(матрица — раздел 3)
total runtime_ms=137836
ECO.EVO7 multiseed wave2: PASS (15 assertions)
```

## 8. Команды

```text
& C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe --headless `
  --path C:\distributed-world-simulator\worktrees\eco-water-r1 `
  --script res://tests/research/ecology/eco_evo7_multiseed_wave2_acceptance.gd
# GODOT_EXIT_CODE=0
```

Перед полным прогоном выполнен быстрый синтаксический контроль той же команды с `--check-only` (успешно).

## 9. Целостность рабочей копии

- Пробой создал ровно 2 файла: `tests/research/ecology/eco_evo7_multiseed_wave2_acceptance.gd` и настоящий документ. Ничего не изменено и не закоммичено; `.uid`-сайдкар для нового теста при headless-прогоне не генерировался.
- Ранее существовавшие untracked-артефакты (`.uid`, `__pycache__`, FFF6-verification evidence) пробой не затрагивались.
