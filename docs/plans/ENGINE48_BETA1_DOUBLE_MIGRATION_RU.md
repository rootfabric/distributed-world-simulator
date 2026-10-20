# ENGINE48 R1 — переход Distributed World Simulator на Godot 4.8 beta 1 (x86_64 / double precision)

**Дата решения:** 2026-10-20. **Решение пользователя:** перейти на Godot 4.8, сразу начинать параллельную Windows + Ubuntu приёмку. **Тип:** ENGINE_UPGRADE_CANDIDATE, HIGH risk, migration gate; не объявлять работу VERIFIED без независимых машинных доказательств.

## 0. Границы и источники истины

- Канонический базовый HEAD проекта: `0a4f48d018e7eadfbb4df377b386be89062537f1`. Worktree создаётся из этой миграционной ветки; если origin/main двинулся, сообщать `MAIN_DRIFT`, не переосновывать/мержить молча.
- Исходник Godot: официальный source asset `https://github.com/godotengine/godot-builds/releases/download/4.8-beta1/godot-4.8-beta1.tar.xz`.
- SHA256 исходного tar.xz: `6d49c02e438935e49a12231d857b2b56131948b004d5b668bf295c9bc3b2281c` (проверять обязательно до распаковки).
- В официальном release metadata указан движковый source commit `4d10419cacd6d3009976e8f9fd3abd970fd58018`. Обязательно задать переменную окружения `GODOT_VERSION_STATUS=beta1` при каждой сборке, записать `--version`.
- Компилировать НА КАЖДОЙ ОС самостоятельно: `platform=windows|linuxbsd target=editor arch=x86_64 precision=double`, `target=template_debug` и `target=template_release` с теми же `arch=... precision=double`; без модификаций upstream source. Это разные требования: x86_64 — разрядность исполняемого файла, double — численная точность.
- Проектный renderer остаётся `GL Compatibility`, physics interpolation и остальные runtime-конфигурации неизменны. Не совмещать engine upgrade с переходом на Vulkan/Forward+, новым сетевым протоколом или оптимизациями предметной модели.
- Нельзя заменить старый binary, удалить существующий `C:\Godot\godot\bin` / `~/.local/opt/godot-double-4.7.1-a13da4f`, использовать обычный Godot single, менять canonical main или force-push.
- `project.godot` в ветке-кандидате получает маркер `4.8`; `main` до отдельной приёмки остаётся работоспособной точкой отката на 4.7.1.

## 1. Необходимые роли и порядок

**ENGINE48-B1-WIN (Windows implementer/executor)** и **ENGINE48-B1-LNX (Ubuntu implementer/executor)** выполняются независимо по одному точному product HEAD; каждый записывает `OS`, `product_head`, `product_tree`, `engine_origin_commit`, `source_archive_sha256`, `engine_sha256`, `editor_version`, `export_debug_sha256`, `export_release_sha256`, toolchain, build flags, тесты, лог, machine summary. Fresh независимый verifier проверяет обоих; implementer не self-accept.

## 2. Gates

| Gate | Минимальное доказательство | Fail-closed |
| --- | --- | --- |
| E48.0 SOURCE_IDENTITY | Оба скачали официальный архив, SHA совпал, один upstream commit | checksum, неизвестная версия, single precision, не x86_64 |
| E48.1 ENGINE_BUILD | Собраны 3 native binaries на Windows и 3 на Ubuntu, версия 4.8 beta1 double, файлы хэшированы; headless/GPU поддерживаются | build / missing executable / wrong version |
| E48.2 COLD_IMPORT | Отдельный чистый worktree, `--headless --editor --import --quit`, class cache и ресурсы валидны; tracked clean | parse/script/UID/import error, unexpected diff |
| E48.3 GDSCRIPT_REGRESSIONS | Актуальные LIVE2, USER1, M6, NX2, MVP, construction, ECO и FABRIC тесты из HEAD без ослабления assertions | any test fail |
| E48.4 MULTIPROCESS | Реальный сервер + 2 клиента; visibility/movement/mining/build, region seam, authority, reconnect, server restart, replay, ownership; отдельные user-data/ports и deterministic seeds | дубли authority, divergence, lost committed state, crash, partial without report |
| E48.5 GUI | Windows + Ubuntu graphical scenes (не считать headless заменой GPU-теста): камера, CHAR1/CHAR2, GL Compatibility, terrain/vegetation, mining/build, seams, screenshots/logs | crashes, missing avatar, persistent rendering failures |
| E48.6 PERF_PAIRED | На том же хосте сравнить baseline 4.7.1 double и 4.8 beta1 double на одном exact product content/seed/topology (для 4.7.1 использовать совместимый snapshot без 4.8 marker); >=3 paired runs; p50/p95/p99 tick/frame, stalls, allocation, RSS/VRAM, load time | uncontrolled run, no baseline, reproducible severe regression |
| E48.7 INDEPENDENT | Fresh Reviewer + fresh Verifier проверяют точные HEAD/TREE/binaries/logs, PR + PC0/check consistency | self-accept/partial evidence/identity drift |

### Разделить два вердикта

