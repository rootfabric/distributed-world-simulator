# G7.2 Composition / Provenance — ACCEPTED

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g7-semantic-field-fabric`
**Tested runtime head:** `70d9a78d8f176ce532412a64afbbcb2592623720`
**Engine:** `Godot 4.7.1.stable.double.custom_build.a13da4feb`

## Решение

```text
G7.2 Composition / Provenance: ACCEPTED
```

Полный Windows gate завершился:

```text
G7.2 FULL ACCEPTANCE: PASS
Global revision: GLOBAL-P0-2026-08-08-R1
G7.1 ACCEPTED ancestor: PASS
G7.2 composition scope: PASS
Deterministic bundle + provenance receipt: PASS
World/core regression: PASS
Working tree: CLEAN
```

`main_scene_cli_all` также завершился `6 PASS / 0 FAIL`.

## Принятая композиция

```text
G3/G5/G6 partial adapter results
              │
              ▼
    SemanticFieldComposerV1
              │
              ├─ SemanticFieldBundle
              └─ SemanticFieldCompositionReceipt
```

Принята строгая политика:

```text
semantic-composition-policy/require-complete-v1
```

Она запрещает:

```text
missing requested fields
duplicate field ownership
duplicate adapter ids
unrequested contributions
```

Входные adapter results нормализуются по `adapter_id`; перестановка эквивалентных входов не меняет bundle/receipt checksum.

## Provenance

Composer не переписывает source semantics. Receipt фиксирует:

```text
query checksum
bundle checksum
adapter id/version
field ids
sample checksums
upstream provenance checksums
```

Таким образом, G5 `FeatureId`, G6 `FluidRegionId` и G3 provider identity продолжают принадлежать upstream и сохраняются через исходные sample provenance.

## P0

```text
composer != WorldQuery foundation
composer != SurfaceCell / LOD identity
composer != Authority / Interest
composer != Persistence / Network
composer != Material Ontology
composer != Scheduler / Cache owner
composer != Geomorphology
receipt != world identity
```

G7.2 не менял G3/G5/G6 runtime, Hydrology, Matter, Network или global program config.

## Следующий checkpoint

```text
G7.3 — Cross-Cell / Cross-LOD Invariance
```

G7.3 должен доказать, что canonical semantic values, sample/provenance checksums, bundle composition и upstream identities не зависят от representation SurfaceCellKey и LOD.
