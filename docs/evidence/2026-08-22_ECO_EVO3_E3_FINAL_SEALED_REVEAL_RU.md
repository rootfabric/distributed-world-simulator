# ECO EVO3 E3.FINAL — Sealed Prediction Reveal и Falsification Evidence

Статус: `RESEARCH_ONLY / POST_FREEZE_REVEAL_RECORDED`.
Программа: `planetary_ecology_program_hash 6d28b032c193cb046d48a07a21fd31996331ef4cbb19add25e5eb1fd2b228767` (артефакт sha256 `8235b4a6cf322101c5c9c578b7a94d182667c57b27d7c78c65686474c5cc2c1f`, git blob `24c677884c47b6662917372731d8b25b374da0f9`).

## Дисциплина

Предсказания запечатаны ДО первой компиляции: 12 sha256-коммитментов в репо (`e3_final_sealed_prediction_commitments.v1.json`), plaintext вне репозитория. Вскрытие выполнено только после заморозки байт программы. Все 12 печатей верифицированы (`12/12 PASS`). Расхождение предсказания с наблюдением фиксируется как falsification evidence и не проваливает компиляцию (политика контракта).

## Итог: 6 CONFIRMED / 6 FALSIFIED

Единицы: в столбце «Наблюдение» в скобках — число колонизованных ВИДОВ (species-level, диапазоны предсказаний тоже в видах); patch-уровневые счётчики установлений приведены в самой программе (например, 88 и 99 установлений на 11 патчах для extended-комбинаций oceanic/polar).

| Комбинация | Предсказание | Наблюдение | Вердикт |
|---|---|---|---|
| arid-basin-02__baseline | NO_COLONIZATION_ALL [0,0] | NO_COLONIZATION_ALL_SPECIES (0) | CONFIRMED |
| arid-basin-02__extended_r1 | MIXED_DROUGHT_GAIN [1,4] | NO_COLONIZATION_ALL_SPECIES (0) | FALSIFIED |
| arid-basin-02__mono_r1 | NO_COLONIZATION_ALL [0,0] | NO_COLONIZATION_ALL_SPECIES (0) | CONFIRMED |
| oceanic-ridge-03__baseline | PRESERVED_COLONIZED [2,2] | COLONIZED_ALL_SPECIES (2) | CONFIRMED |
| oceanic-ridge-03__extended_r1 | PRESERVED_COLONIZED [1,12] | MIXED_PARTIAL_COLONIZATION (8) | FALSIFIED |
| oceanic-ridge-03__mono_r1 | COLONIZED [1,1] | COLONIZED_ALL_SPECIES (1) | CONFIRMED |
| polar-plateau-04__baseline | PRESERVED_COLONIZED [2,2] | COLONIZED_ALL_SPECIES (2) | CONFIRMED |
| polar-plateau-04__extended_r1 | PRESERVED_COLONIZED [1,12] | MIXED_PARTIAL_COLONIZATION (9) | FALSIFIED |
| polar-plateau-04__mono_r1 | COLONIZED [1,1] | COLONIZED_ALL_SPECIES (1) | CONFIRMED |
| volcanic-isles-05__baseline | PARTIAL_REVERSAL [0,1] | NO_COLONIZATION_ALL_SPECIES (0) | FALSIFIED |
| volcanic-isles-05__extended_r1 | MIXED [1,6] | NO_COLONIZATION_ALL_SPECIES (0) | FALSIFIED |
| volcanic-isles-05__mono_r1 | PARTIAL_REVERSAL [0,1] | NO_COLONIZATION_ALL_SPECIES (0) | FALSIFIED |

## Научное содержание расхождений (falsification evidence)

1. **Пороговая чувствительность establishment (60000 ppm).** На arid-basin-02 засухоустойчивые grid-виды из extended-каталога не дотянули до порога установления на source-порту единицами ppm (наблюдаемые scores 59943, 59593, 51811 при пороге 60000). Гипотеза «drought-adapted gain» опровергнута: экстремальная сушка (moisture/4) обваливает limiting-ресурс ниже порога для ВСЕХ каталоговых фенотипов, а не только для baseline-видов.
2. **Volcanic-isles-05 полностью стерилен.** Предсказанный PARTIAL_REVERSAL [0,1] не состоялся: disturbance x3 при неизменном питании даёт persistence 400000 и limiting-ресурс, обваливающий establishment ниже порога на всех 12 патчах для всех трёх каталогов. Нулевой исход валиден по контракту (`no_colonization_is_valid: true`).
3. **Extended-каталоги на океаническом/полярном мирах дают частичную колонизацию, а не полную.** Из 12 grid-видов устанавливаются 8 (oceanic) и 9 (polar): виды с низкой dispersal capacity (короткие дистанции переноса, малые seed_count) отбрасываются фильтром arrival >= 150000 ppm на edge-continuity. Предсказание PRESERVED_COLONIZED [1,12] было слишком щедрым.
4. **Baseline и mono-каталоги предсказаны точно (6/6).** Механика переноса принятой пары видов на новые миры качественно предсказуема из E3.8-family данных; ошибка сосредоточена в экстраполяции на новые фенотипы — ровно там, где у цепи нет эмпирического якоря.

Методологический вывод для E3.FINAL-заключения: компилятор корректен (детерминизм, пороги нетронуты, цепь не модифицирована), но предсказательная сила исследователя за пределами принятого каталога ограничена; sealed-prediction дисциплина отработала как задумано — расхождение зафиксировано до всякой интерпретации.

## Машинное evidence

`validation/ecology/eco-evo3-e3-final-sealed-reveal-evidence.json` (schema `…evo3_e3_final_sealed_reveal_evidence.v1`): 12 records, digest_verification `12/12 PASS`, divergences[6].
