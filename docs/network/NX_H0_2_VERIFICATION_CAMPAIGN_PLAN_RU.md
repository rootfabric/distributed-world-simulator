# План верификационной кампании H0.2 / NX.C1 (owner authority)

- Статус документа: план (PLANNING). Документ не создаёт предикатов в registry и не заявляет ни одного PASS.
- Ветка: `feature/h0-2-nx-c1-owner-authority-r3` (worktree `/home/yurig/distributed-world-simulator/worktrees/nx-h02-verification`).
- Паспорт: `config/control/branches/feature__h0-2-nx-c1-owner-authority-r3.v1.json`.
- Registry: `config/control/project-program-registry.v1.json`, программа NX, роль `CONVERGENCE_FRONTIER`.
- Текущая стадия по паспорту и registry: `IMPLEMENTED_WAITING_EXACT_GODOT_RUNTIME_VERIFICATION`, health YELLOW.

## 1. Цель кампании

Достичь на точном head ветки:

1. **H0_2_PASS** — подтверждённый реальными Godot-прогонами набор верификаций H0.2/NX.C1;
2. **NX SOURCE_ACCEPTED** — приёмка исходной реализации NX.C1 owner authority после полного evidence-пакета, независимого review и свежей CH→NX directional revalidation.

Runtime merge остаётся человеческим гейтом (`RUNTIME_FEATURE_MERGE_REMAINS_HUMAN_GATED`) и в объём кампании не входит.

## 2. Сверка фактов (выполнена 2026-08-24, read-only)

| Заявление registry | Факт на origin/ветке | Вывод |
|---|---|---|
| lifecycle head `d1a4466775a6e08192179dfc9af397eafbf574c0` | фактический tip = `d1a4466775a6e08192179dfc9af397eafbf574c0` (`git rev-parse HEAD`) | СОВПАДАЕТ |
| source head `1814ca72c9569ea2aa7e3d1dd4a69eb790888908` | объект существует; `git merge-base --is-ancestor 1814ca72… HEAD` = да | ДОСТИЖИМ, предок tip |
| Расстояние source→lifecycle | 4 контрольных коммита после source head: `b1459f89`, `42d95422`, `fcaeb4ff`, `d1a44667` — только passport/lifecycle/docs, без runtime-кода | СОГЛАСОВАНО с формулировкой «lifecycle head after implemented docs» |
| Базовый коммит паспорта `09714b6f2681e3b5cf3f2f9e28416cf9a7378304` | присутствует в истории (`parent_branch_or_checkpoint: main @ 09714b6f…`) | СОГЛАСОВАНО |
| PR #97 | локально неверифицируемо (нет `gh`-CLI в этой среде); заявление registry принято как декларация | НЕ ПРОВЕРЕНО локально |

Расхождений между registry/паспортом и фактическим git-состоянием не обнаружено. Примечание: файл паспорта физически находится на самой ветке NX; в рабочем дереве главного чекаута (repair/v0-p6-persistence-exactly-once-r1) его нет — это не расхождение, а следствие того, что паспорт добавлен коммитами ветки.

Все прогоны кампании выполняются строго на точном head `d1a44667…`; если до старта этапа ветка двинется вперёд — fence перечитывается заново для нового head.

## 3. Инструменты и ограничения машины

- Единственный double-бинарник Godot (пересборка не требуется, все прогоны — ровно им):
  `$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64`
  (наличие проверено; версия/сборка фиксируются из `BUILD_INFO.json` рядом с бинарником и вывода `--version` в каждом логе).
- Машина зарезервирована под критический путь P6 (soak): **тяжёлые Godot-прогоны — только в согласованные окна вне P6-soak**.
- Лёгкие python-аудиты (PC0 standard/directional) допустимы в любое время — это минуты CPU без Godot.
- Оценки длительности ниже — оценки для планирования окон, а не свидетельства; фактические времена фиксируются в логах прогонов.

## 4. Матрица блокер → команда → статус

Источники блокеров: `blockers` в паспорте (= список в registry).

### 4.1 EXACT_GODOT_FOCUSED_RUNTIME_VERIFICATION_REQUIRED — PENDING

- Команда:
  ```bash
  GODOT_PATH="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64" \
    ./RUN_H0_2_NX_C1_TESTS.sh
  ```
- Состав (5 фокусных SceneTree-тестов, `tests/network/`):
  `test_nx_owner_movement_authority.gd`, `test_nx_render_physics_separation.gd`,
  `test_nx_owner_item_projection_rollback.gd`, `test_nx_client_tick_robustness.gd`,
  `test_nx6_predicted_item_interactions.gd`.
- Что доказывает: серверная валидация owner-locomotion (включая отказ по stale/wrong `ownership_epoch`), разделение render/physics тиков, rollback-safe проекцию владельца, устойчивость клиентского тика, предсказанные item-взаимодействия — в одном процессе, на exact head.
- Длительность: ~5–15 мин (импорт + 5 headless скриптов).
- Окно: короткое, согласуемое между soak-итерациями P6.

