# G8.2 River Channel Incision — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

G8.2 принят после полного Windows acceptance на tested head:

```text
491fe10877c70c362c14ab595a8a0204165a880a
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Итог полного gate:

```text
G8.1 parent ACCEPTED: PASS
G8.2 river channel incision: PASS
Valley + river composition: PASS
Geomorphology ownership boundary: PASS
World/core regression: PASS
Working tree: CLEAN
G8.2 FULL ACCEPTANCE: PASS
```

Дополнительное regression evidence из финального прогона:

```text
RL3 representation-aware network streaming: 175 assertions PASS
RL3 representation streaming processes: 37 assertions PASS
main_scene_cli_all: 6 PASS / 0 FAIL
lifecycle: STOPPED
world/core regression through NX4: PASS
```

## Принятый контракт

G8.2 использует принятую G8.1 valley deformation на том же semantic bundle и profile, затем добавляет только `river_channel_delta_m`.

```text
half_width_m        = river_width_m * 0.5
normalized_distance = river_distance_m / half_width_m
river_delta_m       = -river_max_depth_m * channel_weight
```

Центр и core-зона достигают профильной максимальной глубины. Во внешней `river_edge_softness_ratio` зоне incision плавно уходит в ноль. На `distance >= half_width` river incision равен нулю.

Принятые инварианты:

- `geo/river-distance-m` — расстояние до canonical G6 centerline;
- `geo/river-width-m` — полная canonical G6 channel width;
- valley component сохраняется без изменения;
- G8.2 добавляет только river-channel component;
- bank/floodplain/erosion-deposition остаются нулевыми;
- результат deterministic и связан checksum-ами source semantic bundle и geomorphology profile;
- G8.2 не владеет SurfaceCellKey, LOD, Matter, authority, persistence, material ontology или network replication.

Следующий этап: **G8.3 Banks and Floodplain Shaping**.
