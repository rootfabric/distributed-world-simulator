# FABRIC R5.6.2 R1.3 — независимая приёмка / role handoff

**Status:** `WINDOWS_EXACT_PASS / LINUX_EXACT_PASS / SOURCE_CONTRACT_PASS / REVIEWER_PENDING / VERIFIER_ACCEPTANCE_PENDING / MERGE_READY=false`.
**Предмет неизменяемой проверки:** `repair/fabric-r562-r13-genesis-admission-r1`,
HEAD `d8e8361419b1fbcf0138c4deea18d19accc297f6`, TREE `7c5c0a4e6546b4f3f444c8a17582518c099b951e`.
**Родитель:** R1.2 PR #800 @ `c9966b4f51dd623ddc6ec335b67452ccf96f7090`.
**Другой необходимый dependency:** R5.6.1 R2 PR #784 @ `60f193d6602d2d6ebb62393d3db6633b14623627`.
**Risk:** HIGH (restart / admission / persistence boundary).
**Этот документ — routing/evidence index, НЕ заключение независимого Reviewer или Verifier и НЕ право на merge.**

## Факты, проверенные до role dispatch

- PR #818 содержит четыре пути относительно frozen R1.2: один аддитивный `if initial_events.size() > MAX_EVENTS` в `bootstrap`; дополнения 16/17 тестового сценария на двух разных конструкциях; документ Repair Map; scoped CI. Никаких Construction/Matter/BRIDGE-4/R1.2 runtime изменений.
- Исходный frozen R1.2 RED: 17 корректных `initial_events` были приняты bootstrap, но отвергнуты при cold recover; независимый falsifier размещён на `review/fabric-r562-r12-genesis-event-budget-falsifier-r1`. R1.3 GREEN 4/4.
- Windows fresh exact PASS: [PR #818 verifier report](https://github.com/rootfabric/distributed-world-simulator/pull/818#issuecomment-6353187754), [separate evidence branch](https://github.com/rootfabric/distributed-world-simulator/tree/verify/fabric-r562-r13-windows-exact-d8e836-r1), archive `evidence/fabric-r562-r13-5fc86d24557e46668893f6185a429d90.zip`, declared SHA256 `50edb57a5e9b64647305eb578b7b47a130f3cd7c81be6f51f21891cd021af9e2`; independent Windows verifier reports all raw stages PASS, 10 process receipts, 54 SHA manifest entries MATCH.
- Linux exact **independently hosted by Actions**: [run 39773841137](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39773841137), jobs `scope-and-source=success`, `linux-exact=success`, Godot canonical SHA `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`; Godot stages, collector and strict R1.3 budget gate PASS. Linux CI archive 12453011111, SHA256 `7ba2876c718761f5e125f9252e9877b43f0d72f1d176107551aae718248d530b`.
- Exact frozen GitHub source archive 12423945806, SHA256 `896fd1d79ab7af8d639b5a76a9d1066ffee8e3dea9814f4fab3992c29d941601`; 2/2 inner archive hashes verified separately. Local Linux evidence `FABRIC_R562_R13_LINUX_EXACT_EVIDENCE.zip`, SHA256 `d1316b9b0551165178031572a5cd82b7232ed1a334bab833ff52020223b5e1fa`, internal package SHA256 checks **69/69**.
- Windows + Linux functional result hash: `0804d1dbd4b0c6f0111ed964e5c0a5ceb6d054b699ae9dd2580964742fc587a5`; 3×628/0; negative 76; 10 committed owner events; 30 cold recovery sessions; 42 binary receipts; 14 independent FULL point-mass checks; R2 626/0, COM 18/0, R1 203/0, BRIDGE-4 49 assertions PASS.

## WORK ORDER A — отдельный свежий Reviewer (не Implementer/Windows Verifier)

Читать по порядку: root `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, обязательные FABRIC scoped guidance, Work Order R1.2 и [R1.3 Repair Map](https://github.com/rootfabric/distributed-world-simulator/blob/repair/fabric-r562-r13-genesis-admission-r1/docs/research/FABRIC_R562_R13_GENESIS_EVENT_BUDGET_REPAIR_RU.md).
Создать отдельный role context + clean exact checkout; **не** править product HEAD, не пользоваться чьим-либо Implementer заключением как независимым review.

Проверить:
1. `bootstrap` отклоняет 17+ исходных событий до публикации derived state; после отказа тот же объект остаётся в NEW и допускает корректный retry без полуинициализации.
2. `bootstrap`, `_prepare`, `_replay`, `recover` имеют согласованный лимит 16 с реальным counted `initial_events + committed + pending`; соседние случаи 0/1/15/16/17/много, корректность sorted unique IDs.
3. После owner commit до ACK и при конфликте точного successor старые физические данные недоступны; нет способа принять ложный ACK или затереть повреждение при ошибке REBAKE.
4. `ConstructionConstructStore` и `MatterBatch` не получают второго writer / source authority; journal является derived DTO, `store_var(false)` — тестовый crash fixture, НЕ доказательство power-loss durability.
5. ABI/schema/Fenwick/COM численные ограждения R1.2 не ослаблены; нет изменённых производственных путей и скрытой зависимости от тестовых fixture как authority.
6. Прочитать исходный RED и GREEN без изменения original falsifier. Если новая ошибка воспроизведена — фиксировать конкретный falsifier и `FAIL`; отсутствие нового falsifier допустимо при достаточном доказательстве.

**Выход Reviewer:** `PASS` | `FAIL` | `INSUFFICIENT_EVIDENCE`, отдельно `required_fixes`, `rank_up_moves`, `evidence_gaps`, `risk_assessment`, точные reviewed HEAD/TREE и ссылки на исходные команды/файлы. Опубликовать в PR #818 от отдельного review actor. Никакого самоподписания Implementer'ом.

## WORK ORDER B — отдельный свежий Verifier / final evidence concordance

Verifier обязан отличаться от Reviewer. Windows exact run в PR уже имеется; **не требуется бессмысленный повтор без изменения HEAD**, если по Harness достаточно существующих свежих raw доказательств и независимой сверки. Проверить:
1. Точное совпадение HEAD/TREE R1.3 на Windows и Linux; чистое дерево/пин Godot/версия и identity before/after.
2. Считать реальный архив Windows evidence из отдельной verify-ветки, проверить ZIP SHA256 и каждую из 54 SHA256SUMS строк; все 42 бинарных receipts и 10 отдельных process/argv receipts, `gameplay_detected=false`, отсутствие timed_out.
3. Независимо сверить Linux Actions job logs + artifact 12453011111, collector JSON и источник; 3 byte-identical результата и cross-platform result hash.
4. Убедиться, что новые границы 16/17 и оригинальный reviewer GREEN присутствуют на этом product HEAD, а не на историческом R1.2.
5. При невозможности загрузить/прочесть реальные raw evidence — `INSUFFICIENT_EVIDENCE`, а не предположительный PASS.

**Выход Verifier:** exact-head `VERIFIED` или подробный `FAIL/INSUFFICIENT_EVIDENCE` по контракту проекта, evidence map и ссылки; отдельно от решения о слиянии.

## Director / integration gates

После свежих независимых Reviewer и Verifier:
- Выполнить required PC0/directional audit, подтверждение dependency PR #784 и актуальность обоих HEAD.
- Свести review findings по Repair Doctrine; при `FIX_REQUIRED` начать новый narrow repair и fresh exact/review на новом HEAD, без изменения принятого evidence задним числом.
- **MERGE_READY не менять до всех prerequisite и отдельного явного human approval** на research merge в объявленную branch; `main` и R6 вне scope.
- В конце R5.6.2 R1 передать в R5.6.2 R2 только доказанные ограничения: owner receipts, outbox / fault injection, долговечная атомарность требуют отдельного исполнения; process restart + Construction CAS не равны end-to-end distributed exactly-once.

Не заявлять reviewer/verifier conclusions заранее, не считать CI success разрешением на merge.