### 4.2 FULL_WORLD_CORE_REGRESSION_REQUIRED — PENDING (набор требует фиксации)

- Команды: полный применимый набор `RUN_*.sh` на exact head (репозиторий содержит ~60+ сюитов: C*, MW*, RL*, NX*, M*, H* и др.). Агрегатная точка входа `RUN_A1_GENERIC_AGGREGATE_TESTS.sh` покрывает editor_import + contracts + integration, но единого канонического скрипта «full world/core» на ветке нет.
- Перед прогоном фиксируется точный fence (полный перечень RUN-сюитов или согласованный поднабор по практике byte-fence C22) отдельной строкой в evidence-документе прогона.
- Что доказывает: отсутствие регрессий world/core от opt-in NX.C1 листьев на дефолтном `SERVER_PREDICTED` пути.
- Длительность: часы (оценка ~2–6 ч непрерывного окна).
- Окно: только вне P6-soak, по согласованию.

### 4.3 TWO_CLIENT_PROCESS_VALIDATION_REQUIRED — GAP

- Существует: `RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.sh` → `tests/runtime/test_m7_playable_networked_processes.gd` — выделенный сервер + **два графических клиента** (Xvfb), файлы состояний `a.json`/`b.json`; аналог `tests/runtime/test_m3_graphical_multiplayer_processes.gd`. Оба гоняют **базовые** рантаймы (дефолт `SERVER_PREDICTED`).
- Проблема: NX.C1 owner-movement листья — отдельные классы
  (`scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd`,
  `m3_dedicated_server_runtime_owner_movement.gd`,
  `scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd`),
  наследующие базовые; CLI/env-переключателя активации листа в процессных раннерах нет, процессного теста с двумя клиентами на `OWNER_AUTHORITATIVE_VALIDATED` нет.
- Что нужно (тестовый Work Order, без изменения gameplay-логики): переключатель выбора листа (CLI/env) + процессный тест/раннер вида `RUN_H0_2_NX_C1_TWO_CLIENT_TESTS.sh`: сервер + 2 клиента, оба в owner-authoritative режиме; проверка авторства движения, отклонений сервером, консистентности реплик у второго клиента.
- Что докажет: owner-authoritative locomotion в реальной двухпроцессной топологии, а не только in-process.
- Длительность после реализации: ~10–20 мин за прогон.

### 4.4 IMPAIRED_NETWORK_VALIDATION_REQUIRED — PENDING (база) + GAP (связка с NX.C1)

- База существует:
  - пресеты `config/network/network-condition-presets.v1.json`: `LOCAL`, `GOOD_BROADBAND`, `AVERAGE_BROADBAND`, `MOBILE`, `BAD_MOBILE`, `EXTREME`, `LAG_SPIKE`, `ASYMMETRIC`;
  - `RUN_NX1_DETERMINISTIC_NETWORK_CONDITION_TESTS.sh` (+ `tests/network/test_nx1_network_condition_processes.gd`, детерминированные условия на сервере, acceptance на `AVERAGE_BROADBAND`);
  - `RUN_NX2_REALTIME_TRAFFIC_SEPARATION_TESTS.sh` (+ `test_nx2_physical_channel_processes.gd`);
  - env `NX4_TEST_CLIENT_NETWORK_PROFILE` в M7 process-тесте (профиль на стороне клиента).
- GAP: прогон impaired-профиля против активного owner-movement листа отсутствует по той же причине, что в 4.3 (лист не активируется в процессных тестах).
- Что докажет (после закрытия 4.3): owner-authoritative режим деградирует управляемо (rejection/reconciliation) под потерями/джиттером/лаг-спайками.
- Длительность: ~5–20 мин на профиль.

### 4.5 RECONNECT_OWNERSHIP_EPOCH_VALIDATION_REQUIRED — PENDING (unit/legacy) + GAP (process для NX.C1)

- Unit-уровень покрыт: `tests/network/test_nx_owner_movement_authority.gd` отвергает state с чужим/stale `ownership_epoch` (входит в фокусный набор 4.1).
- Process-уровень (legacy): `tests/runtime/test_m3_graphical_multiplayer_processes.gd` проверяет инкремент `ownership_epoch` 1→2 при реконнекте; также `RUN_M6_DEDICATED_RECOVERY_TESTS.sh`, `tests/runtime/test_m6_dedicated_recovery_processes.gd`, `tests/runtime/test_m7_playable_networked_recovery_processes.gd`, `tests/network/test_n1_reconnect_replay_processes.gd`.
- GAP: реконнект с инвалидацией/переизданием ownership epoch именно для NX.C1 owner-movement листа на process-уровне отсутствует (зависимость от 4.3).
- Что докажет: после реконнекта старые owner-state подписки/эпохи не принимаются сервером, новый владелец авторитетен.
- Длительность: ~10–15 мин за сценарий.

### 4.6 POST_BUILD_INDEPENDENT_REVIEW_REQUIRED — PENDING (процессный шаг)

- Не автоматизация: независимый Reviewer/Verifier по evidence-пакету (Evidence Map + логи всех прогонов + точные SHA + версии Godot) согласно риск-маршруту HIGH.
- Стоимость машинная: ~0. Человеческая: одна review-сессия.
- Вход: завершённые 4.1–4.5 и 4.7.

