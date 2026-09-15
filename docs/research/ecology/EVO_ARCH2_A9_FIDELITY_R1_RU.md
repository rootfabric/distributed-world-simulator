# EVO ARCH2 A9 — Ecological Fidelity / Render LOD Separation

Дата: 2026-09-15. Work Order `EVO-ARCH2-A9-20260915-R1`, HIGH. Текущее состояние: REPAIR_R1_CANDIDATE, не acceptance.

## Основание и владельцы

Явное поручение пользователя — реализовать A9. Ветка `feature/eco-evo-arch2-a9-fidelity-r1` создана от `main@675c04bb213bbb68b8cdb500d540d57ce1490318`, TREE `04b217ff7acfcd6336490f139f9239a7f6b59b7d`. A8 PR #630 merged; exact R6 `34835588608` PASS; post-merge PC `34849654191` SUCCESS. Registry generation82, architecture `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`.

Исходный train: `8eccf6304078bec3a3ccaa5860c5aab6ee311209:docs/research/ecology/EVO_ARCH2_A0_RECONCILIATION_RU.md`. Полный первоначальный Design Brief до реализации сохранён в commit `febdf1dbacd0ca598f92fcf41475839f77f4eb0a`. Эта редакция уточняет фактические границы после review, не подменяет историю design-before-code.

Прочитаны main-owned routing/control/Harness/review/autonomy/channel-recovery, registry/goals/catalog, MCP_GODOT и A6/A7/A8 contracts. ECO остаётся research family. A9 не активирует central registry/scheduler и не создаёт новых владельцев Authority/Region/Matter/ресурсов. A6 исполняет биологию, A8 — consistent cut, handoff и durable store; A9 владеет только представлениями и их admission.

## Четыре представления

| Режим | Сохранённые данные | Исполнение и восстановление |
|---|---|---|
| FULL | Полные exact A8 bytes, source cursor, patch accounts | Команды исполняет неизменный A8/A6 |
| REDUCED | Те же exact bytes в bounded lossless zlib/base64 | Явная распаковка, затем тот же A8; это не новая biological approximation |
| PATCH | Per-site conserved accounts, field anchors/stocks, counts, blueprint cohorts; полного payload нет | Exact advance требует refinement; historical individuals только из exact external snapshot |
| AGGREGATE | Общие accounts/counts/stocks; spatial/cohort detail удалена; source binding сохранён | Никакой исторической реконструкции из totals или reseeding |

Rendering DETAIL/SUMMARY/HIDDEN не входит в biological packet и не меняет fidelity, owner, epoch, tick, accounts или hash. Renderer не имеет права незаметно переводить PATCH/AGGREGATE обратно в FULL.

R1 — консервативный representation/control layer, **не реализация активной coarse population dynamics**. Для lossy state нет принятого замкнутого biological transition kernel: неподдерживаемый exact advance возвращает `REFINEMENT_REQUIRED` до запуска native работы. Это не молчаливый пропуск tick. Компрессия не называется сокращением активного biological state; million-organism throughput не заявлен.

Рассмотренные и отклонённые альтернативы: переписать A6 под новую approximation law без error envelopes; выдавать visual LOD за ecological reduction; бесплатно воссоздавать исторические особи из aggregate seed. Последующие cohort dynamics потребуют собственного scientific contract и сравнения ошибок.

## Admission и сохранение ресурсов

Native bridge `fidelity_admission_v1.gd` делает настоящий A8 load/apply/observe с внешними snapshot/origin anchors. Patch accounts приходят через A7.observe из канонического A6.balance, не из независимой формулы Python.

Accounts: initial/external/current/sinks; units: material_mg/water_mg/energy_mj; invariant `initial+external=current+sinks`. Dead provenance не суммируется второй раз поверх corpse.remaining; оплаченные propagule endowments сохраняются. Blueprint cohort hash — grouping, не biological species и не ancestry proof.

