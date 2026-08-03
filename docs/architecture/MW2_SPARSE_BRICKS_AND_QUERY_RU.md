# MW2 — иерархические matter cells, sparse bricks и canonical query service

**Checkpoint:** `v17.2.0-simulation-mw2-sparse-bricks`
**Статус поставки:** implementation candidate
**Base:** принятый `v17.1.0-simulation-mw1-fixed-seed-asteroid`
**Ветка:** `feature/mw2-sparse-bricks`
**Следующий этап:** MW3 — локальный mesh, collision и streaming laboratory

## 1. Назначение

MW2 добавляет первый материализуемый слой над процедурным астероидом MW1. Полное тело по-прежнему не разворачивается в voxel array. Каноническая база остаётся процедурной, а память выделяется только для явно запрошенных cells.

```text
MW1 procedural field
        ↓ fallback
MatterQueryService
        ↑ exact lattice read
SparseMatterBrickStore
```

MW2 не меняет геометрию астероида. Materialized brick является детерминированным снимком базового генератора и подготавливает границу для будущих persistent mutations.

## 2. Root bounds теперь являются доказуемым контрактом

MW1 использовал фиксированный root radius `1450 m`. MW2 связывает его с параметрами генератора.

Профиль вычисляет консервативную нижнюю границу:

```text
profile_required_radius =
    reference_radius × max(axis_scale)
  + Σ(surface_noise_amplitudes)
  + numerical_margin
```

Конфигурация генератора дополнительно учитывает каждую `ADD_LOBE` feature:

```text
feature_required_radius =
    |feature_center|
  + max(feature_radii)
  + numerical_margin
```

Итоговый root обязан быть не меньше максимума этих значений. Нестандартный профиль или feature catalog больше не может пройти валидацию, если вещество потенциально выходит за root bounds.

## 3. Иерархическая адресация

MW2 повторно использует принятый `SimulationCellAddress`. Matter grid является body-fixed octree:

```text
universe_id:   planet-simulator
instance_id:   matter-lab
space_id:      asteroid-mw0
grid_id:       matter-grid-mw2
grid_revision: 1
root_id:       asteroid-mw0-root
branching:     2 × 2 × 2
max_level:     5
root cube:     [-1450, +1450] m по каждой оси
```

Child index кодирует знаки координат:

```text
bit 0 → +X
bit 1 → +Y
bit 2 → +Z
```

На точной разделяющей плоскости применяется единый tie-break: точка принадлежит положительной половине. Это исключает зависимость адреса от порядка обхода соседей.

`MatterCellGrid` предоставляет:

- root address;
- parent/child navigation;
- детерминированные bounds;
- position → address;
- containment validation;
- запрет child indices вне octree диапазона `0…7`.

## 4. Brick layout

В MW2 одна cell материализуется в один brick.

```text
interior cells per axis: 8
interior lattice points: 9
one ghost sample per side: 2
sample axis count: 11
sample count: 11³ = 1331
sample order: X fastest, then Y, then Z
```

Адрес brick строится из:

```text
SimulationCellAddress
storage_level = cell.level
brick_x = brick_y = brick_z = 0
```

Такое ограничение намеренно. Оно проверяет hierarchy, seams и sparse allocation до появления нескольких bricks внутри одной cell.

## 5. Ghost samples

Ghost samples нужны только как производное представление для meshing и collision следующего этапа. Они не являются отдельным persistent state.

Позиция sample вычисляется из body-local bounds cell и spacing. Для внутренних boundary points используются exact `minimum_m` и `maximum_m`, а не повторное накопление шага. Поэтому две соседние cells получают битово одинаковую координату общей грани.

Для пары соседних bricks выполняются три равенства:

```text
left interior max == right interior min
left positive ghost == right first interior step
left previous interior == right negative ghost
```

Сравниваются SDF, occupancy, composition, density, integrity, temperature, porosity и flags.

## 6. Materialization

`MatterBrickMaterializer`:

1. валидирует body, generator profile, feature catalog и grid profile;
2. вычисляет cell bounds один раз;
3. проходит lattice в каноническом порядке;
4. запрашивает MW1 sampler в body-fixed coordinates;
5. создаёт MW0 `MatterBrickSnapshot`;
6. связывает snapshot с exact body checksum, generator version и seed.

