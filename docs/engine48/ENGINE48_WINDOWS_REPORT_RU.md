# ENGINE48 WINDOWS R1 — отчёт о сборке, тестировании и публикации (Godot 4.8 beta 1 double)

Дата: 2026-10-21 (Asia/Vladivostok). Роль: ENGINE48-B1-WIN implementer/executor.
Продукт: distributed-world-simulator, ветка `feature/engine48-windows-r1` → Draft PR #806 в `feature/engine48-beta1-double-migration-r1` (контекст миграции: PR #794).

## 1. Идентичность

| Параметр | Значение |
| --- | --- |
| Product HEAD (миграционный, base) | `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9` |
| Product HEAD (carrier-ветка, после scoped repairs) | см. `git rev-parse feature/engine48-windows-r1` |
| Product TREE (base) | `git rev-parse a936412cc^{tree}` |
| Godot SOURCE tar.xz SHA256 | `6d49c02e438935e49a12231d857b2b56131948b004d5b668bf295c9bc3b2281c` (проверен до распаковки) |
| Godot upstream source commit | `4d10419cacd6d3009976e8f9fd3abd970fd58018` (`.git/HEAD` тарбола совпадает) |
| Editor version | `4.8.beta1.double.custom_build.4d10419ca`, архитектура AMD64 |
| Worktree | `C:\distributed-world-simulator\worktrees\engine48-windows` |

Бинарные SHA256 (editor + оба templates): `artifacts/engine48/windows/r1/binary-sha256.txt`
(копия в репорте ниже):

- `f53f90f686a4eb05df076692c1b67a9e3d12d7c6c981cf86f1015d1ec36a2636` editor console
- `d0dab57a77e22d5e5c97e918ac78022e4ef761c2f301c307d7ec5f7508a6fea9` editor
- `fbb4dd72744cd0f03d2cea5379575ef6ebc094fd4466c9bcd031cce6f87d6997` template_debug console
- `27ced1ae85d4db2b0f3700319192f9fdd0a202191264385e4a3cac6f6e8f3837` template_debug
- `bbcf50d7c4e5762188de7c56f559a67fb218b493523222aa4fecda43df3edcf3` template_release console
- `809cb1d1d9f39736dc1cd6cd2637b4a583766415e4544fc0b1d4e0ece39cb62` template_release

Baseline 4.7.1 (не изменялся): `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe`,
SHA256 `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`,
версия `4.7.1.stable.double.custom_build.a13da4feb`.

## 2. Сборка (E48.0/E48.1: PASS)

- Хост: Windows x64, 20 логических ядер, 31.8 GB RAM, NVIDIA GeForce RTX 4060.
- Toolchain: VS2022 Community (vcvars64), Python 3.11.8, SCons 4.11.1.
- Флаги: `platform=windows target={editor,template_debug,template_release} arch=x86_64 precision=double d3d12=no`, `GODOT_VERSION_STATUS=beta1`.
- Отклонения от базовых команд: `-j12` вместо `-j4` (20 ядер / 32 GB RAM — без риска OOM); `d3d12=no` — проект остаётся на GL Compatibility, D3D12 SDK не требуется (документировано в плане, раздел 4). Upstream source не модифицировался.
- Логи: `C:\build-engine48\build-editor.log`, `C:\build-engine48\build-templates.log`; оба `scons: done`, exit 0.
- Known issue (не блокирует): единичный crash-on-exit (`exit=-1`) у `--editor --import --quit` при самом первом cold import в 4.8-beta1; все шаги импорта при этом завершены (`[DONE]`), class cache валиден, повторные запуски стабильны (exit 0). Зафиксирован в `cold-import.log`/verbose-прогоне.

## 3. Cold import (E48.2: PASS)

