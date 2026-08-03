# Checkpoint v16.13.0 — NX3 Fixed-Tick Authoritative Simulation

```text
checkpoint: v16.13.0-network-nx3-fixed-tick-authoritative-simulation
build_id: nx3-fixed-tick-authoritative-simulation
branch: feature/nx3-fixed-tick-authoritative-simulation
base: accepted v16.12.0 NX2 fix2
base commit: f1abeca
status: CANDIDATE
```

## Изменение

Production M7 movement переведён с обработки по arrival callback на 60-Hz fixed server scheduler. Input batches проходят validation и помещаются в отдельный bounded buffer каждого peer. Authoritative movement выполняется только simulation tick с delta `1/60`.

Добавлены:

- wrap-safe `InputSequence` и сквозная wrap-aware обработка batch/ACK/movement;
- `FixedTickScheduler`;
- `FixedTickInputBuffer`;
- transition-history redundancy;
- bounded catch-up;
- stale/window/queue protection;
- jump edge и 250-ms input hold fail-safe;
- fixed-tick telemetry;
- NX3 configuration, contracts и focused runners.

NX0 observability, NX1 conditions и NX2 channel/suppression contracts сохранены.

## Принятие

Перед `ACCEPTED` требуется независимый managed-MCP прогон на Godot 4.7.1 double после editor import:

```text
NX3 focused
network non-process regression
ENet process regression
M3 graphical
M7 playable
M7 restart/reconnect recovery
```