- `ENGINE48_MIGRATION_PASS`: функциональная совместимость и отсутствие статистически подтверждённой регрессии; цель теста — безопасная смена движка.
- `NET_SMOOTH_P99_TARGET_PASS`: серверный p99 <= 25 мс — отдельный performance verdict. Известные ~39.81–41.31 мс NET-SMOOTH1 R3C.4 R2 и работа нормализации M6 в главном потоке не считаются автоматически решёнными новым движком. Если миграция не ухудшила это, фикс остаётся отдельной задачей.
- **Не сравнивать raw FPS Windows и Ubuntu как признак регрессии; сравнивать пару 4.7.1 vs 4.8 на одном железе.** Если 4.7.1 не запускает конфигурацию 4.8, использовать временную отдельную копию того же tracked content с исходным feature marker как benchmark-only, не коммитить её.

## 3. Подтверждённые в репозитории источники команд

- `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/GODOT_LOCAL_TESTING_RU.md`, `docs/MCP_GODOT.md` — прочитать перед работой.
- `.github/workflows/v0-live2-r1-targeted-windows.yml`, `.github/workflows/v0-user1-sem1-linux-exact.yml` — реальные проверенные примеры точных команд; старые хэши 4.7.1 заменить В ИЗОЛИРОВАННОМ ENGINE48 гейте, не ослаблять старые product workflows без контроля.
- Примеры существующих тестов: `tests/network/test_v0_live2_enet_rollover.gd`, `tests/network/test_nx2_physical_channel_processes.gd`, `tests/runtime/test_v0_live2_human_gameplay_bridge.gd`, `tests/runtime/test_v0_user1_first_usable_slice.gd`, `tests/runtime/test_v0_user1_product_seam_bridge.gd`, `tests/runtime/test_v0_p4_live_two_client_reconnect_convergence.gd`, `tests/runtime/test_m6_dedicated_recovery_processes.gd`, `tests/integration/test_v0_mvp_5_graphical_material.py`. Перед запуском подтвердить наличие на точном HEAD и контракт каждой команды.
- `PLAY_M7_NETWORKED_PLAYGROUND.ps1` / `.sh` — существующие entrypoints, использовать после чтения актуальных аргументов и зависимостей. Для графической автоматизации следовать MCP Godot, не фальсифицировать screenshots.
- Обнаружены реальные hardcoded 4.7.1 guards в `RUN_V0_PLAYABLE_SEAMLESS_CLIENTS.sh` и `RUN_V0_SM1_GRAPHICAL.sh`, а также 4.7.1 runtime paths/version checks в части legacy workflow. Перед тестом ENGINE48 необходимо отдельно заменить их на **строгую проверку фактически собранной** 4.8-beta1 double binary (с её подтверждённым SHA) только в scoped migration/runner changes; не удалять guard и не объявлять skip PASS. Старые 4.7.1 workflows остаются baseline, пока не проверены новые.
- `RUN_C22_COMPILED_PROXY_TESTS.ps1` / `.sh` и `RUN_ECO_A10_5_POLYGON.ps1` — дополнительные области регрессий при наличии поддерживаемых входов. Подобрать сопоставимые Ubuntu invocation из реальных runner commands.

## 4. Машинные инструкции по получению исходника

Windows: отдельный каталог `C:\Godot\godot-4.8-beta1-src`; проверить SHA256 `Get-FileHash`; распаковать официальный tar.xz; MSVC x64 compiler / Python 3.9+ / SCons 4.4+; использовать `d3d12=no`, если SDK отсутствует и не требуется текущему GL Compatibility, все отключённые modules/flags документировать. Собирать editor, template_debug, template_release, протоколировать полный stdout/stderr и коды выхода. Не заменять канонический исполняемый файл.

Ubuntu: отдельный каталог `$HOME/.local/src/godot-4.8-beta1` и install `$HOME/.local/opt/godot-double-4.8-beta1`; `curl --fail --location` + `sha256sum -c`; GCC 9+ / Python 3.9+ / SCons 4.4+ и официальные libx11/libxcursor/libxinerama/libxi/libxrandr/mesa/alsa/pulse/wayland dependencies. Собирать x86_64/double editor + 2 templates. Не запускать движок через sudo.

При компиляции фиксировать toolchain, exact flags, source digest и бинарные SHA256. Обязательно проверить `--version` у editor и templates с учетом поддержки CLI. `custom_build` suffix допустим только при точном source SHA; Godot 4.8 beta1 обязателен.

## 5. Артефакты и выход

Сохранять в `artifacts/engine48/<os>/<run-id>/`: `source.json`, `build.json`, `binary-sha256.txt`, `cold-import.log`, `test-matrix.json`, `gui-screenshots/`, `net-traces/`, `performance.json`, `summary.json`, `tracked-status.txt`, `reproduction.md`. В финале: `PASS | FAIL | INSUFFICIENT_EVIDENCE` для каждого gate, точные SHA проекта и движка, ссылки на GitHub Actions/PR evidence, и раздел `NEXT_ACTION`.

## 6. Интеграция

Только после независимой Windows + Ubuntu приемки — обновление канонических runtime pins, тестовых workflows и документации, свежий exact-head verifier, PC0, затем явный merge gate на `main`. В тестовой ветке не заявлять `main` migrated и не принимать временную успешную CLI-сборку за готовый сетевой продукт. Контрольная 4.7.1 double остаётся rollback-путём, а исправление NET-SMOOTH1 продолжает собственный performance-gate.

## Официальные источники

- https://github.com/godotengine/godot-builds/releases/tag/4.8-beta1
- https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/
- https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_windows.html
- https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_linuxbsd.html
- https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
