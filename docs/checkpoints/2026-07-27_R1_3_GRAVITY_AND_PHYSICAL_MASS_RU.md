# Чекпоинт R1.3 — gravity wells и рекурсивная физическая масса

**Версия:** `v15.8.1-r1.3-fix1`
**База:** принятый `v15.7.0-r1.2`
**Статус:** реализовано, требуется приёмочный прогон на целевой Godot 4.7.1
double build.

## Цель

Убрать жёстко заданную лунную силу из item presentation и заложить общий слой,
который одинаково пригоден для поверхности Луны, Земли, межпланетного
пространства и будущих естественных/искусственных спутников.

Одновременно физическая масса контейнера должна соответствовать доменной массе
содержимого.

## Реализовано

### 1. Общий gravity field

Добавлены:

- `GravityMath`;
- `GravityField`;
- `GravityTrajectoryIntegrator`;
- gravity snapshot в `CelestialSystem`.

Поле использует сферические источники Солнца, Земли и Луны. Для каждого тела в
`celestial_system.json` зафиксирован `gravitational_parameter_m3_s2`.
Ускорения суммируются, а расстояние и направление рассчитываются в
канонических double coordinates.

### 2. Ослабление с высотой

Снаружи тела действует inverse-square field. Поэтому:

```text
Moon surface: приблизительно 1.62 m/s²
2 Moon radii: приблизительно 0.405 m/s²
```

Внутри тела используется uniform-sphere field без сингулярности.

### 3. Body-relative компенсация

Для `body/earth/*` и `body/moon/*` вычитается внешнее ускорение центра reference
body. Это сохраняет локальную физику на поверхности при одновременном наличии
солнечного и лунного полей.

Чистое абсолютное поле остаётся доступно в `sol.barycentric`.

### 4. Базис орбитального движения

Velocity-Verlet integrator принимает position, velocity, frame и simulation
time. Он позволяет выполнять test-particle propagation без привязки к Godot
RigidBody.

Regression проверяет приблизительно полный круг спутника на высоте 400 км вокруг
изолированной Земли и контролирует сохранение радиуса орбиты.

На R1.3 celestial bodies всё ещё используют аналитические orbit providers.
Обратное влияние спутника на тело отсутствует.

### 5. Item physics environment

Удалена константа:

```gdscript
Vector3(0.0, -1.62 * mass, 0.0)
```

WORLD item получает `GravityBodyDriver`, который каждый physics step
запрашивает поле по текущему положению. Лаборатория использует локальный
сферический источник Луны, центр которого расположен под площадкой.

### 6. Recursive physical mass

`ItemRepresentationSystem` получает `ItemMassService`. Масса `RigidBody3D`
вычисляется через `item_recursive_mass_kg()`.

Пример из лаборатории:

```text
crate shell: 4 kg
3 rocks: 6 kg
physical RigidBody mass: 10 kg
```

После извлечения содержимого масса существующего тела обновляется до 4 кг, а
сила пересчитывается по новой массе.

## Новые тесты

### `tests/unit/test_gravity_field.gd`

Проверяет:

- лунную поверхностную гравитацию;
- inverse-square falloff;
- uniform-sphere interior;
- отсутствие singularity в центре;
- superposition и cancellation;
- dominant source;
- Earth/Moon/Sun dynamic sources из FrameGraph;
- body-relative external acceleration compensation;
- circular/escape speed relation;
- velocity-Verlet test-particle orbit;
- удержание естественного спутника в движущемся Earth frame при активных полях Солнца и Луны.

### `tests/items/test_item_physics_environment.gd`

Проверяет:

- nested physical mass: crate + inner bag + rocks = 11 kg;
- force = acceleration × recursive mass;
- отключение Godot global gravity;
- ослабление поля с высотой;
- обновление массы и силы после изменения вложенного содержимого;
- преобразование ускорения из frame coordinates в повёрнутые оси сцены.

Расширен `test_item_lab_integration.gd`: он подтверждает реальную физическую
массу заполненного ящика и наличие radial Moon field.

## Приёмочный барьер

```powershell
.\RUN_ITEM_SYSTEM_TESTS.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Ожидается:

```text
29/29 tests
32/32 steps
checkpoint v15.8.1-r1.3-fix1
main-scene regression PASS
```

## Следующий этап

R1.4 должен собрать атомарный persistence bundle:

```text
Items + Containers + Attachments + Operation Ledger + physics SpatialRef
```

После R1.4 можно переносить предметы из лаборатории в пользовательский workflow
R2 на playground.

## Fix1: применение гравитации до входа в SceneTree

`GravityBodyDriver.apply_now()` больше не обращается к `global_transform`, если
физическое тело или его coordinate root ещё не находятся в `SceneTree`.
Локальная цепочка `Node3D.transform` композиционно разрешается вручную. Это
сохраняет правильные координаты и ориентацию frame во время конструирования
предмета, headless-тестов и будущей активации объектов из пула.

Regression дополнительно проверяет вложенную и повёрнутую detached-иерархию:
ускорение на расстоянии двух радиусов Луны равно четверти поверхностного, сила
учитывает массу тела, а вектор корректно переводится в координаты сцены.
