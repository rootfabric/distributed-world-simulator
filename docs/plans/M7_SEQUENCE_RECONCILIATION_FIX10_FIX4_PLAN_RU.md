# M7 / FIX10 fix4 — ACK Timeline + MTU Headroom

## Статус

```text
base:   FIX10 fix3 @ 15e19b25b92c7938e940b1a09311a62300befd52
branch: feature/m7-sequence-aware-reconciliation-fix10-fix4-ack-timeline-mtu-headroom
state:  IMPLEMENTED CANDIDATE
```

FIX10 fix3 визуально закрыл исходный дефект: во время локального input удалённый персонаж больше не замирает с последующим catch-up teleport. Пользователь подтвердил, что пролаг исчез и явных визуальных багов в длинном двухклиентном прогоне не заметил.

Fix4 не меняет принятую fix3 presentation lane и не тюнит remote interpolation.

## Остаток после fix3

В длинном прогоне были выделены два независимых технических дефекта.

### 1. Ложные ACK mismatch

Standalone `PREDICTION_ACK` отправляется по независимому TELEMETRY каналу. ACK содержит clock movement snapshot, для которого он был создан, но может быть обработан рядом с более новым gameplay snapshot.

Старый reconciler требовал:

```text
ack.snapshot_server_tick == currently_reconciled_snapshot.server_tick
ack.input_sequence == currently_reconciled_player.last_input_sequence
```

Для независимых каналов это неверная идентичность. В длинном прогоне это дало тысячи `fix10_ack_mismatches`, хотя ACK transport registration не имел rejects.

Fix4 вводит правило:

```text
ACK semantic identity = client_tick + input_sequence + authoritative post-input baseline
transport snapshot tick = provenance only
```

Допускается:

```text
ack.transport_snapshot_tick < current_snapshot.server_tick
authoritative_player.last_input_sequence > ack.input_sequence
```

если ACK уже существовал в authority к моменту более нового snapshot.

ACK из будущего относительно текущего snapshot откладывается. При cross-channel reorder более старый client-tick ACK не может заменить новый pending ACK.

Policy:

```text
SEMANTIC_ACK_BASELINE_DECOUPLED_FROM_TRANSPORT_SNAPSHOT_V1
```

## 2. MTU headroom

Fix2 сохраняет hard guard:

```text
unreliable safe packet budget = 1350 bytes
```

В fix3 long run no-ACK movement frame достигал `1361 bytes`, поэтому 68 movement snapshots были безопасно отброшены. Повышать лимит fix4 не будет.

Realtime message уже однозначно определяется как:

```text
COMPACT_GAMEPLAY_SNAPSHOT
```

Поэтому high-frequency envelope больше не передаёт дублирующий диагностический field:

```text
reason = MOVEMENT_NETWORK_TICK
```

Reliable full/resync `GAMEPLAY_SNAPSHOT` сохраняет `reason` без изменений.

Policy:

```text
OMIT_REDUNDANT_REASON_ON_REALTIME_SNAPSHOT_V1
```

Цель — вернуть no-ACK compact frame под 1350 bytes, не меняя canonical compact snapshot, checksum, authority или transport delivery semantics.

## Analyzer correction

Fix3 analyzer ошибочно требовал:

```text
standalone_ack_sent >= ack_omitted_for_mtu
```

Но standalone ACK отправляется только после успешной отправки movement snapshot. Если snapshot после ACK omission всё равно был отброшен по MTU, standalone ACK для него не отправляется.

Правильная coverage формула:

```text
expected_standalone_ack = ack_omitted_for_mtu - movement_snapshots_dropped_for_mtu
```

При этом fix4 отдельно требует:

```text
movement_snapshots_dropped_for_mtu == 0
max_unreliable_sent_bytes <= 1350
max_without_ack_bytes <= 1350
```

## Remote presentation

Fix3 visual continuity сохраняется без изменений. Из предыдущего длинного run допускаются небольшие bounded startup HOLD/underrun counters, если они не перерастают в устойчивый рост/телепорты. Apply failures и same-clock conflicts по-прежнему должны быть нулевыми.

Canonical `same_revision_semantic_conflicts` fix4 не маскирует и не ослабляет; это отдельный remaining invariant issue после ACK/MTU проверки.

## Проверка

Focused:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\VALIDATE_M7_SEQUENCE_RECONCILIATION_FIX10.ps1 `
  -GodotPath $Godot `
  -FocusedOnly
```

Full inherited gate:

```powershell
.\VALIDATE_M7_SEQUENCE_RECONCILIATION_FIX10.ps1 `
  -GodotPath $Godot `
  -IncludeTwoClientProcess
```

После этого — длинный LOCAL run и:

```powershell
.\ANALYZE_M7_FIX10_RESULTS.ps1 `
  -ServerJson <run>\server.json `
  -ClientAJson <run>\a.json `
  -ClientBJson <run>\b.json
```

Ключевые fix4 acceptance targets:

```text
ack_mismatches                         0 / 0
ack_registration_rejections            0 / 0
movement_snapshots_dropped_for_mtu     0
max_unreliable_sent_bytes              <= 1350
max_without_ack_bytes                  <= 1350
hard_corrections                       0 / 0
remote apply failures                  0 / 0
remote same-clock conflicts            0 / 0
```

Correction density и canonical same-revision conflicts остаются полными gates для общего FIX10 acceptance.