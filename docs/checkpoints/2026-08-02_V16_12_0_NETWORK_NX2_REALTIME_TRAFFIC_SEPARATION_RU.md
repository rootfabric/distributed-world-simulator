# Checkpoint v16.12.0 — NX2 Realtime Traffic Separation

## Решение

```text
checkpoint: v16.12.0-network-nx2-realtime-traffic-separation
build_id: nx2-realtime-traffic-separation
branch: feature/nx2-realtime-traffic-separation
base checkpoint: v16.11.0-network-nx1-deterministic-condition-simulator / fix2
base commit: f1abeca
status: implementation candidate
```

## Реализовано

- шесть production logical/ENet channels;
- raw ENet unreliable с application-level latest-wins sequencing;
- outbound queues, разделённые по peer/delivery/channel stream;
- reliable FIFO и транзакционный realtime latest-pending coalescing;
- compact `PlayerInputBatch` до трёх transition segments;
- input send interval `33 ms` и redundancy/retransmission до authoritative ACK;
- подавление successful movement results, per-input delta и full snapshot;
- compact movement snapshots с интервалом `50 ms`;
- compact wire budget меньше `1200 bytes` без unreliable fragmentation;
- строгий Item Graph delta по отдельному reliable item channel с full-resync fallback после committed mutation;
- join/full resync по `RESYNC`;
- explicit Item Graph resync при base revision/checksum mismatch;
- server-authoritative persistence capability вместо глобального отключения `item.save`;
- NX2 telemetry/counters и process assertions;
- обновлённый protocol hash со всеми sequencing/input-history policies.

## Сохранённые границы

NX2 не является fixed-tick или prediction checkpoint. Server movement budget пока ограниченно формируется из packet arrival delta. Movement persistence cadence `1500 ms` не изменена. Эти изменения относятся к NX3, NX4 и NX9.

## Implementation evidence

Контролируемые direct headless/graphical прогоны приложенной Godot 4.7.1 double:

```text
Editor import:                 PASS
NX2 focused contracts:        116 assertions
NX0 preparation:              115 assertions
NX0 baseline:                 150 assertions
NX1 contracts:                282 assertions
Compatibility handshake:       31 assertions
Conditioned ENet:               27 assertions
Network non-process:           50/50 PASS
ENet process regression:        4/4 PASS
T1 multi-peer:                  20 assertions
N1 snapshots:                   28 assertions
N1 remote Item Graph:           51 assertions
N1 reconnect/replay:            67 assertions
M7 playable NX2 process:        43 assertions, 0 failures
M7 recovery:                    36 assertions, 0 failures
```

M3 graphical assertion body сообщил `57 assertions, 0 failures`, но direct harness не завершил родительский процесс после отчёта и был остановлен внешним timeout. Поэтому clean-exit M3 не заявляется как implementation PASS и должен быть подтверждён managed-MCP приёмкой.

Окончательный статус остаётся `CANDIDATE` до независимого managed-MCP прогона.

## Delivery artifacts

- `NX2_REALTIME_TRAFFIC_SEPARATION_PATCH_MANIFEST.json`
- `validation/v16.12.0-network-nx2-realtime-traffic-separation-validation.json`
- `validation/v16.12.0-network-nx2-realtime-traffic-separation-files.txt`