Restore требует внешний hash всего A9 packet и origin hash из caller-owned durable acknowledgement. FULL/REDUCED дополнительно проходят native A8 admission и сравнение derived projection. PATCH/AGGREGATE допускаются как сохранённые authenticated summaries, но не как exact historical state. Refinement требует исходные exact bytes и совпадение source hash/origin/owner epoch/revision/ecological cursor и сохранённой projection.

Python structural constructor и admission callback не являются защитой от враждебного coordinator: доверенный public entry point — NativeA8 с approved binary и внешними anchors. Хеш, взятый из самого подменённого файла, не является внешним якорем.

Batch aggregation bounded и детерминирована; повтор `(region_id,entity_id)`, в том числе на другом epoch/hash, отклоняется. Batch является `REPORT_ONLY_NOT_SPENDABLE`, не новым consistent world cut, field owner или восстанавливаемым снимком исторических особей. Реальные scale fixtures — независимые bounded research partitions, не production terrain coverage.

## Budgets и A8 persistence

Raw snapshot ≤2MiB; **весь A9 packet ≤2MiB**, совместимо с неизменным A8 SnapshotStore.MAX_SNAPSHOT_BYTES. Первоначальное значение4MiB было ошибкой и исправлено по P1 `4016102680`. A8 source, помещающийся в raw limit, не обязательно помещается в FULL после projection и JSON escaping: oversized envelope явно отвергается, не обрезается и не меняет режим автоматически.

Decompression ограничена; trailing/truncated streams, invalid base64/JSON, bool-as-int/nonfinite/overflow и неправильные schema/cursors rejected. До512 batch members. Достижение лимита — отказ без изменения исходного immutable record.

Persistence использует неизменный A8 SnapshotStore с fsynced caller-owned `{tip,sequence,snapshot_sha256}` за пределами store. Неудачный CAS не публикует локальное предложение. Валидный старый packet сам по себе не возвращает старому owner право записи поверх более нового acknowledgement. A→B→A исполняет только A8; A9 пересоздаёт source-bound packet из настоящего принятого результата.

## Repair R1

1. Post-build counterexample: NativeA8.restore перепаковывал валидный REDUCED stream и менял acknowledged packet hash без команды. Теперь semantic admission выполняется, а возвращаются исходные immutable bytes. Тестируются compression levels0/1/6/9.
2. Review P1 `4016102680`: packet limit приведён к2MiB; тест raw-valid источника с quote escaping проверяет отказ oversized FULL envelope. Canonical store не меняется.
3. Review P2 `4016102692`: negative owner test требует именно `A8_STALE_OWNER`, а не любую ошибку процесса/binding. PASS summary публикуется только после проверки полного mandatory-count.

Карты причин/воспроизведения опубликованы отдельно на validation branch: `c92c2e849d0ac8a9de08ac10185287bf945b81f0` и `a59c1cbd19637ae6a25809cc1468a04d3a4a156c`. Independent review на первоначальном `920a6f3a...` исторический после repair.

## Required gates и продолжение

Все32 contract test methods обычным и optimized Python; actual native continuation FULL/REDUCED; lossy refinement and no free history; render immutability; A→B→A ownership/epochs; paid corpses/propagules; четыре fresh-process persistence modes; duplicate rejection; отдельные synthetic и actual native scale measurements.

Полный exact Linux затем обязан исполнить все принятые A0–A8 tests/restart/repeats/A5 repair oracles, реальную A7 graphics capture, полный Harness и explicit non-RED audits на текущем HEAD. Existing A8 verifier не редактируется: адаптер расширяет только addition whitelist на восемь A9 paths, отдельно доказав current-main byte immutability. Результаты не переименовываются в global GREEN.

Дальше: freeze repaired HEAD/TREE, новый exact run, fresh whole-head review, artifact-byte inspection и append-only evidence отдельно от source. Main merge — отдельный human gate. A10/A11 и production promotion не запущены. Отсутствующий central A9 execution не объявляется MISSION_COMPLETE.
