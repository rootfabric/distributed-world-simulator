# ECO EVO7 / ECO-VIS2 — Procedural Plant Renderer R1

## Статус маршрута

Принятый predecessor: ECO-VIS1 `57577f5a7798d7e87ac50bb20fa56b74d351a913`.

```text
LS3.0–LS3.FINAL                 CLOSED
ECO-VIS1 Spatial World Viewer  CLOSED
        ↓
ECO-VIS2 Procedural Plants     IMPLEMENTATION CANDIDATE
        ↓
ECO-VIS3 Planet/Biome Viewer
        ↓
LS4
```

## Цель VIS2

Заменить абстрактные population dots на процедурные растения, визуальная морфология которых причинно связана с уже вычисленным состоянием симуляции. Renderer не вычисляет биологию повторно и не становится ecology truth.

Источник визуальных данных после generation 1 — только уже опубликованный LS3.4 `competition_field.evaluations` из публичного LS3.6 Workbench ecology snapshot.

```text
LS3.4 accepted phenotype evidence
  realized_height_m
  leaf_area_index_proxy
  realized_root_depth_m
  realized_root_spread_m
  root_shoot_ratio
  water_satisfaction
  effective_light
  realized_resource_balance
            ↓
VIS2 read-only phenotype adapter
            ↓
procedural plant descriptor
            ↓
VIS2 pure plant renderer
            ↓
pixels only
```

## Generation 0

В generation 0 competition phenotype evidence ещё не существует. VIS2 не подделывает его: каждая существующая особь получает явный `FOUNDER_RECORD_ONLY` neutral sprout marker без `phenotype_hash`. После первого competition generation surviving records обязаны иметь `LS3.4_COMPETITION_PHENOTYPE` evidence.

## Procedural mapping

- `realized_height_m` → высота stem;
- `leaf_area_index_proxy` → размер/число элементов crown;
- `root_shoot_ratio` → пропорции stem/crown;
- `realized_root_depth_m` → глубина debug-root;
- `realized_root_spread_m` → ширина debug-root;
- `water_satisfaction` + `realized_resource_balance` → visual health;
- `lineage_id` → стабильный deterministic plant hue;
- `record_id` → только sub-cell jitter, чтобы несколько особей не лежали в одной точке.

Sub-cell jitter и цвет lineage являются presentation mapping и не входят в ecology identity.

## UI

VIS2 наследует весь VIS1 viewer:

- 32x32 spatial field;
- pan / zoom;
- cell selection;
- environment / population / biome overlays;
- Start / Pause / Reset / +1 / +10;
- world/environment seed + recipe.

Добавлено:

- procedural plants overlay;
- `Show root debug`;
- phenotype evidence counters;
- phenotype sample выбранной клетки.

## Authority boundary

- adapter не импортирует simulation modules;
- plant renderer не импортирует Workbench/ecology;
- VIS2 viewer расширяет accepted VIS1 и не обращается напрямую к LS3.3/LS3.4/LS3.5;
- no genome write;
- no records write;
- no fitness write;
- no mutation/dispersal/recruitment authority;
- no persistence/network authority;
- terminal extinction является валидным пустым renderer state.

## Acceptance R1

Focused exact-double acceptance проверяет:

1. generation 0 = 64 explicit founder markers, 0 fabricated phenotype evidence;
2. generation 1 = every living record backed by LS3.4 phenotype evidence;
3. descriptor phenotype hash и morphology metrics совпадают с LS3.4 exact values;
4. taller phenotype → taller rendered stem;
5. greater LAI → larger crown;
6. deeper/wider roots → deeper/wider root debug geometry;
7. water/resource stress → lower visual health;
8. camera/root debug/selection не меняют ecology/workbench identity;
9. extinction → zero plant descriptors, not renderer failure;
10. source guards preserve presentation-only boundary.

Локальный R1 результат: VIS1 PASS 41/41; VIS2 PASS 59/59 на exact double Godot `4.7.1.stable.double.custom_build.a13da4feb`.

## Запуск Windows

```powershell
.\OPEN_ECO_EVO7_VIS2_PROCEDURAL_PLANT_VIEWER.ps1 -GodotBin 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
```

После открытия нажать `+1`: neutral founder markers сменятся phenotype-driven procedural plants. `Show root debug` включает корневую геометрию.
