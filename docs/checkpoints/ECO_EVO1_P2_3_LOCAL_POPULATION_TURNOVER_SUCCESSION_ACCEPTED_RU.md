# ECO.EVO1 / P2.3 — Local Population Turnover + Succession — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation origin: `b8d6553df911a4eca9765509c018987fe9f5cd4b`.
Parser repair: `87c7838f9d476735ef92db0d662290b58861cd56`.
Canonical tested control head: `7f7ca23f001fed3979900684cc260978b6e781a3`.
Parent: `ECO.EVO1/P2.2 ACCEPTED`, aggregate `633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86`.

## Exact Windows canonical evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

```text
aggregate_hash = 15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e

initial EARLY share        = 0.875000000000
initial BANKED share       = 0.125000000000
BANKED pre-change share    = 0.199612211554
BANKED final shade share   = 0.964707699557
BANKED final open share    = 0.369379521845
shade_delta                = 0.595328177712
banked_gain_after_shift    = 0.765095488003

seed-bank reactivated      = 48
reproduction events        = 15
emitted seeds              = 325

short-life mortality       = 0.050232535701
long-life mortality        = 0.028476366298
max biomass kg/m2          = 0.101663621317
max adult cohorts          = 17
max bank cohorts           = 31
top lineage changed        = true
```

Acceptance: `PASS (168 assertions)`. Fresh-process replay A and B both returned the exact same aggregate hash.

## Meaning

P2.3 closes the first self-renewing local plant population loop:

```text
adult cohorts
  -> lifespan/resource turnover
  -> CAL1-D reproduction
  -> P2.1 dispersal
  -> P2.2 recruitment + seed bank
  -> new adults + persistent seed memory
  -> repeat
```

Succession is demonstrated continuously by abundance shares: the BANKED lineage gains strongly after the open-to-shade history and ends much higher than in the unchanged open control. This is caused by inherited life-history/resource traits and history, not a biome/species table.

The matched lifespan control also confirms causal turnover direction: the short-lived strategy accumulates more adult mortality than the otherwise matched long-lived strategy.

## Historical parser repair

The first Windows attempt stopped before execution because preload alias `Engine` shadowed Godot native class `Engine`. The repair renamed only the alias to `PopulationEngine`; no ecological formula or threshold changed. The repaired runner added a parser/preload preflight before the long parent regression chain.

## Boundary

P2.3 remains local. Outside-domain seeds are counted only as export; no neighbour graph, patch routing, colonization topology or cross-patch insertion exists here.

Therefore:

```text
P2.3 = ACCEPTED
P2.4 = EXECUTE_NOW
```

Next: `ECO.EVO1 / P2.4 Patch Colonization / Isolation / Migration`.
