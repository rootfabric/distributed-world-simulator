# G3 — Mega Casual Macro Surface — ACCEPTED

**Дата:** 2026-08-08
**Accepted branch:** `feature/g3-casual-macro-surface`
**Accepted head:** `bc58f650ffb43775667bf0d07cb361a98a40d294`
**Decision:** `ACCEPTED`

Пользователь подтвердил успешный полный G3 acceptance gate перед началом G4.

Зафиксированы инварианты:

```text
canonical macro geography != LOD
macro provider != renderer
macro provider != SurfaceCellKey
body-fixed point -> stable macro height
provider parameters -> provenance
```

G4 строится поверх этого accepted baseline и не имеет права переписывать `casual_macro_terrain_provider_v1.gd`, `GeoKernel` или G2 addressing/LOD.
