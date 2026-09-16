# MVP3 — план продолжения на Windows

Дата: 2026-09-13. Результат текущей задачи — исследование, загрузка кода и план;
это не dispatch нового runtime worker и не приёмка MVP3.

## 1. Восстановленная точка продолжения

- Репозиторий: `rootfabric/distributed-world-simulator`.
- Ветка: `feature/v0-mvp-playable-seamless-planet-r1`.
- HEAD: `605e4634f147c34c9e98155d6f96853aeeec70a9`.
- TREE: `994fd72b163e72584e4d1a51d18259b682964d0a`.
- Полученный `origin/main`: `7dfc68ab5a1e90254a1b7039807f275b5da04eef`.
- Worktree: `C:\distributed-world-simulator\worktrees\mvp3-continuation`.
- Checkpoint: `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`.
- Epoch: `E2026-09-09-V0-MVP-R1`; parent WO: `V0-MVP-R1-WO-001`.

Выполнены fetch, проверка remote refs, history/reflog/worktree inventory.
Ветка отсутствовала среди локальных рабочих веток и создана с tracking remote
в отдельном чистом worktree. Остальные checkout не переключались и не очищались.
Указанный во входной инструкции `fff07006` уже имеет шесть последующих commits.

Прочитаны приложенная инструкция, центральные AGENTS/PC0/Harness contracts,
main-owned goals/catalog/registry, паспорт ветки, MVP3 brief, Work Orders R8/R9,
разрешение HA, инструкции Godot и текущие runtime/test/launcher paths.
Старый паспорт и ранний brief местами описывают более раннюю стадию; фактическое
продолжение определяется кодом, R8/R9 и execution ledger.

## 2. Что уже есть и что действительно проверено

| Область | Состояние на выбранном HEAD |
|---|---|
| Разрешение live hooks | HA-V0-MVP3-LIVE-PLAYER-HOOKS-R1 уже RESOLVED; R8 и amended parent WO присутствуют в Git |
| Native staging/activation | Реализованы hooks PlayerRegistry, PlayerOwnershipService, NetworkedGameplayService и MVP transfer port |
| P6/SM1 composition | Есть live command route, coordinator/pivot binding и commit-aware completion |
| Проверка owner handoff | Локально Windows: 232 assertions, 0 failures, четыре передачи; это один процесс с реальными Service owners |
| Межпроцессная основа | Есть authority worker, authenticated protocol, backend link и read-only remote owner views |
| Интегрированная сцена | Новые process components ещё не собраны в полноценную двухклиентскую игровую цепочку |
| Старый seam launcher | RUN_V0_MVP_SEAM.py запускает SM1 operator/observer subgate; он не закрывает MVP3 |
| MVP2 | Сохранённая VERIFIED evidence; его graphical scene ещё использует прежнюю M3 runtime composition |

Локально выполнены `--version`, SHA-256, свежий `--editor --import --quit`
и `test_v0_mvp3_live_owner_handoff.gd`. Exit codes импорта и теста — 0;
в import log не найдены SCRIPT ERROR / ERROR / Parse Error / Compile Error.
Логи и JSON: `artifacts/mvp3-continuation-plan/`.
Полная регрессия, отдельные authority-процессы и graphical acceptance в этой
плановой задаче не выполнялись. Новые transport components требуют своих тестов.

## 3. Первый шаг: актуальный epoch-аудит

`CONTROL_DEVELOPMENT.ps1 -Plan` успешно загружает contracts, но возвращает:

```text
runtime_authorized = false
epoch.validation.status = MAIN_MOVED_REVIEW_REQUIRED
epoch.validation.reason = CANONICAL_MAIN_ADVANCED_WITHOUT_RECORDED_AUDIT
epoch.validation.action = BLOCK_CONTINUATION
human_decision_required = false
```

До runtime edits провести standard и directional PC0 для точного текущего main,
проверить critical watched dependencies и записать предусмотренный Harness
epoch-audit в execution evidence. Проверить reducer и повторить Plan/Drive.
Если итог CONTINUE — продолжать R8; если REFRESH_REQUIRED — оформить предусмотренное
обновление execution, сохранив существующую реализацию. Простая смена SHA в старом
аудите не является проверкой. Новое разрешение на уже разрешённые hooks не нужно.

