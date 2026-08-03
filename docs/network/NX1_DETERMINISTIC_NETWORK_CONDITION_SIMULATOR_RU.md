# NX1 Deterministic Network Condition Simulator

## Статус

```text
checkpoint: v16.11.0-network-nx1-deterministic-condition-simulator
build_id: nx1-deterministic-network-condition-simulator
base checkpoint: v16.10.8-network-nx0-observability-baseline
base commit: f1abeca
branch: feature/nx1-deterministic-network-condition-simulator
status: implementation candidate
```

## Назначение

NX1 добавляет воспроизводимую эмуляцию реального интернет-соединения между runtime и конкретным transport adapter. Сетевые условия применяются без изменения gameplay-команд, authoritative state, Item Graph и ENet wire-контрактов.

Production-композиция:

```text
NetworkTransportBoundaryV2
        ↓
NetworkConditionSimulatorPort
        ↓
ENetMultiPeerTransportPort
```

`LOCAL` является production-default и работает как прямой passthrough. При нулевых условиях wrapper не создаёт дополнительной очереди и не меняет порядок событий.

## Детерминизм

Симулятор не использует глобальный `randf()` и системную случайность. Для каждого эффекта создаётся независимый поток PRNG:

```text
random_seed
+ direction: OUTGOING / INCOMING
+ logical frame channel
+ effect: latency / jitter / loss / burst / duplicate / reorder
```

Изменение частоты вызовов одного эффекта не сдвигает последовательность другого. При одинаковом профиле, seed, порядке пакетов и ручном времени план доставки совпадает побайтно.

Для unit/property тестов доступен `MANUAL` clock. В production используется монотонный `Time.get_ticks_msec()`.

## Поддерживаемые воздействия

Профиль задаёт:

```text
outgoing_latency_min_ms / outgoing_latency_max_ms
incoming_latency_min_ms / incoming_latency_max_ms
jitter_ms
packet_loss_percent
burst_loss_probability_percent
burst_loss_duration_ms
duplicate_percent
reorder_percent
bandwidth_limit_kbps
queue_limit_bytes
lag_spike_ms
disconnect_duration_ms
random_seed
```

В `config/network/network-condition-presets.v1.json` определены:

```text
LOCAL
GOOD_BROADBAND
AVERAGE_BROADBAND
MOBILE
BAD_MOBILE
EXTREME
LAG_SPIKE
ASYMMETRIC
```

## Семантика reliable и unreliable

### Reliable

Симулятор не удаляет reliable application frame. Попадание reliable-пакета под loss/burst/blackout превращается в детерминированную задержку повторной передачи:

```text
base latency
+ retransmission penalty
+ остаток blackout при необходимости
```

Если нижележащий delegate временно отклоняет отправку, reliable frame остаётся в очереди и повторяется через короткий retry interval.

При переполнении исходящей очереди reliable send возвращает явный `NETWORK_SIMULATOR_QUEUE_LIMIT`, чтобы producer получил backpressure, а не ложный success. Входящий reliable frame, уже полученный ENet, не удаляется из-за искусственного лимита и учитывается как queue-limit bypass.

### Unreliable

Unreliable frame может быть:

- потерян;
- продублирован;
- переупорядочен;
- отброшен при queue pressure.

Для `UNRELIABLE_SEQUENCED` boundary теперь использует `GAP_TOLERANT_LATEST_WINS_V1`:

- потеря sequence не блокирует следующий frame;
- более новый sequence принимается;
- поздний старый frame и duplicate подавляются;
- reliable и unreliable используют независимые sequence-cursors по классу доставки и группе ENet-канала;
- reliable stream принимает глобальные sequence gaps, занятые кадрами других transport streams, но отклоняет stale/duplicate внутри собственного stream.

Это изменение необходимо, иначе честная эмуляция packet loss превращала бы каждый пропуск unreliable frame в ложную ошибку сессии.

## Bandwidth и очереди

`bandwidth_limit_kbps` моделируется как serialization timeline отдельно для outgoing и incoming направлений. Пакеты получают дополнительное ожидание, когда предыдущие данные уже заняли доступную полосу.

Очереди ограничены `queue_limit_bytes`. В telemetry публикуются:

```text
network_simulator_outgoing_queue_messages/bytes
network_simulator_incoming_queue_messages/bytes
network_simulator_ready_events
network_simulator_ready_message_events
network_simulator_ready_message_events_blocked
network_simulator_profile_generation
network_simulator_*_blackout_remaining_ms
```

Также считаются scheduled/actual delay, retransmission delay, serialization delay, bandwidth queue delay, drops, duplicates, reorder, burst windows, retries и backpressure.

## Lag spike и blackout

Профиль `LAG_SPIKE` добавляет spike каждому шестнадцатому пакету соответствующего stream. Профиль с `disconnect_duration_ms > 0` создаёт transport blackout каждому шестьдесят четвёртому пакету.

Runtime API позволяет вызвать воздействие вручную:

```gdscript
runtime.trigger_network_lag_spike("BOTH", 1000)
runtime.trigger_network_disconnect_blackout("BOTH", 3000)
```

`disconnect blackout` означает временную невозможность доставки application frames. Физический ENet socket не закрывается. Уже поставленные в очередь reliable и unreliable frames удерживаются до окончания blackout; новые unreliable frames, попавшие в активное окно blackout, отбрасываются, а новые reliable frames сохраняются до доставки. Manual lag spike также удерживает уже queued frames до своего deadline.

