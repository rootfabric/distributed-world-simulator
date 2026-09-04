# WORLD PACKS Gallery — запуск и MCP-захват под Windows

Ветка: `feature/world-packs0-content-packs-r1`.
Worktree: `C:\distributed-world-simulator\wp-r1` (основной checkout не переключается).
Godot: `4.7.1.stable.double.custom_build.a13da4feb` —
`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe` (тесты)
или `...\double.x86_64.exe` (графика). Все команды — PowerShell, из корня worktree.

## A. Графический просмотр галереи (без тестов)

```powershell
$Gui = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
# Общий вид: 6 площадок с нейтральной средой
& $Gui --path C:\distributed-world-simulator\wp-r1 res://scenes/labs/world_packs/world_packs_gallery.tscn
# Фокус одного пакета (полное окружение: небо/свет/туман)
& $Gui --path C:\distributed-world-simulator\wp-r1 res://scenes/labs/world_packs/world_packs_gallery.tscn -- --pack=WP-MOON-INDUSTRIAL
```

Ожидаемый маркер в stdout: `WORLD_PACKS_GALLERY_READY` (и
`WORLD_PACKS_GALLERY_PACKS=6` в pads-режиме). Закрытие — окно крестом.

## B. Тест-гейты (headless)

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_WORLD_PACKS_WP0_1_TESTS.ps1        # схема манифестов
.\RUN_WORLD_PACKS_WP0_2_TESTS.ps1        # лицензионный ledger
.\RUN_WORLD_PACKS_PROFILE_TESTS.ps1      # все 6 пакетов (selftest)
.\RUN_WORLD_PACKS_WP0_9_TESTS.ps1        # POI-библиотека
.\RUN_WORLD_PACKS_WP0_10_HARNESS.ps1     # полная цепочка + harness
```

Ожидаемые финальные строки: `WORLD PACKS WP0.x: PASS`.
Свежий worktree сам сделает import-preflight (первый запуск дольше).

## C. MCP-захват с проходом камер (автоматические скриншоты)

Требования: Node.js 22+ (npx), аддон `breakpoint_mcp` уже включён в проект,
никакой второй Godot-игры на порту 9081 параллельно.

```powershell
node tools\world_packs\mcp_capture_driver.mjs
```

Скрипт сам: поднимает MCP-host (`npx breakpoint-mcp`, loopback-порты),
запускает галерею как managed-процесс, делает обзорный кадр, 8-ракурсный
орбитальный проход камерой вокруг ряда площадок (`orbit_step` через
`runtime_call_method`), по кадру на каждый пакет в фокусе и 8-ракурсную орбиту
вокруг Moon Industrial, затем останавливает именно свой процесс.

Результаты: `artifacts\world_packs_mcp\*.png` (каталог вне git),
лог: `artifacts\world_packs_mcp\driver.log`, сводка: `summary.json`.
Ожидаемо: `pads static+orbit shots: 9/9` и `RESULT ... shot=true` по каждому
пакету.

## Диагностика

- `bridge_ready=false` при старте: подождите и повторите — после force-kill
  предыдущей игры порт 9081 освобождается с задержкой.
- `9081 is already bound`: жива предыдущая игра — остановите её
  (`Get-NetTCPConnection -LocalPort 9081` → `Stop-Process -Id <pid>`), только
  убедившись по пути процесса, что это ваш экземпляр.
- Осиротевший MCP-host (node) — ищется так:
  `Get-CimInstance Win32_Process -Filter "Name='node.exe'" | ? { $_.CommandLine -match 'breakpoint-mcp' }`.
- Диагностика мостов без входа в игру:
  `npx -y breakpoint-mcp doctor --project C:\distributed-world-simulator\wp-r1 --json`.
- Ошибки загрузки сцены — читать stderr managed-процесса
  (`godot_output` в драйвере) или логи в `artifacts\world_packs_mcp\`.
