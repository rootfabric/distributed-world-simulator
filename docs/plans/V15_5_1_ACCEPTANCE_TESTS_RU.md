# Приёмка v15.5.1 — coordinate foundation

## Автоматический запуск

```powershell
.\RUN_COORDINATE_FOUNDATION_TESTS.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Требуется double-precision Godot, совместимый с `project.godot`.

## Обязательные проверки

### Часы

- масштаб `2x` переводит 0,5 секунды wall time в 1 секунду simulation time;
- pause не изменяет время;
- manual step работает в pause;
- clock сохраняется при смене runtime мира;
- новый authority epoch принимается;
- snapshot старого authority epoch и более старого tick отвергаются.

### Frame graph

- точка body-fixed корректно переходит в root и обратно;
- вращение тела меняет root-положение неподвижной поверхности;
- преобразование скорости содержит `ω × r`;
- SpatialRef roundtrip сохраняет position, orientation и velocity;
- FrameGraph отвергает SpatialRef из другого `instance_id`.

### Движение тел

- Земля меняет положение по аналитической орбите;
- расстояние Земля–Луна остаётся в диапазоне настроенной эллиптической орбиты;
- Moon fixed frame ориентирован на Землю;
- координата земной поверхности не переписывается из-за движения Земли.

### Partition

- одинаковые face/zone/chunk Земли и Луны дают разные ID;
- `CubeSphereGrid` одинаково работает для Земли и Луны;
- длина direction vector не влияет на адрес;
- центры zone/chunk дают точный roundtrip на всех шести гранях;
- переход через каждое ребро и угол всех шести граней не создаёт пустых или
  схлопнутых соседств zone/chunk;
- изменение плотности сетки требует новой scheme revision;
- manifest отклоняет другую плотность при той же scheme revision;
- неверный namespace и невалидная grid-конфигурация завершают setup ошибкой без
  fallback на значения Луны;
- scheme revision входит в ID и путь хранения;
- persistent и scenario instances дают разные ID;
- legacy ID мигрирует в namespaced v2;
- повреждённые и отрицательные адреса отвергаются, а не превращаются в нулевой chunk;
- partition вычисляется только из `partition_frame_id`;
- две удалённые interest sources удерживают объединённое окно;
- удаление последней interest source полностью освобождает окно.

### Entity

- legacy `lunar.entity.v1` читается как Entity v2;
- одна spatial command увеличивает revision один раз;
- изменение одной orientation/velocity без перемещения не теряется;
- SpatialRef из другого `instance_id` отвергается partition resolver;
- stale authority epoch отвергается;
- replica eviction не считается authoritative delete.

### Persistence

- новый chunk сохраняется в namespaced пути;
- legacy `zones/...` читается как fallback;
- ранний каталог `cube_sphere_v1` с instance читается и переносится в
  `cube_sphere_r1`;
- pre-instance namespaced каталог читается и переносится в текущий namespace;
- после повторного сохранения используется schema v2;
- старый постоянный маяк не теряется;
- legacy manifest дополняется universe/instance identity;
- journal содержит universe/instance/partition-space identity;
- непостоянный instance получает отдельный корень persistence;
- repository отказывается запускаться поверх manifest другого instance и не пишет в него;
- удаление последней сущности удаляет текущий и все legacy-файлы чанка, не
  позволяя удалённой сущности восстановиться при следующей загрузке.

## Ручная проверка

В консоли:

```text
time.status
time.scale 3600
world.load earth_moon
space.frame.current
space.frame.set body/earth/fixed
space.frame.set body/earth/inertial
space.frame.set sol.barycentric
runtime.snapshot
```

Ожидается, что смена frame не изменяет физическое положение наблюдателя, а
ускорение времени меняет взаимное положение тел без переписывания локальной
координаты поверхности.
