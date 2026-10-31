# NET-SMOOTH1 R4.1-P1 F1/F2 — узкий ремонт ACK escrow и disconnect

Статус: IMPLEMENTER REPAIR CANDIDATE / NOT VERIFIED / NO MERGE. База PR #756: 538628fe72e77f993e16a78a3a1a60f9e1f9e302. Изменения scoped: M3 server, новый falsifier, focused runner, эта карта.

## Exact RED

F1. До repair сервер посылал success перед проверкой головы pending ACK, а ошибку mark_delivered игнорировал. При failed reliable enqueue A оставался escrow-ready, но B мог мутировать мир и получить success вне очереди. Это не premature ACK относительно B's *own* checkpoint, но нарушение FIFO и session fence.

F2a. Disconnect напрямую выполнял leave_transport_session, даже если checkpoint pending; позднее уведомление от старой session также могло стереть сведения более новой session того же peer.

F2b. Construction исполнялся через отдельный ConstructionMultiplayerGateway без M6 checkpoint. submit() изменяет executor, event stream и terminal ledger, но сам не вызывает ConstructionMultiplayerPersistence.save. M6 service export не содержит этот gateway. Нельзя считать такой success M6-durable.

## Выбранный R4.1-P1 repair

1. Все success paths JOIN_ACK, MOVE, PRESENTATION, ITEM_COMMAND, LEAVE_ACK проходят проверку головы escrow, peer, transport session, logical player и ownership epoch **до** real reliable enqueue. M6 replay разрешён при свободном escrow; проверка ошибочной головы FAIL_CLOSED, а не success/out-of-order.
2. После успешного enqueue обязательно проверять mark_delivered. Failed enqueue **не** является delivered: карантин ACK этой session через discard_stale_session, сохраняя M6 canonical replay. Product runtime запрещает новую mutation пока есть undelivered ready ACK, даже если kernel capacity ещё позволяет несколько записей. Proof kernel #755 не меняется.
3. Disconnect при pending checkpoint сначала карантинит старый ACK и снимает совместимость транспорта, но сохраняет авторитетный state до освобождения gate. Очередь до 64 с дедупликацией peer+session и обработкой 1 записи за цикл. Старый disconnect не стирает обновлённую session.
4. В persistence-enabled world пока запрещён CONSTRUCTION_COMMAND через gateway, который не предоставляет durable-before-ACK: ошибка M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED. Это **намеренное временное функциональное ограничение**, не полноценная интеграция Construction! В persistence-disabled режиме прежняя команда не меняется. Отдельный Construction owner/Persistence Work Order требуется для восстановления durable construction в сетевой игре.
5. НЕ МЕНЯТЬ M6 checkpoint/replay, NX3/NX5, protocol, session ownership, durability-before-ACK и performance thresholds. Persist по-прежнему synchronous, smoothing-performance ещё FAIL.

## Обязательный falsifier

tests/runtime/test_net_smooth1_r41_p1_fifo_disconnect_repair.gd моделирует:
- A generation 11 durable и неудачу reliable ACK enqueue. A не marked delivered, M6 replay A допустим без повторной mutation;
- до удаления A запись B не является escrow FIFO head; после карантина A B generation 12 и успешный enqueue B разрешены;
- C disconnect во время COMMIT_PENDING generation 13 не вызывает authority.leave, а сохраняет отложенный terminal event; после durable completion ACK старой session отсутствует;
- повторный disconnect coalesces, stale disconnect не затрагивает session/new, Construction persisted fence закрыт.

## Windows и независимая приёмка

- Exact 4.7.1 double cold import; analyzer 20/20; 22 focused suites (18 regular + 4 process), новый falsifier и kernel 66/66.
- Два реальных GUI Quaternius клиента, 24+ ITEM durable commands, duplicate operation_id replay, USER1 roundtrip/reconnect, отрицательные stall controls и отдельное persisted Construction negative proof.
- Сохранять original timing budgets (25/50/100 ms, ≥59 Hz), trace и identity. P1 не обещает улучшение performance; R4.1-P2 asynchronous persistence остаётся отдельной HIGH-risk работой с crash matrix.
- GitHub Project Control candidate CANDIDATE_MAIN_DRIFT требует независимого route/fix по control-plane: не менять main-owned registry из этой ветки.
- Fresh Reviewer/Verifier, exact HEAD/TREE, fail-closed при неполных evidence. Не выполнять merge.
