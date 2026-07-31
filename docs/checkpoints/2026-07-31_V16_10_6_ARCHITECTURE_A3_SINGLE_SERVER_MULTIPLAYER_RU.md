# Checkpoint v16.10.6 — A3 Single-Server Multiplayer

```text
checkpoint: v16.10.6-architecture-a3-single-server-multiplayer
build_id: a3-single-server-multiplayer-architecture-freeze
base: v16.10.5-persistence-m6-dedicated-recovery
branch: feature/a3-single-server-multiplayer-architecture
status: candidate
```

## Состав

- машинно-читаемый A3 freeze manifest;
- scene-tree-independent architecture auditor;
- contract/runtime-equivalence A3 test;
- focused Windows/Linux runners;
- обновлённые A2, post-A2 и network roadmaps;
- финализация M2, M3 и M6 acceptance metadata;
- полное ограничение B1 как server-to-server adapter;
- сохранение multi-authority gate до B2.

## Проверка поставляемого кандидата

```text
Godot: 4.7.1 stable.double custom build a13da4feb
Focused A3: 12/12 PASS
A3 contracts/runtime equivalence: 140 assertions, 0 failures
Network/runtime: 60/60 PASS, 4759 assertions
World regression: 105/105 PASS
Main scene CLI: 6/6 PASS
```

Статус остаётся `candidate` до независимой приёмки на целевой локальной double-precision сборке.

## Критерии принятия

```text
Focused A3: PASS
A3 contracts/runtime equivalence: PASS
Network/runtime: PASS
World regression: PASS
Main scene CLI: 6/6 PASS
git diff --check: PASS
JSON/GDScript/UID/shell gates: PASS
remaining Godot processes: 0
```

После независимой приёмки статус A3 меняется на `ACCEPTED`. Следующий checkpoint — `v16.11.0-data-plane-b1-nats-core`.
