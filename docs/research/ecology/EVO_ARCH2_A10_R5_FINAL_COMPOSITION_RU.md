# EVO ARCH2 A10 — R5 final composition candidate

Дата: 2026-09-18. Work Order `EVO-ARCH2-A10-20260918-R5`, HIGH.
Parent: A10-R4 `96d152176a813535db6950085cb10fff33c1464f`, TREE `b554647557a6b78b79c24f4cd3a8ef63513a6468`.

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
`96d152176a813535db6950085cb10fff33c1464f / b554647557a6b78b79c24f4cd3a8ef63513a6468`.
Предыдущие R4 heads `9e7deeb1...` и `511a1e0f...` являются историческими и не могут использоваться для current R5 acceptance.

## Scope boundary

R5 доказывает A10 integration contracts, но не является A11:
- нет игровой habitat scene;
- нет ускорения поколений/UI;
- нет автоматического terrain extraction;
- нет default nutrient/organic Matter identities;
- нет biological repair или возврата destroyed tissue в Matter.

После exact PASS всех R1–R5, fresh review/verifier и main epoch check A10 может стать merge/acceptance candidate. До этого R5 остаётся stacked candidate.

## Windows Repair R2

Canonical Windows double Godot on historical R5 `57d274de...` exposed typed-array runtime errors in R2/R4 and deterministic parser inference failures in R3/R5. The current lineage carries the fixes at their owning layers: R2 field arrays are `Array[String]`, R3/R5 transition state is explicitly typed, and all R4 exact-field arrays are `Array[String]`. The external Matter batch checksum anchor introduced before this repair remains mandatory.

## Windows Repair R3 — R4 negative-control

Historical Windows exact on `2d322129...` produced R1/R2/R3/R5 PASS and one R4 failure. The R4 failure was a latent test defect: its forged event assigned `m000003` to a row already mapped to `m000003`, so the tamper was a semantic no-op. Current R4 changes the row `part_id` to another real part, re-seals `binding_hash`, and requires exact `A10_R4_EVENT_MAPPING`. Runtime damage semantics are unchanged.

## Fresh whole-stack authority review repair

Fresh review текущего frozen closure выявил, что R1 допускал `WARM` Region как исполняющий. Это слабее production handoff semantics, где подготовленный target остаётся закрыт до `ACTIVE`. Текущий стек требует `ACTIVE` для `admit_cursor` и Matter-backed site execution; `WARM` остаётся допустимым только в R3 как preparation target до COMMITTED. R5 имеет отдельный negative control для premature WARM target admission.

## Fresh trust review repair R2

Дополнительный whole-stack review усилил trust boundaries. R1/R2 теперь доказывают, что schema-valid rehashed record/batch не заменяют ранее сохранённый caller-owned checksum. R3 разрешает handoff preparation только по WARM target и отвергает ACTIVE до commit. R4 `apply_damage()` требует caller-owned `expected_event_binding_hash`: корректно пересчитанный, но семантически изменённый event не получает authority от собственного self-seal. R5 сохраняет trusted batch/record/event anchors отдельными значениями и передаёт их между слоями.

## Verifier-only refresh

R4 individual exact initially failed before Godot because its Python verifier contained a literal `\\n` introduced during a static-guard edit. R4 runtime already passed inside the R5 whole-stack exact. The R4 verifier syntax was repaired in `96d152176a813535db6950085cb10fff33c1464f`; no GDScript runtime adapter or runtime test semantics changed. R5 is rebound to that exact R4 parent/tree.
