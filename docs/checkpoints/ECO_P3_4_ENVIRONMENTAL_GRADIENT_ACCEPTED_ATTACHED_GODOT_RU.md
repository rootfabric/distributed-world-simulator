# ECO P3.4 — Environmental Gradient — ACCEPTED

Статус: `ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL`.

Дата: 2026-08-13.

P3.4 принят строго после фактического acceptance P3.3 (`23f1a98479dacf1d88e016493d026fb462ffb6b9`). Human-directed execution для текущих трёх lifecycle-пунктов разрешает использовать exact Godot, приложенный к проекту; Windows PASS не заявляется.

## Exact identities

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
parent P3.3 aggregate=37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
kernel_blob=11e2b281c48d378da906f0739c739eecf9aa8465
acceptance_test_blob=f3412bd53ebe7d647b83266e4945d758924ab66b
```

## Durable full evidence

```text
P3.3 parent regression = PASS (66 assertions)
P3.4 fresh A/B/C = PASS (56 assertions each; byte-identical logs)
aggregate_hash=a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
gradient_hash=2651bb4da195af4c1d2ba7f6b09ef9bdc9e459f9206c32ef1e9eb0dbddd6b293
empty_hash=13ec0762efeec0e0130f7b587b17bc7bd5b133fafa4f8eaf2975c5c5ff5c91a1
```

Fresh current-head attached-Godot integration recheck also passed using exact P3.3/P3.4/P3.5 kernel blobs. Supplemental P3.4 fixture hash:

```text
6c4da52f0ca5da551236df7c8c2051545d60ef62a9751ae0a40e86b48ecbc720
```

This fixture hash is smoke evidence only and does not replace the canonical aggregate.

## Decision

`P3.4 Environmental Gradient = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL`.

P3.5 may now be lifecycle-promoted only against this accepted parent and its frozen implementation/test identities.
