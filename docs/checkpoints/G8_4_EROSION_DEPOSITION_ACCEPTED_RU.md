# G8.4 Erosion / Deposition Baseline — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

G8.4 принят после полного Windows acceptance на tested head:

```text
82cc31429f2bf2ea419bf1b50159838eea51c727
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Финальный gate:

```text
G8.3 parent ACCEPTED: PASS
G8.4 erosion/deposition baseline: PASS
Valley + river + banks/floodplain + erosion/deposition composition: PASS
Geomorphology ownership boundary: PASS
World/core regression: PASS
Working tree: CLEAN
G8.4 FULL ACCEPTANCE: PASS
```

Дополнительное regression evidence:

```text
RL3 representation-aware network streaming: 175 assertions PASS
RL3 representation streaming processes: 37 assertions PASS
main_scene_cli_all: 6 PASS / 0 FAIL
lifecycle: STOPPED
world/core regression through NX4: PASS
```

## Принятый контракт

G8.4 — статический процедурный signed redistribution baseline. Он вызывает принятый G8.3 на том же semantic bundle/profile, сохраняет `valley_delta_m`, `river_channel_delta_m`, `bank_delta_m` и `floodplain_delta_m` и добавляет только `erosion_deposition_delta_m`.

```text
signed_weight = deposition_weight - erosion_weight
erosion_deposition_delta_m = erosion_deposition_max_delta_m * signed_weight * valley_influence
```

Отрицательные значения означают erosion, положительные — deposition. Амплитуда ограничена уже принятым G8.0 profile.

G8.4 не является sediment simulation: он не владеет sediment inventory, mass-conservation ledger, time integration, Matter mutations, persistence, authority, materials или network replication. `geo/fluid-surface-distance-m` не интерпретируется как signed water elevation.

Следующий этап: **G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance**.