Обновить continuation brief и при необходимости выпустить bounded continuation WO
с точным новым baseline и перечисленными ниже slices. Старые события и evidence
сохранить. Наличие кода и пустой diff до origin/main не заменяют epoch-аудит.

## 4. Последовательность реализации

### Этап A. Проверить существующие границы владельцев

Использовать имеющиеся `prepare_export`, `stage_export`, `retire_source`,
`activate_target`, `discard_aborted_stage` в `v0_mvp3_live_player_transfer_port.gd`.
Не проектировать пять новых конкурирующих API поверх них.

Составить матрицу покрытия всех обязательных negative controls: неверные
player/entity/session/source/target/epoch, checksum и пересчитанный checksum,
пониженный sequence, conflicting transfer replay, duplicate active, запись до
activation, запись source после freeze/retire, старый activation token, abort.
Дополнить только отсутствующие проверки и исправлять подтверждённые дефекты.

Отдельно проверить WARM: реальная запись уже лежит в существующих native staging
stores, её содержимое доступно проверке готовности, но она не появляется как active
authoritative player. Одного shadow report или label WARM недостаточно.
Проверить согласованность отказа при частичном registry/ownership/replay install.

Критерий выхода: native gate остаётся зелёным; каждая запрещённая запись отклоняется
на самом owner entrypoint без мутации, а не только на gateway.

### Этап B. Собрать gateway над существующими P6/SM1

Добавить bounded gateway composition под `scripts/runtime/networked_gameplay/mvp/`:
один внешний endpoint, два независимых client bindings и два backend links.
P6 Identity/Ledger/Admission и SM1 Carrying/Coordinator/Pivot остаются владельцами
своих решений. Remote views лишь передают authenticated read models.

Нынешний `v0_mvp3_player_command_route.gd` обращается к локальному Service через
WeakRef. Нужен bounded remote command-port adapter к `LOOKUP`/`MOVE` и настоящей
owner receipt. Не записывать APPLIED по успешной доставке RPC или внешнему envelope:
проверять вложенный native result, actor, operation и fingerprint.

Для каждого игрока собрать последовательность:

```text
accepted SM1 freeze -> native source export -> native target stage
-> WARM validation -> SM1 commit -> native source retire + receipt
-> SM1 activation -> native target activation -> gateway pivot
-> дальнейший реальный input на новом owner
```

Точный порядок отдельных SM1 вызовов взять из уже работающего owner test.
До commit abort возвращает источник к разрешённой работе; после commit отказ
не должен самовольно оживлять source. При временном handoff удерживать ограниченную
очередь ввода/явно отвергать команды без ложного ACK; sequence не сбрасывать.

Критерий выхода: отдельные authority/a и authority/b процессы выполняют A→B→A
для игрока A; игрок B продолжает выполнять собственные команды. Затем B проходит
свой A→B→A. Нет reconnect, двойной записи или повторной мутации на exact replay.

### Этап C. Подключить одну общую игровую сцену

Переиспользовать оформление, P7 surface preview и управление из MVP2.
Новый MVP adapter/scene разместить в разрешённых MVP/app paths. Оба клиента
управляют собственными персонажами через один продуктовый input path.
Не подменять привычное движение scripted телепортами или сменой route label.

Пересечение определять по подтверждённой canonical position с явным seam corridor
и гистерезисом. Проверить совместимость существующего MOVEMENT_DELTA live route
с SERVER_PREDICTED/fixed-tick input: clock worker сам по себе не доказывает это.
Если нужны дополнительные hooks — только в четырёх разрешённых M3 owner files.

Собирать клиентскую read-only проекцию из двух authority snapshots, учитывая
per-player authority epoch и revision. Общая service revision одного процесса
не является глобальным порядком между двумя authority. Сохранить last valid view
на переходе; не удалять и не создавать заново body/camera из-за transient absence
source row. Отвергать устаревшие snapshot/epoch без rollback положения.

Критерий выхода: два окна видят оба независимо движущихся тела в одной сцене;
body/camera instance IDs, player/entity/session/spawn identity сохраняются на
обоих направлениях. На target и после возвращения есть подтверждённое движение.

### Этап D. Windows launcher и процессная проверка

Добавить launcher `RUN_V0_MVP_*` и integration validator в разрешённых paths.
Топология: gateway + authority/a + authority/b + два graphical clients.
Конфигурации и manifests связать с exact HEAD/TREE/run ID, отделить клиентские
capabilities от внутренних ключей. Ключи не включать в отчёты.

