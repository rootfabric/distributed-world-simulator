# EVO ARCH2 A5 — Repair Map R20

Дата: 2026-09-10  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## Bounded scope

Источник repair — fresh independent Codex review exact subject `041556b9e372afefa7342e153b0c5b724e6769b1` / tree `bbf3f53ad3f927736bc58f666831cb2e8d15168b`.

Repair закрывает только два новых blocking findings этого review. Accepted A0–A4 contracts, production ecology, simulation/network authority, A6 decomposition и A3 mutation/crossover не входят в scope.

## RM-A5-32 — persisted field-intake lifecycle causality

Finding: persisted state мог согласованно увеличить `field_intake`, `assimilated` и `metabolic_reserves`, сохранив conservation equation. Для age-zero `PARENT_TRANSFER` это позволяло заявить массу из A4 allocation, которого физически ещё не было.

Repair:

1. cumulative `field_intake[resource]` для каждого A4 resource ограничен `age_ticks * F.MAX_REQUEST`;
2. следовательно, при `age_ticks == 0` весь field intake обязан быть нулевым;
3. age-zero state также не может заявлять `last_environment_source`;
4. источник bound — существующий A4/A5 executable contract: один lifecycle step формирует не более одного demand на resource, а demand amount bounded `F.MAX_REQUEST`.

Oracle: `validation/ecology/evo_arch2_a5/rm_a5_32_field_intake_lifecycle_causality.gd`.
Он воспроизводит exact reviewer tamper, проверяет serialize/deserialize/runtime admission и per-resource request-cap boundary.

## RM-A5-33 — persistent non-reproductive module maintenance causality

Finding: при `event_count == 0` существующий maintenance floor мог учитывать только root payments. Если A2 ранее создал persistent support module, refund части cumulative maintenance обратно в reserves сохранял conservation, хотя runtime такую историю произвести не мог.

Repair использует только доказуемый нижний предел без реконструкции неперсистируемой полной module-age history:

1. A2 modules persistent;
2. текущие non-root modules, которые не были созданы latest development tick, гарантированно существовали перед этим последним оплачиваемым development tick;
3. поэтому каждый такой модуль добавляет минимум один доказуемый maintenance payment;
4. modules с `MODULE_CREATED` в latest development frame/events не тарифицируются ретроактивно на tick их создания;
5. существующий reproduction-derived floor сохраняется и объединяется с новым conservative floor через `max`, чтобы не double-count доказательства одного и того же module payment.

Oracle: `validation/ecology/evo_arch2_a5/rm_a5_33_nonreproductive_module_maintenance_history.gd`.
Он воспроизводит root-only refund tamper, проверяет fail-closed persistence, conservative positive boundary и отдельно доказывает отсутствие retroactive maintenance для latest-created support module.

## Source diff fence

Source candidate изменяет только разрешённые A5 research paths:

- `scripts/research/ecology/v2/organism_life_state_v1.gd`;
- `validation/ecology/evo_arch2_a5/rm_a5_32_field_intake_lifecycle_causality.gd`;
- `validation/ecology/evo_arch2_a5/rm_a5_33_nonreproductive_module_maintenance_history.gd`;
- A5 Work Order и этот repair map.

Ни один accepted A0–A4 core file, production/simulation/network path или workflow source candidate не изменяется.

## Acceptance

A5 остаётся `READY_FOR_FRESH_ACCEPTANCE`, не `ACCEPTED`.

Следующий gate: canonical exact verifier должен выполнить полный A5 bundle вместе с RM32/RM33, accepted A4/A0–A3 regressions и VIS5 regression на одном final HEAD/TREE. После verifier PASS требуется новый fresh independent review именно этого final subject. Human merge gate сохраняется.
