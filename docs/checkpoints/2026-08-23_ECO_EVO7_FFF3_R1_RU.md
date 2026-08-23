# ECO.EVO7 FFF3 — Light Feedback R1 — CANDIDATE

**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1`
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§7, §8, §13, §19 FFF3; gates G6, G7, G10, G12)
**Основание:** FFF0 (mapping), FFF1 (functional phenotype), FFF2 (heritable morphology, single authority).

## Design brief (pre-build, research MEDIUM)

- **Проблема:** растения уже эволюционируют морфологией (FFF2), но не влияют на среду — контур разомкнут. Нужно: публикация эффектов (§7), агрегация тени (§8, §13), understory light в fitness, counterfactual ON/OFF.
- **Выбрано:** `plant_environment_effect.v1` (записи эффектов, канонический порядок по identity, неактивные каналы = 0) + `understory_light_field.v1` (cell-buckets, Beer-Lambert `exp(-K·overlap)`, вертикальное правило «только более высокий затеняет», канонический порядок суммирования) + `evo7_light_feedback_bridge_v1` (микрокосм 5×5, сетка 0.35 м — crown-scale, см. ограничения).
- **Отвергнуто:** all-pairs O(N²) скан (§13 запрещает); прямая запись растений в среду; затенение без вертикальной структуры (низкое не должно затенять вершину высокого).
- **Риски:** слабый градиент света в микрокосме (гасится калибровкой: сетка 0.35 м, предок с foliage 0.65 ⇒ ~18% затенения); дрейф-доминирование при коротких прогонах (16 поколений); дубликаты identity у потомков одной позиции (ловится дедупликацией по позиции — identity есть канонический ключ).

## Что реализовано

1. `scripts/research/ecology/plant_environment_effect_v1.gd` — контракт §7: каналы `shade_ppm` (активен) + `water_uptake/evaporation_suppression/litter_input/soil_binding_ppm` (зарезервированы под FFF4/FFF5, **ненулевое значение в неактивном канале = нарушение контракта** — «no creation from nothing»); `effect_hash`; `canonical_sort` + `combined_hash` (порядко-инвариантная публикация).
2. `scripts/research/ecology/understory_light_field_v1.gd` — агрегатор §8+§13:
   - `overlap_lai(p) = Σ_{q≠p, height_q>height_p} lai_q · (1 − dist/r_q)`; `transmittance = exp(-0.9·overlap)`; `understory = base_sunlight·transmittance`;
   - cell-buckets `CELL_SIZE_M=1.0` (детерминированное membership, per-cell canopy load для наблюдаемости);
   - канонический порядок: записи сортируются по identity, все float-суммы идут в этом порядке ⇒ инвариантность к перестановке входа (G12);
   - fail-closed: пустой/дубликат/out-of-range — пустой результат.
3. `scripts/research/ecology/evo7_light_feedback_bridge_v1.gd` — замкнутый контур:
   - 25 позиций (5×5, шаг 0.35 м), identity привязан к позиции;
   - каждый generation: реализация фенотипов под текущий свет (пластичность) → публикация геометрии + effect-записей → агрегация поля → **ON**: каждое растение реализуется и оценивается под СВОИМ understory light; **OFF** (counterfactual): все под базовым светом; формула mutation stream `EVO7-LIGHT|seed|gen|parent|off` идентична в обоих режимах — различается только назначение среды (это и есть тестируемая причинность);
   - воспроизводство через единственную lineage authority (FFF2), по одной особи на позицию.
4. Тест `eco_evo7_fff3_light_feedback_acceptance.gd` (51 assertion) + раннер `RUN_ECO_EVO7_FFF3_TESTS.ps1` (цепочка 10 наборов, включая P1B-S1 kernel 5834 assertions).

## Наблюдаемая динамика (lineage_seed 20260823, 16 поколений, 25 растений)

```text
base sunlight (plateau)            = 0.6749
feedback ON  mean understory light = 0.5523   (крона затемнила грунт на ~18%)
feedback ON  final field hash      != initial field hash        (G10: среда сдвинулась)
feedback ON  final population hash != feedback OFF population hash (G7: отбор изменил потомков)
deep-shade quartile LAI = 0.205  <  open-light quartile LAI = 0.271   (G7: в той же
популяции растения под пологом несут на ~25% меньше листвы — форма подлеска)
```

Интерпретация: конкуренция за свет отбирает высоту (уйти из-под кроны соседа) и одновременно создаёт затенённые ниши, в которых выживают мало-лиственные мало-затратные формы — пары «крона/подлесок» внутри одной популяции. Это первый замкнутый контур «растения → среда → отбор» (§8.4 Experiment A в зачатке; полный succession-цикл с gap-восстановлением — FFF6).

## Gates

- **G6 Tall canopy changes light** — высокое плотное растение снижает свет низкого в перекрывающейся ячейке; удаление кроны восстанавливает base **bit-exact**; две кроны темнее одной (монотонность); формула Бугера—Ламберта сверяется с независимым `exp(-K·overlap)`; вертикальное правило: низкое не затеняет высокое, равные по высоте не затеняют друг друга (R1). PASS.
- **G7 Light changes descendants** — ON/OFF при идентичной формуле мутационного потока дают разные финальные популяции; в ON-популяции глубокая тень ⇒ меньше LAI (understory-форма получает преимущество в своей нише). PASS.
- **G10 Closed-loop causality** — начальное поле ≠ финальному (среда сдвинута растениями), ON ≠ OFF, mean understory < base − 0.05. PASS.
- **G12 Order invariance** — 3 перестановки входного порядка 5 растений ⇒ идентичные `field_hash`, `plant_light_hash` и per-plant light; `combined_hash` effect-записей также порядко-инвариантен. PASS.

## Focused evidence

`Godot 4.7.1.stable.double.custom_build.a13da4feb`, Windows headless:

```text
ECO.EVO7 FFF3 Light Feedback:           PASS (51 assertions)   # bridge ~3 s
ECO.EVO7 FFF2 Morphology Evolution:     PASS (56)
ECO.EVO7 FFF1 PlantFunctionalPhenotype: PASS (110)
ECO.EVO7 FFF0 Contract Mapping:         PASS (112)
ECO.P1B-S1 Mutation/Lineage kernel:     PASS (5834)
ECO.PH2: PASS (107)  P1A-S1: PASS (109, b862c4fc…)  P1A-S2: PASS (235)
P1C-S4: PASS (15)    PH0: PASS (63, 9d812950…)
EVO6-WATER -SkipBaseline: PASS, result_hash 7010e307… (не изменён)
```

## Осознанные ограничения R1

1. Микрокосм в масштабе кроны (сетка 0.35 м, ячейка 1 м): скелетные кроны суб-метровые; «настоящие» лесные масштабы — FFF6/FFF7.
2. Равные по высоте не затеняют друг друга (упрощение R1); диффузное световое насыщение по слоям — FFF6.
3. ON/OFF: общий поток мутаций, среда назначает его линиям — назначение среды и есть тестируемая причинность (задокументировано; «common pool» в смысле EVO6 применяется к сценариям среды, здесь сравнивается ON/OFF одного сообщества).
4. Shade_tolerance генома пока не входит в light-компоненту (наследие water fitness); световая толерантность в R1 выражается через low-cost формы.
5. Water/litter каналы effect-записей зарезервированы и защищены нулями — активируются в FFF4/FFF5.

## Следующий шаг

FFF4 — Water + Soil Texture Feedback R1: transpiration demand, bounded uptake (вода не ниже нуля), evaporation suppression от кроны, root access по глубине/распространению, sand/loam/clay fixture-канал (G8, G9).
