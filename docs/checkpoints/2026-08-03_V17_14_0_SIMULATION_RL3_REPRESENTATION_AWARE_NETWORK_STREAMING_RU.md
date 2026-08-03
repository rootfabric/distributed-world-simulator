# v17.14.0 — RL3 Representation-aware Network Streaming

## Решение

```text
checkpoint: v17.14.0-simulation-rl3-representation-aware-network-streaming
build_id:   rl3-representation-aware-network-streaming
base:       v17.13.0-simulation-rl2-matter-multiresolution-meshing
branch:     feature/rl3-representation-aware-network-streaming
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

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
multi-process:      37 assertions
combined:          212 assertions
```

## Обязательные независимые gates

```text
RL3 focused:       212/212 PASS
RL2 regression:    197/197 PASS
MW10 regression:   235/235 PASS
MW9 regression:    428/428 PASS
MW8 regression:     98/98 PASS
git diff --check:  PASS
```

## Неподвижные границы

Artifact bytes и presentation не являются canonical world state. RL3 не меняет MW7 global/regional canonical replication, MW10 transaction semantics, MW9 durable authority directory, production Moon или world catalog.
