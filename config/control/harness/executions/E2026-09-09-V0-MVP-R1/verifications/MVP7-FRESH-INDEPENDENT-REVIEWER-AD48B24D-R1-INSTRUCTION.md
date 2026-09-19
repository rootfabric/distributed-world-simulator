# MVP7 — FRESH INDEPENDENT REVIEWER R1

Ты работаешь как **FRESH INDEPENDENT REVIEWER**, не Implementer и не Verifier, для `rootfabric/distributed-world-simulator`.

## Exact subject

Перед любым выводом перепроверь live и остановись при drift:

- product branch: `feature/v0-mvp-playable-seamless-planet-r1`
- frozen HEAD: `ad48b24d8cde350db8c26adb958d9a0d62c6ff56`
- frozen TREE: `f306e84ebce87ea3644c60b5dd75779d7980f8bb`
- implementation base: `8d10bcf896547476d6f9a1db8769fa8c41110291`
- Work Order: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`
- target predicate: `MVP_RECONNECT_AND_RESTART` plus all seven RECOVER/LATE_JOIN sub-predicates in the Work Order.

**READ ONLY.** Не редактировать runtime/tests, не merge, не создавать `PREDICATE_VERIFIED`, не принимать whole MVP, не начинать MVP8.

## Входная implementer evidence

Прочитать, но не принимать вывод как свой:

- `config/control/harness/executions/E2026-09-09-V0-MVP-R1/evidence/MVP7-PRODUCT-EVIDENCE-AD48B24D-R1.v1.json`
- Linux exact run `35447331651`
- attempt 1 job `105908424301`, artifact `10586196268`, digest `sha256:799a2c2707e3a77bf2ace4615ae09141a4d4c24c84a34e0bacccaa9819cf0877`
- fresh rerun job `105909777021`, artifact `10585912124`, digest `sha256:e14d190412999720257ffca0156e9efdc30236924d6e09437377e0473d7c093b`
- pinned Linux double Godot SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Оба CI запуска должны быть перепроверены по metadata/log/artifact, а не по этой инструкции.

## Обязательный source review

Просмотреть полный diff `8d10bcf896547476d6f9a1db8769fa8c41110291..ad48b24d8cde350db8c26adb958d9a0d62c6ff56` (13 commits, 24 paths) и искать P0/P1, особенно:

1. **Ownership:** не появился ли второй canonical Item/Matter/Construction/player owner. MVP7 обязан только оркестрировать M6/M4/MW5/M0/C17/SM1 владельцев.
2. **Quiescent cut:** checkpoint разрешён только при reconciled/quiescent handoff; после seal новые gameplay/material mutations должны быть fenced. Нельзя заявлять arbitrary power-loss незакоммиченных операций.
3. **Recovery ordering:** validate/preflight до mutation; gameplay/replay/Matter cut должны быть одной согласованной generation; rollback/mixed/corrupt cut fail closed.
4. **Auth/replay:** historical operation ID не должен обходить новую transport session/ownership epoch. Старые credentials после restart должны отвергаться; exact terminal replay не должен создавать второй предмет/выемку/Construction mutation.
5. **Container semantics:** durable shared container graph/content восстанавливается, но transient open lease намеренно не durable. Не считать это потерей canonical state.
6. **Terrain/Material:** MW5 state восстанавливается из native repository; material identity/quantity при replay сохраняются; новый dig после recovery реально меняет terrain один раз.
7. **Construction:** новый PID обязан открыть тот же M0 repository, восстановить C17 single-writer A/read-only B, terminal ADD/REMOVE commands, exact snapshot/collision; removed east leaf не должен вернуться.
8. **Reconnect/current-state:** fresh ENet peer должен получить current post-Construction terrain/material/Construction state, а не исторический observer cache; продолжение движения — authoritative fixed tick.
9. **Transport lifecycle:** MVP7 backend liveness не меняет timeout/reconnect/payload/order policy и не выполняет backend reconnect. FINISH считается доказанным только после client ACK delivery witness / reconnect peer disconnect.
10. **Inherited gates:** MVP3–MVP6 checks и 13 negative controls не ослаблены; MVP7 добавляет 7 falsifiers.
11. **Workflow/evidence:** exact HEAD/TREE binding, clean tracked checkout, pinned engine hash, no stale ancestor artifact route.
12. **Scope:** нет forbidden path/architecture/acceptance/main mutation.

## Verdict

Верни только один из результатов:

- `PASS` — blocking P0/P1 нет и exact evidence contract sound;
- `FIX_REQUIRED` — с конкретными file/line/reproducer;
- `EVIDENCE_GAP` — если независимый вывод невозможен из-за реально отсутствующего доказательства.

CI success сам по себе не является Reviewer verdict.

## Durable result

Если работаешь с Git, создай отдельную ветку, например `review/v0-mvp7-ad48b24d-r1`, от `control/v0-mvp7-independent-handoff-r1`. Product SHA не менять.

Рекомендуемый result path:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP7-INDEPENDENT-REVIEW-AD48B24D-R1.v1.json`.

Обязательно записать exact HEAD/TREE, reviewed diff/base, findings, evidence independently checked, verdict, source cleanliness и явно `merge_performed=false`, `predicate_verified=false`, `human_acceptance=false`.
