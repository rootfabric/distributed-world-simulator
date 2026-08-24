# V0 P6 R3 — MCP visual evidence (HA-001): исполнение и результат

Дата: 2026-08-24 (UTC+10)
Решает: `P6-R3-HA-001-MCP-VISUAL-EVIDENCE-ROUTING` из event 0007 (WAITING_HUMAN)
Закрывает предикат: `V0_P6_P7_P11_MCP_VISUAL_EVIDENCE_PASS` (№12 леджера WO `V0-P6-R3-WO-001`)
Маршрут: **вариант 2 из decision queue — «предоставить среду (MCP)» и провести сессию автономно** на этой же Ubuntu-машине. Операторская Windows-сессия не потребовалась; deferral не понадобился.

## Exact head и среда

```text
ветка ............ repair/v0-p6-persistence-exactly-once-r1
exact HEAD ....... 20b00f897e1f42bea9bc5474f85d3995a0d0a478
checkout ......... /home/yurig/distributed-world-simulator/worktrees/v0-p6-r3-mcp-evidence
                   (изолированный detached-worktree на 20b00f89; tracked-файлы не менялись)
Godot ............ 4.7.1.stable.double.custom_build.a13da4feb
путь ............. /home/yurig/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64
SHA-256 .......... bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7 (совпадает с каноном GODOT_LOCAL_TESTING_RU.md)
MCP host ......... breakpoint-mcp 1.82.0 (npx, stdio), BREAKPOINT_TOOLSETS=cli,runtime,processes,
                   BREAKPOINT_PRIVILEGED_GROUPS=code-execution
addon ............ Breakpoint MCP 1.7.0 (checked-in, локальный фикс physical_keycode сохранён; init --force не запускался)
дисплей .......... X11 через DISPLAY=:0 (XWayland), OpenGL 3.3 NVIDIA 580.173.0; Xvfb не требовался
viewport ......... 1280x720
```

Отступление от буквы контракта `docs/MCP_GODOT.md` (честно фиксируется): документ
описывает Windows-путь `godot.windows.editor.double.x86_64.console.exe`; здесь
использован канонический double-бинарник той же custom-сборки для Ubuntu из
`docs/GODOT_LOCAL_TESTING_RU.md` (§3), версия и SHA-256 сверены. Это Linux-эквивалент
пункта чек-листа №1 «double x86_64 сборка». Секрет `.godot/breakpoint_mcp.secret`
не читался и не выводился (пункт №10). Сессия выполнена агентом через JSON-RPC
over stdio к host (эквивалент операторской MCP-сессии; все вызовы — только через
MCP tools, без SendKeys/PostMessage/desktop capture).

## Канонический прогон (final)

Запуск: `godot_run_managed {"scene":"res://scenes/testing/playground.tscn"}`
→ `managed_id=godot-1`, `bridge_ready` за 3054 мс; готовность подтверждена
`runtime_get_tree` (UniversalTestPlayer + ItemGameplayController + ItemWorldInteractor)
и `runtime_assert_scene_structure` (4/4, ok). Baseline `runtime_get_log` latest_seq=2.

### Сценарий 1 — инвентарь (Tab)

| Проверка | Результат |
|---|---|
| `inventory_open` исходно `false` | PASS (runtime_get_property) |
| Tab down/up (`keycode 4194306`) → `inventory_open:true` | PASS (`runtime_assert_node_state`, mismatches: []) |
| `runtime_assert_screen_text "ИНВЕНТАРЬ"` | PASS (2 совпадения, вкл. `ItemInventoryUI/InventoryScreen/Margin/Main/Header`) |
| Hover занятого слота рюкзака (263,282) | PASS — кадр изменился, инспектор показал карточку «Полевой маяк» (survey_beacon, стак 3/5) |
| Повторный Tab → `inventory_open:false` | PASS |

### Сценарий 2 — подход к контейнеру и открытие по `E`

Навигация агента: калибровка чувствительности камеры по узлу
`UniversalTestPlayer/CameraAnchor/CameraYaw` (40 px → −0.0625 рад), серво-наведение
на цель (3, 0.8, −2), короткие импульсы `move_forward` с release, проба
`ItemWorldInteractor.current_snapshot` на каждой итерации.

