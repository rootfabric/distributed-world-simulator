# ECO.EVO7 FFF3 — Light Feedback R1 — Независимый финальный обзор (REVIEWER)

**Дата обзора:** 2026-08-23
**Роль:** изолированный независимый REVIEWER (свежая роль, без участия в реализации стадии)
**Ветка:** `feature/eco-evo7-fff-r1`, worktree `C:\distributed-world-simulator\worktrees\eco-water-r1`

---

## Вердикт

**PASS** (кандидат соответствует контракту стадии FFF3; все гейты G6/G7/G10/G12 подтверждены собственным прогоном; блокеров нет).

Условие перед выходом из статуса CANDIDATE: исправить формулировки в чекпоинт-документе — одну **MAJOR** (ложное утверждение об отвергнутом O(N²)-скане, см. Находка F-1) и одну **MINOR** (неточная формулировка «пластичность под текущий свет», см. Находка F-2). Обе находки — документационные, на поведение кода, детерминизм и результаты гейтов не влияют.

---

## Проверенный HEAD

- `git rev-parse HEAD` = `07939f8c38706e3ec005712e0037f29f99408b70` — **совпадает с ожидаемым** `07939f8c38706e3ec005712e0037f29f99408b70`.
- Индекс чистый: `git diff --cached --stat` пуст (staged changes отсутствуют). В рабочем дереве только несканированные артефакты Godot/редактора (`*.gd.uid`, `__pycache__/`), не являющиеся содержимым.
- Родитель коммита: `a4a460b9` (FFF2 review evidence). `git diff --name-status a4a460b9..07939f8c` — ровно 6 файлов, все `A` (добавлены), существующие файлы не модифицированы. Примечание: в задании указано «6 files, 5 new», фактически новых 6 из 6; расхождение чисто описательное, цель обзора не меняется.

---

## Фактические числа прогонов (выполнены reviewer'ом самостоятельно на этом HEAD, Windows)

### `.\RUN_ECO_EVO7_FFF3_TESTS.ps1` — exit code 0

Терминальная строка: `ECO.EVO7 FFF3 Light Feedback candidate: PASS` — **совпадает с ожидаемой**.

| Набор | Факт | Ожидание | Совпадение |
|---|---|---|---|
| FFF3 light feedback acceptance | PASS (51 assertions) | PASS (51) | да |
| — bridge runtime | runtime_ms=2944, result_hash=cd30fcbfeb294e19 (префикс) | своя строка runtime | да |
| FFF2 morphology evolution chain | PASS (56) | PASS (56) | да |
| FFF1 functional phenotype chain | PASS (110) | PASS (110) | да |
| FFF0 contract mapping chain | PASS (112) | PASS (112) | да |
| P1B-S1 mutation lineage kernel | PASS (5834) | PASS (5834) | да |
| PH2 environment-coupled development | PASS (107) | PASS (107) | да |
| P1A-S1 parent environment regression | PASS (109), environment_hash=`b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` | PASS (109), hash `b862c4fc…` | да |
| P1A-S2 parent resource regression | PASS (235) | PASS (235) | да |
| P1C-S4 parent aggregate regression | PASS (15) | PASS (15) | да |
| PH0 development trait contract | PASS (63), development_traits_hash=`9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` | PASS (63), hash `9d812950…` | да |

### `.\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline` — exit code 0

- Итог: `ECO.EVO6-WATER strong water rules + evolutionary divergence + visual adapter: PASS`.
- `result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` — **идентичен** в evolution-прогоне и в visual observatory (`ECO.EVO6-WATER-VIS: READY plants=72 result_hash=7010e307…`) и совпадает с ожидаемым. Регрессия G14 в норме.

---

## Чеклист R1–R8 (пункт → результат → файл::строка)

### R1. Контракт эффектов (§7) — ПРОЙДЕН

- Shade-канал активен, остальные зарезервированы: `scripts/research/ecology/plant_environment_effect_v1.gd::15-18`.
- «No creation from nothing»: неактивные каналы жёстко равны нулю, ненулевое значение → `ECO_EFFECT_INACTIVE_CHANNEL_NONZERO`: `plant_environment_effect_v1.gd::75-77`; отрицательные каналы отвергаются: `::72-74`. Подтверждено тестом (тамперинг litter_input_ppm=5 и shade_ppm=-1 отвергаются): `tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd::45-50`.
- `effect_hash` детерминирован (фиксированный порядок полей + sha256): `plant_environment_effect_v1.gd::84-96`; воспроизводимость проверена тестом: `…acceptance.gd::44`.
- `canonical_sort` по plant identity: `plant_environment_effect_v1.gd::100-104`; `combined_hash` порядко-инвариантен: `::106-110`, тест: `…acceptance.gd::54-58`.
- Замечание (NOTE, F-5): `create` молча обрезает отрицательный shade до 0 (`::38`), тогда как `validate` отрицание отвергает; при дубликатах plant_identity порядок внутри `canonical_sort` не определён (нестабильная сортировка) — неактуально, т.к. агрегатор fail-closed по дубликатам identity: `understory_light_field_v1.gd::62-65`.

