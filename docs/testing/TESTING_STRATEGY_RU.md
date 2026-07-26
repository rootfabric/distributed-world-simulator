# Стратегия тестирования PlanetSimulator

**Статус:** проектный документ
**Область:** Godot 4.x, GDScript, double precision, multi-world simulator
**Изменение production-кода:** отсутствует

## 1. Зачем нужна отдельная стратегия

PlanetSimulator сочетает несколько типов систем, которые требуют разных
методов проверки:

- чистая доменная логика предметов, контейнеров и координат;
- узлы и lifecycle `SceneTree`;
- фиксированные physics ticks;
- фоновые worker-задачи terrain generation;
- persistence и миграции схем;
- процедурная генерация;
- runtime-переключение миров;
- визуальные материалы и GPU-зависимое отображение.

Один вид тестов не способен надёжно покрыть все эти области. Например, прямой
вызов `_physics_process()` проверяет функцию, но не проверяет PhysicsServer,
контакты, deferred callbacks и фактический порядок кадров.

## 2. Сохраняем существующую тестовую систему

В проекте уже используется правильный базовый механизм:

```text
PowerShell runner
→ Godot editor double precision
→ --headless --path <project> --script <test.gd>
→ реальный SceneTree и engine services
→ quit(0) или quit(1)
```

`--headless` не означает «без движка». Godot запускает SceneTree, GDScript,
physics, ресурсы, сигналы и серверы, но использует headless display driver и
Dummy audio. Поэтому большинство component, scene и physics тестов можно
выполнять без окна и GPU.

Полная замена текущих тестов на GUT или GdUnit4 не требуется. Возможное
подключение framework рассматривается как отдельное решение после проверки:

- совместимости с точной версией Godot;
- поддержки double-precision сборки;
- времени импорта addon;
- стабильности headless CLI;
- отсутствия конфликтов с текущим manifest и runner;
- возможности экспортировать JUnit без переписывания существующих тестов.

На момент исследования GUT имеет отдельную ветку для Godot 4.7.x. GdUnit4
предоставляет расширенный Scene Runner, mocks и fuzzing, но его стабильная
таблица совместимости должна перепроверяться перед установкой. Это не блокирует
развитие текущей native test infrastructure.

## 3. Уровни тестирования

### 3.1. Domain unit tests

Тестируют объекты без добавления в SceneTree:

- Item Registry и relations;
- Container Registry;
- mass, capacity и validation rules;
- SpatialRef;
- FrameGraph providers;
- PartitionAddress и CubeSphereGrid;
- migration functions;
- Earth rule pipeline;
- orbital calculations;
- command parsing.

Требования:

- не использовать `await`, Timer, Input или physics nodes;
- использовать фиксированные входные данные;
- проверять успешные и ошибочные ветки;
- при отказе проверять отсутствие частичной мутации;
- выполнять много вариантов быстро.

### 3.2. Component tests внутри SceneTree

Тестируют один реальный компонент с минимальными зависимостями:

- RuntimeTestRegistry;
- CommandRegistry signals;
- ItemRepresentationSystem;
- TerrainStreamingManager;
- WorldInteractor;
- DeveloperConsole;
- atmosphere manager;
- controller host.

Компонент добавляется в дерево, после чего тест ожидает реальные process или
physics frames. Проверяется публичный контракт и diagnostic snapshot, а не
внутренняя структура реализации.

### 3.3. Scene integration tests

Загружают настоящую `.tscn` и проверяют её как runtime:

- сцена создаётся без ошибок;
- обязательные узлы доступны;
- команды и тесты зарегистрированы;
- взаимодействие приводит к ожидаемому состоянию;
- unload освобождает владельцев и узлы.

Тест не должен зависеть от длинных UI-путей вроде
`Root/Panel/Margin/VBox/Button`. Для стабильности предпочтительны публичные
методы, группы и diagnostic snapshots.

### 3.4. Physics tests

Используют реальные physics frames и реальные тела:

- `RigidBody3D`;
- `CharacterBody3D`;
- `StaticBody3D`;
- collision shapes;
- raycasts;
- signals контактов.

Physics ticks отделены от rendered frames и выполняются с фиксированной
частотой. Поэтому нужно ожидать число physics frames, а не произвольное время.

Физический движок Godot не детерминирован. Тесты не должны сравнивать точную
позицию после большого числа тиков. Следует проверять:

- направление движения;
- допустимый диапазон;
- факт контакта;
- отсутствие проваливания;
- достижение покоя за ограниченное число кадров;
- сохранение массы и доменных инвариантов.

### 3.5. System tests

Запускают полный `main.tscn` и проверяют несколько подсистем вместе:

- boot matrix всех миров;
- переключение runtime;
- сохранение и полное восстановление;
- terrain generation во время unload;
- регистрация и очистка команд;
- отсутствие orphan nodes;
- повторный запуск после ошибки.

Их должно быть меньше, чем unit/component тестов, потому что они медленнее и
сложнее диагностируются.

### 3.6. Stress и soak tests

Запускаются отдельно, не на каждый небольшой commit:

- десятки или сотни переключений миров;
- тысячи предметов и entity records;
- длинные последовательности terrain requests;
- многократные save/load;
- cache eviction;
- bounded history;
- отсутствие роста числа узлов и памяти.

