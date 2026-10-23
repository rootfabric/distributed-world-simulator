# ENGINE48 Linux R2 — Независимый верификационный отчёт (Verifier R2)

- Роль: независимый Verifier (не участвовал в реализации, все проверки выполнены с нуля на машине).
- Дата выполнения: 2026-10-23 (UTC), машина: shared Ubuntu 22.04, Xvfb :99 (llvmpipe software GL).
- Изданный tip: `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` (origin/feature/engine48-linux-r1).
- BASE: `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9`, BASE^{tree} (вычислен независимо): `3c0a04c78eca918717e8e836b1c1bf2836cb5596`.
- Все логи независимых прогонов: `worktrees/engine48-linux-guards/artifacts/engine48/linux/verification/r2_*.log` (untracked evidence).

---

## A. Git identity — PASS

| Проверка | Факт | Результат |
|---|---|---|
| guards worktree HEAD | `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` | PASS (совпадает с ожидаемым) |
| HEAD^{tree} (вычислен самостоятельно) | `0d49082be99b0bb125d26c28f45ac19840426f0d` | зафиксировано |
| BASE^{tree} (вычислен из git, не из чата) | `3c0a04c78eca918717e8e836b1c1bf2836cb5596` | PASS (совпадает с заявленным BASE_TREE) |
| `git rev-list --count BASE..HEAD` | **7** | PASS |
| `git merge-base --is-ancestor BASE HEAD` | OK | PASS |
| `git status --porcelain --untracked-files=no` (guards) | 0 строк | PASS |
| `git fetch origin feature/engine48-linux-r1` | origin = `7aaa7fa9…` == локальный tip; diff пуст | PASS |

7 коммитов (старые → новые):
1. `29d2e4af4678745d59e2dbc7a4f8902121851702` fix(engine48): pin Linux runner guards to Godot 4.8 beta1 double build
2. `231b3e9b2b7f7d7810c6729dd59b4a1db3ed075d` chore(engine48): adopt Godot 4.8 generated import metadata and script UIDs
3. `24fc10ee1dedfe5b49d8b819fe7ef6591f5c0750` fix(engine48): pin Linux graphical integration engine to 4.8 beta1 double
4. `c1d3070fec0cd2cb87d002bb8bd3205bd0d7a4ca` fix(engine48): allow Xvfb location override in Linux SM1 graphical gates
5. `5f71900ff2668f32b42588581b80eaa89e1c876e` fix(engine48): resolve Xvfb via XVFB_BIN in Linux graphical process gates
6. `841cf13e2c3435a04da30a65062a722ed6f704c2` fix(engine48): align P7.1 gate summary pins with 88-assertion current test
7. `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` fix(engine48): align MW10 suite marker pins with current assertion counts

### A5. Аудит diff BASE..HEAD на ослабление тестов — PASS (ослаблений нет)

Содержательные изменения: ровно 30 файлов (16 *.sh, 13 *.gd, 1 *.py), 56 вставок / 56 удалений; плюс 296 новых `*.uid` (A) и 13 изменённых `*.import` (только метаданные текстур/аддона, сгенерированные 4.8). Игнорируя `*.uid/*.import` — ничего кроме перечисленного.

- (a) Пины движка 4.7.1→4.8.beta1: **да** — `EXPECTED_GODOT`/`EXPECTED_GODOT_VERSION` = `4.8.beta1.double.custom_build.4d10419ca` в 15 RUN-скриптах; в `tests/integration/test_v0_mvp_4_graphical_shared_dig.py` пин linux-бинарника `bfa7ce63…` → `4d72a93e…` (совпадает с evidence-таблицей).
- (b) XVFB_BIN override с fallback `/usr/bin/Xvfb`: **да** — в `RUN_V0_SM1_AUTHORITY_RECOVERY.sh`, `RUN_V0_SM1_GATEWAY_FAILURE_RESTART.sh`, `RUN_V0_SM1_GRAPHICAL.sh` (`${XVFB_BIN:-/usr/bin/Xvfb}`) и в 10 `tests/runtime/*.gd` (`OS.get_environment("XVFB_BIN")` с fallback).
- (c) Пины числа assertions ТОЛЬКО увеличены: **да** — MW10 `184→201`, `51→53` (RUN_MW10_CROSS_REGION_MATTER_TRANSACTIONS_TESTS.sh); P7.1 `83→88` (RUN_V0_P7_3 и RUN_V0_P7_4 gates). Других числовых изменений пинов нет.
- (d) Ни одного уменьшения assertions/таймаутов/порогов: **подтверждено** полным просмотром diff (все числовые изменения — три увеличения из (c); таймауты/пороги не менялись).
- (e) Продуктовый код `scripts/` не изменён: **подтверждено** — в scripts/ только 133 новых `.uid`-файла (A), ни одного M/D `.gd`.

