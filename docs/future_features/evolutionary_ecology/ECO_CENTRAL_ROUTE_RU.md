# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-F IMPLEMENTED CANDIDATE / EXACT WINDOWS ROBUSTNESS GATE`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Accepted chain

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A                ACCEPTED
ECO.CAL1-B                ACCEPTED
ECO.CAL1-C                ACCEPTED
ECO.CAL1-D                ACCEPTED
ECO.CAL1-E                ACCEPTED
```

Canonical hashes:

- CAL1-A `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- CAL1-C `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`;
- CAL1-D `c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`;
- CAL1-E `6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814`.

CAL1-E canonical matrix: `192` rows / `24` contexts, `96` dense interaction rows, `0` sparse interaction rows, multi-member Pareto in all `24` contexts, `2` distinct Pareto signatures.

## Central route

```text
CAL1-A ACCEPTED
   ↓
CAL1-B ACCEPTED
   ↓
CAL1-C ACCEPTED
   ↓
CAL1-D ACCEPTED
   ↓
CAL1-E ACCEPTED
   ↓
CAL1-F ← CURRENT CANDIDATE GATE
calibration + full-pool robustness
   ↓ PASS
CAL1 ACCEPTED / EVO0 CAUSAL FOUNDATION COMPLETE
   ↓
EVO1 / P2.1 Seed Dispersal Kernel
```

## CAL1-F implementation

Implementation head: `e5a42237d025ff0f0e28623b5f9461ed65149874`.

The implementation commit adds exactly five ECO-owned files and modifies no accepted A-E source or runtime path.

### Calibration rule

No empirical external target exists yet, so CAL1-F does not invent one. Selected baseline is `UNITY` only if it survives robustness:

```text
morphology = 1.0
vertical   = 1.0
crown      = 1.0
root       = 1.0
```

Sensitivity envelope is symmetric `±15%` over morphology, vertical-light, spatial crown/root, and all channels together. Small perturbations are allowed to move winners/Pareto membership; they are not allowed to create a completely unrelated regime without failing the robustness gate.

### Sweep surface

```text
phenotype seeds:     5 seeds / 40 contexts / 320 rows
environment:         5 variants per accepted environment / 20 contexts / 160 rows
density:             5 controlled points / 20 contexts / 160 rows
disturbance:         5 severities / 20 contexts / 160 rows
calibration profile: 9 profiles / 72 contexts / 576 rows
strategy pools:      5 pool compositions / 20 contexts
```

Seed `0` reproduces the accepted CAL1-E phenotype event. Seeds `1..4` use distinct deterministic events.

Environment perturbations are ±10% moisture or sunlight around each accepted environment.

Density moves from `0.50m @ 1.00` through the accepted `0.75m @ 0.90` toward the `50m @ 0.15` sparse anchor. Interaction magnitude must be monotonic non-increasing along that controlled sequence.

Disturbance severity runs `0 / 0.1 / 0.2 / 0.5 / 0.9`; survival and post-disturbance seed potential must be non-increasing.

### Robustness classification

CAL1-F accepts only as:

`ROBUST_UNITY_CALIBRATION`.

Important gates:

- exact CAL1-E parent hash;
- seed sweep actually changes deterministic phenotype realization;
- at least 75% seed contexts retain multi-member Pareto fronts;
- environment perturbations retain at least two Pareto signatures;
- zero density monotonicity violations;
- zero disturbance monotonicity violations;
- UNITY recomposition exactly matches accepted CAL1-E metrics;
- ±15% profile envelope has minimum Pareto Jaccard >= `0.25` and mean >= `0.50` versus UNITY;
- all restricted strategy pools retain valid Pareto fronts;
- zero resource pairwise/full-pool contradictions;
- exact same/fresh-process aggregate replay.

If any of these fail, CAL1-F remains open and the finding must be diagnosed. The implementation must not be retuned merely to produce PASS.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_F_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
CAL1-F = IMPLEMENTED_CANDIDATE
CAL1-F != ACCEPTED
EVO1 = BLOCKED
```

After PASS, CAL1 closes. The next executable checkpoint is not more morphology calibration or presentation; it is `ECO.EVO1 / P2.1 Seed Dispersal Kernel`, beginning the autonomous spatial Plant World Proof.

## Global boundary

Standalone EVO remains research-only. `XFER1/LIVE` wait for canonical simulator foundations. ECO does not create private global runtime foundations.

Current resolver: `RUN CAL1-F EXACT WINDOWS CALIBRATION + FULL-POOL ROBUSTNESS GATE`.
