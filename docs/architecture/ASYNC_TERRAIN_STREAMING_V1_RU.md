# Асинхронная подгрузка рельефа v1

## Задача

До v15 перестройка LOCAL/REGIONAL поверхности выполнялась синхронно. Один кадр
последовательно рассчитывал кратеры, высоты, вершины, нормали, UV, tangents,
камни, `ArrayMesh` и `ConcavePolygonShape3D`. Поэтому суммарная работа в несколько
секунд превращалась в остановку изображения на те же несколько секунд.

Цель v15 — оставить старую поверхность рабочей, а следующую подготовить заранее
в фоновом потоке. Полное время вычислений может остаться большим, но оно больше
не должно целиком находиться на критическом пути одного кадра.

## Три независимые системы разбиения

Нельзя смешивать следующие понятия:

```text
Simulation Zone/Chunk
    persistence, сущности, будущий владелец процесса/сервера

Terrain Streaming Cell
    дискретный центр фоновой генерации локального меша

Render LOD
    GLOBAL / REGIONAL / LOCAL / ULTRA
```

В v15 размер Terrain Streaming Cell равен 512 м. Она не является файлом
сохранения и не является границей физического мира. Это только стабильный адрес,
по которому менеджер решает, когда нужен новый центр детальной поверхности.

## Компоненты

```text
ProceduralMoonTerrain
├── активная поверхность и материалы
├── синхронная генерация для старта/телепорта
├── data-only API построения массивов
└── main-thread API создания Godot-ресурсов

TerrainStreamingManager
├── предсказание следующей cell
├── очередь latest-wins
├── WorkerThreadPool job
├── очередь готовых результатов + Mutex
├── staged commit
├── double-buffer swap
└── performance telemetry

Worker Sampler
└── отдельный off-tree экземпляр генератора
    ├── собственные noise и RNG state
    ├── собственные crater arrays
    └── не обращается к SceneTree
```

## Поток данных

```text
CharacterBody3D position + velocity
              │
              ▼
Predictive target
position + tangent_velocity × prediction_seconds
              │
              ▼
512 m Terrain Streaming Cell
              │
              ▼
TerrainBuildRequest
              │
              ├──────── WorkerThreadPool ────────┐
              │                                   │
              │                         crater catalogs
              │                         height sampling
              │                         vertices/indices
              │                         normals/colors
              │                         UV/tangents
              │                         rock transforms
              │                                   │
              ◄──────── TerrainBuildResult ───────┘
              │
              ▼
Main-thread staged commit
ArrayMesh → collision → rock layers → atomic swap
```

## Что выполняется в фоне

- определение локальных и микрократеров;
- вычисление якоря и локального базиса;
- sampling высоты для LOCAL и при необходимости REGIONAL;
- индексы;
- нормали;
- vertex colors;
- UV и tangents;
- все `Transform3D` для шести слоёв камней.

Фоновая задача возвращает только данные: `PackedArray`, словари и трансформации.

## Что остаётся в главном потоке

Godot-сцена и физический сервер меняются только в главном потоке:

1. `ArrayMesh.add_surface_from_arrays()` для LOCAL;
2. при необходимости два REGIONAL mesh resource;
3. `create_trimesh_shape()`;
4. один `MultiMesh`-слой камней за кадр;
5. добавление готовых узлов и atomic swap.

Параметр `main_thread_commit_budget_ms` является диагностическим бюджетом. Он не
может прервать один атомарный вызов Godot посередине. Если, например,
`create_trimesh_shape()` занимает 180 мс, событие будет отмечено как
`over_budget=true`. Следующее архитектурное решение в таком случае — tiled
collision.

## Состояния

```text
IDLE/ACTIVE
    текущая поверхность готова

QUEUED
    есть latest pending request

GENERATING
    CPU job выполняется в WorkerThreadPool

READY_CPU
    логическое состояние результата между очередью и commit

COMMITTING
    создаются Godot-ресурсы по одной стадии за кадр

ACTIVE
    новая поверхность подключена
```

Устаревшие задачи помечаются revision. Явный синхронный переход, случайный spawn
или телепорт вызывает `cancel_all()`. Результат с отменённой revision не может
заменить активную поверхность.

## Двойной буфер

Старая LOCAL поверхность и её collision не удаляются во время фоновой генерации.
Новые ресурсы сначала полностью создаются в staging slot. На стадии
`atomic_swap`:

- старые visual nodes скрываются;
- старая collision отключается;
- применяются новый anchor и crater state;
- новые LOCAL/collision/rocks добавляются в сцену;
- старые узлы удаляются deferred.

Таким образом, отсутствие готового результата не создаёт дыру под персонажем.

## Предиктивная подгрузка

Для персонажа используется только касательная к поверхности составляющая
скорости:

```text
prediction_distance = min(speed × prediction_seconds,
                          max_prediction_distance_m)
```

Значения по умолчанию:

```text
prediction_seconds = 6
max_prediction_distance_m = 420
stream_cell_size_m = 512
```

Вертикальная скорость джетпака не уводит целевой центр в сторону. Менеджер
готовит cell впереди направления полёта.

## Latest-wins без starvation

Одновременно выполняется одна CPU job. Пока она работает, новые запросы не
запускают дополнительные потоки. В pending slot остаётся только последний
целевой участок.

Завершающаяся работа не отбрасывается только потому, что появился соседний
pending request: иначе при непрерывном быстром движении ни одна поверхность не
успевала бы подключиться. Отбрасывание происходит только после явной отмены
revision.

## Начальная и аварийная синхронная генерация

Синхронный путь сохранён для:

- первого запуска;
- восстановления сохранённой позиции;
- случайного spawn;
- телепорта персонажа из спектатора;
- fallback при выключенном async manager.

Он полностью профилируется событием `synchronous_surface_rebuild`.

## Следующие улучшения по результатам логов

1. **Tiled collision**, если доминирует `collision_shape`.
2. Разделение LOCAL mesh resource на несколько clipmap rings, если доминирует
   `local_mesh_resource`.
3. Quality tiers для высокой скорости джетпака.
4. Кэш intermediate height/crater descriptors, если повторная CPU generation
   остаётся главным ограничением.
5. Две очереди: critical physical surface и low-priority decoration.
6. Переход от lat/lon streaming cell к cube-sphere cell около полюсов.

## Стабилизация v15.1

По первому реальному логу обнаружены два архитектурных дефекта первой версии:

1. предиктивная ячейка становилась активной до того, как наблюдатель фактически
   входил в неё, что могло вызвать обратный запрос предыдущей ячейки;
2. вся физическая сетка создавалась одним вызовом `create_trimesh_shape()`.

В v15.1 введены:

- гистерезис между ранним prefetch и обязательным recenter;
- минимальная скорость для предиктивной смены;
- ограничение целевого шага одной соседней ячейкой;
- блокировка очереди от покадровой замены обычных запросов;
- tiled collision, подготовленная в worker и подключаемая частями;
- согласование наземных акторов с новой поверхностью до retirement старого slot;
- неразрушительный streaming mini-test.