## B. Строгие проверки движка — PASS

- `sha256sum` всех 4 бинарников **точное совпадение** с `artifacts/engine48/linux/build/binary-sha256.txt`:
  - `4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f` godot-double-4.8-beta1 editor
  - `af1e29d1c53688786e0551c54b1d1105300955302180b02a7fdf5711d46ff897` 4.8 template_debug
  - `fffb8f53f85bda1757572638d88386e80f90a7e0abf1be61638544197f4506e7` 4.8 template_release
  - `f8dbe9d873d368e1b7587ce3aae022b980e8176e9d1fd237894764d574fc272a` godot-double-4.7.1-a13da4f editor
- `--version` точные строки: `4.8.beta1.double.custom_build.4d10419ca` (exit 0) и `4.7.1.stable.double.custom_build.a13da4feb` (exit 0).

### B8. Расхождение с work order (GODOT_EDITOR_SHA256=25047b82ab92…) — NOT_FOUND

- Поиск: все файлы `~/.local/opt` (любого размера), все файлы ≥1MB под `~/.local/src` (включая деревья godot-4.8-beta1 и godot-4.7.1-baseline), top-level файлы `~/.local/src` (включая оба tar.xz и .sha256-sidecar'ы; sidecar'ы совпадают с фактическими tarball'ами: `0230d490…` и `6d49c02e…`).
- Результат: **ни один файл на машине не имеет SHA256 с префиксом `25047b82ab92`**. Реальный 4.8 editor = `4d72a93e…`, что совпадает с evidence-таблицей и с пином в `test_v0_mvp_4_graphical_shared_dig.py`. Зафиксировано как расхождение документа (work order), не как дефект ветки.

## C. Cold import на свежем worktree изданного tip — PASS

- `git worktree add --detach worktrees/engine48-r2-verify 7aaa7fa9…` — создан, HEAD подтверждён.
- Cold import: `BREAKPOINT_RUNTIME_DISABLED=1 GODOT_SILENCE_ROOT_WARNING=1 … --headless --editor --import --quit` → **exit 0**, stderr/stdout: SCRIPT ERROR: **0**, Parse Error: **0**, ERROR: **0** (лог `r2_cold_import.log`).
- После импорта `git status --porcelain --untracked-files=no` = **0** tracked-изменений.
- По завершении всех проверок worktree удалён (`git worktree remove --force`), список worktree чист.

## D. Headless-перезапуски на 4.8 (свежий worktree `engine48-r2-verify`) — PASS 7/7

Критерий: exit 0 + ожидаемая PASS-строка + 0 SCRIPT ERROR/Parse Error. Все прогоны на `4.8.beta1.double.custom_build.4d10419ca`.

| # | Suite | Exit | PASS-строка (факт) | Script/Parse errors | Лог |
|---|---|---|---|---|---|
| 12 | MW0 matter contracts | 0 | `MW0 matter contracts: PASS (2011 assertions)` | 0/0 | r2_mw0.log |
| 13 | MW4 matter mutations | 0 | `MW4 matter mutations: PASS (187 assertions / 25.269 s)` | 0/0 | r2_mw4.log |
| 14 | C22 compiled proxy (4 подсьюта) | 0 | contracts PASS (29) / integration PASS (52) / graphical PASS (35) / scale/soak PASS (75) | 0/0 | r2_c22.log |
| 15 | P7.2 lunar matter bubble gate | 0 | `V0-P7.2 BOUNDED LUNAR MATTER BUBBLE GATE GREEN`, EXACT_HEAD=7aaa7fa9…, GODOT=4.8.beta1… | 0/0 | r2_p72.log |
| 16 | P7.3 material batch item graph gate | 0 | `V0-P7.3 MATERIAL BATCH TO ITEM GRAPH GATE GREEN`; внутри `P7.1 authority gate: PASS (88 assertions, 0 failures)` — новый пин подтверждён живым прогоном | 0/0 | r2_p73.log |
| 17 | PLAYABLE_SEAMLESS (all, STEP_MS=800, DISPLAY=:99, LIBGL_ALWAYS_SOFTWARE=1) | 0 | `V0 PLAYABLE SEAMLESS TEST CLIENTS: PASS` (client A/B, gateway A→B→A, dedicated server READY, items convergence) | 0/0 | r2_seamless.log |
| 18 | SM1 L0 | 0 | `SM1_L0_EXACT_HEAD_EXECUTABLE_PASS head=7aaa7fa9… godot=4.8.beta1.double.custom_build.4d10419ca` | 0/0 | r2_sm1l0.log |

TIMEOUT не зафиксировано; все suite уложились в бюджет.

## E. Parity claims на 4.7.1 — PASS (прямые прогоны выполнены, ограничений UID не обнаружено)

Прямой запуск тест-скриптов MW10 бинарником 4.7.1 (`4.7.1.stable.double.custom_build.a13da4feb`) в worktree изданного tip — БЕЗ runner-пина версии:

- `res://tests/matter/transactions/test_mw10_cross_region_transactions.gd` → **PASS (201 assertions)**, exit 0 (r2_mw10_471_direct.log)
- `res://tests/matter/transactions/test_mw10_cross_region_processes.gd` → **PASS (53 assertions)**, exit 0 (r2_mw10_471_proc.log)

Симметричный прямой запуск на 4.8 в том же worktree: **201 / 53 assertions**, exit 0 оба (r2_mw10_48_tx.log, r2_mw10_48_proc.log).

→ Пины 201/53 в RUN_MW10_CROSS_REGION_MATTER_TRANSACTIONS_TESTS.sh — это реальные текущие числа assertions на ОБОИХ движках. Пины (184→201, 51→53) не ослабление: фактическое число assertions выросло ещё до ветки (на BASE), runner-пины приведены к реальности вверх. Техническое ограничение UID (прогнозировавшееся в задании) НЕ подтвердилось — 4.7.1 грузит проект изданного tip без ошибок формата; tracked-статус после 4.7.1-прогонов остался 0.

Сверка пинов семи коммитов с логами gates/ (guards worktree):
- `gates/mw-mw10.log`: `PASS (201 assertions)` / `PASS (53 assertions)`, `MW10 runner: PASS (2/2 suites)` — совпадает с пинами HEAD.
- `gates/mw10-direct-rerun.log`: диагностика старых пинов — реальные выводы 201/53 против старых требуемых маркеров 184/51 (FAIL) — документирует необходимость коммита 7aaa7fa9.
- `gates/p7-3-material-batch.log`: `V0-P7.1 authority gate: PASS (88 assertions, 0 failures)` — совпадает с пином 88 (коммит 841cf13e) и с моим живым прогоном P7.2/P7.3 gates.

## F. M7 multiplayer live (4.8) — PASS (substance) с FINDING по механике result=PASS

### F21. PLAY_M7_NETWORKED_PLAYGROUND.sh (guards worktree, M7_PORT=24699, 2 клиента, LOCAL, DISPLAY=:99)

- Скрипт завершился exit 0, сервер READY, клиенты запущены. Run root: `artifacts/runtime/m7-network-playground/20261023-050047/`.
- `server.json` (живой снимок во время сессии): `state = READY`, `connected_peer_count = 2`, `joins = 2`, `leaves = 0`, handshake `rejections = 0`, `last_error_code = ""`; оба пира в state READY, телеметрия идёт (input/snapshot/control каналы непустые, fixed tick 60Hz тикает, persistence failures = 0).
- Script errors: server.log **0**, client-a.log **0**, client-b.log **0** (также 0 строк ERROR любого рода).
- Процессы остановлены штатно: `STOP_M7_NETWORKED_PLAYGROUND.sh` exit 0, все PID прекращены. Повторный прогон (второй контрольный) — те же результаты (20261023-050434).

### FINDING F-1: `result=PASS` из result JSON при остановке недостижим

`server.json` остаётся `state=READY, passed=false` и после STOP. Причина установлена из кода: `m3_dedicated_server_runtime_p2.gd::stop()` пишет `_write_report("STOPPED", true)` только при вызове stop() внутри движка (строки 1656–1658), а `STOP_M7_NETWORKED_PLAYGROUND.sh` и `perf/perf_pair_run.sh` убивают процессы SIGTERM+SIGKILL через 0.5 c — терминальная запись не выполняется. Контрольный graceful-эксперимент: отдельный прогон с `kill -TERM` серверу и ожиданием 30 c — сервер вышел через 2 c, но `server.json` всё равно `READY/passed=false` (Godot SIGTERM не вызывает runtime stop()). То есть `passed=true` терминально достижим только из in-process жизненного цикла (автоматический тест-драйвер). Это FINDING об evidence-механике PLAY_M7, а не о здоровье сессии: READY/2 пира/0 ошибок подтверждены в двух прогонах.

### Дополнительная независимая проверка: автоматический M7 acceptance на 4.8

`tests/runtime/test_m7_playable_networked_processes.gd` (автоматический демо-драйвер: dedicated server + 2 графических клиента, свой Xvfb через XVFB_BIN):
- Прогон 1: `55 assertions, 4 failures` (B ore pickup не подтверждён сервером; A/B не сошлись с authoritative player checksum; last_error_code клиента B: `ITEM_NOT_VISIBLE_TO_PLAYER`). Exit code процесса 0 (скрипт не выставляет ненулевой exit при failures — отметка для гейтов, см. FINDING F-2).
- Прогон 2 (retry, идентичные условия): **`M7 playable network processes: 55 assertions, 0 failures`** — PASS, полная конвергенс чек-сумм (client == server == `611435a7…`), все clean shutdown. Логи: r2_m7_gate_proc.log, r2_m7_gate_proc_retry.log.
- Исторических M7 acceptance-артефактов на машине нет (это первый запуск такого gate здесь), поэтому прогон 1 классифицирован как **timing-флак под llvmpipe/нагрузкой**, а не регрессия 4.8: детерминированного воспроизведения нет, retry прошёл полностью. В regression-лист 4.8 не включается.

### FINDING F-2: тест-скрипт M7 возвращает exit 0 при failures

`test_m7_playable_networked_processes.gd` печатает failures, но завершается с кодом 0; защита — только grep-обёртка в RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.sh (`grep -Eq '…FAIL…'`). Прямой запуск скрипта (как это делается в ряде пайплайнов) может «молча пройти». Рекомендация (вне scope верификации): ненулевой exit из тест-скрипта.

### F22. Очистка — выполнено

`bash STOP_M7_NETWORKED_PLAYGROUND.sh` после обоих прогонов (exit 0, процессы убраны, active-json удалён). Tracked-статус guards worktree после M7-прогонов: 0.

## G. Ограничения и evidence, потреблённый без перезапуска

- GUI/PERF сырые артефакты НЕ перезапускались (по заданию). Наличие подтверждено:
  - `artifacts/engine48/linux/gui/` — 8 файлов: 471-earth-client-godot.log, 471-earth-server.log, 4 скриншота окон (window-*.png), mcp_runtime_evidence.py, mcp_host_world.py + 7 каталогов MCP-сессий (mcp-471-host, mcp-48-reconnect, mcp-host-world, mcp-main, mcp-world{,2,3}).
  - `artifacts/engine48/linux/perf/PERF_PAIRED_RESULTS.md` + godot48-r{1,2,3} / godot471-r{1,2,3} каталоги и .metrics.json, perf-summary.json.
- Верdict парного PERF (потреблён, не перепроверен запуском): «NO 4.8 REGRESSION FOUND (3+3 pairs)»; парные числа: worst server stage max 686.0 ms (4.8) vs 743.0 ms (4.7.1) — 4.8 лучше на 7.7%; cpu parity (−0.4%); RSS +2.9% стабильно; FPS p50 = 16/16 (llvmpipe-bound).
- REAL_GPU_EVIDENCE = INSUFFICIENT_EVIDENCE: рендер идёт через `Mesa llvmpipe (LLVM 15.0.7)` software GL под Xvfb (подтверждено строкой в gui/471-earth-client-godot.log: `OpenGL API 4.5 … Using Device: Mesa - llvmpipe`), дискретного GPU на машине нет. Это технически корректная фиксация, не провал.
- Тайм-бюджет соблюдён: ни один процесс не потребовал принудительного убийства по 10-минутному лимиту.

## Сводка FINDINGS (не блокирующие миграцию)

1. **B8**: SHA256 `25047b82ab92…` из work order не соответствует ни одному файлу на машине; фактический 4.8 editor = `4d72a93e…` (совпадает с evidence-таблицей и пинами в тестах). Расхождение документа.
2. **F-1**: `PLAY_M7_NETWORKED_PLAYGROUND.sh` + `STOP_M7_NETWORKED_PLAYGROUND.sh` не могут терминально записать `result=PASS` в result JSON (SIGTERM/SIGKILL обходит runtime stop(); проверено дважды, включая graceful-эксперимент). Требование задания «result=PASS» выполнимо только через автоматический M7 acceptance-драйвер.
3. **F-2**: `test_m7_playable_networked_processes.gd` завершается с exit 0 даже при failures; валидация только grep-обёрткой gate-скрипта. Наблюдено на прогоне 1 (4 failures, exit 0).
4. **F-3 (flak)**: разовый сбой M7 acceptance на 4.8 (конвергенс чек-сумм + ore pickup) при первом прогоне; retry при идентичных условиях — PASS 55/0. Классифицировано как timing-флак (llvmpipe/нагрузка), детерминированной регрессии 4.8 нет. Рекомендация: при интеграции M7-gate в Linux-пайплайн предусмотреть один retry либо ужесточить допуски ожидания конвергенса.

---

# Итоговый вердикт

```text
ENGINE48_LINUX_R2_INDEPENDENT_VERIFIER_VERDICT
GIT_IDENTITY = PASS (HEAD 7aaa7fa9ebcabeeca33f15696002ff3907c22ffb; HEAD^{tree} 0d49082be99b0bb125d26c28f45ac19840426f0d; BASE^{tree} 3c0a04c78eca918717e8e836b1c1bf2836cb5596 — вычислен из git; 7 коммитов BASE..HEAD; ancestor OK; tracked status 0; origin/feature/engine48-linux-r1 == локальный tip)
GUARDS_INTEGRITY = PASS (ослаблений нет: пины движка 4.7.1→4.8.beta1; XVFB_BIN override с fallback /usr/bin/Xvfb; пины assertions только увеличены MW10 184→201, 51→53, P7.1 83→88; таймауты/пороги не тронуты; scripts/ — только новые .uid)
ENGINE_STRICT_CHECKS = PASS (4/4 sha256 точное совпадение с binary-sha256.txt; --version точные строки обоих; FINDING: GODOT_EDITOR_SHA256=25047b82ab92… из work order на машине НЕ найден — реальный 4.8 editor 4d72a93e…)
COLD_IMPORT_FRESH_TIP = PASS (worktree engine48-r2-verify @ 7aaa7fa9…; --editor --import --quit exit 0; 0 SCRIPT ERROR / 0 Parse Error / 0 ERROR; tracked status после импорта 0; worktree удалён)
HEADLESS_RERUNS = MW0=PASS(2011 assertions) | MW4=PASS(187 assertions) | C22=PASS(29+52+35+75 assertions) | P7.2_GATE=GREEN | P7.3_GATE=GREEN(P7.1=88 assertions подтверждён живьём) | PLAYABLE_SEAMLESS=PASS(all, 0 reconnects, A→B→A) | SM1_L0=PASS(SM1_L0_EXACT_HEAD_EXECUTABLE_PASS) — все на 4.8.beta1.double, exit 0, 0 script errors
M7_MULTIPLAYER_LIVE = PASS (server READY, connected_peer_count=2, joins=2/leaves=0/rejections=0, 0 script errors в server+client логах, процессы остановлены штатно; автоматический M7 acceptance на 4.8: 55 assertions/0 failures на retry; FINDING: терминальный result=PASS из result JSON недостижим через STOP-механику — см. F-1/F-2/F-3)
PERF_PAIRED = EVIDENCE_CONSUMED_NO_REGRESSION_CLAIM (PERF_PAIRED_RESULTS.md + 3+3 пары raw metrics подтверждены наличием; не перезапускались)
REAL_GPU_EVIDENCE = INSUFFICIENT_EVIDENCE (llvmpipe software GL под Xvfb :99, подтверждено логом Mesa)
REGRESSIONS_ATTRIBUTABLE_TO_48 = NONE_FOUND (разовый флак M7-конвергенса не воспроизведён; retry PASS 55/0; MW10 parity 201/53 подтверждена на обоих движках прямыми прогонами)
OVERALL = FINDINGS_REPORTED
NEXT_ACTION = Принять evidence-пакет R2 как verified: все гейты на 4.8 зелёные, parity 4.7.1 подтверждена прямыми прогонами; направить findings B8 (SHA в work order), F-1/F-2 (result=PASS механика и exit-код M7-скрипта) и F-3 (retry-политика M7 gate) в repair/документацию — миграционных блокеров нет.
```
