# ECO ARCH2 A12 — Multi-Generation Population Scale / Work Order R1

Статус: implementation candidate.

База:
bfc335a86153a9f12e03563901d26c3253130d65
(A11 merged main)

## Цель

Следующий canonical gap после A11 — реальный многопоколенный population scale и пересмотр population/corpse limits.

A12 R1 не вводит второй ecology runtime и не добавляет скрытое culling. Он масштабирует тот же A5/A6/shared EcologyRuntime truth.

## R1 scope

- единый versioned ecology_scale_contract_v1.gd;
- canonical ceiling 256 population / 256 corpses;
- A5 и shared EcologyRuntime читают один contract;
- 256 founders admitted без потери записей;
- 257-й founder rejected fail-closed;
- 256 starvation deaths создают 256 canonical corpse records;
- mutation-enabled lineage достигает generation 3;
- checkpoint на generation 2 -> restore -> generation 3 даёт exact canonical state;
- A11 exact regression остаётся green;
- habitat UI показывает текущие contract limits, а не hardcoded 128.

## Инварианты

- no top-k selection;
- no hidden culling;
- no aggregate replacement of canonical population;
- no second field/population state;
- no change to A4 ownership/conservation;
- overflow is an explicit error;
- mutation remains receipt-backed;
- checkpoint/replay uses existing A8/A11 transport.

## Не заявляется

R1 не является production-scale ecology и не обещает тысячи/миллионы организмов.
R1 не повышает 2 MiB transport bound.
Следующее увеличение лимитов требует отдельного contract revision и evidence.
