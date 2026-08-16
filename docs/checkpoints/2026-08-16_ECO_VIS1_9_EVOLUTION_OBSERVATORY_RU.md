# ECO VIS1.8B-R1 validation + VIS1.9 Evolution Observatory

Дата: 2026-08-16

## Подтверждённый вход

На Windows exact Godot `4.7.1.stable.double.custom_build.a13da4feb` подтверждено:

- continuous turnover проходит дальше G12;
- spectator снова управляется мышью и клавиатурой;
- старые representatives умирают, новые появляются;
- realtime proxy tier остаётся отзывчивым;
- `PH5_turnover_rebuilds=0`;
- вблизи уже существует рабочая LOD/PH5 архитектура.

VIS1.8B-R1 используется как validated presentation baseline.

## VIS1.9

VIS1.9 добавляет observability поверх существующей evolution logic и не меняет turnover kernel.

Evolution Observatory показывает последние 64 generation summaries:

- population size;
- births / deaths;
- mean fitness;
- unique genome count;
- alpha / beta composition.

Панель является read-only presentation и имеет `mouse_filter=IGNORE`, поэтому не может снова блокировать spectator mouse-look.

`O` включает/выключает observatory.
`PageUp/PageDown` перемещают inspection cursor по сохранённой истории независимо от live generation.

## Progressive PH5 detail

Во время PLAY сохраняется только быстрый realtime proxy tier.

Во время PAUSE для generation > 0 ближайшие к камере representatives постепенно, по одному, заменяются настоящей PH5 geometry:

`genome -> inherited DevelopmentTraits -> local EnvironmentSample -> EnvironmentCoupledDevelopment -> GrowthGraph -> RenderDescription -> Plant3DMaterializer`.

Ограничение: максимум 5 detailed plants одновременно.

При возобновлении PLAY detailed overlays немедленно освобождаются и proxy снова становятся видимыми.

Whole-field PH5 rebuild по-прежнему запрещён:

`PH5_turnover_rebuilds == 0`.

## Truth boundary

VIS1.9 остаётся наблюдательным lab-derived слоем:

- canonical population truth: OFF;
- canonical timeline truth: OFF;
- VIS1.2 biomass source остаётся read-only;
- observatory/history не изменяют simulation state;
- progressive PH5 — derived presentation.

Статус: IMPLEMENTED_CANDIDATE до Windows exact gate и визуальной проверки.
