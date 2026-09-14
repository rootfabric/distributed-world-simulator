# EVO ARCH2 A8 — Snapshot / Seam R1

Статус: DESIGN / IMPLEMENTATION_PENDING. Work Order `EVO-ARCH2-A8-20260913-R1`, HIGH. Пользователь явно разрешил реализовать A8 после merge A7; A8 merge и production promotion не разрешены.

## Источники, epoch и границы

Новая ветка `feature/eco-evo-arch2-a8-snapshot-seam-r1` создана от canonical main `9e10e640ffc53f82195f1fd930ebafbbc85e482f`, TREE `27c62c3774117c5163d0d5dacf789b1310638a92`. A7 PR #617 merged, post-merge PC0 run `34752963523` SUCCESS. Registry generation 82; architecture `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`. Global audits YELLOW, не GREEN; исторические ECO/G directional findings не объявляются закрытыми.

Прочитаны main-owned AGENTS/PROJECT_CONTROL/HARNESS_CONTROL, development/review/autonomous/channel-recovery contracts, registry/goals/catalog и MCP_GODOT. Центральная ECO lane остаётся PARALLEL_RESEARCH, не production writer. Устаревшие LS4/PLAY1 routing строки не превращаются в A8 acceptance; основание этой отдельной research-миссии — явное поручение пользователя и принятый ARCH2 train.

Исходный A8 контракт: `8eccf6304078bec3a3ccaa5860c5aab6ee311209:docs/research/ecology/EVO_ARCH2_A0_RECONCILIATION_RU.md`, train A8 = full organism+field consistent snapshot, restart и seam ownership. A7 guide прямо оставляет crash journal / atomic pointer recovery для A8. A9 fidelity и A10 terrain/Matter/network production bindings — следующие отдельные задачи.

## Объект и ownership

Единица A8 R1 — **целый связанный research-участок A7** с wet/dry/dark sessions. Переносится consistent cut всех организмов и полей, а не только mesh/genome. Сохраняются BodyGraph/development, возраст, reserves/ledger, field stocks/revisions/ticks, corpses/remaining, оплаченные propagules вместе с witnesses и все A6 genesis/replay anchors. Делить coupled cut и бесплатно пересаживать организм из wet в dry запрещено. Это bounded partition handoff, не доказательство отдельной миграции организма в соседнюю biological cell.

Исполнитель участка и логический владелец environmental field — разные понятия. A4 field owner_token/epoch и A6 genesis не переписываются при смене сервера: это разрушило бы accepted replay. Ресурсные writers остаются существующими A4/A5/A6. Меняется только binding исполнителя всего cut. Один принятый durable checkpoint определяет единственного исполнителя; старый локальный candidate может быть вычислен, но не опубликован после смены tip.

A8 **потребляет**, не копирует/изменяет, `scripts/network/contracts/handoff_ticket.gd` и `scripts/network/handoff/handoff_state_machine.gd`. WorldEntityAggregate не используется как фиктивный world_item для экологии. Новых глобальных Authority/Region/Matter owners нет; подключение к реальным network/region owners остаётся A10.

## Модель и журнал

Новый `snapshot_seam_v1.gd` — bounded research controller. Origin содержит stable entity/region ID, initial executor+epoch и A7 treatment. Snapshot содержит origin, упорядоченный command journal и текущий cut: полный canonical A7 payload, executor/epoch, monotonic command revision, monotonic handoff clock и последний canonical ticket.

Команды имеют exact schema, operation ID, actor/epoch, expected revision, clock и typed arguments. ADVANCE разрешён только текущему owner без активного handoff. BEGIN проверяет canonical REQUESTED ticket, entity/region/source/epoch/revision/time и уникальность ticket ID. На время REQUESTED→TARGET_PREPARED ecological advance блокируется, чтобы snapshot cut оставался неизменным. PREPARING/FROZEN/SNAPSHOT_READY/COMMITTED/ABORTED/EXPIRED используют existing state machine; TARGET_PREPARED требует целевой actor и реальные полученные payload bytes. COMMITTED меняет executor/epoch ровно один раз. ABORTED/EXPIRED возвращают возможность advance прежнему исполнителю, не меняя ecology.

