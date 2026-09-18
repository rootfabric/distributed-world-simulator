# EVO ARCH2 A10 — R5 final composition candidate

Дата: 2026-09-18. Work Order `EVO-ARCH2-A10-20260918-R5`, HIGH.
Parent: A10-R4 `ef5a9ecccdc403631d11c2cebe0b95d8971243bf`, TREE `a2cd902fff7375f611fe5f1889d3111619da41d3`.

## Назначение

R5 не добавляет нового runtime owner или новую биологическую модель. Это один whole-A10 composition gate поверх R1–R4.

Один Godot process должен связать:

1. real A8 `SnapshotSeam` cursor;
2. production `AuthorityRegionDescriptor`;
3. production Matter query/site binding из R1;
4. explicit catalog-bound Matter resource admission из R2;
5. exact BodyGraph ↔ Construction binding и persistent damage overlay из R4;
6. production `HandoffTicket` / real A8 handoff через R3;
7. повторное admission world site на target owner после COMMITTED.

## Обязательная причинная цепочка

До handoff:
- source Region owner допускает A8 cursor;
- Matter site привязан к source owner/epoch;
- explicit Matter batch mapping сохраняет mapped+unmapped mass;
- externally anchored C9 damage выключает физически уничтоженный BodyGraph subtree;
- historical BodyGraph bytes не меняются.

Затем:
- A8 проходит REQUESTED→...→COMMITTED через production state machine;
- biology payload и ecology_step не меняются от одного handoff;
- old Region owner после COMMITTED отвергается;
- target ACTIVE Region принимает cursor;
- тот же production Matter sample повторно bindится к target owner/epoch;
- persistent damage overlay и effective function остаются byte-identical.

## Exact lineage

R5 verifier и Work Order обязаны ссылаться на один и тот же exact parent:
`ef5a9ecccdc403631d11c2cebe0b95d8971243bf / a2cd902fff7375f611fe5f1889d3111619da41d3`.
Предыдущие R4 heads `9e7deeb1...` и `511a1e0f...` являются историческими и не могут использоваться для current R5 acceptance.

## Scope boundary

R5 доказывает A10 integration contracts, но не является A11:
- нет игровой habitat scene;
- нет ускорения поколений/UI;
- нет автоматического terrain extraction;
- нет default nutrient/organic Matter identities;
- нет biological repair или возврата destroyed tissue в Matter.

После exact PASS всех R1–R5, fresh review/verifier и main epoch check A10 может стать merge/acceptance candidate. До этого R5 остаётся stacked candidate.
