# Real Scale Procedural Moon v13

Проект для Godot 4.7.1, собранного с `precision=double`.

## Главное в v13

- постоянный изменяемый слой поверх процедурной Луны;
- `world.json` с seed и версией генератора;
- разреженное сохранение сущностей по чанкам;
- Survey Beacon как первый размещаемый объект;
- загрузка маяков при входе чанка в Warm/Active окно;
- выгрузка при уходе чанка из окна;
- журнал операций JSONL;
- восстановление последней точки игрока;
- отключаемое меню и диагностические тесты.

## Управление

```text
B          поставить Survey Beacon
Delete     удалить ближайший маяк
Ctrl+S     сохранить постоянный слой
F10        тест запись → выгрузка → загрузка
F7         тест миграции сущности между чанками
F9         сохранить диагностический JSON
F1 / Esc   открыть или закрыть меню
Tab        захватить или освободить мышь
F3         персонаж / спектатор
F6 / R     случайная точка Луны
F8         сменить разрешение
F11        полный экран / окно
```

## Данные мира

```text
user://worlds/moon-experiment-001/
├── world.json
├── journal/events.jsonl
└── zones/<zone>/chunks/<chunk>.json
```

Файлы чанков существуют только для изменённых областей. Процедурные меши, кратеры и декоративные камни не сохраняются.

## Тесты

```powershell
.\RUN_ARCHITECTURE_TESTS.ps1
.\RUN_ENTITY_INTEGRATION_TEST.ps1
.\RUN_PERSISTENCE_TEST.ps1
```

Подробная документация находится в `docs/README_RU.md`.


# v14 — подключаемые контроллеры

Новые клавиши:

```text
C    первое/третье лицо
J    Lunar EVA/Jetpack
F12  мини-тест controller/camera
```

Профили:

```text
config/controllers/lunar_humanoid.json
config/controllers/lunar_jetpack.json
config/controllers/earth_humanoid.json
```

Архитектура описана в:

```text
docs/architecture/PLUGGABLE_CONTROLLER_ARCHITECTURE_RU.md
docs/contracts/CONTROLLER_PROFILE_V1_RU.md
```
