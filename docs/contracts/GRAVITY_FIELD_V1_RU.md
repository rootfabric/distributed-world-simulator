# Gravity Field v1

## Назначение

`GravityField` — общий вычислительный слой гравитации для предметов, аппаратов,
игроков и будущих test-particle орбит. Он не принадлежит Луне или конкретной
сцене и работает в канонических double-precision координатах `FrameGraph`.

Основные файлы:

- `scripts/simulation/gravity/gravity_math.gd`;
- `scripts/simulation/gravity/gravity_field.gd`;
- `scripts/simulation/gravity/gravity_trajectory_integrator.gd`;
- `config/planets/celestial_system.json`.

Runtime snapshot использует схему:

```text
planet_simulator.gravity_field.v1
```

## Источник поля

Каждое сферическое тело задаёт:

```text
id
radius_m
gravitational_parameter_m3_s2
interior_model
gravity_enabled
```

`gravitational_parameter_m3_s2` является каноническим параметром источника. Для
старой конфигурации разрешён fallback:

```text
mu = gravity_mps2 * radius_m²
```

Центр динамического тела берётся из `CelestialSystem/FrameGraph` на указанное
`sample_time_s`. Поэтому Земля и Луна могут двигаться по аналитическим орбитам,
а поле вычисляется в их актуальном положении.

## Закон поля

За пределами сферического тела используется поле точечной массы с законом
обратных квадратов. Ускорения всех активных источников суммируются.

Внутри радиуса по умолчанию используется модель однородной сферы: ускорение
линейно уменьшается до нуля в центре. Это предотвращает сингулярность и делает
ошибочное попадание физического объекта под поверхность численно безопасным.

Поддерживаемые interior-модели:

- `uniform_sphere` — рекомендуемая;
- `surface_clamp` — постоянная поверхностная величина внутри радиуса;
- `none` — источник не действует внутри радиуса.

## Системы отсчёта

В `sol.barycentric` возвращается абсолютная сумма ускорений.

Для `body/<id>/inertial` и `body/<id>/fixed` автоматически определяется
reference body. Из результата вычитается внешнее ускорение центра этого тела.
Это необходимо, потому что Земля и находящийся рядом предмет одинаково падают к
Солнцу. Без компенсации предмет в земной системе координат получил бы ложное
почти однородное ускорение относительно поверхности.

В v1 не включены псевдосилы вращающейся системы:

- центробежная;
- кориолисова;
- эйлерова.

Они должны быть отдельным слоем `NonInertialFrameForces`, чтобы чистое
гравитационное поле оставалось пригодным для inertial-расчётов и серверной
репликации.

## Основные запросы

```gdscript
field.get_acceleration_at_position(
    position_m,
    frame_id,
    sample_time_s,
    reference_body_id
)

field.get_acceleration_at_spatial_ref(spatial_ref)
field.get_contributions_at_position(...)
field.get_dominant_source_id_at_position(...)
field.get_circular_orbit_speed_mps(body_id, radius_m)
field.get_escape_speed_mps(body_id, radius_m)
```

`reference_body_id` обычно не нужен: для стандартных body frames он определяется
автоматически. Явное значение предназначено для будущих локальных кадров баз,
кораблей и partition authorities.

## Test-particle движение

`GravityTrajectoryIntegrator` использует velocity Verlet. Он предназначен для:

- естественных и искусственных спутников;
- выброшенных объектов в космосе;
- баллистических траекторий;
- серверной проверки прогнозируемого пути;
- будущего orbital autopilot.

Интегратор может работать как в `sol.barycentric`, так и в body-centered
inertial frame. Во втором случае `GravityField` вычитает общее внешнее ускорение
центра reference body, поэтому спутник остаётся в локальном гравитационном
колодце, пока Солнце, Земля и Луна продолжают движение в `FrameGraph`.

На этом этапе тела из `CelestialSystem` продолжают двигаться по аналитическим
орбитам. Test particles испытывают их поле, но не влияют обратно на планеты.
Это осознанная промежуточная модель, а не полноценный N-body solver.

## Физические предметы

`GravityBodyDriver` обновляет `RigidBody3D.constant_force` каждый physics
step:

```text
force_scene = frame_to_scene(gravity_acceleration_frame) * physical_mass
```

Драйвер принимает `coordinate_root`, чьи локальные координаты соответствуют
`frame_id`. Позиция body переводится из сцены в этот root, а вычисленное
ускорение — обратно в оси сцены. Поэтому один драйвер можно использовать для
предметов, кораблей и спутников даже при повёрнутом presentation root. Для
физического root не допускается неравномерный масштаб.

`gravity_scale` предмета равен нулю, чтобы не складывать поле Planet Simulator с
глобальной гравитацией Godot.

Физическая масса WORLD-контейнера равна собственной массе плюс рекурсивная масса
всего содержимого. При изменении container graph существующие WORLD bodies
пересчитывают массу и силу.

## Ограничения v1

- нет взаимного влияния celestial bodies через N-body integration;
- нет аэродинамики и атмосферного сопротивления;
- нет relativistic corrections;
- нет вращательных псевдосил;
- terrain collision и floating-origin representation остаются отдельными
  подсистемами;
- большие временные шаги trajectory integrator должны выбираться вызывающей
  системой с учётом требуемой точности.