### R2. Корректность агрегатора (§8+§13) — ПРОЙДЕН

- overlap = Σ по q≠p при height_q > height_p из lai_q·(1−dist/r_q): `scripts/research/ecology/understory_light_field_v1.gd::77-90` (строго более высокие: `::80`; вес в (0,1] через отсечение dist ≥ r: `::88-90`).
- transmittance = exp(−0.9·overlap) (EXTINCTION_K=0.9): `understory_light_field_v1.gd::24, ::92`; understory = base·transmittance: `::93`.
- Вертикальное правило: низкое никогда не затеняет высокое, равные по высоте не затеняют друг друга (строгое `>`): `understory_light_field_v1.gd::80`; тесты: `…acceptance.gd::82-86`.
- Cell-бакеты детерминированы (floori деление на CELL_SIZE_M): `understory_light_field_v1.gd::52-53`; используются только для observability (canopy_load/plant_count: `::101-105`) и membership (cell_identity в plant_light: `::94-96`); per-plant свет от бакетов не зависит.
- Все float-суммы в canonical (identity-sorted) порядке: сортировка `understory_light_field_v1.gd::69-70`, внутренний цикл по отсортированному массиву `::77`, хэши сортируют ключи `::143-144, ::155-156`; средний свет в бридже суммируется по keys() в порядке вставки = canonical: `evo7_light_feedback_bridge_v1.gd::152-158`. G12 подтверждён тестом: `…acceptance.gd::94-120` (3 перестановки, побайтно идентичные хэши и точное равенство per-plant света).
- Fail-closed: пустой вход `understory_light_field_v1.gd::67-68`; дубликат identity `::62-65`; out-of-range (density/sunlight/отрицательные/не-finite) `::32-50`; всё возвращает пустой результат; тесты: `…acceptance.gd::88-92`.
- Нет RNG, нет SceneTree/Node: скрипты `extends RefCounted`, grep по randf/randi/randomize/RandomNumberGenerator/Time — 0 совпадений в трёх новых скриптах; source-границы дополнительно проверены тестом: `…acceptance.gd::145-155`.

### R3. Дисциплина причинности в бридже — ПРОЙДЕН

- Формула mutation stream `EVO7-LIGHT|seed|gen|parent|off` едина для обоих режимов (общий код `_run_mode`, параметр только `use_feedback`): `evo7_light_feedback_bridge_v1.gd::208`; различается только назначение среды: `::164-166` (ON — свой understory, OFF — base).
- Порядок поколения: реализация → публикация геометрии+эффектов (`::141-146`, effect-записи через `LightField.effect_records` в canonical порядке: `understory_light_field_v1.gd::121-139`) → агрегация поля (`::143`) → переоценка под свет (`::160-193`).
- Репродукция через единственную lineage-authority: `LineageExtension.reproduce_bundle` `evo7_light_feedback_bridge_v1.gd::209`; делегирование генома 1:1 в v1-ядро без его модификации: `scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd::7-8, ::119`.
- Дедупликация «одно растение на позицию»: сортировка по parent_fitness (убыв.), затем bundle_checksum (возр.) `evo7_light_feedback_bridge_v1.gd::221-224`; остаётся первый = лучший кандидат `::227-236`; identity и мировая позиция наследуются от родителя `::213-219` — позиционная привязка сохранена.

### R4. Детерминизм — ПРОЙДЕН

- Нет платформенного RNG в трёх новых скриптах (см. R2); мутирующий seed — детерминированный `String.hash()`: `evo7_light_feedback_bridge_v1.gd::208`.
- result_hash покрывает initial field/plant-light хэши + для обоих режимов population/field/effects-combined хэши и mean understory: `evo7_light_feedback_bridge_v1.gd::354-372`.
- Эмпирически: повторный прогон даёт идентичный result_hash, смена seed меняет хэш: `…acceptance.gd::140-143`. Подтверждено прогоном.

### R5. Качество тестов — ПРОЙДЕН (с двумя NOTE)

