# FABRIC R5.3 — Recursive Hierarchical Execution

Статус: implementer candidate. База — T16 merge `604192f07070d0f0e38a94445611d09d92cb7f7f`.

## Что доказывается

Четырёхуровневая generic electrical hierarchy:

```text
8 physical leaf networks
  ↓ T1 exact leaf BAKE (>=100 hidden variables каждый)
4 module ROM
  ↓ child boundary ROM only
2 assembly ROM
  ↓ child boundary ROM only
1 machine ROM
```

T1 acceptance floor не ослабляется. Leaf проходит существующий T1 compiler. Parent R5.3 compiler получает только four-port Schur ROM детей и выполняет тот же exact Schur reducer на маленьком composition graph. Parent capsule содержит child node hashes, graph/descriptor hashes, topology revision, complexity accounting и checksum.

Baseline: 1812 physical components скрыты за machine compile graph из 24 derived/connectors components и machine executable из 4 equations. 512 steady machine executions не обходят leaf/source components.

## Recursive rebuild

Acceptance последовательно меняет уровень 0, 1, 2 и 3:

```text
leaf mutation      → leaf + module + assembly + machine = 4 changed nodes
module topology    → module + assembly + machine        = 3
assembly topology  → assembly + machine                 = 2
machine topology   → machine                            = 1
```

Runtime `refresh()` обязан повторно prepare только changed nodes и переиспользовать остальные prepared sessions. Неверная changed-path карта отклоняется до mutation runtime registry.

Leaf mutation увеличивает hidden leaf topology с 100 до 120 internal nodes. Physical machine complexity растёт 1812 → 1852 components, но machine compilation graph остаётся 24 components, steady executable — 4 equations.

## Oracle

Чтобы R5.3 не превращался в R5.1 dense-scale benchmark, physical equivalence проверяется по индукции:

- каждый leaf уже проходит полный T1 source→ROM gate;
- module дополнительно сравнивается с реально развернутыми source graphs двух leaf (~200 hidden variables);
- каждый assembly/machine ROM сравнивается с прямым full solve его immediate child-ROM composition graph;
- после каждого уровня mutation parity проверяется снова.

Максимальные наблюдавшиеся ошибки в implementer preliminary run: flow `6.394884621840902e-14`, power `2.2737367544323206e-11`.

## Границы

Это exact-linear recursive ROM falsifier, а не утверждение универсальной рекурсивной reduction для nonlinear/hybrid systems. R5.4 должен смешать разные классы сложности. R5.3 не вводит production state owner, network/persistence handoff или device-specific kernel. Parent compiler не читает hidden child source graph.

Fresh exact Linux/Windows, fresh review/verifier и human merge обязательны перед закрытием checkpoint.
