# G1 — fly-in geodesy continuity — exact-engine evidence

**Дата:** 2026-08-08
**Ветка:** `feature/g1-geodesy-body-shape`
**Base:** `feature/g0-geo-contracts @ 7632ed576a3c0d9007c0ff1296d1d89cd43756d7`
**Production runtime changed by this test:** NO

---

## Цель

Закрыть геодезическую часть G1 fly-in gate до появления G2 LOD/streaming.

Тест не проверяет renderer. Он проверяет, что одна и та же точка поверхности при приближении от десятков километров до земли остаётся одной и той же canonical географической точкой и не меняет локальный tangent basis.

---

## Траектория

Фиксированы:

```text
latitude  = 37.25°
longitude = -122.5°
```

Altitude samples:

```text
50 000 m
25 000 m
10 000 m
5 000 m
1 000 m
250 m
50 m
10 m
1 m
0 m
```

На каждом sample проверяются:

```text
GeodeticPosition validation
geodetic_to_body()
BodyFixedPosition validation
body_to_geodetic()
latitude stability
longitude stability
altitude roundtrip
local_tangent_frame()
Up stability
East stability
North stability
radial step continuity
```

---

## Exact-engine result

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
cold editor import:                 PASS
G1 fly-in geodesy continuity:       PASS — 117 assertions
```

До этого тот же isolated harness подтвердил:

```text
G1 deep geodesy smoke:              PASS — 76 assertions
```

Итого isolated G1 evidence включает pointwise geodesy и trajectory continuity.

---

## Что это доказывает

Для гладкой сферы G1 на фиксированной lat/lon:

```text
body-fixed position changes continuously with altitude
restored altitude agrees with requested altitude
surface normal does not rotate while moving radially
East/North/Up basis does not jump during fly-in
sub-meter samples remain stable on the double build
```

Это специально отделено от будущего G2: LOD/cells могут менять representation density, но не имеют права менять эти canonical geodesy semantics.

---

## Full acceptance

Этот evidence не заменяет full project regression. Финальный G1 gate остаётся:

```powershell
.\RUN_G1_FULL_ACCEPTANCE.ps1
```

Focused runner теперь запускает оба теста:

```text
g1_geodesy_body_shape_acceptance.gd
g1_fly_in_continuity.gd
```

После полного PASS можно фиксировать `G1 ACCEPTED` и начинать `feature/g2-planetary-cells-lod`.