Блокировка применяется и к `MESSAGE_RECEIVED`, которые уже были перемещены из condition queue в `_ready_events`. Такие сообщения остаются готовыми, но не выдаются приложению до deadline blackout/spike. Их FIFO-порядок сохраняется. Connection lifecycle events (`PEER_CONNECTED`, `PEER_DISCONNECTED`, `TRANSPORT_ERROR`, listener lifecycle) проходят независимо от active incoming condition, чтобы simulator не подменял жизненный цикл adapter. Реальный process kill, restart, reconnect и replay продолжают проверяться M7 recovery suite.

## Область действия endpoint

Профиль принадлежит одному runtime endpoint.

```text
server profile = MOBILE
client profile = LOCAL
```

моделирует условия только на стороне server wrapper.

Если одинаковый профиль включён и на сервере, и на клиенте, воздействия складываются. Например, `AVERAGE_BROADBAND` на обоих концах даёт примерно удвоенный application-path latency относительно одного endpoint.

Для независимого моделирования upload/download обычно достаточно включить профиль только на одной стороне. `ASYMMETRIC` уже имеет разные outgoing/incoming диапазоны.

## Запуск

CLI:

```text
--network-profile=AVERAGE_BROADBAND
--network-presets-file=res://config/network/network-condition-presets.v1.json
```

Manual playground:

```bash
M7_SERVER_NETWORK_PROFILE=LOCAL \
M7_CLIENT_NETWORK_PROFILE=MOBILE \
./PLAY_M7_NETWORKED_PLAYGROUND.sh /path/to/godot.linuxbsd.editor.double.x86_64
```

PowerShell:

```powershell
.\PLAY_M7_NETWORKED_PLAYGROUND.ps1 `
  -GodotPath "C:\Godot\godot.windows.editor.double.x86_64.console.exe" `
  -ServerNetworkProfile LOCAL `
  -ClientNetworkProfile MOBILE
```

## Runtime switching

M3 server/client runtime exposes:

```gdscript
set_network_condition_profile(profile_id)
trigger_network_lag_spike(direction, duration_ms)
trigger_network_disconnect_blackout(direction, duration_ms)
```

При переключении:

- новый профиль валидируется через `NetworkConditionProfileStore`;
- уже queued packet сохраняет ранее назначенный deadline;
- новые пакеты используют новый профиль;
- PRNG streams и packet counters начинаются заново от seed нового профиля;
- generation увеличивается и попадает в telemetry/report.

## Сохранённые baseline-инварианты

NX1 намеренно не исправляет M7 traffic flow:

- successful movement result остаётся;
- per-input delta/full snapshot остаются;
- движение ещё зависит от packet arrival delta;
- ENet channel policy ещё не разделена на NX2 layout;
- persistence cadence не изменена.

Эмулятор делает эти проблемы воспроизводимыми и измеряемыми. Их исправление относится к NX2, NX3 и NX9.

## Тестирование

Focused runner:

```text
RUN_NX1_DETERMINISTIC_NETWORK_CONDITION_TESTS.sh
RUN_NX1_DETERMINISTIC_NETWORK_CONDITION_TESTS.ps1
```

Порядок:

1. обязательный editor import;
2. NX0 preparation contracts;
3. NX0 baseline contracts;
4. NX1 deterministic unit/property/integration contracts;
5. NX0 real ENet handshake regression;
6. NX1 conditioned real ENet process test.

NX1 contract suite проверяет:

- повторяемость PRNG и packet scheduling;
- независимость streams;
- все восемь presets;
- latency/jitter/burst/loss/duplicate/reorder;
- reliable retransmission preservation;
- queue backpressure и unreliable queue drops;
- bandwidth serialization;
- manual и periodic spikes/blackouts;
- удержание уже готовых incoming `MESSAGE_RECEIVED` при `poll_events(1)`;
- пропуск lifecycle events во время incoming block и FIFO после release;
- runtime profile switching;
- gap-tolerant latest-wins в boundary;
- telemetry, CLI и production wiring.

Real ENet process-test запускает dedicated server и probe под `AVERAGE_BROADBAND`, проверяет handshake ACK, измеримую задержку, отсутствие gameplay JOIN, заполнение telemetry и полное осушение simulator queues.

## Следующий этап

После независимой приёмки NX1:

```text
NX2 — Realtime Traffic Separation
```

NX2 должен разделить ENet channels, убрать успешные movement results, прекратить per-input full snapshots, ввести batching/redundancy input и ограничить snapshot publication rate.

## 12. Implementation validation

На delivery candidate выполнены:

```text
focused:                         6/6 PASS
NX1 contracts:                  282 assertions
conditioned real ENet:           27 assertions
network non-process:             49/49 PASS
ENet process regression:          4/4 PASS
M3 graphical:                    56 assertions
M7 playable:                     34 assertions
M7 restart/reconnect:            36 assertions
failures:                         0
```

Fix2 focused, network non-process и ENet process regression выполнены через controlled headless shell-процессы с приложенной double-сборкой. M3/M7 после fix2 независимо не подтверждены; для acceptance требуется managed MCP и обязательный editor import перед process-тестами.
