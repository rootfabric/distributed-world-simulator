# Real Scale Procedural Moon v15.3

Проект для Godot 4.7.1, собранного с `precision=double`.

## Главное в v15.3

- добавлен независимый `WorldInteractor` с центральным physics ray из камеры первого лица;
- введён общий контракт группы `world_interactable`;
- Survey Beacon показывает карточку состояния, ID и дистанцию;
- объект получает контурную подсветку при наведении;
- клавиша `E` включает и выключает сигнал маяка;
- состояние сохраняется в `beacon_state`, записывается в journal и восстанавливается после перезапуска;
- выключенный маяк скрывает дальнюю метку и перестаёт удерживать terrain cell как pinned;
- дальний шрифт метки уменьшен примерно в 5 раз: `56 → 11`, outline `12 → 2`;
- сохранены RAM-cache LOCAL-поверхностей и pinned cache для активных маяков из v15.2.

Процедурная поверхность по-прежнему не является частью постоянного сохранения. Кэш можно потерять без изменения мира: после перезапуска участок будет рассчитан заново.

## Взаимодействие

```text
1. Закрыть меню F1/Esc.
2. Переключиться в первое лицо клавишей C.
3. Поставить маяк клавишей B.
4. Подойти ближе чем на 6 м и навести центр экрана на маяк.
5. Нажать E, чтобы включить или выключить сигнал.
```

В третьем лице, спектаторе, открытом меню или при освобождённой мыши взаимодействие отключено.

## Асинхронный streaming и surface cache

- CPU generation работает через `WorkerThreadPool`;
- старая поверхность остаётся активной до готовности новой;
- collision разделена на плитки примерно по 2048 треугольников;
- предиктивная подгрузка имеет гистерезис;
- `K` выполняет безопасный staged-тест без замены активного участка;
- готовые LOCAL-поверхности удерживаются в LRU RAM-cache;
- обычная ёмкость — 8 recent cells и до 8 дополнительных pinned cells активных маяков;
- повторная генерация при cache hit не запускается;
- тайминги пишутся в отдельный JSONL-лог.

## Управление

```text
E          взаимодействовать с объектом в центре экрана
C          первое/третье лицо
J          Lunar EVA/Jetpack
K          безопасный тест terrain streaming
M          включить/выключить дальние метки маяков
F12        тест controller/camera
B          поставить Survey Beacon
Delete     удалить ближайший маяк
Ctrl+S     сохранить постоянный слой
F10        тест persistence
F7         тест Entity Registry
F9         сохранить диагностический JSON
F1 / Esc   открыть или закрыть меню
Tab        захватить или освободить мышь
F3         персонаж / спектатор
F6 / R     случайная точка Луны
F8         сменить разрешение
F11        полный экран / окно
```

## Логи и диагностика

```text
user://logs/terrain_performance.jsonl
user://logs/lunar_simulation.jsonl
user://diagnostics/diagnostic_*.json
```

На Windows:

```text
%APPDATA%\Godot\app_userdata\Real Scale Procedural Moon\
```

Сводка и диагностический архив:

```powershell
.\ANALYZE_TERRAIN_LOG.ps1
.\EXPORT_TERRAIN_DIAGNOSTICS.ps1
```

Для проверки cache hit ищите события:

```text
terrain_surface_cached
terrain_surface_cache_hit
terrain_pinned_cache_return_triggered
terrain_surface_cache_evicted
```

Для взаимодействия добавлены события:

```text
interaction/interaction_performed
persistence/survey_beacon_signal_toggled
journal operation=entity_component_changed
```

## Тесты

```powershell
.\RUN_ARCHITECTURE_TESTS.ps1
.\RUN_ENTITY_INTEGRATION_TEST.ps1
.\RUN_PERSISTENCE_TEST.ps1
.\RUN_CONTROLLER_TEST.ps1
.\RUN_TERRAIN_STREAMING_TEST.ps1
.\RUN_INTERACTION_TEST.ps1
```

Подробная документация находится в `docs/README_RU.md`.
