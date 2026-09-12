# MVP3 — сужение недостающего binding после независимого review

Статус: **PROPOSAL; НЕ РАЗРЕШАЕТ FOUNDATION CHANGE; MVP3 НЕ ЗАКРЫТ**.
Родитель: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`.
Исходный runtime: `6dca13bfc91698551544271a0245246e6d2ead12` / tree `9bb56d31bb1a384a6b2e581d6797c0d142639443`.

## Исправление вывода R4

Независимое review PR #615, comment `3996545246`, указало на пропуск принятой цепочки P6IdentityRegistry/P6OperationLedger → SM1PlayerCarryingDomain → SM1TransferCoordinator → SM1GatewayRoutePivot → P6GatewayCommandRoute. Это **существующий control-plane**, и проектировать его повторно не требуется.

Первоначальное предложение о новом полном freeze/warm/commit API отозвано. R4 характеризует только проверенные restart/unbound paths, а не доказывает отсутствие всех безопасных композиций. Ошибка первой R4-фикстуры (неверный namespace transport-session) исправлена; неуспешные запуски не являются product evidence.

## Что проверяет R5 вместо предположений

`test_v0_mvp3_bound_sm1_m3_route.gd` собирает настоящий accepted route с test-only адаптерами к публичному M3 Service. Handler не увеличивает фиктивный счётчик вместо игры: команда реально вызывает `handle_player_input`, и проверяются канонические координаты и input watermark.

Два M3 игрока независимо двигаются. Во время SM1 freeze игрока A gateway-pivot и bound handler запрещают его команды, а B продолжает двигаться через собственный per-player маршрут. Exact replay не повторяет движение; изменённый payload под прежним OperationId отклоняется до P6 id-only replay shortcut.

PlayerCarryingDomain получает реальное завершённое OperationId после freeze; P6 shadow строится как read-only projection реальных canonical snapshots. Существующий coordinator проверяет WARM chain. Перед ownership commit адаптер отдельно проверяет, существует ли на B настоящий live M3 player. Тест **не активирует B по одному control-plane report**. Если actor не staged, выполняется существующий `abort_before_commit`, затем A продолжает ввод без rejoin.

P6 требует namespaces `client-session/`, `player/`, `entity/`, тогда как текущий MVP2 M3 использует id `a`/`b`, entity `player/a`/`player/b` и `transport-session/`. Test-only aliases явно отображаются на исходные canonical identities и проверяются каждым вызовом. Это не смена личности M3 игрока.

Успех R5 доказывает только bounded command-port composition и точно выявленную target-readiness границу. Он **не доказывает** полную network/fixed-tick интеграцию M3, миграцию, камеры, graphical A→B→A, persistence или продуктовый PASS.

## Минимальная следующая правка при подтверждении missing hooks

Переиспользовать без изменения SM1 freeze, carrying manifest, warm checksum chain, commit, retirement, activation, replay fencing и gateway pivot.

Добавить только недостающие **live-player staging/activation hooks существующего M3 canonical owner** и подключение их к уже принятому SM1 owner decision. Нельзя создавать второй coordinator/epoch owner, новый Item Graph, новый identity/replay owner или новый механизм persistence.

Нужен bounded live actor payload с исходными identity/session bindings, input watermark и ровно относящимся к игроку canonical состоянием. Restart `export_durable_state`/`restore_durable_state` остаётся отдельным неизменным контрактом; нельзя очищать сессии при обычном crossing или выдавать весь M6 aggregate за одного игрока.

Рассматриваемый минимальный owner-hook scope (финальный список фиксируется до кода):

- `scripts/runtime/networked_gameplay/services/player_registry.gd`: атомарное staging/retirement одного player record в существующем registry;
- `scripts/runtime/networked_gameplay/services/player_ownership_service.gd`: сохранение live binding без обычного join/reconnect и проверки источника по существующему SM1 решению;
- `scripts/runtime/networked_gameplay/networked_gameplay_service_p2.gd`: публичный orchestration port у существующего Service, без внешних private-field writes;
- `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd`: binding real mutation/fixed-tick admission к переносу, если публичного composition seam недостаточно;
- только необходимые `mvp/**`, tests и evidence. Изменение SM1/MW8/MW9, M4 Item Graph или protocol ownership **не входит** в это предложение и требует отдельного обоснования.

Если player/replay/Item closure невозможно сохранить без расширения этого списка, остановиться на конкретной новой границе, а не расширять scope скрыто. UI/P6 aliases не являются authority. Чужой игрок, его inventory, общий Item Graph и мировой aggregate не перемещаются за пересекающим игроком.

## Приёмка исправления

Сначала owner-hook tests: штатный same-owner restart не меняется; live staging не становится writable до существующей SM1 activation; source после retirement fenced; replay и conflicting replay; identity/input watermark; чужой actor/Item Graph не перенесён; abort до commit не ломает источник.

Затем один настоящий двухклиентский scene/process workload: A проходит A→B→A, B независимо управляется до/во время/после переходов; роли меняются. Те же Node/Camera, одна gateway session, no reconnect/respawn. Проверяются фактические source/target mutations и observed shared state, не только labels.

MVP1/MVP2, затронутые M3/SM1/P7.6 tests, требуемая world/core regression, Harness/PC0 и свежие независимые роли остаются обязательными. Только после этого можно подтверждать leaf MVP3; whole MVP и merge не следуют автоматически.

## Граница полномочий

Родительский WO разрешает composition и имеет stop condition `New canonical owner or foundation change required`. Если R5 и независимое рассмотрение подтверждают необходимость перечисленных owner hooks, требуется ограниченный scope amendment **для hooks внутри существующих owners**, не разрешение повторно реализовать SM1 или создавать новые owners. До его утверждения production runtime остаётся неизменным.
