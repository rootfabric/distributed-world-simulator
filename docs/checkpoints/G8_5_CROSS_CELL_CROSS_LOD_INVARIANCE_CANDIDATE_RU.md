# G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance — Candidate

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

Parent checkpoint: **G8.4 Erosion / Deposition Baseline — ACCEPTED**.

## Цель

Доказать, что полный принятый geomorphology result G8.1→G8.4 является canonical функцией semantic bundle + geomorphology profile и не меняется из-за presentation `SurfaceCellKey`, cube-sphere face или LOD.

G8.5 не добавляет новый terrain generator и не исправляет швы специальной логикой. Это proof-only stage.

## Реальные upstream inputs

Proof строит semantic bundle через принятые production-shaped adapters:

```text
G3 surface provider -> G3 semantic adapter
G5 FeatureGraph valley -> G5 semantic adapter
G6 compiled cross-cell river -> G6 semantic adapter
                         ↓
               G7 SemanticFieldComposer
                         ↓
              accepted G8.4 deformation
```

Поля:

```text
geo/surface-height-m
geo/valley-influence
geo/river-distance-m
geo/river-width-m
```

Synthetic semantic samples для основного invariance proof не используются.

## LOD proof

На одном и том же body-fixed point отдельно вычисляются внешние representation cells для:

```text
LOD 2
LOD 4
LOD 8
LOD 12
```

Ожидается, что cell identities различаются, но остаются идентичными:

```text
SemanticFieldQuery checksum
SemanticFieldBundle checksum
Geomorphology deformation checksum
source_semantic_bundle_checksum
profile_checksum
все пять component_deltas_m
```

`SurfaceCellKey` и LOD не передаются в semantic query или geomorphology runtime.

## Cross-cell / cross-face proof

Для того же world point создаются альтернативные валидные external SurfaceCellKey и cube-face labels. Они намеренно остаются вне canonical query. Повторный semantic + geomorphology evaluation обязан дать тот же deformation checksum.

Отдельно весь canonical G6 river centerline прогоняется через LOD8 addressing. Fixture должен пересечь несколько representation cells и обе стороны PX/PZ seam, а full G8.4 deformation должна успешно вычисляться на control points по обе стороны seam.

## Query-order proof

Перестановка requested field IDs должна canonical-нормализоваться и не менять query, semantic bundle или final deformation checksum.

## Архитектурная граница

G8.5 не создаёт:

- GeomorphologyCellId;
- seam-owned canonical truth;
- LOD-owned terrain truth;
- camera/representation ownership;
- Matter mutation;
- authority/persistence/network ownership.

## Acceptance

Сначала:

```powershell
.\RUN_G8_5_CROSS_CELL_CROSS_LOD_INVARIANCE_TESTS.ps1 -GodotPath $Godot
```

Focused gate также повторно прогоняет accepted G7.3 и G8.0→G8.4 regressions.

При PASS на том же clean checkout без fetch/reset:

```powershell
.\RUN_G8_5_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Только полный PASS открывает **G8.6 Geomorphology Visual Lab**.
