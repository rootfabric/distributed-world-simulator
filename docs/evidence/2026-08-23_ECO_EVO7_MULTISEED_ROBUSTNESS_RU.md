# ECO.EVO7 — Мульти-seed робастность эволюционных мостов (независимый research-probe)

**Дата:** 2026-08-23
**Вердикт:** **PASS** — `ECO.EVO7 multiseed robustness: PASS (10 assertions)`, код выхода 0.
**Роль:** независимый research-probe линии EVO7 (изоляированная делегированная сессия).
**Ограничение роли:** созданы ровно 2 новых файла; ни один существующий файл не изменён и не закоммичен.

## 1. Точная голова

- Worktree: `C:\distributed-world-simulator\worktrees\eco-water-r1`, ветка `feature/eco-evo7-fff-r1`.
- `git rev-parse HEAD`: `fd6855e32f1151bc2d52faba385afae883a472a3` — начинается с `fd6855e3`, совпадает с ожидаемой.
- На момент старта пробы `git status --porcelain` содержал только ранее существовавшие untracked-файлы (`.uid`, `__pycache__`); изменённых tracked-файлов не было.

## 2. Что проверяется

Мульти-seed устойчивость НАПРАВЛЕНИЯ отбора (не точных хешей) для обоих детерминированных эволюционных мостов на 5 lineage-seeds `[20260823, 11, 22, 33, 44]`:

- **FFF2** `evo7_morphology_evolution_bridge_v1.run_all(seed, 24, 18, 4)`:
  - `dry_ridge` mean `realized_root_depth_m` > `wet_lowland` (направление, ≥ 4/5 seeds);
  - `sunny_slope` mean `realized_crown_density` > `shaded_slope` (направление, ≥ 4/5 seeds);
  - анти-runaway (жёсткие ворота, 5/5 seeds): mean ext `foliage_density` в [0.07..0.98] и mean ext `root_shoot_ratio` в [0.17..0.83] в каждом из 5 сценариев (окна внутри контрактных границ [0.05..1.0] / [0.15..0.85] — pinned-среднее означало бы эволюцию «в рельс»);
  - детерминизм: строгий двойной прогон seed 20260823 → идентичный `result_hash`.
- **FFF3** `evo7_light_feedback_bridge_v1.run_all(seed)` (16 поколений):
  - `feedback_on.final_population_hash` != `feedback_off` (причинность, 5/5 seeds);
  - `deep_shade_mean_lai` < `open_light_mean_lai` (направление, ≥ 4/5 seeds);
  - `mean_understory_light` < `base_sunlight` − 0.03 (направление, ≥ 4/5 seeds);
  - детерминизм: двойной прогон **каждого** seed → идентичный `result_hash` (5/5).

### Методическая заметка (извлечение trait-средних FFF2)

`run_all` не отдаёт средние ext-признаки `foliage_density`/`root_shoot_ratio` (в `mean_features` их нет). Тест воспроизводит финальную популяцию каждого сценария собственными строительными блоками моста (тот же ancestor-шаблон, та же формула мутационного потока `EVO7-MORPHO|…`, те же `Bridge._evaluate` и `_rank_order`) и доказывает точность воспроизведения поэлементным равенством `final_population_hash` с результатом `run_all` для всех 5×5 seed×сценариев; только после этого читаются trait-средние. Код мостов не изменялся и не ослаблялся.

## 3. Таблица seed × check (наблюдаемое)

Источник: `tests/research/ecology/eco_evo7_multiseed_robustness_acceptance.gd`, прогон от 2026-08-23 (полная матрица напечатана тестом; колонка rate теста = «совпало/требуется»).

| Проверка (требование) | 20260823 | 11 | 22 | 33 | 44 | Rate |
|---|---|---|---|---|---|---|
| FFF2 root_depth: dry_ridge > wet_lowland (≥4/5) | pass | pass | pass | pass | pass | **5/5** |
| FFF2 crown_density: sunny_slope > shaded_slope (≥4/5) | pass | pass | pass | pass | pass | **5/5** |
| FFF2 anti-runaway: foliage_density в [0.07..0.98] (5/5) | pass | pass | pass | pass | pass | **5/5** |
| FFF2 anti-runaway: root_shoot_ratio в [0.17..0.83] (5/5) | pass | pass | pass | pass | pass | **5/5** |
| FFF2 детерминизм: replay = финальные популяции моста (5/5) | pass | pass | pass | pass | pass | **5/5** |
| FFF3 причинность: feedback_on != feedback_off (5/5) | pass | pass | pass | pass | pass | **5/5** |
| FFF3 форма: deep_shade_lai < open_light_lai (≥4/5) | pass | pass | pass | pass | **FAIL** | **4/5** |
| FFF3 затемнение: understory < base − 0.03 (≥4/5) | pass | pass | pass | pass | pass | **5/5** |
| FFF3 детерминизм: двойной прогон, идентичный result_hash (5/5) | pass | pass | pass | pass | pass | **5/5** |

