# Подключаемая архитектура контроллеров v1

## Назначение

Физическое тело, визуальная модель, камера и логическая сущность не должны зависеть от конкретного способа управления. Один и тот же `LunarPlayer` может получить контроллер ходьбы, джетпака или другой профиль без замены Entity Registry, persistence и системы зон.

```text
Actor: LunarPlayer / Robot / Drone / Vehicle
        │
        ▼
ControllerHost
        │
        ├── PlanetaryHumanoidController
        ├── JetpackController
        ├── будущий WheeledRobotController
        ├── будущий TrackedRobotController
        └── будущий FlightController
```

## Ответственность Actor

`LunarPlayer` владеет:

- `CharacterBody3D` и collision shape;
- абсолютной мировой позицией через `MoonWorld`;
- моделью персонажа;
- камерами первого и третьего лица;
- подключённым `ControllerHost`;
- интерфейсами `get_world_position`, `align_body_to_up`, `get_view_basis`.

Actor не содержит правил ходьбы, прыжка или полёта.

## Ответственность ControllerHost

- загружает профили из `config/controllers`;
- создаёт реализацию контроллера по `controller_script`;
- безопасно заменяет текущий контроллер;
- передаёт ему physics tick и mouse input;
- применяет camera profile;
- создаёт диагностический snapshot.

## Контракт контроллера

```text
setup(actor, world, profile, logger)
set_enabled(value)
on_activated()
on_deactivated()
physics_step(delta)
handle_input(event)
get_profile_id()
get_display_name()
get_capabilities()
```

Контроллер не должен самостоятельно сохранять сущность или менять Zone/Chunk ID. Эти обязанности остаются у общих подсистем мира.

## Камеры

Actor содержит две камеры:

- FirstPersonCamera — расположена в точке глаз;
- ThirdPersonCamera — размещена через `SpringArm3D`, который не позволяет камере проходить сквозь рельеф.

Клавиша `C` переключает режим. В первом лице модель персонажа скрывается, чтобы шлем и тело не перекрывали обзор. Позднее можно добавить отдельную модель рук.

## План расширения

### Планетарные гуманоиды

Одна реализация может использовать разные профили:

- `lunar_humanoid`;
- `earth_humanoid`;
- `mars_humanoid`;
- `asteroid_humanoid`.

Гравитацию предоставляет World, а профиль задаёт скорость, ускорение, прыжок и допустимый склон.

### Роботы

Для роботов следует создавать отдельные Actor и Controller:

```text
WheeledRobotActor + DifferentialDriveController
TrackedRobotActor + TrackedDriveController
DroneActor + FlightController
ManipulatorActor + JointController
```

Общий ControllerHost можно переиспользовать, но физический интерфейс Actor будет специализированным.

### Оборудование

Джетпак реализован как отдельный контроллер, а не условие внутри humanoid controller. В будущем экипировка может временно подключать профиль `lunar_jetpack`, после снятия возвращая `lunar_humanoid`.
