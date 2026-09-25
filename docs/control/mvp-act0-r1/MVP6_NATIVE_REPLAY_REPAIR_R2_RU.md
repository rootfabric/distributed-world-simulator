# MVP6 Native Replay Repair R2

## Точный отрицательный контроль

HEAD `98c66cceb4626fd2137ca50a2496463b6639ed4d`, TREE `3148fea590dc4b1248a7241f3502eb73e4b2b7db`; run `35082503932`, job `104749582061`, artifact `10441485219`.

ZIP SHA-256 `2fa4e63128578998095de3022457a37a794903cf9012769a1526fa8ad2592e03`, 18 manifest entries перепроверены по скачанным байтам, расхождений нет. Native transfer 408/0, неизменённые MVP3 232/0 и MVP5 270/0 остаются PASS. Новый security gate: 48 assertions, 5 failures, две root causes. Его FAIL не переписывается и не считается полноценным MVP6 PASS.

## Причины и canonical fix

Owner: существующий `m4/canonical_multiplayer_item_graph_service.gd`, ранее явно разрешённый HA-V0-MVP6-NATIVE-ITEM-CARRY-R1. Старые p1–p5 owners не меняются.

1. `apply_server_output` получал от parent `OPERATION_REPLAY_CONFLICT`, но затем `_tag_live_replay6` всё равно присваивал existing entry actor текущему запросу. Semantic rejection корректен, journal side effect — нет. Исправление: attribution разрешена только для действительно новой native ledger entry; существующие entries при replay/conflict никогда не переназначаются. Проверить siblings execute/output/Construction consume, включая прямой вызов graph, не только Service.
2. Native opt-in admission проверял readiness, но не supplied ownership epoch. Service фильтровал такой запрос, прямой native graph — нет. Исправление: проверка ожидаемой эпохи до native replay и до execute. Item commands используют bound player ownership epoch; trusted server output/consume — текущую backend authority epoch. Legacy не-opt-in поведение сохраняется.

Дополнительные стыки при проверке: bounded packet canonical JSON должен быть устойчив к транспортному roundtrip; staged install не становится active truth до общей readiness. Эти условия нельзя заменять значением checksum от клиента.

## Validation

Не ослаблять security assertions. Добавить прямой foreign graph replay control и проверить native ledger до/после отказа. Повторить полный native carry, security и неизменённые MVP3/MVP5 на новом exact subject. Затем продолжить live composition; native PASS не закрывает Construction/graphical/full-world gates.
