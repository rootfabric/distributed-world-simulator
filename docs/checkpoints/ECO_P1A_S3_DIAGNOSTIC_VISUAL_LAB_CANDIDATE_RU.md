# ECO.P1A-S3 — Diagnostic Visual Lab + Controlled Trait Probes — FIX1 CANDIDATE

## Статус

`FIX1_LOCAL_HEADLESS_PASS / WINDOWS + MANUAL_GRAPHICAL_RERUN_PENDING`.

Автоматический baseline S3 ранее прошёл exact Windows: S1 `109/109`, S2 `235/235`, S3 `114/114`. Первый ручной graphical review показал, что **экологический результат выглядит правдоподобно, но presentation недостаточно читаем**: диагностический текст визуально заходил на heatmap и не хватало явного объяснения, что изменил probe и почему конкретный patch успешен или неуспешен.

Это классифицировано как `FIX_REQUIRED_PRESENTATION_ONLY`, а не как failure ecology truth.

## Что было нормальным в первом graphical review

На наблюдаемой точке для `SUN_FAVORED` было видно отрицательный `net` при `limit=WATER` и классе `UNSUSTAINABLE`. Это согласуется с моделью: больше света не устраняет дефицит воды, то есть probe не получает магического глобального преимущества.

Heatmap также имел непрерывную структуру без очевидных seams.

## Что исправлено в Fix1

- Heatmap и diagnostics теперь физически разделены: справа отдельный `PanelContainer`.
- Панель anchored к правому краю и имеет вертикальный scroll, поэтому небольшое окно не должно заставлять текст заходить на карту.
- Для текущего view добавлены краткое объяснение и legend.
- Для текущего probe показываются traits и их delta относительно `BASE`.
- Добавлен глобальный результат: viability counts/percentages, limiting-factor counts, average net и biomass.
- Добавлен `PROBE EFFECT VS BASE`: delta favourable patches, average net и average biomass.
- Для выбранного patch теперь показываются:
  - raw environment;
  - effective soil moisture;
  - light/water/nutrient/temperature responses;
  - LIGHT/WATER/NUTRIENT/TEMPERATURE/FLOOD limitations;
  - gross income;
  - regular costs;
  - stress costs;
  - explicit `gross - total = net`;
  - final/peak biomass;
  - productive/stress seasons;
  - short `WHY` explanation;
  - local delta versus `BASE`.
- Полные hashes сокращены только визуально; canonical hashes в truth/test evidence не изменены.

## Fix1 automated evidence

Godot `4.7.1.stable.double.custom_build.a13da4feb` local focused run:

- S1: `109 assertions, 0 failures`;
- S2: `235 assertions, 0 failures`;
- S3 Fix1: `208 assertions, 0 failures`;
- focused dataset hash remains `dff41c7b5ae3e2744b957ea0dd81fa3830de6365711b34d66024115509aa3690`;
- scene headless smoke remains PASS, `33x33`, BASE hash `9713cd410b54731fb151893ea78bec056672e6ad344c47a10046ab34d5dd2a7c`.

То есть Fix1 добавляет derived diagnostics/presentation и не меняет accepted S1/S2 truth или S3 dataset identity.

## Что проверить повторно на Windows

Сначала automated runner: ожидается S3 `208/208` при прежних hashes.

Затем graphical scene:

1. heatmap не пересекается с правой diagnostic panel;
2. panel читается на текущем размере окна и при необходимости scroll-ится;
3. `PROBE EFFECT VS BASE` действительно помогает понять направление изменения;
4. после клика видно `RESP`, `LIMIT`, `ENERGY`, `BIO`, `RESULT`, `WHY`, `LOCAL VS BASE`;
5. `1..8` и `Q/E` остаются понятными;
6. graphical state не меняет accepted hashes.

Только после этого S3 переводится в `ACCEPTED` и открывается `P1A-S4 Determinism, Sensitivity and Failure Classification`.
