# M7 FIX10 fix5 — Composite ACK Semantic Identity

## Статус

`IMPLEMENTED CANDIDATE — Windows validation required`

База: exact FIX10 fix4 head `e0aab932904c8951c935147f607f85f32b12d128`.

## Что показал exact Windows full gate fix4

Автоматический gate прошёл полностью:

- focused FIX10 fix4/fix3/fix2/core — PASS;
- FIX9/FIX8/NX4 — PASS;
- accepted network/inventory baseline — PASS;
- two-client graphical process — `51 assertions, 0 failures`;
- Item Graph и player replicas сошлись;
- transport quarantine/disconnect не повторился;
- hard corrections — 0.

Но на клиенте B остался один ACK semantic reject:

```text
fix10_ack_mismatches               1
fix10_ack_registration_rejections  0
sidecars_received                  17
sidecars_registered                16
sidecars_rejected                  1
standalone_ack_received             4
standalone_ack_registered           4
standalone_ack_rejected             0
```

Это локализует проблему в регистрации snapshot sidecar. Это не MTU, не ENet, не standalone fallback и не повреждённая форма ACK.

## Ошибка модели fix4

Fix4 правильно отвязал ACK от точного transport snapshot tick, но продолжал считать, что один `client_tick` может соответствовать только одному `input_sequence`.

Это неверно для текущего клиента.

Movement submission увеличивает `input_sequence` независимо, а `client_tick` берёт как следующий prediction tick:

```text
input_sequence = next(input_sequence)
client_tick = prediction_tick + 1
```

Если до симуляции следующего prediction tick произошло несколько state transitions, несколько последовательностей законно получают один и тот же будущий `client_tick`.

Следовательно:

```text
same client_tick + different input_sequence
```

не является semantic contradiction.

## Новый контракт fix5

ACK identity:

```text
(client_tick, input_sequence)
```

Policy:

```text
CLIENT_TICK_AND_WRAP_AWARE_INPUT_SEQUENCE_V1
```

Порядок:

1. сначала сравнивается `client_tick`;
2. при одинаковом tick используется wrap-aware `InputSequence.is_newer()`;
3. более новая sequence на том же tick supersedes старую;
4. более старая sequence на том же tick считается stale metadata и игнорируется;
5. mismatch остаётся только если exact composite key имеет противоречащий authoritative baseline.

Это сохраняет строгую проверку реальных конфликтов.

## Почему нужен wrap-aware sequence order

`input_sequence` циклический:

```text
1 .. 2147483647 -> 1
```

Поэтому численное сравнение `sequence > other_sequence` некорректно около wrap boundary.

Fix5 использует существующий `InputSequence.is_newer()`.

## Repeated ACK

Exact duplicate ACK после уже принятого baseline не отбрасывается до reconciliation.

Он остаётся eligible для существующего режима:

```text
ACK_REPLAY
```

Это важно: повторный movement snapshot с тем же semantic ACK не должен внезапно возвращать клиент к wall-clock fallback reconciliation.

## Local timeline supersession

Локальная prediction timeline хранит фактически использованную sequence для каждого prediction tick.

Если приходит ACK старой sequence, но timeline на том же `client_tick` уже содержит более новую sequence, это классифицируется как:

```text
local_timeline_superseded_ack
```

а не как history miss или protocol mismatch.

Сам authoritative snapshot при этом остаётся на консервативном fallback path — fix5 не скрывает реальное расхождение состояния.

## Новая telemetry

```text
fix10_fix5_ack_identity_policy
fix10_fix5_same_tick_sequence_supersessions
fix10_fix5_same_tick_sequence_stale
fix10_fix5_exact_key_conflicts
fix10_fix5_local_timeline_superseded_acks
```

Старые строгие counters остаются:

```text
fix10_ack_mismatches
fix10_ack_registration_rejections
```

## Focused regression

Добавлен:

```text
res://tests/network/test_m7_sequence_reconciliation_fix10_fix5.gd
```

Проверяет:

- две input sequences на одном future client tick;
- newer same-tick ACK supersedes older;
- reordered older same-tick ACK benign/stale;
- exact same composite key с другим baseline по-прежнему reject;
- sequence ordering корректен через MAX -> 1 wrap;
- source contract действительно допускает независимое увеличение input sequence при stamp `prediction_tick + 1`.

## Windows gate

Сначала:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\VALIDATE_M7_SEQUENCE_RECONCILIATION_FIX10.ps1 `
  -GodotPath $Godot `
  -FocusedOnly
```

Затем:

```powershell
.\VALIDATE_M7_SEQUENCE_RECONCILIATION_FIX10.ps1 `
  -GodotPath $Godot `
  -IncludeTwoClientProcess
```

До длинного stress run обязательные результаты:

```text
fix10_ack_mismatches               0 / 0
fix10_ack_registration_rejections  0 / 0
sidecars_rejected                  0 / 0
standalone_ack_rejected            0 / 0
hard_corrections                   0 / 0
movement_snapshots_dropped_for_mtu 0
max_unreliable_sent_bytes          <= 1350
```

Только после этого имеет смысл повторять >=5 minute LOCAL movement/item stress и `ANALYZE_M7_FIX10_RESULTS.ps1`.
