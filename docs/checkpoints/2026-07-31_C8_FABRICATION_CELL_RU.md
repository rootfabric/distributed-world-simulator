# Checkpoint C8 — Fabrication Cell

**Дата:** 2026-07-31
**Статус:** ACCEPTED
**База:** `C7 @ 923bfe1`
**Рекомендуемая ветка:** `feature/c8-fabrication-cell`

## Цель

Создать первую производственную ячейку, которая принимает реальные `ItemInstance`, резервирует и расходует сырьё через C2A/C2B authority boundary, выпускает новые предметы с проверяемым происхождением и передаёт их обратно в обычный Item Graph и C3 BuildPlan.

## Архитектурная граница

```text
versioned FabricationRecipe
        ↓ deterministic input allocation
FabricationJob
        ↓ reserve
C2A ConstructionItemTransactionPlan
        ↓ C2B authoritative commit
real inputs move to machine input container
machine ConstructSnapshot pins active job
        ↓ idempotent work progress
        ↓ complete
single authoritative plan:
  consume reserved inputs
  create fabricated ItemInstance outputs
  update machine ConstructSnapshot
        ↓
normal Item Graph / containers / BuildPlan
```

Очередь хранит управляемое состояние процесса. Материалы, продукт и machine runtime являются авторитетными через Item Graph, shared ledger и `ConstructSnapshot`. Ни recipe catalog, ни queue не создают вторую identity предметов.

## Реализовано

- строгий `ConstructionFabricationRecipe` с неизменяемой версией и checksum;
- versioned recipe catalog с exact replay, conflict и version-gap rejection;
- machine definition, связывающая станок с concrete parts, bonds, C5 capability и C7 utility;
- derived machine profile `ONLINE/DEGRADED/OFFLINE`;
- checksum-pinned job с точными входными и выходными bindings;
- priority queue и idempotent progress operations;
- atomic reservation, completion и release plans;
- частичный расход стека и полное удаление исчерпанного стека;
- выпуск нового item с `fabrication_origin` provenance;
- cancel с возвратом входов в исходные relations;
- crash reconcile после authoritative commit;
- persistence catalog + queue;
- generic fabrication agent;
- проверка изготовленного предмета как входа C3 BuildPlan.

## Расширение C2A

В канонический transaction plan добавлены команды:

```text
FABRICATION_RESERVE
FABRICATION_COMPLETE
FABRICATION_RELEASE
```

В item mutation добавлены purposes:

```text
TRANSFER_FABRICATION_INPUT
CONSUME_FABRICATION_INPUT
CREATE_FABRICATED_ITEM
```

Production C2B adapter остаётся общим: он применяет тот же набор CREATE/UPDATE/DELETE mutations, проверяет Item Graph, записывает shared operation ledger и переводит план в один M0 batch.

## Контрольная ячейка

```text
CNC fabrication cell
├── frame
├── controller
├── spindle
├── input container
├── output container
├── C5 WORKSTATION capability
└── C7 POWER utility

recipe structural-beam v1
├── coolant ×1
├── steel_ingot/S355 ×3
├── work units: 10
└── beam ×1
```

Проверенный поток:

```text
coolant stack 1 → reserved → deleted
steel stack 6 → reserved → quantity 3
beam item → created in output container
machine revision 0 → 1 reserve → 2 complete
beam fabrication_origin pins job, recipe, version, checksum and machine
beam → valid source projection in C3 BuildPlan
```

## Recovery

```text
completion plan committed in C2B
→ process crashes before queue update
→ output and machine last_completed_job_id are authoritative
→ C8 reconcile marks job COMPLETED
→ exact plan replay does not create a second output
```

Integral JSON numbers in item components are compared canonically. Поэтому `100.0` и `100` не вызывают ложный input-precondition mismatch после C2A adapter canonicalization.

## Локальные проверки

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5:              PASS — 204 assertions
C6:              PASS — 218 assertions
C7:              PASS — 225 assertions
C8 contracts:    PASS — 91 assertions
C8 integration:  PASS — 130 assertions
C8 total:        PASS — 221 assertions
Editor parse:    PASS
```

Локально проверенная сумма C1+C2A+C3+C4+C5+C6+C7+C8: **1533 assertions**.

C2B focused, Network N0–M4, полный world regression и main-scene CLI должны быть повторены на полном checkout.

## Gate принятия

```text
C1/C2A/C2B/C3/C4/C5/C6/C7 compatibility PASS
C8 focused PASS — 221 assertions
Network N0–M4 PASS
World regression PASS — 117/117 tests, 120 steps
Main-scene CLI PASS — 6/6
git diff --check PASS
```

## За границей C8

- визуальная анимация станка;
- физическое время обработки и энергопотребление по tick;
- temperature/tool wear/quality simulation;
- сетевой command endpoint и permissions;
- UI очереди;
- автоматическая логистическая сеть между несколькими cells;
- damage/split/repair изготовленных constructs — C9.


## Внешняя приёмка

```text
C8 contracts:     PASS — 91 assertions
C8 integration:   PASS — 130 assertions
C8 total:         PASS — 221 assertions
C1–C7:            PASS
C2B:              PASS — 258 assertions
Network N0–M4:    PASS
World regression: PASS — 117/117 tests, 120 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

Reviewed SHA-256: `977056921d0da4fe148a9496524b90908afe1aafcd3b2d95f7b1fbe1681f477e`. C8 принят как база C9.
