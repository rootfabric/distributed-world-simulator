# ECO VIS2.2-D — Ubuntu graphical validation checkpoint

Дата: 2026-08-17

Ветка:

`feature/eco-vis2-2-replicated-causal-observatory`

Graphically validated code-under-test:

`7bf0e83ed6c6907731022ff4d372980e596b2135`

Evidence checkpoint before this graphical validation:

`5abcbfc79cd5ecf7aa770cf1200fa17d7564a3c4`

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Платформа:

Ubuntu/Linux native double-precision Godot build.

## Предшествующий automated evidence

Ubuntu focused gate на реальном ecology dependency graph уже прошёл:

- exact Godot identity: PASS;
- isolated dependency graph: PASS;
- parser preflight: PASS;
- strict ObjectDB/RID/resource/StringName shutdown gate: clean;
- `ECO.VIS2.2-D integrated observatory lab: PASS (63 assertions)`;
- `ECO.VIS2.2-D Ubuntu focused gate: PASS`.

## Graphical validation

Пользователь выполнил реальный graphical запуск VIS2.2-D на Ubuntu и подтвердил работу integrated lab.

Наблюдалось до replicated fork:

- VIS2.2-D READY;
- BASELINE source world;
- realtime Treatment LOD active;
- existing VIS1.9 observatory and VIS2.0 experiment panel present до fork;
- один ecology field.

После replicated fork наблюдалось:

- `ECO.VIS2.2-D` active;
- selected replicate `R0/8`;
- Treatment profile `NUTRIENT_PULSE 100%`;
- `VIS2.2 — REPLICATED CAUSAL EFFECT` observatory visible;
- aggregate effect curves обновляются по поколениям;
- `visible_fields=1`;
- Control + nonselected Treatment branches остаются `data-only`;
- selected Treatment world рендерится через inherited realtime LOD;
- новые растения визуально материализуются в текущем LOD tier;
- progression после fork продолжается без графических/runtime ошибок.

Пользователь сообщил: «новые растения отрисовываются одним лодом, все работает».

## Interpretation

Один одновременно видимый LOD tier для новых растений на конкретной позиции камеры не является нарушением контракта: realtime LOD выбирается presentation-layer по дистанции камеры. Критический VIS2.2-D invariant — отсутствие нескольких одновременно материализованных replicated ecology worlds — выполнен через `visible_fields=1`.

Выбор replicate остаётся presentation-only по архитектурному контракту; aggregate observatory показывает replicated causal effect, а физически материализуется только выбранный Treatment replicate.

## Status

`UBUNTU_RUNTIME_AND_GRAPHICAL_VALIDATED_CANDIDATE`

Этот checkpoint является evidence-only и не меняет simulation/runtime code-under-test.

Он не является fresh independent acceptance сам по себе.
