# ECO.EVO1 / P2.5 — Disturbance + Recovery — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `b645ee451dd5c1c2558647c8e50eb293ec80c21c`.

Parent: `ECO.EVO1/P2.4 ACCEPTED`, aggregate `78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97`.

## Purpose

P2.5 adds explicit disturbance-event chronology to the accepted plant ecology chain. It separates event pressure from ecological response and then observes multi-year recovery through surviving adults plus persistent P2.2 seed banks.

No disturbance is encoded as a biome/species modifier.

## Event contract

Each research disturbance event has:

```text
event_id
year
mechanical_severity          0..1
seed_bank_mortality_fraction 0..1
checksum
```

These are independent causal channels. A future storm/fire/flood projection can map physical state into them without changing ECO lineage semantics.

### Adults

Mechanical damage is not a new resilience score. P2.5 calls accepted CAL1-D using realized height/root morphology:

```text
mechanical severity
  -> CAL1-D exposure + anchoring
  -> disturbance survival fraction
  -> surviving / destroyed adult biomass
```

### Seed bank

Seed-bank mortality is an explicit property of the event. Integer seed accounting is exact:

```text
bank_before = bank_after + killed_by_event
```

Surviving banks are rebuilt as valid P2.2 seed-bank cohorts with provenance chained through the event checksum.

## Recovery chronology

After each event, annual recovery reuses accepted semantics:

- P2.2 `advance_seed_bank` for bank decay/germination/recruitment;
- P2.3 `STRESS_MORTALITY_RATE` by reference;
- P2.3 `VEGETATIVE_GROWTH_RATE` by reference;
- accepted ResourceModel for growth/stress;
- accepted single-patch `MAX_BIOMASS_KG_M2` capacity.

No second independent turnover calibration is introduced.

## Controlled experiment

Same initial community and favourable environment are run for eight years as:

```text
CONTROL   no explicit disturbance
MILD      year 1: mechanical=0.35, bank mortality=0.10
SEVERE    year 1: mechanical=0.85, bank mortality=0.35
REPEATED  SEVERE year 1 + mechanical=0.75, bank mortality=0.30 at year 6
```

Two causal lineages start with equal adult biomass and equal bank seed counts:

- `SHALLOW_FAST`: taller, shallow-rooted, faster growth, lower dormancy/shorter bank;
- `DEEP_BANKED`: shorter, deep-rooted, slower growth, higher dormancy/longer bank.

Required evidence:

- severe adult loss > mild adult loss;
- severe seed-bank mortality > mild;
- deep-root lineage mechanical survival > shallow-root lineage under the same severe event;
- every adult and seed-bank event ledger conserves exactly;
- severe event creates immediate biomass loss;
- surviving bank reactivates during recovery;
- single severe run gains biomass after its immediate post-event state;
- second event causes additional damage;
- repeated disturbance final biomass < single severe final biomass;
- all runs remain capacity-bounded and deterministic across fresh processes.

## Strict P2.6 boundary

P2.5 does not implement long-horizon range maps, climate-history biogeography, geographic lineage statistics or regional persistence diagnostics. Those begin in P2.6.

P2.5 also remains research-only and does not claim canonical ENV event generation, Time Fabric, World Lifecycle, Work Budget or persistence ownership.

## Implementation boundary

`122ed0c5f0f08ec36bd4fdec8fda8af1c9e9270b -> b645ee451dd5c1c2558647c8e50eb293ec80c21c` adds exactly five P2.5 research/test files. Accepted P2.4-or-earlier sources and runtime paths are unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_5_TESTS.ps1 -GodotPath $Godot
```

The runner performs parser/preload `--check-only` before the long P2.4 parent regression.

Until PASS:

```text
P2.5 = IMPLEMENTED_CANDIDATE
P2.5 != ACCEPTED
P2.6 = BLOCKED
```
