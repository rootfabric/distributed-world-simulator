# ECO P3.3 — Spatial Dispersal — ACCEPTED

Статус: `ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL`.

Дата: 2026-08-13.

## Acceptance basis

Human направил выполнить следующие три lifecycle-пункта и проверить результат на Godot, приложенном к проекту. Для P3.3 это supersede прежнего Windows-only execution requirement; Windows PASS не заявляется.

Exact execution engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Immutable implementation/test identities:

```text
kernel_blob=43a25eb0e6677749162de99c251231c94d243dc1
acceptance_test_blob=9911c9197663098e1efa8875332b9d7c88ca34c6
parent_p3_2=172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
```

Durable full targeted evidence already on these exact identities:

```text
P3.2 parent regression = PASS (79 assertions)
P3.3 fresh A/B/C = PASS (66 assertions each)
aggregate_hash=37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
network_hash=21a8de4b12cd541d40c8fd34b725e59e493a775e3465b853945f46f85445a8a2
closed_hash=039fb7fc353e36f4d0d42fa146760062704e91a6ed21c03bff8213feec96cc5f
isolated_hash=14d1d467d65047e362fc6bd04dd668ab1713d986c1bb97f79734ecc0370441ec
```

Fresh current-head integration recheck on the attached engine used byte-identical current P3.3/P3.4/P3.5 kernels and a strict minimal P3.2 parent validator. It passed parser/preload plus spatial conservation, canonical patch order, transfers and `P3.3.validate_result()`; integration fixture P3.3 hash was `b248455bccd179065f11b8a86d9c8d3d0c39100265f967b5ad5850f98498d135`.

The integration-fixture hash is supplemental smoke evidence, not a replacement for the canonical P3.3 aggregate above.

## Decision

`P3.3 Spatial Dispersal = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL`.

P3.4 may now be lifecycle-promoted only if its already-frozen implementation/test identities and expected parent/aggregate remain exact.
