# ECO.P1A-S2 — Single-Plant Resource Model — CANDIDATE

## Решение

`ECO.P1A-S2` реализован как research-only fixed-genome experiment и прошёл локальный focused acceptance на Godot 4.7.1 double.

Текущий статус:

`LINUX_FOCUSED_PASS_WINDOWS_CONFIRMATION_PENDING`

Окончательный ACCEPTED фиксируется после запуска `RUN_ECO_P1A_S2_TESTS.ps1` на exact Windows checkout и совпадения accepted hashes.

## Что реализовано

### PlantGenomeV1

Один фиксированный genome со следующими traits:

- height;
- growth_rate;
- root_depth;
- water_preference;
- water_tolerance_width;
- shade_tolerance;
- seed_count;
- seed_dispersal_distance;
- lifespan.

В S2 нет mutation, natural selection и нескольких species.

### PlantResourceModelV1

Результат не сводится к одной magic fitness-функции. Для каждого patch явно рассчитываются:

Income/response:

- light/photosynthetic response;
- water response;
- nutrient response;
- temperature response.

Costs/penalties:

- maintenance;
- roots;
- structure/height;
- growth allocation;
- reproduction allocation;
- water stress;
- flooding;
- density/self-competition.

Итог содержит `net_resource_balance`, `dominant_limiting_factor` и диагностическую viability classification.

### SinglePlantPatchSimulatorV1

Patch-level cohort simulation работает 120 seasons и хранит:

- biomass series;
- net resource balance series;
- recruitment;
- mortality;
- productive/stress season counts;
- final/peak biomass;
- deterministic series hash/checksum.

Это aggregate research truth; отдельных растений пока нет.

## Основной результат

Один и тот же genome на восьми контрольных точках даёт разные исходы:

| Point | Class | Net balance | Dominant limit | Final biomass kg/m² |
|---|---|---:|---|---:|
| river bank | UNSUSTAINABLE | -0.599677 | FLOOD | 0.000000 |
| floodplain | FAVOURABLE | 0.387294 | LIGHT | 2.276921 |
| wet lowland | UNSUSTAINABLE | -1.212373 | WATER | 0.000000 |
| lower slope | FAVOURABLE | 0.469920 | NUTRIENT | 2.812276 |
| sunny slope | MARGINAL | 0.162516 | NUTRIENT | 0.534787 |
| shaded slope | UNSUSTAINABLE | -0.464599 | LIGHT | 0.000000 |
| plateau | UNSUSTAINABLE | -0.955845 | WATER | 0.000000 |
| dry ridge | UNSUSTAINABLE | -0.933244 | WATER | 0.000000 |

Особенно важен `wet_lowland`: там очень много воды и nutrients, но растение всё равно проигрывает из-за excess-water + flood stress. Поэтому модель уже не сводится к правилу «больше влаги всегда лучше».

## Root-depth trade-off

Controlled probe пока не является эволюцией и не создаёт новые species. Он меняет только root depth, чтобы проверить математическую чувствительность.

### Dry ridge

- shallow 0.35 m: net `-1.009518`;
- deep 1.60 m: net `-0.831995`.

Глубокие корни действительно помогают получить больше доступной влаги, но недостаточно, чтобы автоматически сделать экстремально сухой участок жизнеспособным.

### Sunny slope

- shallow 0.35 m: `0.096788`;
- deep 1.60 m: `0.205052`;
- extreme 2.20 m: `0.111927`.

Польза сначала растёт, затем super-linear root cost начинает перевешивать. Значит `more root = always better` не выполняется.

### Floodplain

- shallow 0.35 m: `0.528138`;
- deep 1.60 m: `0.133350`;
- extreme 2.20 m: `-0.095264`.

На уже влажном участке дорогостоящие глубокие корни становятся плохой стратегией.

## Determinism

Accepted parent environment hash остаётся неизменным:

`b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7`

S2 simulation hash:

`618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c`

Финальный локальный прогон:

- S2: `235 assertions, 0 failures`;
- parent S1 regression: `109 assertions, 0 failures`.

## Что S2 пока НЕ доказывает

- visual consistency;
- controlled probes для всех traits;
- full sensitivity matrix;
- evolution/mutation;
- multi-species competition;
- production ecology runtime;
- planet-wide populations.

## Следующий gate

На Windows:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology
git pull
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P1A_S2_TESTS.ps1 -GodotPath $Godot
```

Если parent S1 даёт 109/109, S2 — 235/235, а hashes совпадают, S2 можно перевести в ACCEPTED и открыть `P1A-S3 Diagnostic Visual Lab + Controlled Trait Probes`.