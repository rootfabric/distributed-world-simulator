# ECO VIS1.8B-R1 — spectator mouse-look repair

Дата: 2026-08-16

Ветка: `feature/eco-vis1-visual-proving-ground`

База finding: `fe84376770d6baa8717efa150017ecff23ea1695`

## Наблюдение

Continuous population evolution VIS1.8B работает: generations идут дальше G12, turnover виден, keyboard spectator movement остаётся отзывчивым. Но управление обзором мышью пропало.

## Root cause

Базовый spectator VIS1.0 обрабатывает captured `InputEventMouseMotion` через `_unhandled_input()`.

В окне `1440x900` captured pointer логически находится около центра viewport (`720,450`).

В VIS1.7 диагностический HUD заканчивался около `y=430`, поэтому center mouse motion не попадал внутрь GUI и доходил до spectator `_unhandled_input()`.

В VIS1.8A-R1 / VIS1.8B HUD вырос до `offset_bottom=455`. Таким образом captured mouse center оказался внутри `PanelContainer`. Control-узлы по умолчанию могут участвовать в mouse event routing, поэтому mouse motion больше не гарантированно доходил до `_unhandled_input()`. Keyboard polling в `_process()` при этом продолжал работать, что точно соответствует наблюдаемому симптому.

## Repair

HUD в этих лабораторных сценах является только диагностическим и не содержит интерактивных контролов. Поэтому для всех его Control-узлов установлен `mouse_filter = MOUSE_FILTER_IGNORE` (`2`).

Это восстанавливает прежнюю spectator semantics без изменения camera controller, evolution/turnover model или input hotkeys.

Исправлены сцены:

- `eco_vis1_8a_realtime_turnover_field.tscn`;
- `eco_vis1_8b_continuous_population_field.tscn`.

## Regression coverage

VIS1.8B smoke теперь проверяет:

1. все HUD Controls имеют `MOUSE_FILTER_IGNORE`;
2. при captured mouse synthetic `InputEventMouseMotion` в точке `(720,450)` меняет rotation Camera3D;
3. после release mouse тот же тип motion не меняет rotation;
4. continuous evolution, G13+, rolling cache и restart determinism продолжают проходить прежние проверки.

## Архитектурная граница

Diagnostic overlays не должны влиять на spectator navigation. Если в будущем HUD получит настоящие interactive controls, их следует размещать в отдельном opt-in UI layer, а не возвращать mouse interception на весь diagnostic panel.

Статус: repair candidate до Windows graphical confirmation mouse-look + VIS1.8B automated gate.
