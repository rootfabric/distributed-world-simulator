# v17.14.0 — RL3 Representation-aware Network Streaming

## Решение

```text
checkpoint: v17.14.0-simulation-rl3-representation-aware-network-streaming
build_id:   rl3-representation-aware-network-streaming
base:       v17.13.0-simulation-rl2-matter-multiresolution-meshing
branch:     feature/rl3-representation-aware-network-streaming
status:     ACCEPTED
frozen:     true
```

**Implementation head до acceptance-коммита:** `0cac8a65411b38367b3096bd9d71499a24201d76`

## Реализовано

- exact RL0/RL2 source and spatial-scope fencing;
- representation-aware projection из MW7 subscription;
- deterministic coarse-to-fine plans;
- manifest-first `CACHE_HIT`/`TRANSFER` negotiation;
- content-addressed ordered chunks;
- backpressure и per-client budgets;
- exact stage ACK state machine;
- progressive coarse-to-final presentation;
- request replacement и cancellation generation;
- invalidation-driven stale presentation removal;
- reconnect cache reuse без повторной payload delivery;
- independent server/client/reconnect process tests.

## Focused topology

```text
contracts/runtime: 175 assertions
multi-process:       37 assertions
combined:           212 assertions
```

## Независимая приёмка

```text
RL3 focused:       PASS — 212/212
RL2 regression:    PASS — 197/197
MW10 regression:   PASS — 235/235
MW9 fix3:          PASS — 428/428
MW8 regression:    PASS — 98/98
MW7 regression:    PASS — 114/114
Godot editor import: PASS
git diff --check:  PASS
Conflict markers:  0
```

Независимая матрица закрывает отсутствовавший в authoring-base gate MW8 `98/98`. Цепочка поверхности для интеграции теперь фиксируется одним frozen head RL3, поскольку `feature/rl3-representation-aware-network-streaming` уже содержит принятые MW10, MW9 fix3, RL2, RL1 и RL0.

## Неподвижные границы

Artifact bytes и presentation не являются canonical world state. RL3 не меняет MW7 global/regional canonical replication, MW10 transaction semantics, MW9 durable authority directory, production Moon или world catalog.

## Итоговое решение

```text
checkpoint: v17.14.0-simulation-rl3-representation-aware-network-streaming
decision:   ACCEPTED
branch:     feature/rl3-representation-aware-network-streaming
frozen:     true
includes:   MW10 + MW9 fix3 + RL2 + RL1 + RL0
next:       integration/c24-nx6-mw10-rl3
```

Статус `CANDIDATE_FOR_INDEPENDENT_REVIEW` в authoring validation JSON является историческим статусом до независимой приёмки и этим acceptance-коммитом заменён на `ACCEPTED` для выбора frozen head.
