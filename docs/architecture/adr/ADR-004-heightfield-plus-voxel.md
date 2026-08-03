# ADR-004: heightfield для Луны, voxel/SDF для подземных изменений

**Статус:** superseded
**Заменён:** `ADR-017-dynamic-matter-fabric.md`

## Исходное решение

- глобальная Луна и обычная поверхность остаются spherical heightfield;
- траншеи малой глубины могут храниться как surface displacement delta;
- тоннели, пещеры и навесы хранятся sparse voxel/SDF чанками;
- интерьеры базы используют модульную геометрию.

## Почему решение было уточнено

Общий выбор hybrid heightfield + sparse volume остаётся правильным, но ADR-004 не определял:

- канонический источник вещества;
- сохранение массы;
- связь с Item Graph;
- 3D spatial addressing;
- отделение render LOD от storage/simulation LOD;
- полное разрушение малых тел;
- детерминированные пещеры и месторождения;
- миграцию observer-dependent лунного микрорельефа;
- authority, revision, replay и distributed compute boundaries.

ADR-017 заменяет формулу «heightfield плюс voxels» на общую модель процедурного объёма с разреженными persistent mutations. Heightfield остаётся производным дальним представлением, а не каноническим состоянием.
