# ACT0 — активация MVP после принятого P7

Exact product base: `3d7672cba293d8e7bd72427b803f73fc8fcee5da`.
Exact base tree: `3cdcd33b4a59a93707b7628bc0124184df94cc64`.
Epoch: `E2026-09-09-V0-MVP-R1`.
Work Order: `V0-MVP-R1-WO-001`.
Runtime branch: `feature/v0-mvp-playable-seamless-planet-r1`.
Registry generation: 82. Risk: CRITICAL. Capacity: one runtime worker.

ACT0 не означает готовность MVP. Все product predicates остаются незавершёнными. Branch-only candidate не даёт канонических полномочий. До main adoption `Drive` должен возвращать существующий Director route и запрещать runtime.

После merge необходимы настоящий post-merge Harness/PC0, exact epoch audit с фактическим main SHA и append-only `RECOVERY_RESUMED` в новой MVP-эпохе. Для pre-implementation audit используются actor `INTEGRATOR`, command `MVP_ACT0_POST_MERGE_EPOCH_AUDIT`, state `DISPATCHED`; audit содержит тот же epoch/Work Order, base SHA, фактический main SHA и результаты обоих PC0. Audit должен быть отдельным неизменным committed JSON. Событие не закрывает ни одного product predicate.

После этого реальный `Drive` на runtime-ветке должен дать `MAIN_MOVED_AUDIT_CONTINUE`, `continuation_blocked=false` и действие `CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED`. Work Order имеет тип INTEGRATION, поэтому существующий Harness назначает этому действию INTEGRATOR. Это один исполнитель композиции, не дополнительный параллельный runtime worker.

Первый runtime-пункт — `MVP_SHARED_GRAPHICAL_SCENE`. Затем: два клиента; A→B→A; каноническое копание обоим клиентам; exactly-once material; Item/Construction/persistence; reconnect/restart; bounded interactive workload. Полная world/core-регрессия, fresh Reviewer и Verifier, PC0 и Human MVP acceptance обязательны. ECO/FABRIC/WORLDGEN1 full/RF1/P8/PACKS не являются preconditions.

Runtime branch должна содержать принятый ACT0 control commit. Она продолжает exact accepted-P7 product base через control-only descendant, а не стартует с голого старого checkout без новой эпохи. Пока ACT0 не принят, запись DISPATCHED не означает запущенного агента. Runtime merge и MVP acceptance отдельно human gated.

Временный CI-сборщик удалён. Его использование было ошибкой процесса; точная история и сохранённые FAIL приведены в `PROCESS_CORRECTION_RU.md`. Конечный `mvp-act0-validation.yml` не делает commit/push/merge и выдаёт только машинную evidence, не независимый verdict.
