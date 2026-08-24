# ECO.EVO7 — Независимый аудит исследовательской линии по гейтам ТЗ (G1–G15, §22, §17)

**Дата:** 2026-08-23
**Роль:** независимый LINE AUDITOR (изолированная свежая роль; ограничение роли — создан ровно 1 новый файл, ничего не изменено и не закоммичено).
**Worktree:** `C:\distributed-world-simulator\worktrees\eco-water-r1`, ветка `feature/eco-evo7-fff-r1`.
**`git rev-parse HEAD`:** `d129b0ba3fff1ae303216a47628d2a4a7f49a904` — совпадает с ожидаемым (STEP 0 PASS).
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md`.
**Метод:** тестовые наборы НЕ перезапускались (числа цитируются из зафиксированных checkpoint/evidence-документов); вместо этого выполнены адресные spot-check'и КОДА и ассертов: `plant_mutation_lineage_kernel_v1.gd` (`MUTABLE_TRAITS` = ровно 5 полей), `plant_mutation_lineage_extension_evo7_v1.gd` (делегация `Kernel.reproduce`, 8 канонических осей), `plant_functional_phenotype_v1.gd` (перекалиброванные константы, `age_fraction` в hash-токенах), `understory_light_field_v1.gd` (bucket-pruning, `exp(-K·overlap)`), `soil_water_field_v1.gd` (ёмкость 4·10⁶, texture-параметры, retention-связка, формула доступа БЕЗ rsr), `soil_organic_field_v1.gd` (decay 1.3/1.0/0.75, `retention_multiplier = 1+0.35·o`), `evo7_succession_simulation_v1.gd` (6 зон, STABILITY=108, pinning, Experiment A), лаба `scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd` (C-режим, оверлеи 1–5, X/R, AUTOCAP), а также все acceptance-файлы `tests/research/ecology/eco_evo7_*`.

---

## A. Матрица гейтов G1–G15 (§16 ТЗ)

Итог: **PROVEN — 14, PARTIAL — 1 (G5), DEFERRED — 0.**

| Гейт | Этап доказательства | Конкретное доказательство (тест::assertion / evidence) | Статус |
|---|---|---|---|
| **G1** Deterministic phenotype | FFF1 | `eco_evo7_fff1_functional_phenotype_acceptance.gd`: «G1: identical inputs give byte-identical payload», «G1: identical inputs give identical hash», «G1: input key order does not matter», «age_fraction participates in phenotype hash identity» (spot-check: `age_fraction` действительно в hash-токенах `plant_functional_phenotype_v1.gd::175`, repair R1 FFF1). Зафиксировано: PASS (110 assertions). | **PROVEN** |
| **G2** Plasticity without Lamarckian write | FFF1 | Тот же тест: «G2: drought suppresses realized height», «G2: environment changes realized phenotype hash», «G2: genome checksum unchanged by environment», «G2: mutation authority untouched», source-gate «functional phenotype never touches heredity path». Код: компилятор не импортирует kernel; fail-closed на checksum-mismatch. | **PROVEN** |
| **G3** Heritable morphology | FFF1 (+FFF2) | Одноосные контролируемые пробы на ветвящейся референс-морфологии: stature/foliage/leaf_economics/structural/root_spread/rsr/genome root_depth — направления с bit-identical несвязанными сторонами (ассерты «G3 stature…», «reference morphology carries lateral segments» и далее). Задекларированные couplings R1 проверяются тестом. | **PROVEN** (в рамках declared R1: structural = cost-only, allocation без геометрии) |
| **G4** Common mutation pool causality | FFF2 (+FFF6) | `eco_evo7_fff2_morphology_evolution_acceptance.gd`: «G4: generation-one candidate pool hash present», «G4: final selected populations differ across environments (pairs >= 8 of 10)», replay-хэш идентичен, seed-sensitivity. Формула потока `EVO7-MORPHO|seed|gen|parent|off` едина. В FFF6: «G4: one generation-one candidate pool across all zones» + общий пул между ON/OFF. | **PROVEN** |
| **G5** Geometry divergence | FFF2 (числ.) + FFF6 (визуал C-neutral) | Численно: 10/10 пар geometry-distinct, ≥3 сценария vs baseline (набл. 4/4), направления dry-roots/sunny-density/shade-dwarf — ассерты FFF2 + мульти-seed направление 5/5 seeds (`2026-08-23_ECO_EVO7_MULTISEED_ROBUSTNESS_RU.md`). Визуально: C-режим реализован в лабе (единый серый `StandardMaterial3D`, `_apply_neutral`), headless-autocap PASS `rendered=150 geom_pairs=4`. **Но** GUI-прогон со скриншотом при нейтральном материале явно отложен на line-level checkpoint (ограничение №1 FFF6) — визуальная половина гейта не имеет человекочитаемого evidence. | **PARTIAL** |
| **G6** Tall canopy changes light | FFF3 (+FFF6) | `eco_evo7_fff3_light_feedback_acceptance.gd`: «G6: tall canopy reduces understory light below base», «G6: canopy removal restores base light exactly» (<1e-9), монотонность двух крон, точная сверка Beer-Lambert с независимым `exp(-K·overlap)` (K=0.9 в коде), вертикальные правила (низкое/равное не затеняет). FFF6 Experiment A: post_light > pre_light ×3. | **PROVEN** |
| **G7** Light changes descendants | FFF3 (+multiseed) | «G7: feedback ON/OFF select different descendants», «deep-shade plants carry less leaf area» — причинность 5/5 seeds (мульти-seed док); направление quartile-LAI — **4/5 seeds** (seed 44 инвертирован, перевес ~0.009, честно зафиксировано; порог пробы ≥4/5 соблюдён точно). Ядро гейта (смена потомков при том же потоке мутаций) единогласно. | **PROVEN** (с задокументированной слабостью направления understory-LAI: маржа 0.004–0.009 на части seed'ов) |
| **G8** Water engineering | FFF4 | Ассерты: влага каждой ячейки [0,1] и ≤ базы; «per-cell total uptake never exceeds available water» (структурно + stress-проба 10×); «high-LAI community dries the soil more than the low-LAI control» (>0.05); suppression = clamp01(cover·0.6) точной математикой; sand/clay контрасты испарения/uptake; effect-записи с nonzero водными каналами; fail-closed 8 классов. Код: `uptake=min(demand, remaining·access·texture_eff)`, clamp01, ёмкость 4·10⁶. | **PROVEN** |
| **G9** Sand vs loam | FFF4 | dry_sand: LAI ниже (>0.05, набл. 0.131), корни глубже (>0.30, набл. 1.39), rsr выше (>0.015, набл. 0.048); mesic_loam не запрещает высокие стратегии (net>0, высота 3.85 м). Source-gates: texture-токены только в fixture-конструкции («texture lines outside fixture == 0»), нет `if texture`/archetype в поле/мосте/fitness-пути. Cross-seed автоматизирован repair R1 (seed'ы 20260824/25). | **PROVEN** |
| **G10** Closed-loop causality | FFF3 → FFF4 → FFF5 → FFF6 | FFF3: initial≠final field hash, ON≠OFF, mean understory < base−0.05; FFF4: оба сценария initial≠final + ON≠OFF; FFF5: organic legacy строится (initial≠final map hash) + ON≠OFF; FFF6: «on_off_divergent_zones == 6». Два и более feedback-циклов — да (16 поколений × петля свет→вода→органика). | **PROVEN** |
| **G11** Trade-off anti-runaway | FFF6 (+FFF2 multiseed) | Stability-прогоны 108 циклов (`STABILITY_GENERATIONS=108` ≥100 ТЗ §19): «G11: no evolvable axis fully bound-pinned» для всех 8 осей, pin-max 0.08, средства конечны/в [0,1] — зоны MESIC_LOAM и DRY_SAND. Мульти-seed FFF2: жёсткие окна foliage_density∈[0.07..0.98], rsr∈[0.17..0.83], 5/5 seeds × 5 сценариев. Ограничение объёма: stability покрывает 2 зоны из 6. | **PROVEN** (scope: 2 зоны ×108 циклов + окна FFF2; см. E-6 про терминологию «preview») |
| **G12** Order invariance | FFF3/FFF4/FFF5 | Перестановки и реверс входных записей ⇒ идентичные `field_hash`/`plant_light_hash`/`plant_uptake_hash`/`organic_field_hash` и per-plant значения; combined_hash effect-записей порядко-инвариантен. Код: каноническая сортировка по identity во всех трёх полях (`sort_custom`). После bucket-pruning света — регрессия бит-идентична (`cd30fcbf…`). | **PROVEN** |
| **G13** No second mutation path | FFF2 (сквозь FFF6) | Source-gate: «genome heredity delegated to the v1 kernel» (`Kernel.reproduce` в исходнике extension), точный текстовый ассерт нетронутости блока `MUTABLE_TRAITS` v1-kernel (spot-check кода: ровно 5 экологических полей), tampered bundle отклоняется checksum-гейтом, запрещённые RNG-токены отсутствуют в evolution-слое, все мосты воспроизводятся только через LineageExtension (ассерты FFF4/FFF5/FFF6). Регрессия ядра P1B-S1 (5834 assertions) зелёная в каждой цепочке. | **PROVEN** |
| **G14** Existing regression | FFF0–FFF6 (каждая цепочка) | Все RUN_ECO_EVO7_FFF{0..6}_TESTS.ps1 включают EVO6-WATER: `result_hash 7010e307…` неизменен через всю линию (зафиксирован в каждом checkpoint); P1A-S1 `b862c4fc…`, P1A-S2 235, P1C-S4 failure matrix, PH0 `9d812950…`, PH2 107 — стабильны. Числа цитируются, не перезапускались (по условию аудита). | **PROVEN** (по зафиксированным evidence) |
| **G15** Visual truth boundary | FFF0 (M9 preview) + FFF6 | M9: render description не зависит от genome-truth, у render pipeline нет mutation-доступа, `ecological_truth_hash` отделён от presentation. Лаба материализуется реальным конвейером PH5 из тех же growth graph'ов («lab materializes through the real PH5 pipeline», «lab visuals come from the shared realization helper» — ассерты FFF6); C-режим/оверлеи/X-toggle — presentation-only, в экологические хэши не входят (по построению: применяют `material_override`/visibility поверх посчитанных данных). Интерактивная проверка «вживую» — только ручная (headless не нажимает клавиши). | **PROVEN** (структурно/source-gate; живая демонстрация — вместе с G5-скриншотом) |

---

## B. Definition of Done §22 — 9 пунктов

| # | Пункт §22 | Чем доказан | Статус |
|---|---|---|---|
| 1 | Одинаковые предки + одинаковые мутации + разные среды → разные наследуемые функциональные стратегии | FFF2 G4/G5 (общий пул ⇒ 10/10 различных финальных популяций, наследуемые направления root/crown), мульти-seed 5/5 по направлениям, FFF6 общий пул ⇒ разные популяции по зонам | **PROVEN** |
| 2 | Различия видны геометрически при выключенном debug-color | FFF6 лаба: C-режим (нейтральный материал), GeometryReadout 7 полей + парные geometry-distinct флаги, headless-autocap PASS rendered=150, geom_pairs=4≥3. **Скриншот GUI-прогонa отложен** (ограничение №1 FFF6) | **PARTIAL** |
| 3 | Форма меняет свет/воду/почву вокруг себя | Свет: FFF3 G6/G10; вода: FFF4 G8 (uptake, evaporation suppression); почва: FFF5 (litter → organic legacy, retention coupling, initial≠final map hash) | **PROVEN** |
| 4 | Изменённая растениями среда меняет selection следующего поколения | Замкнутые контуры FFF3/FFF4/FFF5/FFF6: initial field ≠ final, оценка под СВОЕЙ средой в ON-режиме, ON≠OFF популяции | **PROVEN** |
| 5 | Feedback ON и OFF дают разных descendants | FFF3 5/5 seeds, FFF4 оба сценария, FFF5 пулы A/B + ON/OFF, FFF6 6/6 зон (ассерты on_off_divergent_zones==6) | **PROVEN** |
| 6 | Ни environment, ни renderer не переписывают genome напрямую | G2 (компилятор без heredity-путей, fail-closed), G15/M9 (render derived-only, без mutation-доступа), environment — только derived EnvironmentSample для оценки | **PROVEN** |
| 7 | Нет второго mutation/lineage kernel | G13: единственная делегация в v1-kernel, MUTABLE_TRAITS нетронуты, P1B-S1 5834 зелёный на каждом этапе | **PROVEN** |
| 8 | Deterministic replay сохраняется | Replay-ассерты на каждом этапе; FFF6 REPLAY MATCH (R-клавиша) + байт-идентичность context_finish==run_all; мульти-seed двойные прогоны 5/5 идентичных result_hash | **PROVEN** |
| 9 | EVO6-WATER и ECO.PH invariants не ломаются | G14: result_hash EVO6-WATER 7010e307… сквозь всю линию; baseline-хэши P1A/PH0/PH2/P1C стабильны; бит-идентичность FFF3/FFF4 после изменений контракта (stash round-trip `0b4c9544…`) | **PROVEN** |

DoD: **8 PROVEN / 1 PARTIAL (п.2 — визуальный evidence).**

---

## C. Контрольные эксперименты §17 A–D

| Эксперимент | Статус | Основание |
|---|---|---|
| **A** «Большое дерево создаёт нишу» (succession-loop) | **PARTIAL** | Шаги 1–2, 5 доказаны полностью в FFF6 Experiment A: tall canopy под MESIC, свет UNDER_CANOPY 0.0666 vs 0.63+ после удаления, net −0.039 → +0.014, популяции GAP ≠ UNDER_CANOPY (детерминированное удаление после поколения 8, пороги с запасом ≥2×). Шаги 3–6 в сильной формулировке («light-demanding seedlings подавлены», «pioneer lineage снова получает преимущество») — частично: направление `leaf_economics_proxy` GAP-vs-UNDER нестабильно на горизонте (0.456 vs 0.464, знак против наивного ожидания) и сознательно НЕ гейтится (калибровка п.4 FFF6); «pioneer-преимущество» доказано опосредованно (свет/net/дивергенция), а не идентификацией стратегий линий. Cluster-диагностика (~25 кластеров/зону) слабоинформативна. |
| **B** «Песок делает дерево дорогим, но не запрещает правилом» | **PROVEN** | FFF4 G9: сухой песок ⇒ компактная крона + root-heavy эволюция из trade-off; mesic сохраняет tall-стратегии; source-gate: ни одного `if texture`/архетипа в fitness-пути/поле/мосте; cross-seed направления устойчивы (3 seed'а, автоматизировано repair R1). |
| **C** «Растительность сама сушит участок» | **PROVEN** | FFF4 G8: high-LAI сообщество сушит почву сильнее low-LAI контроля (−0.05 влаги при 7.5× demand, uptake больше); evaporation suppression учтена отдельно (точная математика 20000·0.52); знаковый баланс зафиксирован evidence (сообщество исчерпало ~77% базовой влаги dry_sand за прогон). |
| **D** «Ecological memory» | **PROVEN** | FFF5 Experiment D в полном цикле §17-D: legacy 10 циклов (органика 0.0223→0.1610), растения удалены, два ИДЕНТИЧНЫХ fresh seed-пула (предусловие `seed_pools_identical` ассертом) на modified/pristine: популяции различаются (3/3 seed'а), establishment-компонента выше на modified (+0.00219…+0.00246 при пороге 0.001), органика-наследие реальна. Оговорка: nutrient-ветка §10 отсутствует (осознанно отложена), направление средней влаги между пулами — observability, не гейт. |

---

## D. ЯВНО отложенное (§20 + declared limitations checkpoint'ов)

### D.1. Вне первой волны по §20 (не ожидалось в линии, не долги)
Полная биохимия фотосинтеза; explicit carbon atoms/carbon budget; полноценный groundwater simulator; сущности микробов/грибов (`soil_biotic_legacy` — отдельный будущий этап); генетическая рекомбинация/sexual genetics; пожары; herbivores/predators; neural morphology generation; production persistence/network replication.

### D.2. Задекларированные переносы внутри линии (что и куда)
| Что отложено | Источник заявления | Ожидаемый этап |
|---|---|---|
| Bucket-pruning для water-поля (свет уже O(N+C+local)) | FFF3 огр.2, FFF6 «Bucket-pruning upgrade» | **FFF7** |
| Forest-scale N≥1000, «настоящие» лесные масштабы | FFF3 огр.1, FFF6 огр.2 | **FFF7** |
| Profiling, aggregation LOD, persistence boundary, production environment write authority | §19 FFF7 | **FFF7** (только после research acceptance) |
| Полная fitness-декомпозиция §11 (survival/reproduction компоненты; сейчас net_resource_proxy + establishment bonus) | FFF2 огр.1, FFF1 огр.2 | FFF3+ объявление; фактически не закрыто до FFF6 → хвост (см. E-4) |
| Benefit-сторона structural_investment (сейчас cost-only, дрейфует вниз) | FFF1 огр.2, FFF2 огр.2 | та же фитнес-декомпозиция |
| Пластичность новых extension-осей (realized=potential) | FFF1 огр.1 | «вместе с их feedback-каналами FFF3/FFF4» — фактически не добавлено → хвост (E-4) |
| Water-use coupling на `root_shoot_ratio` в формуле доступа | FFF4 огр.4 + «Следующий шаг» FFF4 | заявлен в FFF5 — **не сделан и не переобъявлен** → хвост (E-4) |
| Nutrient availability (§10) | FFF5 design brief «Отвергнуто» | будущий этап (не FFF6/FFF7 по имени) |
| Полная автоматизированная cross-seed батарея FFF5/FFF6 (сейчас 3 seed'а ручной калибровки) | FFF4 огр.7, FFF5 огр.7 | FFF6/FFF7 (для FFF6 — не сделано) |
| Скриншот/визуальный exact-Windows GUI-прогон лабы (G5/C-режим) | FFF6 огр.1 | line-level checkpoint |
| Пространственно-неоднородные карты texture/organic в сценариях (входы поддержаны, не используются) | FFF4 огр.2, FFF5 огр.4 | последующие R-версии |
| Послойное световое насыщение, равные-по-высоте затенение, площадное canopy cover | FFF3 огр.3, FFF4 огр.5 | FFF6+ (частично), дальше |
| Презентационное масштабирование foliage-инстансов от crown_density | FFF6 вопрос 4 | задекларированное ограничение R1 |
| Groundwater authority как canonical-слой (§9.2) | FFF4 огр.1 | отдельное решение (архитектурное) |

---

## E. Незакрытые хвосты

### E.1. Главное: FFF6 не имеет независимого review/verification
Для FFF0–FFF5 существуют пары `docs/evidence/2026-08-23_ECO_EVO7_FFF{n}_FINAL_REVIEW_RU.md` + `_VERIFICATION_RU.md`. Для FFF6 — **нет ни одного**: checkpoint помечен «CANDIDATE (реализаторская роль; самопринятия нет)», evidence-раздел опирается на autocap/acceptance самой реализаторской сессии. По правилам Harness (IMPLEMENTER CANNOT SELF-ACCEPT) линия не может считаться завершённой даже как candidate-набор этапов, пока FFF6 не пройдёт fresh-reviewer + clean-checkout verifier.

### E.2. Отсутствует line-level итоговый checkpoint
«Следующий шаг» FFF6 прямо называет его: сводка G1–G15, скриншот C-режима, решение candidate→accepted. Настоящий аудит закрывает первую треть (сводка гейтов), но формальный line-level checkpoint-документ и переход статуса не оформлены.

### E.3. Скриншот-доказательство G5/C-режима (DoD п.2)
Headless-autocap доказывает работоспособность рендера и числовую различимость, но человеческое «видно геометрически при нейтральном цвете» нигде не зафиксировано картинкой. Для GUI-прогона требуется desktop/runtime-сессия по `docs/GODOT_LOCAL_TESTING_RU.md`/`docs/MCP_GODOT.md`.

### E.4. Молчаливое непоставленное обещание FFF4→FFF5: water-use coupling на `root_shoot_ratio`
Checkpoint FFF4 (ограничение 4 и «Следующий шаг») обещал в FFF5 «water-use coupling на root_shoot_ratio». Spot-check кода: `soil_water_field_v1.root_access()` использует только depth/spread-нормали; rsr лишь «едет в записи» и публикуется как feature. В FFF5 это ни сделано, ни переобъявлено как отложенное — единственное несоответствие вида «обещание исчезло без следа» в документации линии.

### E.5. Узкая seed-база у поздних этапов
Мульти-seed probe (отдельный evidence-док) покрывает только FFF2/FFF3 мосты. FFF4 — 3 seed'а (автоматизировано), FFF5/FFF6 — 3 seed'а ручной калибровки, автоматизации нет. Для FFF3 честно зафиксирована инверсия направления deep-shade-LAI на seed 44 (4/5, маржа 0.004–0.009) — ядро G7 это не ломает, но «understory-стратегия получает преимущество» остаётся самым тонким местом линии.

### E.6. Терминологический дрейф вокруг G11
В шапке acceptance-теста FFF6 stability-блок назван «G11 preview» (комментарий строки 16), в ассертах — полноценный «G11:», в checkpoint'е FFF6 exit требует «anti-runaway gate». По существу доказано (108 циклов, 8 осей, pin-max 0.08), но покрытие — 2 зоны из 6 (MESIC_LOAM, DRY_SAND); остальные зоны anti-runaway на 108 циклах не прогонялись. Стоит либо прогнать все 6, либо зафиксировать 2-зонный scope как достаточный.

### E.7. Устаревшая формулировка в паспорта-доке
`2026-08-23_ECO_PASSPORT_R3_REFRESH_RU.md`: «FFF6 Succession Lab — в реализации по дизайн-доку» — устарело (FFF6 реализован и закоммичен `d129b0ba`). Документ живёт на другой ветке паспорта, но при следующем refresh формулировку надо обновить.

### E.8. Минимальный запас порога G5 в FFF6
Наблюдаемый минимум geometry-distinct пар = 4 при пороге ≥3 (запас ровно одна пара, задекларировано честно). Рост поколений/потомков или перекалибровка могут потребовать пересмотра — зафиксировано в FFF6 огр.6.

### E.9. Прочее (не блокирует research layer)
- Legacy parse-ошибки трёх `eco_evo5_*.tscn` при import-скане — существуют до линии, отмечены верификаторами FFF0/FFF1 как NOTE.
- Множество untracked `.uid`-файлов в worktree (в т.ч. чужих программ) — шум `git status`, housekeeping вне компетенции аудита.
- FFF6 огр.4: effect-записи публикуются один раз (final generation) на mode-прогон, а не каждый цикл — задекларированное отклонение от паттерна мостов, потребителя промежуточных публикаций нет.
- Квартальная метрика «сухая/влажная четверть» (FFF4) — observability, шумит между seed (не гейт).

### E.10. Требующие human gate / будущих стадий (отдельно)
1. **Human gate:** merge `feature/eco-evo7-fff-r1` в main — только после candidate→accepted (AGENTS.md: merge = HUMAN GATE).
2. **Human gate / runtime-сессия:** интерактивный GUI-прогон лабы со скриншотом C-режима (закрывает G5-visual + DoD п.2).
3. **Будущая стадия FFF7** (§19): profiling, aggregation LOD (water-pruning), forest-scale, persistence boundary, production write authority, network/read-only projection.
4. **Архитектурное решение:** canonical groundwater authority (§9.2) — вне компетенции research layer.
5. **Кросс-программное:** сводный PC0 может оставаться RED из-за чужого V0 `DEPENDENCY_DRIFT` (паспорт-refresh док) — на статус EVO7 не влияет, но мешает общему «зелёному» снимку.

---

## F. Итоговый вердикт

**Готовность как RESEARCH LAYER COMPLETE (candidate) по §22: ЧАСТИЧНО — «да по существу, нет по процедуре».**

- Научно/технически линия состоялась: 14 из 15 гейтов PROVEN, 1 PARTIAL (G5 — только визуальный evidence); DoD 8/9 PROVEN (п.2 PARTIAL); контроли B/C/D PROVEN, A PARTIAL (pioneer-механика не гейтится, структура succession-loop доказана); все девять содержательных утверждений §22 имеют машинные доказательства, детерминизм и единственность mutation authority выдержаны сквозь всю линию, EVO6-WATER/PH-регрессии стабильны по зафиксированным хэшам.
- Процедурно линия НЕ завершена: FFF6 — самопринятый CANDIDATE без независимого review/verification; line-level итоговый checkpoint не оформлен; скриншот-доказательство G5 отсутствует; одно обещание FFF4 (rsr-coupling) исчезло без переобъявления.

**Ровно те действия, которые остались (по порядку):**
1. Independent review + clean-checkout verification для FFF6 (два evidence-дока, как для FFF0–FFF5) — включая перепроверку autocap `result_hash 52995cf4…`, 171 assertion и Experiment A.
2. GUI-прогон лабы + скриншот C-режима (G5-visual, DoD п.2) по каноническому Godot/MCP-пути; приложить к line-level checkpoint.
3. Закрыть хвост E-4: либо доставить rsr→water-access coupling, либо явно переобъявить его отложенным (одна строка в limitations следующего документа).
4. Опционально, до merge: расширить 108-цикловый stability на оставшиеся 4 зоны (или задокументировать 2-зонный scope G11 как принятый) и/или автоматизировать cross-seed батарею FFF5/FFF6.
5. Оформить line-level final checkpoint: настоящий аудит + сводка + решение candidate→accepted; затем merge — human gate.

После пунктов 1–3 (и решения по п.4) линия правомерно носит статус **RESEARCH LAYER COMPLETE (candidate)** с чистой совестью; всё остальное — FFF7 и будущие R-версии.

---
*Аудит выполнен чтением кода и документов на HEAD `d129b0ba`; тестовые наборы не перезапускались. Создан единственный файл — настоящий документ.*

---

## Аддендум (в окне аудита, 2026-08-24): параллельные НЕЗАКОММИЧЕННЫЕ артефакты

Во время аудита в том же worktree параллельной ролью появились два untracked-файла, отсутствующих на HEAD `d129b0ba` и потому не входящих в аудированное состояние:

1. `docs/evidence/2026-08-23_ECO_EVO7_FFF6_VERIFICATION_RU.md` (VERIFIED) — clean-checkout верификация FFF6 на том же exact-head `d129b0ba` в отдельном detached worktree: вся цепочка FFF6 (счётчики и result_hash'и бит-в-бит), autocap бит-в-бит, коды возврата 0.
2. `tests/research/ecology/eco_evo7_multiseed_wave2_acceptance.gd` — wave-2 мульти-seed проба (seed'ы 20260824–26) для FFF4/FFF5/FFF6: направления G9, Experiment D дивергенция, ON/OFF ≥5/6 зон, детерминизм двойных прогонов.

Влияние на выводы аудита:
- **E.1 смягчается наполовину**: verification-половина независимой проверки FFF6 существует, но пока только как незакоммиченный файл; **FINAL_REVIEW (reviewer-роль) для FFF6 по-прежнему отсутствует**, и до коммита evidence не входит в durable record линии (GIT IS DURABLE MEMORY).
- **E.5 частично адресуется** wave-2 пробой, но у неё тоже нет evidence-документа и коммита — фиксация результатов обязательна.
- Матрица гейтов/DoD/вердикт остаются в силе для HEAD `d129b0ba`; ни один гейт не меняет статус от появления этих файлов (они закрывают процедурные хвосты, а не технические).
