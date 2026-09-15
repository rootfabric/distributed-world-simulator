# EVO ARCH2 A9 — Ecological Fidelity / Render LOD Separation

Дата: 2026-09-15. Work Order `EVO-ARCH2-A9-20260915-R1`. Risk HIGH.
Статус этой записи: DESIGN, не acceptance.

## Основание и epoch

Явное поручение пользователя: реализовать A9. Fresh branch `feature/eco-evo-arch2-a9-fidelity-r1` создана от `main@675c04bb213bbb68b8cdb500d540d57ce1490318`, TREE `04b217ff7acfcd6336490f139f9239a7f6b59b7d` (A8 merge PR #630). A8 exact R6 `34835588608` PASS; post-merge PC `34849654191` SUCCESS. Registry generation82, architecture `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`. Исходный train: `8eccf6304078bec3a3ccaa5860c5aab6ee311209:docs/research/ecology/EVO_ARCH2_A0_RECONCILIATION_RU.md`.

Прочитаны root routing/control/Harness/review/autonomy/channel-recovery, current registry/goals/catalog, MCP_GODOT и принятые A6/A7/A8 contracts. ECO остаётся отдельным research family; исторический LS4/PLAY1 route не объявляется A9 production activation. Central registry/scheduler/owners не меняются.

## Проблема и выбранная реализация

Rendering LOD не является ecological fidelity. Сокращение mesh не разрешает потерять запасы, состояние развития, происхождение или idempotency cursor. С другой стороны, настоящий lossy aggregate не содержит достаточно данных для восстановления исторических особей.

A9 R1 реализует **консервативный representation/control layer поверх A8**, а не новую approximation law для биологии:

| Режим | Сохранено | Исполнение / восстановление |
|---|---|---|
| FULL | Полные exact A8 bytes + owner/epoch/cursor + source-bound patch accounts | Команды исполняет неизменный A8/A6 |
| REDUCED | Те же exact bytes в bounded lossless compression, без постоянно распакованных BodyGraph | Явная распаковка по лимиту, затем тот же A8; не новая биология |
| PATCH | Per-site conserved accounts, field anchors, counts, blueprint cohorts; полный payload удалён | Exact advance требует refinement; прежние особи возвращаются только из exact externally retained snapshot |
| AGGREGATE | Общие accounts/counts; spatial/cohort detail удалена, source cursor сохранён | Никакой точной реконструкции из totals; только exact snapshot с соответствующим hash/origin/cursor |

Решение намеренно не обещает дешёвую активную симуляцию всех особей из агрегата. У coarse states отсутствует замкнутый принятый transition kernel: `REFINEMENT_REQUIRED` — проверяемый отказ без продвижения tick, не молчаливый пропуск биологии. Exact stepping доступен FULL/REDUCED через существующий A8. Render options не хранятся в biological packet и никогда не дают полномочий изменять fidelity, owner или tick.

Альтернативы: менять A6 под approximate population dynamics (отклонено: новая научная модель и новые error envelopes); выдавать render-LOD за ecological reduction (отклонено); восстанавливать особей reseeding из aggregate (отклонено: подмена истории). R1 даёт необходимые контракты и границы для последующих cohort dynamics, не объявляет их уже доказанными.

## Source and authority

GDScript admission bridge загружает настоящий A8 по внешним snapshot/origin anchors и получает отчёт через `A8.observe()` → канонический `A6.balance()`. Python fidelity kernel владеет только упаковкой/проекцией, а не запасами или authority. Native bridge и Python public runtime вместе образуют production entry point этого research слоя; синтетический report в unit tests не считается semantic admission.

Conserved accounts: `initial`, `external`, `current`, `sinks`, каждый с `material_mg`, `water_mg`, `energy_mj`; `initial+external=current+sinks`. Поля nutrient/organic не переименовываются в energy, dead provenance не суммируется второй раз поверх corpse.remaining. Cohort hashes — blueprint grouping, не biological species и не доказательство ancestry.

Каждый immutable packet содержит version, representation, exact source binding и projection. При restore нужен внешний hash **всего A9 packet**, а не только внутренний checksum. Для FULL/REDUCED дополнительно нужны повторная A8 admission и равенство derived projection. PATCH/AGGREGATE могут безопасно храниться/отображаться по внешнему packet anchor, но не претендуют на exact historical state. Поздний refinement заново допускает исходные bytes и сверяет сохранённую проекцию, origin, owner epoch, command cursor и ecology hash.

Aggregate batch принимает только явно различные `(region_id, entity_id)`: повтор snapshot, другой epoch того же участка и перекрывающиеся duplicates отклоняются. Суммирование детерминировано, units/overflow/bounds проверяются. Batch — non-authoritative report, не новый field/region owner и не достаточный snapshot отдельной особи.

## Budgets / persistence / seam

Snapshot raw ≤2MiB, packet ≤4MiB, decompression ограничена до выделения произвольного результата; trailing compressed data/encoding errors rejected. Число patches/cohorts и batch members bounded. Достижение cap явно fail-closed.

A9 snapshots сохраняются через неизменный A8 `SnapshotStore` с внешним durable acknowledged head. Representation downgrade не меняет biological source cursor. Handoff A→B→A исполняется только A8; после реального commit создаётся новый source-bound fidelity packet. Старый packet не становится действующим только из-за сохранённого owner_id: caller обязан предъявить актуальный externally acknowledged packet/source anchor. Потеря anchor не разрешает auto-reset.

## Validation plan

- Public mode transitions: FULL↔REDUCED exact; FULL/REDUCED→PATCH→AGGREGATE; невозможность reverse без достаточного retained state.
- Forged totals, duplicate keys, bool-as-int, overflow, unknown versions/modes, encoding/decompression bombs, stale packet/source/epoch and absent anchors.
- Render LOD options leave packet hash/bytes/cursor unchanged; renderer cannot promote fidelity.
- Real A8 source, command continuation, owner fencing, corpses and funded propagules; refinement and native semantic restore; fresh process persistence with A8 store.
- Aggregation conservation, order invariance and duplicate partition rejection; synthetic contract scale clearly separated from real Godot workload. Measure serialized retained bytes, not claim million-organism active simulation or general RSS reduction.
- Exact current-main and addition-only fence; accepted A0–A8 unchanged; inherited full A8/A0–A7 regressions, real A7 capture, full Harness and explicit non-RED audits on current subject.
- Fresh whole-head independent review, artifact hashes/content inspection and bounded post-build critique. Implementation evidence is not independent acceptance.

## Durable recovery

Last durable predicate: fresh branch + design. Next: add Work Order, kernel/runtime/bridge and falsifiers; run local contracts, freeze source; use separate validation branch for exact Linux and append-only evidence; request fresh independent review. GitHub connector is the source write route; local contract tests and repository-owned CI are executors. No ad-hoc network clone, no force push, no rewriting accepted kernels. Human gate: main merge. A10/A11 not started.