### 4.7 CH_TO_NX_DIRECTIONAL_REVALIDATION_REQUIRED_BEFORE_NX_SOURCE_ACCEPTANCE — PENDING

- Команды (python-only, без Godot):
  ```bash
  python3 scripts/control/project_control.py            # standard PC0, ожидание NON_RED
  python3 scripts/control/project_control_directional_watch.py   # directional PC0, ожидание NON_RED
  ```
- Известный WATCH_HIT-блок CH→NX должен быть снят свежей revalidation на актуальном `origin/main` непосредственно перед proposal SOURCE_ACCEPTED (не ранее — иначе результат устареет).
- Что доказывает: направление зависимостей CH→NX чистое на текущем main, пересечения критических путей = 0.
- Длительность: минуты; выполнять последним машинным шагом перед human gates.

### 4.8 RUNTIME_FEATURE_MERGE_REMAINS_HUMAN_GATED — ПОСТОЯННЫЙ ГЕЙТ

- Не команда, а правило: merge PR #97 возможен только по явной человеческой команде после принятия checkpoint proposal.

## 5. Порядок исполнения

| Этап | Содержание | Блокеры | Окно | Оценка |
|---|---|---|---|---|
| 0 | Sanity: git-state exact head, PC0 standard + directional (python) | 4.7 частично (baseline) | любое время | минуты |
| 1 | Focused Godot suite на double-бинарнике; запись `tested_heads.focused` | 4.1 | короткое окно вне soak | ~5–15 мин |
| 2 | Full world/core regression по зафиксированному fence; запись `tested_heads.full_regression` | 4.2 | большое окно вне P6-soak | часы (~2–6 ч) |
| 3 | Тестовый Work Order: активация NX.C1 листа в процессном запуске + two-client раннер (только тестовый код/раннеры) | разблокирует 4.3/4.4/4.5 | любое (без Godot — разработка) | — |
| 4 | Two-client owner-authority прогон; impaired-профили (минимум `AVERAGE_BROADBAND`, `EXTREME`/`LAG_SPIKE`); reconnect/ownership-epoch сценарии | 4.3, 4.4, 4.5 | окна вне soak | суммарно ~1 ч |
| 5 | Независимый post-build review evidence-пакета | 4.6 | человек | сессия |
| 6 | Свежая CH→NX directional revalidation на актуальном main | 4.7 | любое, непосредственно перед proposal | минуты |
| 7 | Checkpoint proposal H0_2_PASS + NX SOURCE_ACCEPTED → human merge gate | 4.8 | человек | — |

Этапы 1–2 можно начинать параллельно с подготовкой этапа 3 (этап 3 не требует машины). Этапы 4+ требуют результата этапа 3.

## 6. Правила честности

1. **PASS только за реальные прогоны exact-head**: засчитывается исключительно прогон, выполненный на зафиксированном SHA ветки (`d1a44667…` или последующем закоммиченном head) указанным двойным бинарником. PASS «по аналогии», с CI, чужой ветки, другого бинарника или предыдущего head не признаётся.
2. Каждый прогон фиксирует: SHA, версию/сборку Godot (`BUILD_INFO.json`, `--version`), полную команду, дату/время, сырые логи в `artifacts/test-results/*` и сводку в новом датированном документе `docs/evidence/YYYY-MM-DD_*_RU.md`.
3. После реальных прогонов заполняются поля `tested_heads` паспорта (`runtime` / `focused` / `full_regression`) отдельными control-коммитами — никакие предикаты не пишутся «впрок».
4. Упадший тест — это `FIX_REQUIRED` по Repair Doctrine: фикс → повторный полный прогон затронутого набора; выборочные перезапуски до зелёного не допускаются.
5. Отсутствие прогона трактуется как `INSUFFICIENT_EVIDENCE`, никогда как PASS.
6. Оценки длительности в этом документе — планировочные; свидетельством являются только записи из п. 2.
7. Настоящий документ не изменяет runtime-код, registry и architecture-конфиги; изменение verification fence (этап 2) согласуется отдельно.

## 7. Человеческие гейты

1. Выделение тяжёлых окон (этапы 2 и 4) вне P6-soak — согласование с держателем P6-критического пути.
2. Принятие verification fence этапа 2 (полный список сюитов).
3. Post-build independent review (этап 5) — независимый reviewer, не автор.
4. Переход к proposal H0_2_PASS / NX SOURCE_ACCEPTED и merge PR #97 — только явная человеческая команда (`RUNTIME_FEATURE_MERGE_REMAINS_HUMAN_GATED`; implementer cannot self-accept).

## 8. Критерий завершения кампании

Все блокеры паспорта сняты: 4.1–4.7 закрыты реальными прогонами/review на exact head, `tested_heads` паспорта заполнены фактами, стандартный и directional PC0 NON_RED на момент proposal, независимый review принят — после чего вопрос SOURCE_ACCEPTED и merge уходит человеку.