Идентичный operation ID + одинаковая команда возвращает прежний receipt без нового перехода. Повтор ID с иными аргументами отклоняется. Receipt/cursor восстанавливается из журнала. Restore требует внешний exact snapshot SHA256 и origin hash; затем заново создаёт trusted A7 genesis, проигрывает все команды через тот же код и сравнивает весь полученный snapshot. Поддельный owner, ticket, receipt, односторонний step, выдуманный ledger/outbox или обрезанный журнал не принимаются только из-за согласованного внутреннего hash.

Bounds R1: A7 horizon16/3sites/2founders unchanged, до96 commands, до8 ticket IDs, весь A8 snapshot≤2MiB. Достижение бюджета — явный отказ без изменения принятого cut. Tick экологии и handoff clock не смешиваются. Номер revision не номер поколения.

## Durable byte store и точка commit

Новый Linux/POSIX `snapshot_store.py` — **хранилище байтов, не валидатор биологии и не глобальная authority**. Использует file lock, content-addressed immutable snapshot blobs, immutable chain record с previous tip, fsync файлов/каталогов и атомарный replace CURRENT. Один store directory принадлежит одному trusted research coordinator; файловые права и выдача owner credentials находятся за границей модели.

Для публикации caller сначала валидирует предложение `snapshot_seam_v1.gd`, затем CAS commit(expected_tip, validated_snapshot). CURRENT — единственная точка линейризации. При конкурентной записи со старым tip только один writer выигрывает; проигравший обязан отбросить локальную модель и reload. После возврата commit acknowledgement не выдаётся до fsync CURRENT directory. Crash до pointer replace оставляет прежний cut; crash после replace может означать ambiguous acknowledgement, поэтому recovery читает CURRENT и проверяет chain, а не выполняет команду повторно вслепую. Dangling blobs/records не считаются commit. Повреждённый CURRENT или отсутствующие/неверные referenced bytes вызывают fail-closed, не тихий откат с возможным вторым владельцем.

Load byte store возвращает проверенные по hash байты; это **не semantic PASS**. Перед advance/показом canonical state обязателен GDScript restore с внешними anchors. Separate-process test связывает настоящий A8 payload → durable store → новый Godot process → семантический restore/continuation. Linux file-lock/fsync contract не объявляется Windows/power-loss/distributed-consensus qualification. Объём диска bounded, автоматического удаления committed history нет; full store отклоняет запись.

## Required gates / falsifiers

1. Истинный полный snapshot и canonical roundtrip; malformed schema/types/unknown keys/anchors/too-large/replayed-forged-state rejected atomically.
2. A→B→A: source freeze, target cannot advance early, actual target payload verification, increasing epochs, IDs and biological hashes conserved, source writes rejected after commit.
3. Duplicate operation idempotency before/after restart; conflicting duplicate/stale revision/wrong owner/epoch/region/ticket/clock, illegal or expired transitions, abort/expiry, command/ticket budgets.
4. Fresh Godot processes restore at all ticket boundaries and continue to identical final snapshot/report; no process-memory authority assumption.
5. Durable crash fault injection at blob/record/pointer stages in real subprocesses; both writers from same expected tip; orphan recovery; corrupt/missing/oversize files; rejected CAS never changes CURRENT. Byte-store tests alone do not establish GDScript semantics.
6. Current-main source fence: accepted A0–A7, canonical handoff and main-owned files unchanged. Approved Linux double Godot exact SHA; cold import; all A0–A7 suites/A5 repair oracles/A6+A7 restarts, mandatory A7 graphics, full Harness, explicit non-RED control audits, exact clean final HEAD/TREE.
7. Fresh independent exact-head whole-A8 review, evidence content/digest inspection and post-build critique. No self-issued independent PASS.

## Продолжение и завершение

Implementation paths: новые `scripts/research/ecology/v2/snapshot_seam_v1.gd`, `snapshot_store.py`; новые A8 tests/config/docs/validation. CI orchestration — отдельная validation branch. Existing accepted source/test/scene/control/network bytes не изменяются. Новый визуальный renderer не требуется: A8 сохраняет состояние existing A7 Observatory; existing graphical regression обязательна.

Last completed durable predicate: A8 fresh-main branch and design. Next: implement bounded controller/store and negative controls, freeze subject, run focused+full exact Linux, fresh review, append evidence отдельно от frozen source. Stop before main merge, A9/A10 dispatch или production promotion. Отсутствующий main-owned A8 execution в Drive/Close диагностируется честно, не подменяется MISSION_COMPLETE.
