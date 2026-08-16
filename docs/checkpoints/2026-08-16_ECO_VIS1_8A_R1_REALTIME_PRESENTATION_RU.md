# ECO VIS1.8A-R1 — realtime turnover presentation repair

Дата: 2026-08-16

Ветка: `feature/eco-vis1-visual-proving-ground`

База finding: `1ef5552c3c841ebbbf66f45f4c7d553c19bcf98a`

## Подтверждение VIS1.8A correctness

VIS1.8A на Windows exact Godot `4.7.1.stable.double.custom_build.a13da4feb` прошёл полный gate:

- VIS1.2 PASS (30 assertions);
- VIS1.3 PASS (38 assertions);
- VIS1.4 PASS (57 assertions);
- VIS1.5 PASS (411 assertions);
- VIS1.6 PASS (412 assertions);
- VIS1.7 temporal bridge PASS (21 assertions);
- VIS1.7 field PASS (289 assertions);
- VIS1.8A turnover bridge PASS (59 assertions);
- VIS1.8A field PASS (40 assertions).

Следовательно, turnover/recruitment correctness подтверждён. Найденный далее дефект относится к interactive presentation/performance.

## Наблюдаемый blocker

При графическом запуске VIS1.8A интерфейс практически перестаёт отвечать: камера не летает, generation visually не меняется, CPU загружен.

Причина найдена в старом interactive path: при каждом generation `_apply_vis1_8a_generation()` освобождает весь `PH5PlantGeometry`, затем для каждого representative синхронно выполняет environment -> phenotype -> GrowthGraph -> RenderDescription -> `Plant3DMaterializer` и создаёт все PH5/MultiMesh nodes заново на main thread.

Correctness-gate такой путь выдерживает, но для live visualization это неправильная граница работы: тяжёлая whole-field materialization блокирует input/render loop.

## Решение R1

VIS1.8A-R1 разделяет correctness и realtime presentation:

- generation 0 остаётся подробным PH5 baseline;
- turnover simulation, fitness, survival, mortality, parent-linked recruitment, genome/lineage inheritance и dispersal остаются теми же;
- generation > 0 НЕ перестраивает whole-field PH5;
- turnover generations отображаются лёгкими tree proxies, derived из тех же genome + local environment records;
- survivors переиспользуют существующие proxy nodes;
- newborn nodes появляются scale-in анимацией;
- dying nodes уходят scale-out анимацией;
- red death markers остаются видимыми для текущего transition;
- autoplay interval уменьшен до 1.15 s, чтобы динамика была наблюдаемой;
- camera/input продолжают обновляться каждый frame;
- HUD публикует `sim ms`, `apply ms`, `animations`, `preview_builds`, `PH5_turnover_rebuilds=0`;
- `represented_biomass_kg` по-прежнему восстанавливает read-only VIS1.2 source biomass;
- `canonical_population_truth=OFF`, `canonical_timeline_truth=OFF` сохраняются.

## Архитектурное решение

Полная PH5 materialization не должна быть обязательной частью realtime ecological playback. PH5 остаётся подробным inspection/render tier, а dynamic population simulation должна иметь дешёвый presentation tier.

Дальнейшее усиление может добавить progressive PH5 refinement только для paused/near-camera subset, но не возвращать whole-field synchronous rebuild в autoplay.

## Проверяемые R1-инварианты

- generation 0: 53 founders и detailed PH5 visible;
- generation > 0: `presentation_mode=REALTIME_PROXY`;
- births/deaths/survivors > 0;
- `visual_count = survivors + births`;
- `ph5_rebuilds_during_turnover = 0`;
- represented biomass остаётся 11.000 kg для текущего fixture;
- rewind generation hashes детерминирован;
- VIS1.2 spatial snapshot не мутируется;
- Space включает autoplay и generation продвигается через cheap path;
- birth/death animations существуют, не блокируя frame loop.
