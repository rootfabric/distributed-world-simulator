# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-D EXECUTE_NOW`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## North Star

ECO остаётся standalone evolutionary-ecology mini-project: landscape + environment/history + initial ancestry должны автономно порождать spatial populations, lineages, succession, migration/extinction и позже trophic webs. Один ecological state meaning должен сохраняться между `INCUBATE_FAST`, `BACKGROUND_COARSE` и `LOCAL_ACTIVE`.

## Accepted chain

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A                ACCEPTED
ECO.CAL1-B                ACCEPTED
ECO.CAL1-C                ACCEPTED
```

Canonical hashes:

- CAL1-A `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- CAL1-C `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`.

CAL1-C proved that crown competition depends on actual pair overlap and neighbour canopy density, while root competition depends on geometrically shared resource zones and normalized claims. Dense root overlap was materially stronger than sparse; deep/shallow shared claims were `0.820512820513 / 0.179487179487` and conserved one.

## Central route

```text
EVO0 — PLANT CAUSAL ECOLOGY
CAL1-A ACCEPTED
        ↓
CAL1-B ACCEPTED
        ↓
CAL1-C ACCEPTED
        ↓
CAL1-D ← CURRENT
lifetime / reproduction / dispersal / disturbance
        ↓
CAL1-E combined mechanism matrix
        ↓
CAL1-F calibration/full-pool robustness
        ↓
EVO1 — PLANT WORLD PROOF
        ↓
EVO2 long-run landscape evolution
        ↓
EVO3 multi-trophic ecosystem
        ↓
EVO4 autonomous regional/planet runner
        ↓
XFER0 EcologyArchive
        ↓ when canonical simulator foundations exist
XFER1 world-generation ecology bridge
        ↓
LIVE local/background continuation
```

## CAL1-D — current work

The current selection surfaces are still too close to instantaneous resource balance. CAL1-D must add lifecycle-scale causal observables without inventing one abstract `tall_bonus` or calibrating magnitudes.

Required independent causal paths:

1. **Size-dependent reproduction** — an immature/small individual cannot realize the same reproductive output as a mature one.
2. **Reserve-constrained seed output** — seed production is limited by current reserve/biomass state, not only the genome's seed-count ceiling.
3. **Release-height dispersal** — for the same seed dispersal trait, greater release height increases potential travel distance through an explicit geometric/flight-time path.
4. **Time-to-maturity** — expensive large morphology and low growth rate delay reproductive onset.
5. **Longevity / structural amortization** — structural investment is interpreted across lifetime rather than only as an instantaneous recurring penalty.
6. **Disturbance survival** — damage depends on disturbance severity and causal morphology/anchoring exposure.
7. **Recovery cost** — surviving damage consumes time/resources before reproduction returns.

### Acceptance principle

CAL1-D does **not** need one lifecycle strategy to win everywhere. It must prove contextual trade-offs such as:

```text
fast growth -> earlier maturity / faster recovery
large release height -> farther dispersal
long lifespan -> more opportunities to amortize structure
high seed ceiling -> useless without maturity/reserves
severe disturbance -> reduced survival/lifetime output
strong anchoring -> better survival under the matched disturbance control
```

All terms must remain separately observable in diagnostics.

## After CAL1-D

CAL1-E combines A/B/C/D mechanisms **without calibration** into strategies × environments × density × disturbance matrix.

CAL1-F is the first stage allowed to tune magnitudes and run full-pool robustness.

After CAL1 closure the branch must immediately prioritize `ECO.EVO1_PLANT_WORLD_PROOF`, not more isolated morphology sophistication.

## Global boundary

Standalone EVO work remains research-only. `XFER1/LIVE` wait for canonical G/ENV/MAT/WQ/SD/TF/POP/LIFE/WB/NX/persistence/authority foundations. ECO does not create private replacements for them.

## Operational resolver

When told `continue ECO`:

1. read North Star and machine roadmap;
2. execute current checkpoint only;
3. preserve accepted hashes;
4. no calibration before CAL1-E mechanism acceptance;
5. after CAL1, move to autonomous Plant World.

Current resolver: `EXECUTE ECO.CAL1-D LIFECYCLE PAYOFFS`.
