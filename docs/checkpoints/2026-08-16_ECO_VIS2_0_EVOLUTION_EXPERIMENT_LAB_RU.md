# ECO VIS2.0 — Evolution Experiment Lab

Дата: 2026-08-16

Ветка: `feature/eco-vis1-visual-proving-ground`

Проверенная база: VIS1.9 `80c64496de7bdff08084219e5ff284c3872e4343`.

## Подтвержденная база

VIS1.9 на Windows exact Godot `4.7.1.stable.double.custom_build.a13da4feb` прошел integrated gate и graphical runtime. Continuous turnover работал по крайней мере до G123, observatory показывал population / births-deaths / fitness / genetic diversity / alpha-beta, spectator mouse-look оставался рабочим, whole-field PH5 rebuild во время playback оставался выключен.

## Цель VIS2.0

Перейти от пассивного наблюдения одной фиксированной среды к воспроизводимым управляемым эволюционным экспериментам.

VIS2.0 добавляет lab-derived environmental interventions:

- BASELINE;
- DROUGHT;
- FLOOD;
- NUTRIENT_PULSE;
- SHADE.

Интенсивность регулируется от 10% до 100%.

## Семантика

Canonical VIS1.2 EnvironmentSample не мутируется. VIS2.0 переопределяет только lab sampling boundary и создает новый валидный `EnvironmentSample` с отдельным checksum/revision для experiment context.

Это означает, что существующие механизмы автоматически получают experiment environment через уже существующие вызовы `sample_environment_at()`:

- fitness evaluation;
- survival/mortality;
- recruitment;
- lineage/genome selection;
- environment-coupled phenotype;
- realtime proxy morphology;
- progressive PH5 detail.

## История и branching

Intervention не переписывает уже вычисленную историю. Она действует на будущие turnover transitions.

Если пользователь отмотался в rolling cache и меняет эксперимент, VIS2.0 удаляет только cached future после текущего generation и продолжает новую deterministic laboratory branch с точки вмешательства. История до intervention остается неизменной.

`R` возвращает founders G0. Текущий experiment profile сохраняется и снова действует на будущие поколения, что позволяет повторять один и тот же эксперимент от одинаковых founders.

## Управление

- `1` — BASELINE;
- `2` — DROUGHT;
- `3` — FLOOD;
- `4` — NUTRIENT_PULSE;
- `5` — SHADE;
- `- / +` — изменить intensity;
- `I` — показать/скрыть experiment panel;
- остальные spectator / playback / observatory controls сохраняются.

## Presentation

Experiment panel показывает baseline→experimental probe для moisture/light/nutrients/flood/temperature и последние intervention events.

Directional light получает слабый presentation cue для активного сценария. Это только визуальная подсказка и не является источником ecology truth.

VIS1.9 observatory продолжает показывать динамику популяции, поэтому эффект вмешательства можно наблюдать по population size, births/deaths, mean fitness, diversity и alpha/beta composition.

## Инварианты

- canonical_environment_truth=OFF;
- canonical_population_truth=OFF;
- canonical_timeline_truth=OFF;
- whole-field PH5 rebuild during turnover=0;
- VIS1.9 regression должен оставаться зеленым;
- одинаковый сценарий/intensity от G0 должен давать deterministic trajectory;
- experiment panel не перехватывает spectator mouse.

Статус: IMPLEMENTED_CANDIDATE до Windows exact gate и graphical experiment confirmation.
