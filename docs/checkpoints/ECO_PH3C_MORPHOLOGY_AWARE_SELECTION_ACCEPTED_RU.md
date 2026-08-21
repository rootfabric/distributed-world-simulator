# ECO.PH3C — Morphology-Aware Selection / Competition Convergence — ACCEPTED

Статус: `ACCEPTED`.

Exact Windows gate выполнен на `Godot Engine v4.7.1.stable.double.custom_build.a13da4feb`.

## Parent regressions

- P1C-S4 aggregate: `PASS (15)`;
- PH0: `PASS (63)`;
- PH1: `PASS (128)`;
- PH2: `PASS (107)`;
- PH3: `PASS (217)`.

## PH3C exact evidence

- focused causal competition: `PASS (97 assertions)`;
- fresh-process restart replay: `PASS (6 assertions)`;
- aggregate hash: `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`.

Crown reversal одной и той же morphology-пары подтверждён:

- `SUN`: `CROWN_WIDE` winner, wide share `0.64978120448288`;
- `DRY`: `CROWN_NARROW` winner, wide share `0.31553289557419`.

Другие selection effects:

- `BRANCH_LOW` share `0.67681023488994`;
- `HEIGHT_LOW` share `0.88312054209733`;
- `GIANT_DENSE` share `0.00014414428813`.

Все resource-only A/B controls остаются нейтральными `0.5 / 0.5`; genome, IndividualSeed и accepted P1 resource result внутри каждой пары идентичны. Следовательно, divergence вызван именно принятым PH3 morphology ledger.

## Scope

PH3C доказывает **причинный morphology-aware selection**, но не объявляет unrestricted morphology coexistence. Full-pool diagnostic всё ещё показывает broad compact/low-height advantage. Этот эффект остаётся явным calibration blocker до любой свободной morphology mutation/evolution или species-emergence claim.

PH3C не вводит species classes, renderer truth, network, authority или persistence semantics.

Следующий шаг: `ECO.PH4 — Seed Development Lifecycle`.
