# ECO / P3.4 — Environmental Gradient — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / TARGETED LINUX PASS / P3.3 ACCEPTANCE + EXACT WINDOWS CANONICAL PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

## Lifecycle boundary

P3.3 ещё не принят exact Windows canonical, поэтому P3.4 реализован как pre-acceptance candidate, аналогично тому, как P3.2 ранее был реализован до принятия P3.1.

Это **не** означает:

```text
P3.3 = ACCEPTED
P3.4 = ACCEPTED
P3.5 = OPEN
```

Canonical `RUN_ECO_P3_4_TESTS.ps1` fail-closed откажется запускаться, пока factual P3.3 validation status не начинается с `ACCEPTED`.

P3.3 candidate aggregate pin:

```text
37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
```

## Цель

Убрать необходимость фиксированных biome tables и дать каждому patch/cell непрерывное детерминированное окружение.

P3.4 вводит четыре environmental channels:

```text
temperature_c
moisture
light
nutrients
```

Каждый P3.3 patch получает единственную координату:

```text
id
x
y
altitude
```

Для каждого environmental channel задаётся affine field относительно configurable origin:

```text
value = base
      + x_slope * (x - origin.x)
      + y_slope * (y - origin.y)
      + altitude_slope * (altitude - origin.altitude)
```

После этого значение детерминированно ограничивается channel `min/max`.

Для `moisture`, `light`, `nutrients` границы обязаны находиться внутри `[0,1]`.

Temperature остаётся отдельным непрерывным числовым каналом и не превращается в категорию `cold/temperate/hot`.

## No-biome invariant

P3.4 **не** выдаёт:

```text
biome
biome_id
forest/desert/tundra enum
winner lookup by environment class
```

Например три patch в acceptance fixture имеют:

```text
A: x=0 y=0 altitude=0
   temperature=20.00 moisture=0.80 light=0.40 nutrients=0.90

B: x=2 y=0 altitude=100
   temperature=17.00 moisture=0.60 light=0.60 nutrients=0.75

C: x=4 y=2 altitude=200
   temperature=15.00 moisture=0.45 light=0.85 nutrients=0.55
```

Промежуточная координата между A и B внутри unclamped области даёт ровно affine midpoint по всем четырём каналам.

## Resource bridge

P3.4 пока не пересчитывает принятые P3.1/P3.2 результаты задним числом.

Он формирует dimensionless next-cycle availability ratios:

```text
resource.light     = environmental light
resource.water     = environmental moisture
resource.nutrients = environmental nutrients
```

Это явная граница для последующего ecology-cycle coupling, а не новая скрытая единица ресурса.

Temperature пока не имеет species-specific response: такая niche differentiation остаётся за последующими P3 checkpoint'ами.

## Spatial edge diagnostics

P3.4 не меняет P3.3 topology. Для каждого уже существующего directed edge он только вычисляет:

```text
XY distance
altitude delta
temperature delta
moisture delta
light delta
nutrients delta
```

и пинит exact P3.3 edge `record_hash`.

Это позволит позднее различать, например, миграцию вверх/вниз по высоте или вдоль moisture gradient без изменения P3.3 transfer ownership.

## Determinism and validation

Результат содержит полный validated P3.3 source result, exact source `result_hash`, canonical coordinates, environmental patch records, edge gradients и min/max summary.

Validator reconstructs результат из source P3.3 + coordinates + field config и требует exact deterministic hash equality.

Fail-closed проверяются:

- missing/duplicate/unknown patch coordinate;
- unexpected coordinate/config fields;
- non-finite coordinate;
- non-finite field coefficients;
- inverted min/max;
- normalized channel bounds вне `[0,1]`;
- tampered P3.3 source;
- tampered patch environment;
- tampered edge delta;
- tampered summary;
- tampered parent/source hashes.

Global RNG не используется.

## Targeted exact-Godot evidence

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Parser/preload:

```text
PASS
```

P3.3 parent targeted regression after adding P3.4:

```text
ECO.P3.3 Spatial Dispersal: PASS (66 assertions)
aggregate_hash=37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
```

P3.4 fresh process A/B/C logs are byte-identical:

```text
ECO.P3.4 Environmental Gradient: PASS (56 assertions)
aggregate_hash=a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
gradient_hash=2651bb4da195af4c1d2ba7f6b09ef9bdc9e459f9206c32ef1e9eb0dbddd6b293
empty_hash=13ec0762efeec0e0130f7b587b17bc7bd5b133fafa4f8eaf2975c5c5ff5c91a1
parent_p3_3=37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
source_p3_3=21a8de4b12cd541d40c8fd34b725e59e493a775e3465b853945f46f85445a8a2
```

## Canonical gate

```text
P3.3 exact Windows canonical
-> separate P3.3 ACCEPTED lifecycle commit
-> RUN_ECO_P3_4_TESTS.ps1
-> exact Windows P3.4 fresh-process equality
-> separate P3.4 ACCEPTED lifecycle commit
-> P3.5 Seasonal World
```

До этого P3.4 остаётся candidate.
