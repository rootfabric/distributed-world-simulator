# EVO ARCH2 A5 — Repair Map R7

Дата: 2026-09-07  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; production/main/network/Matter authority не изменяются.

## RM-A5-09 — propagule identity must bind to parent + emission sequence

Reviewer обнаружил, что propagule validator проверял `id` и `parent_id` как два независимых identifier. Сохранённую запись можно было переименовать так, чтобы она объявляла другого родителя, но всё ещё проходила materialization.

Исправление:

- propagule получает явный `sequence` — номер offspring в persistent parent sequence;
- canonical ID строится только функцией:

```text
seed/<sha256(parent_id)>/<sequence>
```

- `validate_propagule()` требует точного равенства `id == canonical(parent_id, sequence)`;
- `sequence` ограничен тем же lifetime offspring range, что persistent `propagule_seq`;
- endowment по-прежнему обязан точно совпадать с оплаченной inherited policy;
- `parent_state_hash` остаётся provenance exact parent state после resource debit/counter update.

Это связывает materialized child identity с объявленным родителем и конкретным emission sequence. Без криптографической authority подписи A5 не заявляет adversarial authentication; такой authority остаётся вне research scope.

## RM-A5-10 — cumulative lifecycle ledger is not current stock

Reviewer верно указал, что `assimilated`, `maintenance`, `reproduction_*` и `external_energy_mj` — накопительные totals за жизнь организма. Ограничивать их `B.MAX_STOCK` (лимитом мгновенного compartment stock) неправильно: валидный долгоживущий организм может накопить >1e12 total throughput, оставаясь в допустимых instantaneous reserves.

Исправление разделяет две семантики:

```text
metabolic_reserves + one-shot resource bundles -> B.MAX_STOCK
cumulative lifecycle totals                 -> C.MAX_INT
```

`OrganismLifeStateV1`:

- `initial` остаётся bounded one-shot endowment (`B.valid_stock`);
- `assimilated`, `maintenance`, `growth_transferred`, `reproduction_transferred`, `reproduction_cost` валидируются как cumulative body-resource totals до `C.MAX_INT`;
- `field_intake` уже использует cumulative A4 totals;
- `external_energy_mj` расширяется до `C.MAX_INT`;
- conservation equation остаётся exact integer equality.

`ResourceLifecycleRuntimeV1`:

- добавление в current reserves остаётся fail-closed на `B.MAX_STOCK`;
- накопительные ledger additions используют отдельный `C.MAX_INT` helper;
- все cumulative overflow checks выполняются до принятия state transition.

Acceptance witness проверяет, что cumulative helper/ledger принимают значения `B.MAX_STOCK + 1`, при этом current reserve helper всё ещё отвергает переход за `B.MAX_STOCK`.

После публикации все прежние Reviewer/Verifier verdicts считаются stale. Нужны fresh exact Verifier и fresh independent Reviewer нового exact HEAD.
