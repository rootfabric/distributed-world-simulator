# H0.1 / C22 R8 — SOURCE_ACCEPTED_MERGE_READY

Дата фиксации: 2026-08-12

## Решение

H0.1 R8 достиг состояния:

```text
H0_1_PASS
+
C22 SOURCE_ACCEPTED_MERGE_READY
```

Это **не разрешение на runtime merge**. Исполнение останавливается перед отдельным человеческим gate:

```text
HUMAN: C22_RUNTIME_MERGE
```

После человеческого merge обязателен fresh `post-C22 PC0`; только после его `NON_RED` можно объявлять `C22 MAIN_INTEGRATED` и переходить к `GLOBAL-P0 R3 current-main refresh`.

## Канонические SHA

```text
canonical main:
4a42c2fb6befb386f5c3eb48d9ba070745e25bbb

R8 exact implementation / review target:
4c69de50c8374112d82efee2fd6917c770b3eae0

R8 checkpoint control head before this documentation commit:
5bd4a2d2fa1bed600ced88cac9def893263e8a6e

Draft PR:
#90
```

PR #90 остаётся `Draft / unmerged` до явного человеческого решения.

## Почему понадобился R8

R7 корректно завершился `FIX_REQUIRED -> CANCELLED`: финальная проверка обнаружила, что прежний `implementation_head_sha` freshness-fence не включал bounded C22 runtime surfaces и мог направить post-build review на более старый control commit.

R8 создан заново от неизменившегося canonical `main`, причём `scripts/harness/**` и C22 implementation surfaces были объявлены в Work Order **до Director dispatch**.

В R8 `state_builder` теперь строит implementation freshness pathspec из active Work Order scope, исключая append-only execution evidence, branch passport и checkpoint-only documentation из self-staling review target, но сохраняя active transition table в fence.

Regression test подтверждает:

```text
implementation_head_sha == review_target_head_sha
== 4c69de50c8374112d82efee2fd6917c770b3eae0
```

и поздние evidence/control commits этот target не сдвигают.

## C22 source equivalence

Перенесены ровно 13 SOURCE_ACCEPTED C22 blobs.

```text
13 / 13 blob identity: PASS
```

Ни один C22 production/test/runner blob не был переписан при convergence.

## Fresh verification

Exact engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
precision: double
```

Fresh focused runtime gates на exact R8 implementation head:

```text
C22 incremental local rebuild       PASS  28 assertions
C22 compiled proxy graphical        PASS  35 assertions
C24 proxy mesh backend contracts    PASS  81 assertions
------------------------------------------------------
TOTAL                               PASS 144 assertions
FAILURES                                   0
```

Control/harness verification:

```text
pinned harness unit suite           PASS 13 / 13
CONTROL_DEVELOPMENT -Status         PASS
CONTROL_DEVELOPMENT -Plan           PASS
CONTROL_DEVELOPMENT -Resume         PASS
fresh Git-only recovery             PASS
```

Full world/core regression evidence с exact Windows head `b75165e48c963bd55b2f6c214e75d1328b0eb187` разрешено промотировать в R8 только после отдельного byte-fence. Проверка `b75165e... -> 4c69de50...` показала, что в runtime/test/runner namespaces отличаются только:

```text
scripts/harness/state_builder.py
tests/harness/test_h0_control_harness.py
```

C22 production, construction tests, C22/C24 runners и `RUN_WORLD_REGRESSION_TESTS.ps1` byte-identical относительно принятого regression evidence.

## PC0 / overlap

Executable Project Control на exact implementation head:

```text
workflow run: 31555576318
standard PC0:    YELLOW / NON_RED
directional PC0: YELLOW / NON_RED
C22 critical directional hits: 0
cross-branch overlaps: 0
blocking human-attention items: 0
```

Оставшиеся directional findings относятся к другим программам и не блокируют H0.1/C22.

## Final evidence chain

Append-only R8 ledger принят reducer-ом в последовательности:

```text
VERIFYING
  -> VERIFIED
  -> AUDITED
  -> CHECKPOINT_PROPOSED
```

Финальный ledger содержит 28 событий и закрывает все required predicates checkpoint `H0_1_CLOSED_LOOP_C22_PILOT`, включая:

- fresh exact-head Reviewer PASS;
- independent Verifier PASS;
- Evidence Map PASS;
- exact tested/review heads;
- standard/directional PC0 NON_RED;
- zero critical overlap;
- empty blocking Human Attention;
- Git-only recovery PASS;
- Draft PR #90 open;
- `C22_CHECKPOINT_PROPOSED`.

Pinned harness повторно прогнан **после сборки полного final candidate commit и до push**:

```text
13 / 13 PASS
checkpoint_blockers = []
checkpoint_proposal_blocked = false
```

## STOP boundary

Разрешено только следующее действие:

```text
HUMAN: C22_RUNTIME_MERGE
```

До него запрещено:

- считать C22 `MAIN_INTEGRATED`;
- запускать runtime H0.2 / NX.C1;
- выполнять GLOBAL-P0 R3 promotion;
- использовать source branch C22 как скрытую canonical truth для V0/NET/GEO/ITEM runtime.

Подготовительные `PREPARE_NOW` работы остаются допустимыми согласно central Project Control dashboard.
