# C20 — Logistics and Construction Economy

**Статус:** ACCEPTED
**База:** принятый C19
**Рекомендуемая ветка:** `feature/c20-logistics-construction-economy`

## Цель

Связать C19 agent goals с реальными поставщиками, складами, перевозчиками, подрядчиками, salvage market и многоступенчатыми C8 production chains. Экономический слой не создаёт второй Item Graph: предметы сохраняют `item_instance_id`, а delivery/production mutations должны завершаться через существующие C2B/C8/C12/C17 boundaries.

## Канонический поток

```text
C19 BOM line PROCURE
→ offers + routes + deadline + budget
→ landed-cost selection
→ atomic stock reservation + escrow
→ multi-leg shipment
→ C2B-compatible item transfer
→ C19 BOM fulfillment
```

## Реализовано

- immutable procurement offers;
- procurement orders с goods/transport/labor/energy breakdown;
- warehouse state и atomic item reservations;
- multi-leg routes и shipment receipts;
- escrow hold/settle/refund с exact replay;
- contractor bids, capability matching и milestone contracts;
- fixed-price/auction salvage listing contract;
- C8-validated multi-cell production chains;
- deterministic economy planner по полной landed cost и deadline;
- persistence coordinator/ledger/warehouse;
- operation ID conflict protection.

## Инварианты

1. Item identity не меняется при продаже или перевозке.
2. Недостаток stock после escrow приводит к полному refund.
3. Order не может быть доставлен дважды.
4. Settlement происходит только после transfer result.
5. C19 line отмечается fulfilled только после фактической delivery.
6. Contractor получает средства только после outcome verification.
7. Production-chain stage pin-ит C8 recipe checksum, machine и output IDs.
8. Restart/replay не дублирует escrow, shipment, fabrication или settlement.

## Focused-профиль

```text
C20 contracts:    PASS — 38 assertions
C20 integration:  PASS — 76 assertions
C20 total:        PASS — 114 assertions
```

## Внешний gate

```text
C2B:               258 assertions
C9:                204 assertions
C17/C18/C19:       PASS
Network N0–M4:     PASS
World regression:  141/141 tests, 144 steps
Main-scene CLI:    6/6
```


## Внешняя приёмка

```text
C20 focused:      PASS — 114 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17–C19:          PASS
Network N0–M4:    PASS
World regression: PASS — 141/141 tests, 144 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
Manifest:         50/50
```