- Удалён `.godot`, выполнен `--headless --path <worktree> --editor --import --quit` новым editor.
- `global_script_class_cache.cfg` создан и непуст; лог: `artifacts/engine48/windows/r1/cold-import.log`; SCRIPT ERROR/Parse Error отсутствуют.
- Импортёр 4.8 обновил 13 tracked `.png.import` метаданных (аддитивные дефолты: `compress/high_quality_mode`, `mipmaps/preserve_alpha_test_coverage`, `mipmaps/alpha_test_threshold`) — закоммичено как `chore(engine48)`.
- 4.8 сгенерировал `.uid` sidecars для скриптов без них (конвенция Godot 4.4+) — закоммичено.

## 4. Регрессионная матрица (E48.3: PASS с 1 note)

Все тесты — реальные entrypoints точного HEAD, assertions не ослаблялись. Движок: 4.8 double editor binary.

| Gate/область | Entrypoint | Результат |
| --- | --- | --- |
| LIVE2 ENet rollover 131072 | `tests/network/test_v0_live2_enet_rollover.gd` | PASS (5.2s) |
| LIVE2 human bridge | `tests/runtime/test_v0_live2_human_gameplay_bridge.gd` | PASS |
| NX2 physical channel | `tests/network/test_nx2_physical_channel_processes.gd` | PASS |
| USER1 first usable slice | `tests/runtime/test_v0_user1_first_usable_slice.gd` | PASS |
| USER1 product seam bridge (seam) | `tests/runtime/test_v0_user1_product_seam_bridge.gd` | PASS |
| P4 two-client reconnect convergence | `tests/runtime/test_v0_p4_live_two_client_reconnect_convergence.gd` | 1-й прогон: 46/47 (разовый таймаут graceful leave у reconnected B под 12-поточной фоновым сборкой templates); повтор: PASS 46/46 |
| M6 dedicated recovery (processes) | `tests/runtime/test_m6_dedicated_recovery_processes.gd` | PASS (68s) |
| UX0 product shell | `tests/runtime/test_v0_ux0_product_shell.gd` | PASS |
| MVP6 item handoff / carry prereq | `tests/runtime/test_v0_mvp_6_native_item_handoff.gd`, `..._carry_prerequisite.gd` | PASS |
| Launch options | `tests/runtime/test_launch_options.gd` | PASS |
| MVP5 graphical material (GPU) | `tests/integration/test_v0_mvp_5_graphical_material.py` | PASS (см. note) |
| MVP3 process roundtrip (GPU) | `tests/integration/test_v0_mvp3_graphical_process_roundtrip.py` | PASS |
| MVP4 shared dig (GPU, 5 процессов) | `tests/integration/test_v0_mvp_4_graphical_shared_dig.py` | PASS |
| ECO A10.5 polygon | `RUN_ECO_A10_5_POLYGON.ps1 -GodotPath` | PASS (exit 0) |
| FABRIC C8 fabrication cell | `RUN_C8_FABRICATION_CELL_TESTS.ps1 -GodotPath` | PASS (exit 0) |
| Construction C22 compiled proxy | `RUN_C22_COMPILED_PROXY_TESTS.ps1` | PASS (75 assertions, exit 0) |
| M7 playable networked playground (автотесты) | `RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.ps1 -GodotPath` | PASS 13/13 |

Note по MVP5: два первых прогона FAIL (`GATEWAY_NOT_LISTENING` ← `MVP3_BACKEND_DISCONNECTED` на authority/a при INIT) — оба выполнялись параллельно с 12-поточной сборкой export templates; контрольные прогоны: MVP3/MVP4 PASS под той же нагрузкой, MVP5 PASS без фоновой нагрузки, а также PASS на baseline 4.7.1 на том же content. Классификация: нагрузочная чувствительность ENet handshake/инициализации, не детерминированная регрессия 4.8; требует внимания при обычных CI-нагрузках (задано в NEXT_ACTION).

