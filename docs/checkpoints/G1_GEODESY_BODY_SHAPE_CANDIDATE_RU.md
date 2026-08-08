# G1 — Geodesy + Body Shape — implementation candidate

**Дата:** 2026-08-08
**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Base:** `feature/g0-geo-contracts @ 7632ed576a3c0d9007c0ff1296d1d89cd43756d7`
**Implementation branch:** `feature/g1-geodesy-body-shape`
**Decision:** `IMPLEMENTED CANDIDATE`
**Production worlds changed:** NO
**Production terrain changed:** NO

---

## 1. Scope

G1 вводит provider-neutral geodesy boundary и первую форму тела — гладкую сферу радиуса `6_000_000 m`.

Реализованы:

```text
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
BodyShapeProvider (IBodyShapeProvider boundary)
SphereBodyShapeProvider
GeodesyService
```

Операции:

```text
body_to_geodetic()
geodetic_to_body()
surface_normal()
altitude()
local_tangent_frame()
```

---

## 2. Coordinate convention

Body-fixed sphere convention v1:

```text
+Y              north pole
longitude 0°    +X
longitude +90°  +Z
latitude         [-90°, +90°]
longitude        [-180°, +180°)
```

At exact poles longitude is canonicalized to `0°`, so one physical pole does not receive infinitely many serialized identities.

Local tangent basis is explicit:

```text
Up      = body-shape surface normal
East    = increasing longitude tangent
North   = East × Up
```

Therefore the ordered basis `East, Up, North` is right-handed. DTO validation checks unit length, orthogonality and this handedness.

---

## 3. Architectural boundary

`GeodesyService` does not contain sphere-specific radius math. It validates identity/contracts, delegates shape operations to `BodyShapeProvider`, wraps results into canonical JSON-safe DTOs and constructs a stable local tangent frame.

`SphereBodyShapeProvider` is replaceable. Its identity/version are included in `body_shape_manifest_hash` together with `PlanetDefinition.checksum`.

G1 intentionally does not modify `GeoKernel`: body shape is a coordinate foundation consumed before future surface-cell/terrain representation layers. G2 may use the service without making LOD part of world truth.

---

## 4. Safety boundaries

G1 does not introduce:

```text
Node / SceneTree dependency in production Geo code
Mesh / renderer dependency
Terrain3D / Voxel dependency
network transport dependency
random generator dependency
planetary LOD
terrain displacement
mountains / rivers / caves
production Moon/Earth replacement
```

---

## 5. Focused acceptance

`tests/procedural/geodesy/g1_geodesy_body_shape_acceptance.gd` covers:

```text
contract exactness and checksums
longitude canonicalization
canonical pole longitude
provider identity/version binding
body-shape provenance hash
equator roundtrip
north/south pole roundtrip
arbitrary geodetic roundtrip
positive and negative altitude
unit surface normals
stable Up/East/North
orthonormal tangent frame
E × U = N handedness
double-precision coordinate retention
NaN/INF rejection
center-of-body rejection
body identity mismatch
source dependency boundaries
```

Focused runners:

```text
RUN_G1_GEODESY_TESTS.ps1
RUN_G1_GEODESY_TESTS.sh
```

Full Windows gate:

```text
RUN_G1_FULL_ACCEPTANCE.ps1
```

It runs focused G1, the existing world/core regression, current-run `:9081` noise audit and `git diff --check` against G0.

---

## 6. Gate

Candidate can become `G1 ACCEPTED` only after the exact Godot double build confirms:

```text
headless editor import PASS
G1 focused PASS
full world/core regression PASS
Breakpoint runtime :9081 collision noise 0
git diff --check PASS
```

Then G2 may start:

```text
feature/g2-planetary-cells-lod
```

G2 adds addressing/quadtree/LOD lifecycle only; it must not change canonical geodesy semantics.
