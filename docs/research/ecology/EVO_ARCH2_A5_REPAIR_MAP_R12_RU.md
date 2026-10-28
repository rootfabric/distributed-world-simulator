# EVO ARCH2 A5 — Repair Map R12

Дата: 2026-09-09  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## Fresh review subject

Предыдущий fresh independent review проверил:

```text
HEAD 5477a030a23794e2d31663c82edcae6abd6cae85
TREE f91a05ed333692a8486cc80748304f24dd499919
```

и вернул `FIX_REQUIRED` с двумя findings.

## RM-A5-23 — Parent-transfer state provenance seal

Finding: `ResourceLifecycleRuntimeV1.individual()` был founder-only, но нижележащий `OrganismLifeStateV1.create()` всё ещё принимал `PARENT_TRANSFER`. Созданный таким образом state проходил `validate`, `serialize`, `deserialize` и `step_population` без propagule + paid-parent witness.

Repair:

- generic `OrganismLifeStateV1.create()` теперь founder-only;
- введён отдельный `create_parent_transfer(blueprint, propagule, paid_parent_state)`;
- factory сам повторно выполняет exact parent-transfer witness validation и не полагается на underscore/private convention;
- `ResourceLifecycleRuntimeV1.materialize_propagule()` делегирует только этой witnessed factory;
- canonical propagule witness validation перенесён в lifecycle-state contract и runtime делегирует ему;
- persisted state получил обязательный `origin_receipt`;
- founder требует пустой receipt;
- `PARENT_TRANSFER` требует canonical receipt, связанный с policy endowment, full-digest seed identity, position, birth tick, latest paid sequence window, parent state hash и exact cumulative reproduction transfer/cost summary;
- manual origin flip / recomputed state hash without receipt fails closed.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_23_parent_transfer_state_provenance.gd
```

Negative controls включают прямой `LS.create(..., PARENT_TRANSFER)`, ручной dictionary forge, serialize/deserialize, population admission, receipt removal, arbitrary endowment receipt и unpaid parent ledger summary.

## RM-A5-24 — RM22 canonical evidence repair

Finding: semantic RM22 repair был подтверждён Reviewer, но shipped oracle не парсился на canonical Godot 4.7.1 double из-за Variant type inference.

Repair:

- `keep_water`, `keep_energy`, `refund_water`, `refund_energy` получили явный `int` type/cast в обеих probe-секциях;
- `required_paid_ticks` также явно типизирован;
- восстановлен отсутствовавший тринадцатый assertion: deserialize rejection для development-history maintenance tamper.

Canonical expected marker:

```text
EVO_ARCH2_A5_RM22 assertions=13 failed=0
```

## Acceptance rule

Ни RM23, ни RM24 сами по себе не закрывают A5. После freeze нового exact HEAD/TREE обязательны:

1. canonical exact Godot verifier;
2. fresh independent review без наследования предыдущих выводов;
3. zero blocking findings;
4. только затем research acceptance.