### 3.7. Visual и export smoke tests

Headless-режим не проверяет реальный Forward+/Mobile/Compatibility renderer.
Отдельный GPU job позже должен проверять:

- загрузку материалов и shaders;
- отсутствие отсутствующих textures;
- стабильные UI-снимки;
- атмосферу и Earth scene с фиксированным seed;
- экспорт Windows/Linux;
- запуск экспортированной сборки.

Pixel-perfect сравнение не подходит для динамической физики, частиц, теней и
разных GPU. Нужны допуски и отдельные эталоны по renderer/backend.

## 4. Правила времени и ожиданий

### 4.1. Нельзя использовать безусловный sleep как основной механизм

Плохо:

```text
подождать 2 секунды
→ надеяться, что worker завершился
```

Правильно:

```text
ожидать signal или условие
→ иметь timeout
→ при timeout вывести snapshot состояния
```

Каждая асинхронная система должна предоставлять или иметь возможность
диагностировать:

- текущий state;
- active operation/revision;
- pending operation;
- last error;
- число owned resources;
- `is_idle()`;
- cancellation state.

### 4.2. Process и physics frames нельзя смешивать

- UI, deferred calls и обычный lifecycle ждут process frames.
- CharacterBody, RigidBody и collision ждут physics frames.
- После `queue_free()` необходимо дождаться как минимум следующего process frame.
- После создания физического тела часто требуется несколько physics frames до
  проверки контакта.

### 4.3. Любое ожидание имеет timeout

Тест не должен зависнуть навсегда. Timeout обязан завершить тест с FAIL и
напечатать:

- имя ожидаемого условия;
- сколько кадров/секунд прошло;
- snapshot компонента;
- активную revision/request ID;
- последние диагностические сообщения.

## 5. Детерминированность

### 5.1. Procedural generation

Все тестируемые генераторы должны получать отдельный
`RandomNumberGenerator` с известным seed. Один и тот же seed должен давать
воспроизводимую последовательность. Глобальные `randf()` и `randi()` внутри
тестируемой логики затрудняют воспроизведение.

Любой property/fuzz тест обязан печатать seed и историю команд при отказе.

### 5.2. Physics

Точную побитовую воспроизводимость физики не считать контрактом. Контрактом
являются допустимые диапазоны и игровые инварианты.

### 5.3. Время симуляции

Доменная логика не должна зависеть от реального wall-clock, если можно передать
SimulationClock или фиксированное время. Тесты должны явно задавать:

- simulation time;
- time scale;
- physics tick count;
- sample time SpatialRef.

## 6. Изоляция тестов

Каждый engine-тест обязан восстановить состояние, которое может протечь между
запусками:

- `Engine.time_scale`;
- pause state SceneTree;
- `Input.mouse_mode`;
- нажатые input actions;
- временные `ProjectSettings`;
- временные файлы `user://`;
- зарегистрированные команды и runtime-тесты;
- созданные nodes;
- активные threads и workers;
- custom Performance monitors.

Для этого на первом инфраструктурном этапе планируется общий
`TestEngineGuard`, но его добавление является отдельной задачей и не входит в
этот документационный патч.

## 7. Что считать покрытием

Процент строк сам по себе недостаточен. Для каждого production-модуля нужно
проверять следующие типы контрактов, если они существуют:

1. happy path;
2. boundary values;
3. invalid input;
4. unsupported schema/version;
5. duplicate/repeated operation;
6. partial failure и rollback;
7. signals и отсутствие duplicate signals;
8. lifecycle start/cancel/unload;
9. serialization round-trip;
10. corruption/fail-closed;
11. concurrency/revision fencing;
12. cleanup и отсутствие утечки ресурсов.

## 8. Performance testing

`Performance.get_monitor()` позволяет получать process/physics time, память,
число объектов и другие метрики. Некоторые значения обновляются с задержкой до
одной секунды, поэтому тесты требуют warm-up и нескольких выборок.

Performance-тесты должны в первую очередь проверять структурные бюджеты:

- cache size не превышает capacity;
- history ограничена;
- число runtime nodes не растёт после циклов;
- terrain commit распределён по стадиям;
- число collision tiles ограничено;
- память возвращается в допустимый диапазон после unload.

Жёсткое требование вида «операция всегда быстрее 16 мс» обычно нестабильно на
разных машинах и не должно блокировать обычный commit без отдельной
контролируемой среды.

## 9. Источники исследования

- Godot command line и `--headless`:
  https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- Physics ticks и rendered frames:
  https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html
- Рекомендации по physics interpolation и тестированию на низком tick rate:
  https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html
- Release policy и недетерминированность physics:
  https://docs.godotengine.org/en/stable/about/release_policy.html
- RandomNumberGenerator и воспроизводимый seed:
  https://docs.godotengine.org/en/latest/classes/class_randomnumbergenerator.html
- Performance monitors:
  https://docs.godotengine.org/en/stable/classes/class_performance.html
- GUT:
  https://github.com/bitwes/Gut
- GUT Input Sender:
  https://gut.readthedocs.io/en/9.3.1/Input-Sender.html
- GdUnit4:
  https://github.com/godot-gdunit-labs/gdUnit4
