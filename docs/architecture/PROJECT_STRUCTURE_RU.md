# Структура проекта v11

## Каталоги

```text
lunar-world-double-godot/
├── assets/
│   └── textures/generated/
├── docs/
│   ├── architecture/
│   ├── contracts/
│   ├── plans/
│   └── terrain/
├── scripts/
│   ├── app/
│   │   └── lunar_app.gd
│   ├── ui/
│   │   └── lunar_hud.gd
│   ├── actors/
│   │   ├── player/
│   │   └── spectator/
│   ├── world/
│   │   ├── moon_world.gd
│   │   ├── terrain/
│   │   ├── lod/
│   │   ├── materials/
│   │   ├── coordinates/
│   │   ├── zones/
│   │   └── chunks/
│   └── simulation/
│       ├── entities/
│       └── construction/
├── main.tscn
└── project.godot
```

## Границы модулей

### `app`

Создаёт подсистемы и связывает их. Не содержит генерацию рельефа или правила
адресации.

### `ui`

Только отображает состояние и вызывает публичные команды приложения.

### `actors`

Управляемые объекты. Они получают World API, но не должны знать устройство LOD
или хранение чанков.

### `world/moon_world.gd`

Стабильный фасад мира. Текущий фасад использует процедурную реализацию. В
будущем под ним можно выбрать:

```text
ProceduralTerrainProvider
NasaDemTerrainProvider
HybridTerrainProvider
```

### `world/terrain`

Генерация геометрии, кратеров, камней и физической поверхности.

### `world/lod`

Только политика детализации и streaming-порогов.

### `world/materials`

Материалы и профили отображения.

### `world/coordinates`

Чистые функции преобразования координат. Не зависят от сцены Godot.

### `world/zones` и `world/chunks`

Логическое разбиение симуляции. Здесь не должно быть UI и визуальных материалов.

### `simulation/entities`

Постоянные сущности и реестр. Пока это фундамент без активного gameplay.

## Правила зависимостей

Разрешено:

```text
app → все подсистемы
ui → публичные read-only методы подсистем
actors → world façade
simulation → coordinates/zones/chunks
terrain → lod/materials/coordinates
```

Запрещено:

```text
world → ui
zones → player
materials → simulation
entity registry → HUD
```

## Совместимость

В корне `scripts/` оставлены тонкие wrapper-файлы старых путей. Они нужны только
для мягкого обновления предыдущих архивов. Новый код не должен импортировать эти
wrapper-файлы.

## Следующее разбиение большого terrain-файла

`procedural_moon_terrain.gd` пока остаётся крупным. Его следует разделять только
после стабилизации v11:

```text
terrain/
├── terrain_runtime.gd
├── height/
│   ├── planetary_height_provider.gd
│   ├── crater_field.gd
│   ├── maria_field.gd
│   └── micro_detail_field.gd
├── mesh/
│   ├── global_mesh_builder.gd
│   ├── regional_mesh_builder.gd
│   └── local_mesh_builder.gd
└── rocks/
    ├── rock_mesh_library.gd
    └── rock_scatterer.gd
```

Не следует выполнять это механически за один большой коммит: каждый извлечённый
модуль должен сопровождаться контрольными snapshot-тестами высоты.
