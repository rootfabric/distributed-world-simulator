# M7 FIX9 — Client Frame Budget / Presentation Hot Path

## Отправная точка

FIX8 закрыл рассинхронизацию prediction clock и прошёл автоматический двухклиентный анализ: hard corrections = 0, moving remote-buffer underruns = 0, серверный process/report budget в норме. При этом в коротком Windows-прогоне оставались единичные клиентские process spikes примерно 105–115 ms при нормальном p50 около 0.3 ms. Это уже не похоже на постоянный сетевой backlog; следующий шаг должен локализовать конкретную клиентскую фазу, а не добавлять ещё smoothing.

Дополнительный сигнал из того же отчёта: `inventory_rev6.sort_layout_updates` и `interaction_hint_layout_updates` росли почти один-в-один с числом client process iterations. То есть UI повторно записывал неизменившуюся геометрию Controls каждый кадр.

## Цель FIX9

1. Разделить клиентский hot path на измеряемые фазы с last/max/mean/count/over-budget.
2. Отделить время известных синхронных фаз от `process_unattributed`, чтобы следующий редкий spike имел адрес.
3. Измерить world/presentation путь отдельно от транспортного runtime.
4. Убрать доказанный безусловный per-frame churn в inventory layout без изменения authority, item graph, prediction или FIX8 clock semantics.
5. Не менять interpolation delay, correction thresholds, snapshot cadence или сетевую семантику в этом фиксе.

## Network client budget

`m3_graphical_client_runtime.gd` сохраняет FIX6 total process timing и добавляет policy:

`PHASE_ACCOUNTING_NO_GAMEPLAY_SEMANTICS_V1`

Измеряются:

- `message_dispatch`;
- `snapshot_message`;
- `item_message`;
- `control_message`;
- `prediction_reconcile`;
- `input_flush`;
- `telemetry_update`;
- `local_prediction`;
- `process_unattributed`.

`process_unattributed` считается как total client process минус синхронные top-level фазы, которые действительно выполнялись внутри этого `_process`. Вложенный reconciliation не вычитается повторно из total, потому что он уже входит в `message_dispatch`.

В `PREDICTION_HEALTH` добавлены peak значения FIX9, поэтому длинный ручной прогон можно разбирать не только по финальному JSON.

## World / presentation budget

Активный путь сцены намеренно остаётся `playground_view_relative_runtime_fix8.gd`, чтобы не ломать принятые tests, проверяющие exact script identity. FIX9 instrumentation добавляется внутрь этого composition leaf и не меняет FIX8 prediction behavior.

Измеряются:

- `world_render_process`;
- `world_physics_process`;
- `world_physics_unattributed`;
- `prediction_sync`;
- `prediction_callback`;
- `presentation_flush`;
- `replica_presentation`;
- `item_projection`.

Так можно различить, например, дорогую обработку snapshot в runtime и дорогой synchronous signal callback, который уже строит/применяет presentation в world node.

## Inventory hot-path fix

Новый `inventory_network_rev6_enhancer_fix9.gd` наследует accepted fix8 enhancer и сохраняет все его activation/sort/carry semantics.

Policy:

`WRITE_CONTROL_GEOMETRY_ONLY_WHEN_CHANGED_V1`

Изменение ограничено presentation properties:

- sort buttons получают `size/global_position` только если target geometry действительно изменилась;
- interaction hint получает `position/size` только при изменении;
- `visible` sort buttons записывается только при смене состояния;
- resize/reflow остаётся корректным, потому что target geometry всё равно проверяется каждый кадр;
- добавлены counters writes/skips для доказательства фактического устранения churn.

Это не кэш Item Graph и не задержка UI state: предметные данные, carry overlay, sort reconciliation и authority callbacks остаются прежними.

## Acceptance

Автоматический gate:

1. editor import/composition;
2. FIX9 focused frame-budget contracts;
3. FIX8 prediction-clock regression;
4. FIX6 graphical telemetry regression;
5. accepted inventory fix8 regression;
6. полный nested FIX8 → FIX7 → FIX6 → FIX5/network/inventory baseline;
7. двухклиентный process runner.

После этого обязателен >=5 минут LOCAL stress двумя графическими клиентами: непрерывное движение/повороты, частые start/stop, параллельные item drop/pickup/transfer/sort действия.

`ANALYZE_M7_FIX9_RESULTS.ps1` должен подтвердить:

- server healthy;
- hard corrections = 0;
- prediction error остаётся в FIX8 budget;
- FIX9 network/world policies присутствуют;
- нет серии >=50 ms client-process кадров;
- известные измеряемые фазы не выходят за budget сериями;
- inventory layout skips реально накапливаются, а layout writes больше не следуют каждому client frame.

Единичный startup/scheduling spike рассматривается отдельно от устойчивой игровой дёрганности; поэтому acceptance смотрит не только абсолютный max, но и число over-budget/slow frames и dominant phase.

## Если FIX9 всё ещё показывает рывки

Следующий патч определяется измерением:

- высокий `message_dispatch` / `snapshot_message` → bounded event budget / snapshot processing;
- высокий `item_projection` → dirty Item Graph presentation / incremental projection;
- высокий `replica_presentation` → remote presenter update batching;
- высокий `prediction_sync` → local movement kernel/input submission path;
- высокий `presentation_flush` → CharacterBody/camera presentation writes;
- высокий `process_unattributed` при низких остальных фазах → boundary polling, peer snapshot/handshake bookkeeping или OS scheduling; тогда добавляется более глубокая boundary phase instrumentation вместо изменения gameplay smoothing.