- G6: добавление кроны затемняет (`…acceptance.gd::64-67`); удаление восстанавливает base с допуском `<1e-9` (`::69-71`; фактически значение ровно 0.8 благодаря snappedf-квантованию); монотонность «две кроны темнее» `::74-77`; точная сверка Бугера—Ламберта с независимым `exp()` в тесте `::79-80`; вертикальные правила `::82-86`; fail-closed `::88-92`.
- G12: три перестановки, побайтно идентичные `field_hash`/`plant_light_hash` и точный per-plant свет `::94-120`; порядко-инвариантный `combined_hash` `::54-56`.
- G7: ON≠OFF по финальной популяции `::134`; quartile-разрез deep-shade LAI < open-light LAI − 0.03 `::137`.
- G10: initial field ≠ final field `::135`; mean understory < base − 0.05 `::136`.
- Тавтологий не найдено. NOTE (F-3): cross-check Бугера—Ламберта переиспользует `overlap_lai` из поля (независима только экспонента); NOTE (F-4): «bit-exact» в чекпоинте vs допуск 1e-9 в ассерте.

### R6. Полнота цепочки раннера — ПРОЙДЕН

- Порядок и состав: FFF3 → FFF2 → FFF1 → FFF0 → P1B-S1 (kernel regression) → PH2 → P1A-S1 → P1A-S2 → P1C-S4 → PH0 — в точности как требуется: `RUN_ECO_EVO7_FFF3_TESTS.ps1::14-25`.
- Проброс кодов выхода: `$ErrorActionPreference="Stop"` + throw при ненулевом `$LASTEXITCODE`: `RUN_ECO_EVO7_FFF3_TESTS.ps1::2, ::26-30`; терминальная строка печатается только после всех наборов `::36`.
- UID-cache preflight с фолбэком `--import`: `RUN_ECO_EVO7_FFF3_TESTS.ps1::4, ::10-13`.

### R7. Честность документации — ПРОЙДЕНА С ЗАМЕЧАНИЯМИ

- Статус CANDIDATE: `docs/checkpoints/2026-08-23_ECO_EVO7_FFF3_R1_RU.md::1`.
- Раздел ограничений присутствует, все 5 требуемых пунктов: микрокосм в масштабе кроны `::66`, равновысотное упрощение `::67`, семантика ON/OFF потока мутаций `::68`, shade_tolerance вне light-компоненты `::69`, зарезервированные каналы `::70`.
- Таблица наблюдаемой динамики согласована с ассертами теста: base 0.6749, ON mean 0.5523 (< 0.6749−0.05 ✓), quartiles 0.205 < 0.271−0.03 ✓ (`…_RU.md::31-38` против `…acceptance.gd::136-137`); «bridge ~3 s» согласуется с фактом 2944 ms.
- Без overclaiming: полный succession-цикл отложен до FFF6: `…_RU.md::40`.
- Замечания: MAJOR F-1 (утверждение «Отвергнуто: all-pairs O(N²) скан» `::12` противоречит фактической реализации) и MINOR F-2 («реализация фенотипов под текущий свет (пластичность)» `::25` vs реализация геометрии под base-средой).

### R8. Соответствие спецификации (выборочно) — ПРОЙДЕНО С ЗАМЕЧАНИЕМ

- §8.2 (вертикальная структура обязательна): выполнено — `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md::417-422` против `understory_light_field_v1.gd::80` и теста `…acceptance.gd::82-86`.
- §8.4 (контрфактический эксперимент ON/OFF + восстановление после удаления верхнего яруса): присутствует — spec `::434-445`; ON/OFF в бридже, removal-тест на уровне агрегатора (направление отбора меняется — через ON≠OFF; NOTE: removal-тест не community-level).
- §13 (запрет полного all-pairs O(N²), бакеты + neighbor sampling): **частичное отклонение** — фактический per-plant цикл полносвязный O(N²) при N=25 (`understory_light_field_v1.gd::74-90`); бакеты не используются для отсечения соседей. Для ограниченного микрокосма R1 это допустимо, НО чекпоинт утверждает обратное (F-1, MAJOR). Спецификация не содержит явного исключения для микрокосма — требуется честная фиксация в ограничениях.
- §19 FFF3 scope (canopy projection, shade aggregation, understory field, light в fitness, canopy-removal counterfactual; exit G6–G7, G10, G12): закрыто полностью — spec `::934-944`.

---

## Находки

### F-1. MAJOR — Чекпоинт утверждает, что all-pairs O(N²)-скан «отвергнут», хотя именно он и реализован