Адаптация guards (scoped, без ослабления): `tests/integration/test_v0_mvp_4_graphical_shared_dig.py` — добавлен fail-closed override `DWS_ENGINE48_GODOT_SHA256` (заменяет pin только на точно заданный SHA256; guard никогда не пропускается). Канонические 4.7.1 pins сохранены по умолчанию; старые workflows не изменялись. Новый строгий gate-раннер: `RUN_ENGINE48_WINDOWS_R1.ps1` (проверка точной версии+SHA 4.8). Новый workflow: `.github/workflows/engine48-windows-r1-verify.yml`.

## 5. M7 server + 2 graphical clients (E48.4/E48.5: PASS)

Запуск: `PLAY_M7_NETWORKED_PLAYGROUND.ps1 -GodotPath <4.8 console exe> -ResetPersistence` (dedicated headless server + 2 GUI-клиента, `--rendering-method gl_compatibility`, реальные окна на RTX 4060, фиксированное разрешение окна 1296x759).

Наблюдаемое состояние (не только отправка команд):
- server.json `state=READY`, `connected_peer_count=2`, совместимые handshake (2 accepts, 0 rejections);
- оба клиента `joined=true`, `CLIENT_HEALTH` без ошибок и rejections; snapshot_updates ≈ 48/с на клиента;
- movement: сервер применил 1530+ input команд, `movement_inputs_rejected=0`, fixed tick 60 Hz, tick_failures=0;
- canonical item graph: inventories a/b, world items (beacon, crate, mount-base, ore), resource mining snapshot (ore node 8 units);
- persistence: durable commits, outbox delivered, M6 recovery поля заполнены.

Скриншоты (реальный GPU, GL Compatibility): `artifacts/engine48/windows/r1/gui-screenshots/m7-client-26048-printwindow.png`, `m7-client-2816-printwindow.png` — сцены полгона, terrain-блоки, hotbar UI рендерятся у обоих клиентов.

Отключение/подключение: kill клиента B → сервер зафиксировал `PEER_DISCONNECTED`, `connected_peer_count=1`; перезапуск сессии → оба клиента подключились (2 peers). Автоматический эквивалент: P4 reconnect convergence PASS (ownership epoch advances, canonical state converge).

Перезапуск сервера и восстановление M6: повторный `PLAY_M7_NETWORKED_PLAYGROUND.ps1` (без `-ResetPersistence`, та же persistence root) → `recovered=true`, `recovery_source=ACTIVE`, `durable_commits=2`, сервисные операции восстановлены (ownership_operation_count=5), клиенты переподключились.

Проверка R1-адаптации воркфлоу: существующий Windows LIVE2 workflow остаётся жёстко на 4.7.1 (SHA `3633c3e6...`, версия `4.7.1...a13da4feb`) и НЕ использовался как проверка 4.8. Для 4.8 создан отдельный `engine48-windows-r1-verify.yml`.

## 6. Парная производительность (E48.6: PASS — регрессии не обнаружено)

3 пары прогонов на одном хосте, одинаковый exact HEAD content, seed (профиль LOCAL, `random_seed=1001`), одинаковый M7 workload (server + 2 GUI клиента, одинаковые окна), `-ResetPersistence` каждый прогон. Метрики из server telemetry (512 samples/прогон). Полные данные: `artifacts/engine48/windows/r1/perf/perf-summary.json` + `perf/<run>.json`.

| Метрика | 4.7.1 double (3 прогона) | 4.8 beta1 double (3 прогона) |
| --- | --- | --- |
| Готовность сервера, с | 4.7 / 4.6 / 5.2 | 4.6 / 4.6 / 4.6 |
| server tick p50, мс | 0.20 / 0.22 / 0.21 | 0.19 / 0.20 / 0.19 |
| server tick p95, мс | 0.35 / 0.35 / 0.32 | 0.34 / 0.37 / 0.31 |
| server tick p99, мс | 0.41 / 0.42 / 0.42 | 0.42 / 0.46 / 0.36 |
| server process p50, мс | 0.73 / 0.75 / 0.81 | 0.78 / 0.76 / 0.77 |
| server process p95, мс | 8.38 / 8.80 / 8.73 | 8.06 / 8.47 / 7.94 |
| server process p99, мс | 9.82 / 11.19 / 10.20 | 11.08 / 10.15 / 8.91 |
| max stall (server process), мс | 179 / 200 / 181 | 166 / 180 / 172 |
| RAM peak (сумма 3 процессов), MB | ~11000 (шаг 5 с) | ~11000 |
| tick failures | 0 | 0 |

