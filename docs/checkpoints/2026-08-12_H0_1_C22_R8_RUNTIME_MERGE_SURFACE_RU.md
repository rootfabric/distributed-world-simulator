# H0.1 / C22 R8 — Runtime Merge Surface

Дата: 2026-08-12

## Решение

После `H0_1_PASS + C22 SOURCE_ACCEPTED_MERGE_READY` безопасный landing shape для human gate:

```text
PR #90 WHOLE-PR NORMAL MERGE COMMIT
```

Не использовать:

```text
SQUASH MERGE       NO
REBASE MERGE       NO
SELECTIVE CHERRY-PICK OF C22 ONLY   NO
FRESH REDUCED RUNTIME-ONLY PR       NO
```

Причина: H0.1 R8 одновременно содержит accepted C22 capability, обязательный Harness freshness-fence fix и canonical append-only execution/recovery provenance. Exact implementation/review target `4c69de50c8374112d82efee2fd6917c770b3eae0` должен остаться реальным предком canonical `main` после landing.

## Canonical pre-merge fence

```text
main:
4a42c2fb6befb386f5c3eb48d9ba070745e25bbb

R8 implementation / review target:
4c69de50c8374112d82efee2fd6917c770b3eae0

R8 branch:
feature/h0-1-c22-current-main-r3

PR:
#90 / Draft / open / unmerged
```

Перед фактическим merge человек обязан повторно убедиться, что `main` всё ещё равен exact base и PR #90 `mergeable=true`. Любое движение `main` до merge invalidates этот landing authorization и требует descendant-main audit/revalidation.

## Классификация merge surface

На момент подготовки merge package PR #90 состоит только из bounded H0.1/C22 surfaces. Temporary validation workflows находятся на отдельной validation branch и **не входят в PR #90**.

### CANONICAL_IMPLEMENTATION_REQUIRED — LAND

```text
scripts/construction/proxies/construction_proxy_array_mesh_backend.gd
scripts/construction/proxies/construction_proxy_artifact_merger.gd
scripts/construction/proxies/construction_proxy_artifact_merger.gd.uid
scripts/construction/proxies/construction_proxy_incremental_local_rebuilder.gd
scripts/construction/proxies/construction_proxy_incremental_local_rebuilder.gd.uid
scripts/construction/proxies/construction_proxy_streaming_controller.gd
```

Это accepted C22 production capability.

### CANONICAL_TEST_RUNNER_VALIDATION_REQUIRED — LAND

```text
RUN_C22_INCREMENTAL_REBUILD_TESTS.ps1
RUN_C22_INCREMENTAL_REBUILD_TESTS.sh
RUN_WORLD_REGRESSION_TESTS.ps1
tests/construction/test_c22_incremental_local_rebuild.gd
tests/construction/test_c22_incremental_local_rebuild.gd.uid
tests/construction/test_c24_proxy_mesh_backend_contracts.gd
validation/c22-incremental-local-rebuild-validation.json
```

Эти файлы входят в accepted/recovery test surface и нужны для post-merge validation.

### HARNESS_FIX_REQUIRED — LAND

```text
CONTROL_DEVELOPMENT.ps1
scripts/harness/state_builder.py
tests/harness/test_h0_control_harness.py
```

`state_builder.py` исправляет обнаруженный R7 exact-head defect: implementation/review freshness теперь строится из active Work Order implementation scope, а append-only evidence/checkpoint docs не self-stale review target.

`tests/harness/test_h0_control_harness.py` закрепляет этот контракт regression-тестом.

`CONTROL_DEVELOPMENT.ps1` переводит canonical public launcher со старого `E2026-08-11-H0-1-R5` на завершённый R8 execution. Без него main после C22 landing продолжал бы публиковать stale H0.1 control target.

### EXECUTION_EVIDENCE_HISTORY_ONLY — LAND AS CANONICAL PROVENANCE

```text
config/control/harness/executions/E2026-08-12-H0-1-R8/**
docs/checkpoints/2026-08-12_H0_1_C22_R8_SOURCE_ACCEPTED_MERGE_READY_RU.md
docs/checkpoints/2026-08-12_H0_1_C22_R8_RUNTIME_MERGE_SURFACE_RU.md
```

Это не runtime gameplay truth, но это canonical H execution/recovery history. Main уже хранит предыдущие H execution directories; исключать R8 ledger из landing нельзя без разрыва Git-only recovery/provenance модели.

В R8 evidence также есть append-only clarification:

```text
H0-1-R8-C22-WO-001-PC0-DIRECTIONAL-CLARIFICATION-002.v1.json
```

Он не переписывает исходный PC0 evidence, а уточняет, что:

```text
G  -> ECO  global_blocking=false
CH -> NX   global_blocking=true for future NX
```

При этом `CH -> NX` не блокирует H0.1/C22 и обязан быть revalidated/resolved перед H0.2/NX.C1 source acceptance.

### BRANCH_LOCAL_CONTROL_ONLY — NONE

```text
0 files
```

Temporary helper/validation workflows не входят в PR #90.

### DO_NOT_LAND — NONE

```text
0 files
```

Нет unrelated NET/ITEM/CH/ECO runtime mutation, scene mutation, canonical architecture mutation или temporary validation workflow в merge surface.

## Почему normal merge, а не squash/rebase

R8 evidence ссылается на exact immutable implementation head:

```text
4c69de50c8374112d82efee2fd6917c770b3eae0
```

Normal merge сохраняет branch commit ancestry в `main`, поэтому этот SHA остаётся прямой частью canonical history и Git-only recovery/review provenance.

Squash/rebase создаёт новые commit identities для landing и ухудшает exact-head provenance. Для первого Harness-controlled runtime convergence это лишний риск без выгоды.

## Human merge procedure

Непосредственно перед merge:

```text
1. fetch current main
2. verify main == 4a42c2fb6befb386f5c3eb48d9ba070745e25bbb
3. verify PR #90 head is current reviewed R8 head
4. verify PR #90 remains mergeable
5. verify latest Project Control == NON_RED
6. mark PR #90 Ready only as part of explicit human gate
7. merge using NORMAL MERGE COMMIT
8. do not merge PR #87/#85/#89 first
```

Если шаг 2–5 не выполняется — STOP, merge запрещён.

## Mandatory post-merge sequence

Сразу после merge:

```text
new main head
      ↓
verify 4c69de50... is ancestor of main
      ↓
run pinned Harness tests
      ↓
run C22 incremental focused
      ↓
run C22 graphical
      ↓
run C24 contracts
      ↓
run applicable full world/core regression or accepted exact promotion fence
      ↓
run standard Project Control PC0
      ↓
run directional Project Control
      ↓
require C22 overlap = 0
      ↓
require PC0 NON_RED
      ↓
C22 MAIN_INTEGRATED
```

Только после `C22 MAIN_INTEGRATED` разрешено:

```text
GLOBAL-P0 R3 exact-current-main refresh
```

R3 promotion всё ещё требует отдельного human architecture gate.

## Rollback / fail-closed

После merge не объявлять `C22 MAIN_INTEGRATED`, если возникает хотя бы одно:

```text
4c69de50 not ancestor of main
focused C22/C24/graphical FAIL
world/core regression FAIL
standard PC0 RED
directional C22 critical hit
critical overlap
Harness exact-head/recovery failure
unexpected main movement during validation
```

В таком случае canonical main содержит merge commit, но Project Control остаётся fail-closed на post-C22 integration repair/recovery; H0.2/R3 promotion не открываются автоматически.