| Проверка | Результат |
|---|---|
| Фокус интерактора получен | PASS — `item_container`, title «Универсальный ящик», prompt «E — открыть контейнер», distance 5.7 м, hit_position [2.85, 0.85, −1.65] |
| `E` down/up (`keycode 69`) → `inventory_open:true` | PASS |
| `runtime_assert_screen_text "Универсальный ящик"` | PASS (TitleLabel внешней панели контейнера) |
| Игрок переместился | PASS (0,0.01,6 → 0.90,0.01,3.60) |

### Завершение

- Все actions отпущены (`pressed:false` для move_*, jump, boost) — пункт №5.
- Финальный `runtime_screenshot` получен — пункт №7 (все кадры только `runtime_screenshot`, не desktop).
- Новые warning/error в runtime-логе после baseline: **0** (latest_seq 2 → 2) — пункт №8.
- `godot_stop {"id":"godot-1"}` → перепроверка `godot_output`: `exited:true` — пункт №11.
- PNG/логи только в `artifacts/` — пункт №9. PASS не фабриковался; каждая проверка
  подтверждена состоянием мира, а не `injected:true` — пункт №6.

Итог прогона: **17/17 проверок PASS** (`all_pass: true`).

## Артефакты

Каталог прогона: `artifacts/test-results/p6r3-mcp-visual-final-2026-08-24T06-44-42/`
(summary.json, transcript.jsonl, tools-list.json, ready-tree.txt, managed-output-final.json,
new-warning-error-log.json — в worktree v0-p6-r3-mcp-evidence).

MCP viewport screenshots (1280x720, `runtime_screenshot`):

| Файл (artifacts/mcp/) | SHA-256 |
|---|---|
| final-s1-inventory-open.png | 738d3a1fb5eb0ba2259cb64931d32944edb9f1cc60fbdbc55bfe86e90effc357 |
| final-s1-hover-backpack-item.png | f489e20439eb59ac4a85eb2bf80ead6708c457cb766e3a6d33e28d8b461580e9 |
| final-s2-container-open.png | 690d0c0fd5fd26e346ad127ae51a5873961201c1e32d9966286ace9c542788d2 |
| final-final-state.png | 8b9940ea61e5dcfb7ae8e2b5694154d6f4976bccf89a6fb3d6be7bf6ff6e4877 |

Копии PNG продублированы в artifacts/mcp/ основного чекаута для удобства просмотра.

## Воспроизводимость и итерации драйвера

Прогон повторён 4 раза; кадры инвентаря/контейнера байт-в-байт воспроизводимы
между прогонами (738d3a1f…, 690d0c0f…, 8b9940ea…). Итерации 1–3 были отладкой
самого драйвера сессии (не мировых дефектов), зафиксированы честно:

- run1: эвристика фокуса интерактора ошибочно пропустила пустой snapshot → `E` без фокуса (ожидаемо не открыл контейнер); парсинг `ok` assert-инструментов отсутствовал;
- run2: yaw читался с корня игрока вместо `CameraYaw` → калибровка 0; hover по пустому hotbar-слоту не меняет кадр (пустые слоты не дают tooltip — по дизайну UI);
- run3: S2 полностью PASS; остался только hover-чек (решён в run4/final наведением на занятый слот);
- прогон 2026-08-24T05-23/06-10 (run3/run4) выполнялся в main-чекауте, который параллельным процессом переключался между ветками (nx2-r1 @66deb46) — эти прогоны не используются как доказательство предиката; канонический прогон выполнен в изолированном worktree на exact 20b00f89.

## Статус предиката

`V0_P6_P7_P11_MCP_VISUAL_EVIDENCE_PASS` — **PASS** (исполненный MCP-прогон,
exact-head 20b00f89, durable-артефакты выше). HA-001 снят из decision queue
(см. event 0008). Чек-лист приёмки `docs/MCP_GODOT.md` (п.1–11): выполнен,
с оговоркой Linux-эквивалента бинарника (п.1) и hover по занятому слоту (п.10 сценария 1).

На следующие роли это не влияет: fresh Reviewer/Verifier, формальный PC0 и
checkpoint proposal продолжают требоваться по леджеру (№14–24).
