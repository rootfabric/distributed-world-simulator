# Checkpoint v16.3.2 — Foundation Lifecycle Part 2

**Дата:** 27 июля 2026 года
**Версия:** `v16.3.2-foundation-lifecycle-part2`
**Основа:** `v16.3.1-foundation-n0-part1-fix3`

## 1. Цель части

Устранить process lifecycle-блокер перед N1: Godot должен безопасно прекращать приём команд, останавливать новые terrain jobs, дожидаться активной фоновой генерации, сохранять canonical state и завершать процесс с кодом 0.

Эта часть не объявляет весь Foundation Gate закрытым. Полное выделение SimulationKernel, единый WorldEntityAggregate и lifecycle сущностей/чанков остаются следующими этапами.

## 2. Реализованный LifecycleCoordinator

Добавлен `scripts/runtime/lifecycle_coordinator.gd` со state machine:

```text
CREATED → STARTING → RUNNING → DRAINING → STOPPING → STOPPED
                                      └──────────────→ FAILED
```

После перехода в DRAINING новые доменные команды отклоняются кодом `RUNTIME_DRAINING`. Повторный shutdown идемпотентен. Snapshot coordinator-а содержит node ID, причину, exit code и историю переходов.

## 3. Graceful shutdown SimulatorApp

Последовательность:

1. `request_graceful_shutdown`;
2. command fencing;
3. lifecycle event `node_draining`;
4. synchronous runtime disposal;
5. terrain drain;
6. persistence/item graph flush;
7. lifecycle event `node_stopped`;
8. `SceneTree.quit(exit_code)`.

`app.quit`, CLI regression completion, scheduled shutdown и закрытие окна используют один путь.

## 4. Terrain worker barrier

`TerrainStreamingManager` получил:

```text
request_stop(reason)
is_drained()
drain_blocking(timeout_ms)
```

После stop manager не принимает новые requests и не начинает новые commits. Активная задача помечается stale, затем runtime дожидается `WorkerThreadPool.wait_for_task_completion` до освобождения узлов. Persistence выполняется только после drain.

Ограничение: Godot не предоставляет жёсткое прерывание уже выполняющегося WorkerThreadPool task. `timeout_ms` является диагностическим пределом; зависший навсегда worker нельзя безопасно preempt-нуть из GDScript. Все текущие terrain jobs завершаются в пределах 30 секунд.

## 5. Синхронная смена мира

Предыдущий runtime теперь полностью drained и освобождён до создания следующего. Тест запускает terrain job, немедленно переключает мир и проверяет:

- revision fence;
- состояние terrain `STOPPED`;
- drain в пределах timeout;
- отсутствие живого старого runtime.

## 6. Simulation-server role policy

Для `--role=simulation-server`:

- DeveloperConsole и SystemMenu не создаются;
- local input callbacks отключаются рекурсивно;
- активные Camera2D/Camera3D отключаются и снимаются с дерева;
- Control/CanvasLayer/Window скрываются и перестают процесситься;
- audio останавливается;
- process test подтверждает `active_presentation_nodes = 0`.

Это server-safe policy поверх текущих runtime-сцен. Физическое предотвращение создания presentation nodes будет завершено при выделении SimulationKernel/PresentationHost.

## 7. Изолированный user data

`tests/process/test_simulation_server_lifecycle.py` создаёт временный профиль и задаёт:

```text
HOME
XDG_DATA_HOME
APPDATA
LOCALAPPDATA
```

Так каждый Godot-процесс получает отдельный `user://`. CLI `--user-data-dir` сохраняется в RuntimeDescriptor для аудита, а `resolved_user_data_dir` подтверждает фактический путь Godot.

## 8. Новые параметры запуска

```text
--shutdown-after-ms=<N>
--shutdown-timeout-ms=<N>
```

Первый используется process harness для воспроизводимого shutdown во время активной генерации. Второй передаёт диагностический бюджет drain.

## 9. Тесты

Добавлены:

- `tests/runtime/test_lifecycle_coordinator.gd` — 26 assertions;
- `tests/process/test_simulation_server_lifecycle.py`;
- `RUN_FOUNDATION_LIFECYCLE_TESTS.ps1`.

Обновлены:

- `test_launch_options.gd` — 25 assertions;
- `test_world_switch_during_generation.gd`;
- полный regression runner — 39 test scripts.

Проверено на Godot `4.7.1.stable.double.custom_build.a13da4feb`:

```text
editor import/parse                 PASS
39/39 Godot test scripts           PASS, exit code 0
unified_runtime_boot               PASS, process exited
world_switch_during_generation     PASS, process exited
world_boot_matrix                  PASS, process exited
simulation-server process test     PASS
playground main scene              6 PASS, 0 FAIL
Foundation/N0 contract profile     4/4, 131 assertions
```

`world_boot_matrix` по-прежнему выводит ранее известный manifest identity mismatch при последовательном использовании `moon-experiment-001` разными runtime-конфигурациями. Он не удерживает процесс и не связан с worker lifecycle; исправление manifest identity вынесено отдельно.

## 10. Принятые инварианты

```text
DRAINING не принимает новые команды
runtime не освобождается до terrain drain
persistence flush идёт после worker drain
server process использует изолированный user://
node_ready → node_draining → node_stopped
```

## 11. Следующая часть Foundation Gate

```text
v16.3.3-foundation-world-aggregate-part3
```

Рекомендуемый scope:

1. физическая граница SimulationKernel/PresentationHost;
2. WorldEntityAggregate как единственная spatial truth WORLD-объекта;
3. migration старого Item relation spatial state;
4. Entity/Chunk lifecycle `Dormant/Warm/Active/Unloading`;
5. server-safe persistence ports.
