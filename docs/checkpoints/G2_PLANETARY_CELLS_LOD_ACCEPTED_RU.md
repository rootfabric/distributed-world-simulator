# G2 — Planetary Surface Cells + LOD — accepted

**Дата:** 2026-08-08  
**Ветка:** `feature/g2-planetary-cells-lod`  
**Accepted head:** `6319e1e312c7c663d5d05c0806f5a42cf68ad441`  
**Decision:** `ACCEPTED`

Пользователь подтвердил успешный полный checkout test gate перед началом G3.

Зафиксированный baseline G2:

```text
SurfaceCellKey
CubeSphereAddressing
SurfaceLodPolicy
SurfaceLodSelector
SurfaceCellLifecycle
```

Архитектурный инвариант:

```text
LOD != World State
```

G3 начинается строго поверх этого accepted head. Детальная acceptance evidence и focused exact-engine результаты остаются в `G2_PLANETARY_CELLS_LOD_CANDIDATE_RU.md`.
