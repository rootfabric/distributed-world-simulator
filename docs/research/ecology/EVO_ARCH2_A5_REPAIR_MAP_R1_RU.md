# EVO ARCH2 A5 — Repair Map R1

Дата: 2026-09-06  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Repair: `RM-A5-01`

## Finding

Implementer self-review после первой публикации `713f69f1...` обнаружил, что `OrganismLifeStateV1` отдельно валидировал metabolic ledger и accepted A2 development state, но не связывал cumulative `resource_ledger.growth_transferred` с `development.received`. Поэтому специально согласованный внутри каждого compartment snapshot мог скрыть cross-compartment рассинхронизацию.

## Repair

Добавлен обязательный инвариант для каждого `BodyGraphV1.RESOURCES` channel:

```text
resource_ledger.growth_transferred[channel]
==
development.received[channel]
```

A5 создаёт A2 development state с нулевым `received`, поэтому cumulative A2 receipts обязаны происходить только через оплаченный A5 growth transfer.

## Regression witness

Exact test создаёт snapshot, который сохраняет внутренний A5 conservation (`growth_transferred +1`, `metabolic_reserves -1`), но не меняет A2 `received`. Snapshot обязан fail-closed с `LIFE_A2_TRANSFER_material_mg`.

Любые Reviewer/Verifier verdicts на `713f69f1...` после этого repair являются historical/stale. Нужны fresh exact gates нового HEAD.
