# ECO VIS1.8A-R1 — Windows validation и переход к VIS1.8B

Дата: 2026-08-16

Ветка: `feature/eco-vis1-visual-proving-ground`

Подтверждённый realtime base: `e62bdc057ffc62a1a5e18772921e51b946e514b0`

## Подтверждение VIS1.8A-R1

VIS1.8A-R1 проверен пользователем на Windows exact double build Godot `4.7.1.stable.double.custom_build.a13da4feb`.

Графический runtime теперь остаётся отзывчивым, камера летает, turnover визуально наблюдаем: появляются новые representatives, исчезают старые, count и placement меняются между поколениями.

На наблюдаемом generation 12 HUD показывал:

- `reps=51`;
- текущий transition `+9/-11`;
- `survivors=42`;
- cumulative events `+144/-146`;
- `represented=11.000kg`;
- `sim≈30.80ms`;
- `apply≈37.23ms`;
- `PH5_turnover_rebuilds=0`.

Следовательно, R1 устранил главный interactive blocker: whole-field PH5 materialization больше не выполняется при turnover playback. Realtime proxy tier является рабочей границей для динамической population presentation.

Остановка autoplay на generation 12 не является runtime hang. Это оставшийся искусственный предел, унаследованный от VIS1.7 `MAX_GENERATION=12`.

## Решение VIS1.8B

Следующий этап фиксируется как **VIS1.8B — Continuous Population Evolution**.

Цели:

1. снять прежний предел G12 для realtime turnover playback;
2. оставить generation 0 detailed PH5 baseline и realtime proxies для turnover generations;
3. продолжать deterministic survival / mortality / recruitment / lineage inheritance / dispersal на G13+;
4. не допустить неограниченного роста RAM при длительном playback;
5. хранить rolling rewind window последних 32 turnover generations плюс generation 0 restart baseline;
6. хранить компактную историю последних 64 generation summaries для наблюдения динамики;
7. показывать `mean_fitness`, `unique_genomes`, alpha/beta composition и краткий history tail в HUD;
8. сохранять `represented_biomass_kg == 11.000kg` для текущего read-only VIS1.2 fixture;
9. сохранять `PH5_turnover_rebuilds=0`;
10. `R` должен детерминированно сбрасывать rolling history к founder generation 0.

## Rolling-cache policy

VIS1.8B не хранит полную тяжёлую историю всех поколений.

- generation 0 хранится как restart baseline;
- в памяти остаются последние 32 turnover generations;
- Left может перемещаться в пределах текущего rolling window;
- запрос поколения, уже вытесненного из window, clamp-ится к самому старому доступному;
- `R` сбрасывает timeline к G0, после чего детерминированный playback может быть повторён;
- компактные history points ограничены 64 записями.

Это сознательная realtime-policy, а не canonical persistence contract.

## Архитектурная граница

VIS1.8B остаётся laboratory derived projection:

- `canonical_population_truth=OFF`;
- `canonical_timeline_truth=OFF`;
- VIS1.2 spatial snapshot read-only;
- 11 kg source biomass не мутирует;
- число representatives является presentation sampling policy;
- continuous max установлен очень высоким safety ceiling (`1_000_000` generations), а не биологическим пределом;
- полноценная долгосрочная persistence/replay ecology timeline остаётся отдельной будущей задачей.

## Проверяемые инварианты VIS1.8B

- G13 достижим вручную и через autoplay;
- autoplay не останавливается на G12;
- G45 и последующие поколения строятся через realtime proxy path;
- rolling cache не превышает generation 0 + 32 turnover generations;
- history window не превышает 64 summaries;
- births/deaths продолжаются после G12;
- represented biomass остаётся равна source biomass;
- whole-field PH5 rebuild count остаётся 0;
- reset G0 очищает rolling timeline;
- replay G1 после reset даёт тот же deterministic field hash;
- R1 smoke остаётся зелёным после небольшого backward-compatible virtual-limit refactor.

Статус после реализации: `IMPLEMENTED_CANDIDATE` до Windows exact-build gate и длительной визуальной проверки G13+.
