# ECO.P1A-S3 — Diagnostic Visual Lab + Controlled Trait Probes — CANDIDATE

## Статус

`HEADLESS_FOCUSED_PASS / GRAPHICAL_REVIEW_PENDING`.

S3 не меняет принятую экологическую математику S1/S2. Он добавляет наблюдаемое представление той же truth-модели и набор контролируемых sensitivity probes.

## Что видно в лаборатории

Клавиши `1..8` переключают:

1. temperature;
2. soil moisture;
3. sunlight;
4. nutrients;
5. flood frequency;
6. final biomass;
7. net resource balance;
8. dominant limiting factor.

`Q/E` переключают диагностические probes:

- BASE;
- SHALLOW_ROOT;
- DEEP_ROOT;
- WATER_LOVING;
- DROUGHT_TOLERANT;
- SHADE_TOLERANT;
- SUN_FAVORED.

Это не новые виды и не evolution. Probes нужны только чтобы руками и численно увидеть чувствительность модели к traits.

Клик по карте показывает точный environment sample и breakdown: gross income, maintenance/root/structural/growth/reproduction costs, water/flood penalties, net balance, biomass, limiting factor и viability class.

## Автоматическое evidence

Godot 4.7.1 double:

- S3 focused dataset/probe acceptance: `114 assertions, 0 failures`;
- dataset hash: `dff41c7b5ae3e2744b957ea0dd81fa3830de6365711b34d66024115509aa3690`;
- scene headless smoke: PASS, `33x33`, BASE, hash `9713cd410b54731fb151893ea78bec056672e6ad344c47a10046ab34d5dd2a7c`;
- parent S2: `235/235` unchanged;
- parent S1: `109/109` unchanged.

## Что проверить глазами

1. Environment heatmaps имеют непрерывную пространственную структуру.
2. Biomass не выглядит простой копией moisture или sunlight.
3. Net balance показывает и положительные, и отрицательные зоны.
4. Limiting-factor map визуально разделяет WATER/LIGHT/NUTRIENT/FLOOD области.
5. DROUGHT_TOLERANT расширяет пригодность сухих мест.
6. SHADE_TOLERANT улучшает тёмный склон.
7. DEEP_ROOT помогает в сухом, но не является бесплатным преимуществом во влажном.
8. Клик по плохой точке позволяет объяснить причину именно через breakdown.

После автоматического Windows PASS и ручного визуального подтверждения S3 можно принять и открыть `P1A-S4 Determinism, Sensitivity and Failure Classification`.
