# Controller Profile Contract v1

Схема:

```text
planet_simulator.controller_profile.v1
```

Пример:

```json
{
  "schema": "planet_simulator.controller_profile.v1",
  "profile_id": "lunar_humanoid",
  "display_name": "Lunar EVA Humanoid",
  "controller_script": "res://scripts/actors/controllers/planetary_humanoid_controller.gd",
  "body_kind": "humanoid",
  "movement": {},
  "camera": {},
  "capabilities": [],
  "environment_tags": []
}
```

## Обязательные поля

- `profile_id` — стабильный идентификатор профиля;
- `controller_script` — подключаемая реализация;
- `movement` — параметры движения;
- `camera` — параметры камеры;
- `capabilities` — декларация возможностей.

## Текущие профили

```text
config/controllers/lunar_humanoid.json
config/controllers/lunar_jetpack.json
config/controllers/earth_humanoid.json
config/controllers/flat_humanoid.json
```

JSON-конфигурация является частью проекта и редактируется без изменения контроллера. Runtime-настройки пользователя позже следует сохранять отдельно в `user://`, не изменяя базовый профиль.


## Совместимость

Встроенные профили переведены на общее имя схемы симулятора. Loader временно
принимает legacy-схему `lunar.controller_profile.v1`, чтобы старые world packs
и сохранённые конфигурации не перестали загружаться одномоментно. Новые профили
обязаны использовать `planet_simulator.controller_profile.v1`.
