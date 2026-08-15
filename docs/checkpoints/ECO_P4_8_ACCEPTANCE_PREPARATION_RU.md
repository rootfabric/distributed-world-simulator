# ECO P4.8 — P4 Acceptance Preparation

Статус: `PREPARATION_READY / P4.7 BOUNDED ROTATING CANONICAL SOAK PENDING`.

P4.8 не добавляет новой runtime-семантики. Это только финальный control manifest поверх уже принятых P4.1–P4.6 и будущего принятого P4.7.

## Уже зафиксировано

- exact accepted validation blobs P4.1–P4.6;
- exact P4.7 bounded rotating canonical-ready validation, runner и soak-test blobs;
- fail-closed pre-acceptance runner `RUN_ECO_P4_8_PREACCEPTANCE_TESTS.ps1`;
- запрет принимать P4.7 по импликации из P4.8;
- запрет принимать P4 без frozen `soak_hash` и `final_interest_hash` P4.7;
- обязательные P4.7 counts: 8 regions, 12 cycles, 8 ecology generation steps, 4 handoffs, 12 persistence round-trips, 12 client updates, 14 interest projections, 3 restart reconstructions;
- full 8-region fanout order-identity check;
- internal non-canonical phase heartbeat для диагностики long-running exact Windows run.

Текущие P4.7 R8 pins:

```text
soak test  = 49821079787479212feb78a10a4703bc52ba89b3
runner     = 5d44dead6bf9bcb5f921e3baf4852acc54adff2c
validation = 8d1f96f34cf5b4095323ac5d1a99d8053280a255
```

## Остаточный путь

1. Прогнать exact committed P4.7 A/B bounded rotating soak.
2. Зафиксировать byte-identical output, `soak_hash`, `final_interest_hash`, exact counts и debt bound.
3. Сделать отдельный P4.7 lifecycle acceptance commit.
4. Перепривязать P4.8 final manifest к accepted P4.7 validation/hash identities.
5. Выполнить final manifest gate.
6. Только после этого записать P4 aggregate acceptance lifecycle commit.

P4.8 не является scheduler, runtime authority, network transport или gameplay integration layer.
