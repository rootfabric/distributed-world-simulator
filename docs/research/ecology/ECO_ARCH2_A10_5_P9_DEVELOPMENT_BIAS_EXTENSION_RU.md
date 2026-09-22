# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P9 DEVELOPMENT_BIAS canonical extension

Статус: **IMPLEMENTED IN REPAIR R2; exact verification pending**. Дата обновления: 2026-09-22.

Этот документ начинался как STOP/proposal: workbench не имел права создавать собственный mutation engine. R2 реализует требуемое расширение в canonical A3/A5 слоях, поэтому Polygon остаётся consumer'ом общей семантики.

## 1. Реализованный A3 contract

`scripts/research/ecology/v2/genome_mutation_v1.gd`:

- `BIAS_SCHEMA = dws.ecology.genome-mutation-bias.v1`;
- `validate_bias(bias)` допускает только имена из закрытого `OPERATORS`;
- веса — bounded non-negative integers, суммарный вес > 0;
- `mutate_with_bias(parent, seed, bias)` детерминированно выбирает существующий оператор и затем вызывает обычный `mutate()`;
- bias не добавляет roles/actions/операторов и не обходит `Genome.validate`.

Фактическая форма:

```text
{
  schema: dws.ecology.genome-mutation-bias.v1,
  name: organization/<profile>,
  version: 2,
  operator_weights: { <existing A3 operator>: weight }
}
```

## 2. A5 admission и наследование

R1 уже добавил `genome_mutation_receipt_v1.gd` и receipt-backed parent transfer. R2 связывает A3 bias с этим же путём:

`EcologyRuntimeV1.admit_propagules`
→ `Mutation.mutate_with_bias`
→ child blueprint
→ `GenomeMutationReceipt.issue(..., bias_hash)`
→ `Lifecycle.materialize_propagule`
→ `LifeState.validate_mutated_parent_transfer`.

Silent fallback на parent genome отсутствует: невалидный mutation/bias/receipt останавливает tick fail-closed.

## 3. OrganizationProfile

`scripts/ecology/workbench/organization_profile_v1.gd`, VERSION=2:

- FREE/CUSTOM — VISUAL_ONLY;
- SOFT/EARTH_LIKE/NMS_LIKE — DEVELOPMENT_BIAS;
- `canonical_bias(profile)` возвращает A3 bias;
- `apply_development_bias(profile)` возвращает `APPLIED_CANONICAL_BIAS`;
- visual profile остаётся presentation-only и не меняет simulation state.

Preset'ы задают только broad prior над существующими A3 operators. Это не species/archetype templates.

## 4. Инварианты R2

1. Новый оператор через profile невозможен: `MUTATION_BIAS_OPERATOR`.
2. Одинаковые parent + seed + bias дают одинаковый selected operator/event.
3. Mutated child входит в lineage только через sealed receipt.
4. Receipt содержит `bias_hash`, поэтому provenance связывает наследуемую мутацию с canonical profile semantics.
5. Conservation, A4 ownership и A6 feedback не зависят от profile.
6. FREE не включает development bias.
7. Visual rendering остаётся non-causal.
8. Polygon не владеет отдельным mutation engine.

## 5. Acceptance coverage

- `test_organization_profile.gd`: bias validation, deterministic selection, unknown-operator rejection, FREE behavior.
- `test_final_polygon_e2e.gd`: executable SOFT/EARTH_LIKE/NMS_LIKE controller path.
- `test_final_polygon_e2e.gd` S9/S10: реальное reproduction + inherited mutated genome + mutation receipt; genesis conservation anchor остаётся неизменным.
- A3/A5 regressions входят в полный A10.5 exact suite.

До exact PASS на frozen R2 HEAD документ фиксирует implemented contract, но не является independent verification evidence.
