# FABRIC R5.3 — Recursive Hierarchical Execution

Статус: R3 implementer repair candidate после fresh falsifier-review R2. База — T16 merge `604192f07070d0f0e38a94445611d09d92cb7f7f`.

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

T1 acceptance floor не ослабляется. Leaf проходит существующий T1 compiler, а R5.3 дополнительно fail-closed сверяет T1 capsule/artifact/reduction с тем же exact source graph: graph hash, artifact/source binding, descriptor, state schema, source count, equation counts и build generation. Повторное связывание ROM от graph A с graph B запрещено. Parent R5.3 compiler получает только four-port Schur ROM детей и выполняет тот же exact Schur reducer на маленьком composition graph. Parent capsule содержит child node hashes, graph/descriptor hashes, topology revision, complexity accounting и checksum.

Baseline: 1812 physical components скрыты за machine compile graph из 24 derived/connectors components и machine executable из 4 equations. 512 steady machine executions не обходят leaf/source components.

## Recursive rebuild

Acceptance последовательно меняет уровень 0, 1, 2 и 3:

```text
leaf mutation      → leaf + module + assembly + machine = 4 changed nodes
module topology    → module + assembly + machine        = 3
assembly topology  → assembly + machine                 = 2
machine topology   → machine                            = 1
```

Runtime `refresh()` обязан повторно prepare только changed nodes и переиспользовать остальные prepared sessions. Неверная changed-path карта отклоняется до mutation runtime registry. R2 дополнительно делает refresh транзакционным: **все** changed sessions сначала готовятся во временный staging; live registry меняется единым commit только если каждый changed node успешно прошёл validation/prepare. Ошибка глубокого descendant не может оставить уже обновлённый root/assembly session.

Leaf mutation увеличивает hidden leaf topology с 100 до 120 internal nodes. Physical machine complexity растёт 1812 → 1852 components, но machine compilation graph остаётся 24 components, steady executable — 4 equations.

## Oracle

Чтобы R5.3 не превращался в R5.1 dense-scale benchmark, physical equivalence проверяется по индукции:

- каждый leaf уже проходит полный T1 source→ROM gate;
- module дополнительно сравнивается с реально развернутыми source graphs двух leaf (~200 hidden variables);
- каждый assembly/machine ROM сравнивается с прямым full solve его immediate child-ROM composition graph;
- после каждого уровня mutation parity проверяется снова.

Максимальные наблюдавшиеся ошибки в implementer preliminary run: flow `6.394884621840902e-14`, power `2.2737367544323206e-11`.

## R1 falsifier repair → R2

Fresh implementer review R1 нашёл два blocking counterexample:

1. rejected refresh мог частично изменить live registry, если ранний ancestor уже prepared, а более глубокий changed node падал;
2. `leaf_from_t1()` принимал T1 reduction от одного source graph вместе с другим graph и тем самым позволял ложный provenance.

Дополнительный recursive falsifier также запретил молчаливую реконструкцию child ROM из неполного Schur: parent теперь требует exact four-port contract, `passivity_certified=true` и фактический Laplacian row-sum contract до извлечения pairwise conductances.

R2 закрывает все три класса отдельными acceptance falsifiers. После repair preliminary exact acceptance: **1212/0**, machine compile graph `24`, executable `4`, physical `1812 → 1852`, `prepare=25`, `reuse=50`, `execute=550`; max flow/power error остаются `6.394884621840902e-14` / `2.2737367544323206e-11`. Эти числа являются implementer evidence, не independent acceptance.

## R2 fresh falsifier review → R3

Fresh review восстановленного R2 source artifact выявил ещё два blocking counterexample:

1. compiler принимал `machine(level=3)` с прямым `leaf(level=0)` ребёнком, то есть позволял пропустить module/assembly уровни при сохранении внешне валидного ROM;
2. T1 graph/capsule/artifact provenance можно было перехешировать под graph B, оставив reduction от graph A: descriptor `source_system_hash` не сверялся с независимо собранной linear system точного source graph.

R3 делает hierarchy admission fail-closed по exact adjacent level и ограничивает R5.3 node levels диапазоном `0..3`. Leaf admission сверяет top-level T1 linear system, embedded graph-compile linear system и reduction source system с независимым `GraphCompiler.compile(graph)`. Эта проверка намеренно остаётся на leaf admission: parent composition продолжает читать только child ROM/capsule и не переходит к hidden leaf source graphs. Добавлены executable falsifiers для skipped-level composition и forged T1 descriptor rebinding.

## Границы

Это exact-linear recursive ROM falsifier, а не утверждение универсальной рекурсивной reduction для nonlinear/hybrid systems. R5.4 должен смешать разные классы сложности. R5.3 не вводит production state owner, network/persistence handoff или device-specific kernel. Parent compiler не читает hidden child source graph.

Fresh exact Linux/Windows, fresh review/verifier и human merge обязательны перед закрытием checkpoint.
