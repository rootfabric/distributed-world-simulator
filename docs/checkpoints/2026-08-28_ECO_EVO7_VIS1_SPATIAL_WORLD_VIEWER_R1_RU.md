# ECO EVO7 / ECO-VIS1 — Spatial World Viewer R1

## Статус маршрута

`LS3.FINAL` принят на immutable candidate `a7e3f81ee10c70757d3604a50f8cf98258b50964` после Project Control #1450 / run `33165946762` SUCCESS. VISUAL ECOLOGY CHECKPOINT открыт.

```text
LS3.0–LS3.FINAL                 CLOSED
        ↓
ECO-VIS1 Spatial World Viewer  IMPLEMENTATION CANDIDATE
        ↓
ECO-VIS2 Procedural Plants
        ↓
ECO-VIS3 Planet/Biome Viewer
        ↓
LS4
```

## VIS1 scope

VIS1 не добавляет экологической логики. Это presentation-only Godot viewer над LS3.6 Workbench public facade.

Реализовано:

- интерактивная карта 32x32 / 1024 cells;
- pan camera через MMB/RMB drag;
- wheel zoom `0.45x..4.0x`;
- выбор клетки LMB;
- environment / population / biome overlays;
- выбор конкретного overlay metric;
- abstract population markers поверх cells;
- panel выбранной клетки: physical environment, population, lineage richness, biome и active overlay;
- Start / Pause / Reset / +1 / +10;
- world seed / environment seed / recipe counterfactual controls через Workbench;
- viewer camera/selection не входят ни в ecology hash, ни в Workbench causal hash.

## Authority boundary

`SpatialCanvas` вообще не импортирует Workbench/ecology. Viewer импортирует только LS3.6 Workbench и environment recipe registry для UI. Он не вызывает LS3.3/LS3.4/LS3.5 напрямую, не редактирует genome/records/fitness, не имеет persistence/network path.

## VIS1 acceptance

1. UI содержит 1024-cell world view.
2. Camera pan/zoom/selection работают и не меняют ecology/workbench identity.
3. Environment/population/biome overlays идут через public Workbench projection facade.
4. Cell observation использует только read-only Workbench snapshots.
5. Population markers являются presentation-only aggregate dots.
6. +1 реальной эволюции обновляет world view и ecology state.
7. Physical counterfactual controls идут через Workbench and reset generation.
8. Source guards не допускают ecology authority bypass.
9. Full LS3.FINAL regression остаётся green.

## Запуск

```bash
GODOT_BIN=/path/to/godot.linuxbsd.editor.double.x86_64 ./OPEN_ECO_EVO7_VIS1_SPATIAL_WORLD_VIEWER.sh
```

Управление: `LMB` — select cell, mouse wheel — zoom, `MMB/RMB drag` — pan.
