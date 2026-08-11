# G8.3 Banks and Floodplain Shaping — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

G8.3 принят после полного Windows acceptance на tested head:

```text
ce8b76f5ba46c3ed105ab6d4ee71ab7d8aadaf50
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Финальный gate:

```text
G8.2 parent ACCEPTED: PASS
G8.3 banks and floodplain shaping: PASS
Valley + river + banks/floodplain composition: PASS
Geomorphology ownership boundary: PASS
World/core regression: PASS
Working tree: CLEAN
G8.3 FULL ACCEPTANCE: PASS
```

Дополнительное evidence:

```text
RL3 representation-aware network streaming: 175 assertions PASS
RL3 representation streaming processes: 37 assertions PASS
main_scene_cli_all: 6 PASS / 0 FAIL
lifecycle: STOPPED
world/core regression through NX4: PASS
```

Принятый контракт сохраняет exact G8.2 valley + river components и добавляет только bank/floodplain shaping. `geo/fluid-surface-distance-m` не интерпретируется как signed water elevation. Erosion/deposition остаётся отдельным следующим компонентом.

Следующий этап: **G8.4 Erosion / Deposition Baseline**.
