# MVP4 — общее каноническое копание, bounded implementation R1

## Durable resume anchor

- Parent: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`, state `IN_PROGRESS`.
- Единственный implementation branch: `feature/v0-mvp-playable-seamless-planet-r1`; PR #597 остаётся draft.
- Закрытые predicates: MVP1, MVP2, MVP3. Immutable events 0006, 0008, 0011 не переписывать.
- Frozen MVP3: `f1d453fb2af49231c30bdc5cbe415ad199394446`, tree `f1697cc52c1abc7f1bb21922c5fab3b49a3c167d`.
- Audited canonical main: `9e10e640ffc53f82195f1fd930ebafbbc85e482f`, tree `27c62c3774117c5163d0d5dacf789b1310638a92`.
- Continuation input: `89bbb90a34ae42adae3462ed8f7bdfbeb729c360`, **actual Git tree `e661d7abc2681325c6913b44a0ace42572ffd83f`**. Ранее напечатанный `dd684884...` для этого HEAD неверен; Git commit object имеет приоритет над текстом PR/чата.
- Input содержит current-main ancestry, immutable MVP3 closure 0011, audit-resume 0012 и bounded Harness repair. Project Control `34759411651` завершён SUCCESS, Harness 349/349. Это не новая продуктовая приёмка и не merge в main.
- Запрос пользователя: «реализуй MVP4». Routine A0–A3 implementation/validation/publication разрешены. Никакого main merge или whole-MVP acceptance.
- Последний завершённый продуктовый predicate: `MVP_SEAM_NO_RECONNECT_OR_RESPAWN`.
- Следующее действие: реализовать `MVP_CANONICAL_DIG_VISIBLE_TO_BOTH_CLIENTS`, выполнить exact tests, затем свежие независимые Reviewer/Verifier.
- Recovery: GitHub connector для чтения/записи; существующий exact checkout либо repository-owned CI для исполнения. Не использовать failed container Git clone/download route и CI как Git-transport.

## Scope lock / Design Brief

Текущая сцена MVP3 отображает immutable P7 bootstrap. Команда пользователя должна менять реальное Matter через существующие P7.1/P7.6/MW4 APIs, а оба независимых графических клиента должны получать канонические изменения и перестраивать свою производную геометрию. Нельзя выдавать анимацию/перекрашивание/локальный вырез за копание.

Сохранять действующий parent allowed/forbidden paths. Новые adapters и тесты размещать в `scripts/runtime/networked_gameplay/mvp/**`, `scenes/labs/mvp/**`, `tests/runtime/test_v0_mvp_*`, `tests/integration/test_v0_mvp_*`, `tests/fixtures/v0_mvp/**`, `RUN_V0_MVP_*`, `docs/control/mvp-act0-r1/**`. Validation-only workflow допустим как инфраструктура проверки, не как обход Git transport. Уже одобренные M3 owner hooks не расширять для нового назначения. P7, SM1, Matter, network, m4, architecture и project.godot не менять.

Canonical owners: native `NetworkedGameplayService` владеет игроками/aggregate revision; его `get_canonical_item_graph_port()` возвращает уже существующий Item Graph. `preflight_canonical_server_output` / `apply_canonical_server_output` сохраняют правильную aggregate revision. P7.1 gate — identity, current one-writer authority, equipped tool, reach, MW8/MW9; P7.6 route — MW4 single-region / MW10 real multi-region; P7.3 delivery — canonical output; MW6/MW7 и принятая representation — доставка/чтение состояния. MVP4 не получает собственного Matter/Item/authority/replay/persistence owner.

Выбранный подход: небольшая интеграция существующих canonical ports в текущую двухклиентскую сцену, переиспользование действующего gateway и транспортных envelopes. Сервер сам строит/проверяет canonical aim/query и request. На клиенте не остаётся изменяемой authoritative Bubble/ExcavationService. Производные mesh/cache и read-only MW6 replica допустимы. Сначала допустим один явно объявленный bounded Matter region; cross-region mutation не имитировать. Не переносить весь мир ради одного игрока. Не подменять настоящие SM1/MW8 gates always-success заглушками из demo.

Риск: CRITICAL по parent catalog. Известные риски: чужая identity/session; устаревшая authority/revision; повтор operation; поддельная geometry; слишком большой пакет; расхождение клиентских caches; нарушение MVP3 из-за equipped/nonempty carrying-domain. Решать в рамках существующих контрактов, а не ослаблением проверок. MVP3 empty-carry A→B→A остаётся обязательной регрессией; item-bearing handoff ещё не принят и не должен молча объявляться поддержанным.

Альтернативы отвергнуты: второй локальный gameplay/Matter/Item Graph owner; клиентский carve; создание нового network protocol вместо передачи существующих canonical DTO; копирование private fields чужого owner; изменение foundation ради ускорения acceptance.

## Проверяемые инварианты

1. Два отдельных клиента подключены к одному текущему MVP world/gateway, видят обоих игроков.
2. При команде dig от живого клиента сервер проверяет actor/session/authority, текущий equipped canonical tool, bounded reach/shape и выполняет принятый Matter path.
3. Серверный Matter content/revision действительно меняется; точный before/after, operation id, changed addresses и canonical route попадают в evidence.
4. Клиент A и клиент B независимо применяют canonical replication, перестраивают затронутую геометрию и наблюдают один и тот же итог. Одна копия server hash без реального client-state/mesh evidence недостаточна.
5. Без committed mutation нет локального видимого carve. Malformed/stale/foreign/unauthorized input не меняет Matter/Item/geometry. Replay не создаёт второй вырез; полноценный MVP5 material-output predicate отдельно не закрывается.
6. Расхождение/пропуск/повреждение replication обнаруживается; потребление bounded, нет unbounded snapshot/replay очереди.
7. Успех MVP4 не завершает parent. Нет `MVP_EXACTLY_ONCE_MATERIAL_OUTPUT`, persistence/restart/whole-MVP claims без их собственных gates.

## Приёмочная лестница

- Перед кодом: root + scoped AGENTS, parent Work Order и current `CONTROL_DEVELOPMENT -Drive`; сохранить exact subjects.
- Focused headless tests actual production adapters: legitimate dig, no-tool, foreign actor/session, wrong authority/revision, out-of-reach/nonfinite shape, replay/conflict, read-only consumer integrity.
- Actual process/graphical test: server authority processes + gateway + два графических клиента; committed dig и совпадающие independently computed client Matter/revision/mesh facts; raw JSON/logs, before/after viewport captures, owned-process cleanup.
- Регрессии MVP1/MVP2/MVP3, включительно R13 source-attestation, fixed-input, native/graphical A→B→A; полный world/core; полный Harness; standard/directional PC0.
- Заморозить runtime HEAD/TREE; затем fresh read-only Reviewer и отдельный Verifier. Implementer не пишет себе independent PASS или PREDICATE_VERIFIED.
- Evidence map и manifests связывают exact HEAD/TREE, commands/exits, CI run и SHA-256 raw files. Автоматический Xvfb run не именовать physical keyboard/manual.
- После самостоятельных ролей/результатов выполнить Drive. Closure MVP4 — отдельный immutable event после независимой верификации; parent остаётся IN_PROGRESS.

## Implementation exit boundary

Код/тесты должны быть реально committed и опубликованы. Комментарий с dispatch не является implementation. При отказе optional executor сразу продолжить разрешённым self-execution/CI route; не повторять недоступный executor. Исторический frozen MVP3 и его raw evidence не менять. Main не изменять.
