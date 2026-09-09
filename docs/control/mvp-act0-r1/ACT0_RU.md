# ACT0 — активация MVP после принятого P7

Exact product base: `3d7672cba293d8e7bd72427b803f73fc8fcee5da`; tree `3cdcd33b4a59a93707b7628bc0124184df94cc64`.
Epoch: `E2026-09-09-V0-MVP-R1`; Work Order: `V0-MVP-R1-WO-001`; runtime branch: `feature/v0-mvp-playable-seamless-planet-r1`.
Generation: `82`; risk: CRITICAL; capacity: one runtime worker.

ACT0 не означает готовность MVP. Все product predicates остаются незавершёнными.
Branch-only candidate не даёт полномочий. До main adoption старый canonical route
должен возвращать Director и запрещать runtime; после merge необходимо выполнить
PC0 и записать exact epoch audit CONTINUE с реальным новым main SHA в свежем
execution ledger. Нельзя менять исторический epoch, подставлять будущий merge SHA
или выдавать запись DISPATCHED за запущенного агента.

Первое runtime-действие после разрешающего Drive — MVP_SHARED_GRAPHICAL_SCENE.
Затем: два клиента; A→B→A; каноническое копание обоим клиентам; exactly-once material;
Item/Construction/persistence; reconnect/restart; bounded interactive workload.
Полная world/core-регрессия, fresh Reviewer и Verifier, PC0 и Human MVP acceptance
обязательны. ECO/FABRIC/WORLDGEN1 full/RF1/P8/PACKS не являются preconditions.

Runtime branch должна содержать принятый ACT0 control commit. Она основывается на
exact accepted-P7 product base через control-only descendant, а не на голом старом
checkout без новой эпохи. Изменения runtime при ACT0 запрещены.

`assemble.py` — одноразовый воспроизводимый сборщик candidate из pinned Git blobs;
не authority и не scheduler. Он не выполняет push, merge, acceptance или worker launch.