- **Где:** `docs/checkpoints/2026-08-23_ECO_EVO7_FFF3_R1_RU.md::12` («Отвергнуто: all-pairs O(N²) скан (§13 запрещает)») против `scripts/research/ecology/understory_light_field_v1.gd::74-90` (полный вложенный цикл по всем растениям) и `::52-53, ::101-105` (бакеты — только observability/membership, neighbor sampling по пересекающимся бакетам отсутствует).
- **Суть:** §13 спецификации (`ECO_EVO7_…_SPEC_RU.md::611-625`) запрещает полный all-pairs O(N²) и предписывает архитектуру «buckets → local contributions → neighbor sampling only from intersecting buckets». Реализация R1 — честный O(N²) на ограниченном микрокосме N=25; это приемлемо для скелетной стадии, но документ не должен утверждать, что запрещённый подход «отвергнут». В разделе ограничений (`::66`) масштаб отложен до FFF6/FFF7, однако путь масштабирования (bucket-pruned neighbor sampling) и факт O(N²)-цикла с ограниченным N явно не названы.
- **Требуемое действие (документарное, до выхода из CANDIDATE):** переформулировать `::12` и дополнить ограничения: «текущий агрегатор — ограниченный all-pairs O(N²) при N=25 (микрокосм); масштабирование через отсечение соседей по cell-бакетам — маршрут FFF6/FFF7». Код менять не требуется.

### F-2. MINOR — Формулировка «реализация под текущий свет (пластичность)» не соответствует механизму

- **Где:** `scripts/research/ecology/evo7_light_feedback_bridge_v1.gd::8` (заголовок «realize every plant under its CURRENT light (plasticity), publish geometry») и `docs/checkpoints/2026-08-23_ECO_EVO7_FFF3_R1_RU.md::25`; код: `evo7_light_feedback_bridge_v1.gd::141` и `::280-288` — геометрия для светового поля реализуется под **base**-средой; свет входит через оценочный проход `::162-193` и отбор.
- **Суть:** замкнутый контур G10 подлинный (состав популяции → геометрия → поле → отбор), но опубликованная (затеняющая) геометрия не светопластична внутри поколения — «пластичность под текущим светом» относится к оценке/отбору, а не к публикации геометрии. Поправить комментарий и формулировку чекпоинта.

### F-3. NOTE — Cross-check Бугера—Ламберта полу-независим

- **Где:** `tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd::79-80` — ожидаемое значение пересчитывается независимым `exp()`, но от `overlap_lai`, взятого из самого поля. Корректность весов перекрытия подтверждается косвенно (add/remove/monotonic/vertical). Тавтологией не является; для R1 достаточно.

### F-4. NOTE — «Bit-exact» в чекпоинте против допуска 1e-9 в ассерте

- **Где:** `docs/checkpoints/2026-08-23_ECO_EVO7_FFF3_R1_RU.md::44` против `tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd::71`. Для протестированной конфигурации восстановление действительно точное (нулевое перекрытие → snappedf-квантование даёт ровно 0.8), но сам ассерт допускает дрейф < 1e-9. Рекомендуется либо ужесточить ассерт до точного равенства, либо смягчить формулировку.

### F-5. NOTE — Мелкие асимметрии контракта эффектов

- **Где:** `scripts/research/ecology/plant_environment_effect_v1.gd::38` (молчаливое обрезание отрицательного shade в `create` при том, что `validate` его отвергает) и `::100-104` (нестабильный порядок равных identity в `canonical_sort`/`combined_hash`). Неактуально в текущем конвейере (агрегатор fail-closed по дубликатам: `understory_light_field_v1.gd::62-65`); зафиксировать на будущее (FFF4/FFF5).

### F-6. NOTE — Расхождение в описании цели обзора

- В задании: «6 files, 5 new»; `git diff --name-status a4a460b9..07939f8c` показывает 6 файлов, все `A` (новые). Ни один существующий файл не изменён. На вердикт не влияет.

---

## Заявление о независимости

Обзор выполнен изолированной свежей ролью REVIEWER, не участвовавшей в реализации стадии FFF3 и не связанной с ролью Implementer/Verifier данного коммита. Точка HEAD проверена мной самостоятельно (`07939f8c38706e3ec005712e0037f29f99408b70`, индекс чист); оба тестовых прогона (`RUN_ECO_EVO7_FFF3_TESTS.ps1`, `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline`) выполнены мной лично на этом HEAD — их результаты приведены выше в разделе «Фактические числа прогонов» и не взяты из документации. Все выводы чеклиста R1–R8 получены из чтения исходников и спецификации, а не из чекпоинт-документа. Изменений существующих файлов нет, коммит/push не выполнялись; создан единственный новый файл — настоящий отчёт.
