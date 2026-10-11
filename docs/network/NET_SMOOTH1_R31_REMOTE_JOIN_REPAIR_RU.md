# NET-SMOOTH1 R3.1 — reconnect при remote peer: ограниченный ремонт USER1

**Frozen parent:** R3 Windows report HEAD `8cb83777d532dcd2a5201dbc56f4c214c756a2dc`, PRODUCT_HEAD `e7b218b8961ca4e74dc1c1687054eedb49c7dbca`. **Risk: HIGH** (network authority/ownership/reconnect). Отдельная ветка и отдельный draft PR поверх `repair/net-smooth1-char2-r1`; исходный PR #751 и `main` не трогаем.

## Доказанный дефект и RED

R3 Windows seam-stress: `USER1_SEAM_JOIN_FROZEN_WHILE_PLAYER_REMOTE`, 5/5 запусков, ни одного доказанного A↔B roundtrip. Базовый `user1_product_seam_gameplay_service.gd:join()` блокирует *любого* JOIN при непустом словаре `_seam_coordinators`. `leave()` и `leave_transport_session()` вызывают `_force_all_primary()`, возвращая **других** игроков из secondary, даже если их session не затронут. Это глобальный freeze и чужая authority mutation на локальном транспортном событии.

Фальсификатор `tests/runtime/test_net_smooth1_remote_owner_reconnect.gd`: два игрока A/B, реальное движение A через х=10 в secondary; C JOIN, B leave_transport_session, B reconnect с новой session/epoch, A должен всё время оставаться у secondary с прежними entity, session и epoch. Переподключение самого remote A должно оставаться запрещённым без разрешения его transfer. До исправления: **24 assertions / 5 FAIL** на CHAR2 базовом файле (его Git blob `4dbcc684...` тождественен R3). После исправления: **37 assertions / 0 FAIL**, включая фактическое продолжение fixed movement обоих игроков после reconnect B.

## Выбранная реализация и границы

- `join()` блокирует JOIN только при собственной активной remote-binding игрока **или** при незавершённом SM1 transfer кого-либо (глобальный quiescence gate остаётся для transition windows). Актвные remote-binding других игроков не препятствуют новой session для локального игрока.
- `leave(logical_id, session)` и `leave_transport_session(session)` возвращают в primary **только владельца указанной активной session**, не все связанные remote-игроки. Старые/неизвестные session не могут вызвать чужое handback.
- `_force_all_primary()` остаётся глобальным только для explicit recovery/shutdown и намеренной глобальной quiescence. Нельзя заменить SM1 coordinator, создать вторую authority, изменить ownership epoch чужого игрока.
- Никакого изменения M6 durable-before-ACK, R3 reliable seam dedupe, NX3/NX5, каналов, checksum, клиента, checkpoint writer, timeouts или performance thresholds.

## Обязательные доказательства

1. RED→GREEN указанный тест (real SM1 secondary crossing, двухклиентские JOIN/LEAVE/reconnect), плюс базовый USER1 product-seam bridge и M6 contracts.
2. Exact Linux Godot 4.7.1 double import; проверить корректность снимка (checksum), durable state (quiescence), B ownership epoch +1 и неизменность A owner/session/entity.
3. Windows independent exact-head проверки двух GUI Earth-клиентов с Quaternius, `seam-stress` с **реальным** crossing A→B→A и rejoin при активном чужом remote binding. Orchestrator no-crossing / missing A-B roundtrip → INCONCLUSIVE; `JOIN_REJECTED` → FAIL. Не принимать fake test как реальный Windows PASS.
4. Независимый Reviewer/Verifier и PC0: нынешний Project Control CI на R3 report-кандидате завершён exit 3 с `PROJECT_CONSISTENCY_ERRORS` — классифицировать и закрыть отдельно. Не подменять сетевой review результатом PC0.
5. После исправления связности следующий самостоятельный HIGH-risk slice: NET-SMOOTH1 R4 ordered durable journal; server message/persistence p99 ещё красные. Затем CPU/render profiling клиента.

Не merge до отдельного human gate. Статус данного документа — implementer design + linux evidence; Windows verification pending.
