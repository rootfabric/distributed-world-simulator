# ECO / P3.1 — Deterministic Resource Competition — CANDIDATE

Статус: `CANDIDATE / RESEARCH_ONLY / TARGETED LINUX PASS / EXACT WINDOWS CANONICAL PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Parent control head: `4a1a4788bf3c1d0704cc1f56bd0815eebfcf7302` (`P2.8 ACCEPTED / EVO1 COMPLETE`).
Parent P2.8 aggregate: `ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6`.

## Цель

P3.1 вводит общий ограниченный ресурсный пул поверх уже существующих CAL1 crown/root competition mechanisms. Он **не заменяет** морфологическую конкуренцию CAL1 и не меняет accepted EVO1 semantics.

Новый kernel `plant_resource_competition_v1.gd` распределяет три research resources:

- `light`;
- `water`;
- `nutrients`.

Каждое растение предъявляет demand и bounded `capture_efficiency` `[0,1]`. Ограниченный ресурс распределяется deterministic weighted water-filling с demand caps. Входные plant IDs сортируются до вычисления, поэтому перестановка входного массива не меняет результат.

Growth response использует limiting-resource ratio по принципу Liebig minimum: самый плохо удовлетворённый demanded resource определяет `growth_factor`. Это узкий research response, а не production physiology claim.

## Contract / invariants

P3.1 обязан fail-closed отвергать malformed resource maps, отрицательные/non-finite значения, duplicate plant IDs, неожиданные plant fields и efficiency вне `[0,1]`.

Для каждого resource:

```text
supply = total_uptake + remaining
0 <= total_uptake <= supply
remaining >= 0
conservation_error <= 1e-12
```

Дополнительно:

```text
input permutation -> identical canonical plant order -> identical result_hash
same input / fresh process -> identical result_hash
abundant supply -> all eligible demand fulfilled
limiting supply -> uptake ratio < 1 and deterministic limiting_resource
tampered result -> validation FAIL
```

Kernel pinning:

```text
parent_evo1_p2_8_aggregate=ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
```

## Targeted Linux evidence

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Parser/preload:

```text
PASS
```

Three independent process runs A/B/C were identical:

```text
ECO.P3.1 Resource Competition: PASS (47 assertions)
aggregate_hash=f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
constrained_hash=5d082433bff9cf5b29707da53657bb02e4575ba018544ebbe86cbfde5fd58dec
abundant_hash=bcd82bb49edbf159c31d8fb15c8aef243d63619e12868b3cfd3d0c06003a7c60
water_limited_hash=d22c326115f880562ed1858ebeeee805d54240d663fbee87a8eb8b7ceec95e84
parent_p2_8=ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
```

Это targeted Linux reproduction exact committed P3.1 kernel/test, **не** полный repository canonical runner и не замена Windows parent regression.

## Canonical acceptance gate

Runner: `RUN_ECO_P3_1_TESTS.ps1`.

Он должен:

1. parser/preload P3.1;
2. прогнать accepted `RUN_ECO_EVO1_P2_8_TESTS.ps1` полностью;
3. выполнить P3.1 process A;
4. выполнить P3.1 fresh process B;
5. проверить одинаковый aggregate hash;
6. проверить exact parent P2.8 aggregate.

До этого:

```text
P3.1 = CANDIDATE
P3.1 != ACCEPTED
```

## Next after acceptance

`P3.2 Density & Carrying Capacity`: связать resource pressure с локальной плотностью/biomass и доказать bounded carrying-capacity response без hard-coded winner.

Небольшой `OBS1` low-poly observer допускается после P3.2 как non-gating read-only layer: `Play / Pause / Step`, год/шаг, resource pressure и простые low-poly plant proxies. Observer не имеет права писать simulation state, использовать simulation RNG или менять deterministic hashes.