Snapshot ID детерминированно выводится из brick address и state revision.

MW2 materialization не является мутацией. Revision `0` означает снимок procedural base. Более высокие revisions уже поддерживаются storage boundary, но их содержимое начнёт меняться только в MW4.

## 7. Sparse store

`MatterSparseBrickStore` — headless `RefCounted`, не использующий `Node`, mesh, scene или network API.

Публичный API хранения намеренно использует предметные имена, не пересекающиеся с базовыми методами `Object`:

```text
put(snapshot)
get_snapshot(address)
has(address)
erase(address, expected_revision)
```

Имя `get` не используется: в Godot 4.7.1 оно конфликтует с унаследованным `Object.get()` при статическом разрешении метода через preload-инстанс.

Гарантии:

- после configuration store пуст;
- allocation происходит только через `put(snapshot)`;
- snapshot копируется при записи и чтении;
- lower revision отклоняется;
- одинаковая revision идемпотентна только при совпадении checksum **и строгого DTO**, включая Variant-типы;
- одинаковая revision с другим checksum конфликтует;
- generator/body/grid mismatch отклоняется;
- content hash зависит от отсортированного списка materialized entries.

Store пока in-memory. Persistence и compaction относятся к MW5.

## 8. Canonical query service

`MatterQueryService` является единой точкой чтения MW2.

### Arbitrary point query

```text
query(body-local position, requested level)
```

Если точка совпадает с lattice point уже materialized brick, источник результата:

```text
MATERIALIZED_BRICK
```

В остальных случаях:

```text
PROCEDURAL_BASE
```

MW2 намеренно не выполняет скрытый nearest-neighbour snap и не интерполирует состав. Off-lattice query остаётся точным запросом MW1 sampler. Это предотвращает изменение канонического результата из-за текущего storage resolution.

### Cell lattice query

```text
query_cell_lattice(cell_address, x, y, z)
```

Этот запрос предназначен для будущих mesh/collision workers. Он читает exact sample из materialized snapshot или воспроизводит ту же точку из procedural base.

Каждый ответ оформляется checksum-protected `MatterQueryResult` с:

- body and frame identity;
- body definition hash, grid profile hash, generator version и seed;
- local position;
- requested cell level;
- source;
- cell and brick address;
- lattice index;
- state revision;
- canonical `MatterSample`.

## 9. Что MW2 не делает

В этап не входят:

- mesh и Transvoxel;
- collision shapes;
- runtime asteroid scene;
- streaming around camera;
- mutations, бурение и deposition;
- Item Graph transfer;
- persistence;
- raycast и nearest-surface query;
- connectivity и fragmentation;
- Moon integration;
- network authority.

Raycast и surface query остаются в roadmap, но их правильнее добавить вместе с local streaming/mesh потребителями в MW3, а не расширять MW2 до общего spatial API.

## 10. Focused gate

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_MW2_SPARSE_BRICKS_TESTS.ps1 -GodotPath $godot
```

Проверяются:

- feature-aware root bounds;
- grid profile contract;
- octree parent/child и position mapping;
- deterministic boundary tie-break;
- flat lattice round-trip;
- все 1331 lattice coordinates;
- deterministic brick materialization;
- shared face и обе ghost overlap полосы на materialized bricks;
- bit-identical lattice seams для пяти вложенных sibling-пар до level 5;
- sparse allocation и revision fences;
- procedural fallback;
- materialized exact-lattice precedence;
- отсутствие скрытого off-lattice snapping;
- foreign body/grid rejection;
- отсутствие runtime/presentation dependencies.

Статическая топология focused-профиля: `7470 assertions`; фактический результат фиксируется только независимым запуском Godot double.

## 11. Gate результата

```text
Untouched asteroid allocates zero bricks.
Requested cells materialize independently.
Adjacent bricks expose identical shared and ghost samples.
Exact stored lattice samples override procedural fallback.
Off-lattice queries remain exact procedural samples.
No existing Moon or production runtime file changes.
```
