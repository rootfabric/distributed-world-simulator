# EVO ARCH2 A5 — Repair Map R14

Дата: 2026-09-09  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## RM-A5-27 — Exact paid-parent state provenance

Fresh review показал, что compact `origin_receipt`, содержащий только `parent_state_hash` и самодекларируемые summary-поля оплаты, остаётся forgeable. Атакующий мог построить seed-shaped child ID, заявить policy endowment, придумать синтаксически корректный 64-hex parent hash, согласованно заполнить schedule/payment summary и пересчитать child state hash. Это не доказывало существование реального оплаченного parent state.

### Repair

`PARENT_TRANSFER` receipt теперь содержит exact paid parent-state preimage:

```text
origin_receipt = {
  schema,
  blueprint_hash,
  parent_id,
  sequence,
  birth_tick,
  position_mm,
  endowment,
  parent_state_hash,
  parent_state
}
```

`parent_state` — exact deep copy состояния родителя, возвращённого тем же reproduction transition, который породил propagule.

При persisted admission `_validate_origin_receipt()`:

1. требует `parent_state` как Dictionary;
2. реконструирует canonical propagule из child state + receipt;
3. повторно вызывает `validate_parent_transfer_witness(...)`;
4. этот validator выполняет полный `LS.validate(parent_state, blueprint)`;
5. пересчитывает `LS.state_hash(parent_state, blueprint)` и сравнивает его с `parent_state_hash`;
6. проверяет parent ID, latest paid sequence window, birth tick, position и `REPRODUCED` event;
7. parent reproduction ledger и maintenance/resource causality тем самым проверяются как часть exact parent state, а не как self-asserted child receipt summary.

Следовательно, произвольный hash, valid founder без reproduction, conservation-preserving unpaid-parent tamper с пересчитанным hash и compact synthetic summary больше не являются достаточным provenance proof.

### Executable controls

Обновлён:

```text
validation/ecology/evo_arch2_a5/rm_a5_23_parent_transfer_state_provenance.gd
```

Добавлен:

```text
validation/ecology/evo_arch2_a5/rm_a5_27_exact_parent_state_receipt.gd
```

RM27 oracle проверяет:

- arbitrary 64-hex без parent preimage → reject;
- serialize/deserialize такого forge → reject;
- exact valid founder parent без paid reproduction → reject;
- real funded parent reproduction → propagule → exact materialization → PASS;
- persisted child сохраняет exact parent preimage → PASS;
- receipt hash, не совпадающий с exact parent preimage → reject;
- coherent unpaid parent-state tamper + recomputed hash → reject.

### Ограничение текущего research contract

Exact parent-state proof образует рекурсивную provenance chain, если родитель сам был `PARENT_TRANSFER`. Это намеренно допустимо только в bounded research A5. Данный repair не заявляет cryptographic signature, external authority или production lineage registry. Если fresh review обнаружит, что размер/depth этой цепочки нарушает bounded lifecycle contract, это будет отдельный новый blocker и отдельный bounded repair, а не основание считать RM27 доказанным автоматически.

## Acceptance

После этого документа product subject должен быть frozen. A5 не считается ACCEPTED до одновременного выполнения:

1. fresh exact canonical verifier на одном exact HEAD/TREE;
2. fresh independent review того же exact subject;
3. zero blocking findings;
4. сохранение A4/A0-A3/VIS5 regressions и bounded research scope.