Дополнительно: строгий двойной прогон FFF2 seed 20260823 → `result_hash=dac30340e0790aed…` идентичен в обоих прогонах (pass).

## 4. Наблюдаемые значения

### FFF2 (morphology)

| Seed | dry_root, м | wet_root, м | sunny_crown | shaded_crown | foliage [min..max] | root_shoot [min..max] |
|---|---|---|---|---|---|---|
| 20260823 | 2.933 | 1.204 | 0.757 | 0.126 | 0.360..0.969 | 0.333..0.498 |
| 11 | 2.136 | 0.624 | 0.644 | 0.054 | 0.154..0.930 | 0.328..0.435 |
| 22 | 1.823 | 0.183 | 0.772 | 0.040 | 0.113..0.971 | 0.264..0.422 |
| 33 | 2.250 | 0.727 | 0.728 | 0.055 | 0.158..0.932 | 0.293..0.552 |
| 44 | 2.290 | 0.353 | 0.735 | 0.047 | 0.134..0.974 | 0.211..0.463 |

(min/max — по 5 сценариям внутри seed; ни одно сценарное среднее не пришпилено к границе окна.)

### FFF3 (light feedback)

| Seed | deep_shade_lai | open_light_lai | understory | base_sunlight | on!=off | result_hash (16) |
|---|---|---|---|---|---|---|
| 20260823 | 0.205 | 0.272 | 0.552 | 0.675 | да | `cd30fcbfeb294e19` |
| 11 | 0.266 | 0.285 | 0.573 | 0.702 | да | `e254d85fa8a70249` |
| 22 | 0.235 | 0.239 | 0.586 | 0.702 | да | `a9fc7eb9bdb31554` |
| 33 | 0.180 | 0.237 | 0.603 | 0.702 | да | `b2583951ba9b5add` |
| 44 | **0.249** | **0.240** | 0.579 | 0.702 | да | `f56c4ba11b2f5259` |

Контроль базовой линии: seed 20260823 воспроизвёл задокументированные одино-seed значения (dry_root ≈ 2.93 vs wet_root ≈ 1.20; understory 0.552 < base 0.675; `result_hash` FFF3 `cd30fcbf…` совпал с принятым evidence FFF3) — прогон соответствовал R1-поведению на HEAD.

### Честная фиксация отклонения seed 44 (FFF3, LAI-направление)

На seed 44 направление «в глубокой тени меньше листовой поверхности» инвертировалось: deep_shade 0.249 > open_light 0.240 (перевес ~0.009). На seed 22 направление держится с минимальным зазором (0.235 < 0.239, ~0.004). Итого направление подтверждено на **4 из 5** seeds — ровно порог устойчивости ≥ 4/5, поэтому общий вердикт PASS. Мост не ослаблялся; порог не пересматривался; отклонение зафиксировано как есть. Интерпретация для следующей стадии: quartile-LAI контраст на части seeds слабый (~0.004–0.009) — для FFF4+ имеет смысл либо усилить формирующий давление отбора канал, либо снизить заявленную силу этого гейта.

## 5. Runtime

| Фаза | Время |
|---|---|
| FFF2: 5 прогонов `run_all` (по ~15.5–16.6 с) + replay 5×5 сценариев + строгий двойной прогон | 175.3 с |
| FFF3: 10 прогонов (5 seeds × двойной, по ~5.6–6.0 с) | 28.7 с |
| **Всего** | **204.0 с (~3 мин 24 с)** |

Примечание: одиночный прогон FFF3 занял ~5.7–6.0 с против ~2.9 с в одино-seed evidence — вероятно, конкуренция CPU на общей машине во время прогона; на детерминизм не влияет (все хеши воспроизведены).

## 6. Итоговый вывод теста

```text
=== ECO.EVO7 multiseed robustness: check x seed (directional >= 4/5; unanimous == 5/5) ===
(матрица — раздел 3)
total runtime_ms=203953
ECO.EVO7 multiseed robustness: PASS (10 assertions)
```

## 7. Команды

```text
& C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe --headless `
  --path C:\distributed-world-simulator\worktrees\eco-water-r1 `
  --script res://tests/research/ecology/eco_evo7_multiseed_robustness_acceptance.gd
# GODOT_EXIT_CODE=0
```

## 8. Целостность рабочей деревa

- Пробой создал ровно 2 файла: `tests/research/ecology/eco_evo7_multiseed_robustness_acceptance.gd` и настоящий документ. Ничего не изменено и не закоммичено; `.uid`-файл для нового теста при headless-прогоне не генерировался.
- Во время прогона пробы в общем worktree параллельной работой (не этой пробой) появились изменения `scripts/research/ecology/plant_environment_effect_v1.gd` и `tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd` (активация water-каналов FFF4). Проба их не касалась и не откатывала. На результаты пробы они не влияют: FFF2-мост Effect не использует, а FFF3-прогон воспроизвёл принятый базовый `result_hash` seed 20260823 (`cd30fcbfeb294e19`) побитово.