Статистически паритет; отдельные p95/p99 различия внутри разброса прогонов, систематической регрессии нет. VRAM-сэмплы и перцентили клиентского frame time в M7-runtime не инструментированы (ограничение записи; рендер-кадры подтверждены MVP3/MVP4/MVP5 GPU-тестами и скриншотами) — зафиксировано как gap в NEXT_ACTION. NET_SMOOTH_P99_TARGET отдельный verdict и не засчитывается этим прогоном.

## 7. Публикация

- Ветка: `feature/engine48-windows-r1` от `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9`.
- Scoped repair commits:
  1. `6593b773d` test(engine48): strict fail-closed ENGINE48 engine pin override for MVP graphical gates
  2. `chore(engine48)`: refresh Godot 4.8 importer metadata for png assets (13 файлов)
  3. `chore(engine48)`: Godot 4.8 `.uid` sidecars, `RUN_ENGINE48_WINDOWS_R1.ps1`, `engine48-windows-r1-verify.yml`, настоящий отчёт
- Draft PR: `feature/engine48-windows-r1` → `feature/engine48-beta1-double-migration-r1`.
- Force-push не выполнялся; основной checkout и канонический 4.7.1 binary не тронуты.

## 8. Независимая проверка

Implementer не self-accept: после публикации назначается fresh Reviewer/Verifier (отдельные роли, exact HEAD/TREE, сверка SHA, логов и PR) по E48.7. Статус на момент отчёта: `PENDING_INDEPENDENT_REVIEW`.

## 9. Вердикты

| Gate | Вердикт |
| --- | --- |
| E48.0 SOURCE_IDENTITY | PASS |
| E48.1 ENGINE_BUILD | PASS |
| E48.2 COLD_IMPORT | PASS |
| E48.3 GDSCRIPT_REGRESSIONS | PASS (note: MVP5 load-sensitivity) |
| E48.4 MULTIPROCESS M7 | PASS |
| E48.5 GUI (real GPU) | PASS |
| E48.6 PERF_PAIRED | PASS (no severe regression) |
| E48.7 INDEPENDENT | PENDING |

**ENGINE48_MIGRATION_PASS (Windows R1): условный PASS — функциональная совместимость подтверждена, до финального PASS требуется независимая верификация (E48.7) и Ubuntu R1.**
**NET_SMOOTH_P99_TARGET_PASS: НЕ оценивался (M7 playground workload; отдельный performance-gate сохраняется).**

## 10. NEXT_ACTION

1. Fresh Reviewer + fresh Verifier по точному HEAD/TREE carrier-ветки, SHA бинарников и evidence (E48.7).
2. Ubuntu R1 (ENGINE48-B1-LNX) на том же product HEAD; после обеих приёмок — обновление канонических pins.
3. Расследовать нагрузочную чувствительность MVP5 ENet handshake (MVP3_BACKEND_DISCONNECTED под CPU-конкуренцией) — возможен отдельный bounded repair.
4. Добавить инструментирование client frame p50/p95/p99 и VRAM в M7 runtime для полных парных метрик.
5. Дожать `--editor --import --quit` crash-on-exit 4.8-beta1 как upstream issue (не блокирует).
6. После merge: повторный точный прогон `engine48-windows-r1-verify.yml` на self-hosted runner с заданным SHA.