Обеспечить явную готовность, лимиты ожидания, свободные loopback ports,
сбор stdout/stderr и остановку только PID данного запуска. Проверить wrong-key,
wrong-sender, replay/sequence conflict, stale decision/receipt, потерю backend,
таймаут и ограничение накопленных операций. Синхронный backend call сейчас может
блокировать до 3 секунд: измерить влияние на ввод B и отсутствие frame stalls;
при доказанной необходимости сделать bounded async pump внутри MVP adapter.

Автоматический сценарий использует тот же input path, что и человек. White-box
fault injection маркировать отдельно от end-to-end управления.
Критерий выхода: воспроизводимый Windows run, проверяемые causal traces и
falsification tests, отвергающие искусственные evidence PASS.

### Этап E. Регрессия и проверка графики

1. Native hooks и adversarial coverage; restart positive controls до live opt-in.
2. Accepted SM1 carrying/pivot; affected M3 fixed-tick/ownership/recovery и P7.6.
3. MVP1/MVP2 focused и существующий полноценный MVP2 process gate.
4. Новый пяти-процессный MVP3 gate; затем интерактивная проверка обоих клиентов.
5. Полные Harness/world-core проверки по WO, standard/directional PC0.

Windows Godot подтверждён:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
4.7.1.stable.double.custom_build.a13da4feb
SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

На каждом свежем exact checkout сначала import. Для Python на Windows включать
`PYTHONUTF8=1` (без него прямой вызов Harness здесь воспроизвёл cp1251 decode error).
Использовать штатный PowerShell wrapper Harness, выставляющий кодировку.

Для автономной графической проверки следовать `docs/MCP_GODOT.md`:
managed Godot, runtime input, properties/assertions и viewport screenshots.
Инструменты MCP доступны в сессии, но их подключение к новому worktree ещё не
проверялось. Два клиента не должны одновременно занимать default bridge 9081:
использовать поддерживаемые раздельные endpoints либо подключать MCP к одному
клиенту за раз при работе второго через repository-owned test driver.
Не менять addon/project.godot ради обхода этой границы.

### Этап F. Evidence и независимое решение

Заморозить runtime HEAD/TREE после исправлений. Manifest должен содержать engine
hash, команды, exit codes, tracked state до/после, hashes логов/JSON/PNG, process
IDs и соответствие run/actor/authority. Записать post-build critique и Evidence Map.
Передать exact subject отдельным Reviewer и Verifier; после runtime fix старые
verdicts больше не свежие. Публиковать append-only execution результаты и выполнять
Drive по Harness contract. Не самопринимать MVP3 и не merge runtime в main.

## 5. Обязательные продуктовые доказательства

- A и B независимо управляются до, во время и после передачи другого игрока.
- Каждый совершает authority/a → authority/b → authority/a с реальной мутацией
  положения на каждом участке; для базового пользовательского сценария обязателен A.
- Сохраняются внешняя gateway session, player/entity identity, spawn generation,
  body/camera instance IDs; observed disconnect/reconnect/respawn counts равны нулю.
- Sequence/replay продолжаются; exact replay не меняет world повторно;
  conflicting replay fail closed, rejected native command не становится P6 APPLIED.
- На target запрещена запись до activation; source frozen/retired не writable,
  включая direct mutation, fixed-tick и presentation/item entrypoints.
- Передаётся только player-domain slice. Другой игрок, world, whole Item Graph
  и чужие replay receipts не переносятся; per-player epoch не вращает service epoch B.
- Неподдерживаемый item payload явно отвергается. Текущая политика
  `MVP3_EMPTY_CARRY_ONLY` не доказывает перенос инвентаря; это отдельная последующая
  composition, а не разрешение терять вещи или молча расширять MVP3 scope.

## 6. Порядок поставки

Control audit/continuation anchor → owner coverage gaps → gateway/process transport
→ shared scene/input continuity → launcher/fault tests → exact regression/evidence
→ fresh review/verification. Один runtime writer.

Рекомендуемая ближайшая реализационная единица — **gateway + два native authority
процесса и headless A→B→A**, после обязательного epoch-аудита. Она проверит ещё
непроверенную сеть и remote command completion до добавления graphical complexity.
После неё подключается общая сцена. Старый operator/observer PASS не заменяет ни
один из этих выходных критериев. MVP4–MVP8 и whole-MVP acceptance остаются впереди.
