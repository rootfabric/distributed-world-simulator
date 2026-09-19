# MVP7 — FRESH INDEPENDENT VERIFIER R1

Ты работаешь как **FRESH INDEPENDENT VERIFIER**, не Implementer и не Reviewer, для `rootfabric/distributed-world-simulator`.

## Exact frozen product

Live-check перед запуском и stop on drift:

- HEAD `ad48b24d8cde350db8c26adb958d9a0d62c6ff56`
- TREE `f306e84ebce87ea3644c60b5dd75779d7980f8bb`
- product branch `feature/v0-mvp-playable-seamless-planet-r1`
- Work Order `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`
- target: `MVP_RECONNECT_AND_RESTART` and all required recovery sub-predicates.

Не принимать Implementer/Reviewer PASS на веру. **NO SOURCE REPAIR, NO MERGE, NO PREDICATE_VERIFIED EVENT, NO MVP8.** Если runtime defect найден — `FIX_REQUIRED`, а repair делает другой role/turn.

## Что перепроверить независимо

1. Git exact HEAD/TREE, clean tracked source, Work Order allowed/forbidden scope.
2. Engine identity. Canonical Linux double SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`. Canonical Windows double SHA256: `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`. Записывать фактически использованную платформу/версию/hash; не подменять другим binary.
3. Independently inspect run `35447331651` attempts/jobs `105908424301` and `105909777021`, artifact IDs/digests from `config/control/harness/executions/E2026-09-09-V0-MVP-R1/evidence/MVP7-PRODUCT-EVIDENCE-AD48B24D-R1.v1.json`; recompute/download where available.
4. Выполнить fresh runtime verification на exact frozen subject в изолированном checkout/profile. Не использовать старые result files.

### Required runtime facts

- three different PIDs for native gameplay produce/recover1/recover2;
- exact durable/replay/Item Graph checksum continuity between generations;
- inventory/hotbar/equipment + durable container graph restored; old sessions cleared;
- old session/epoch rejected and exact replay creates no duplicate output;
- corrupt/mixed/rollback recovery rejected before canonical mutation;
- MW5 terrain/Matter produce/recover1/recover2 in distinct PIDs, exact hashes, and new post-recovery dig;
- Construction produce/recover1/recover2 in distinct PIDs, same M0 repo, exact M4/C17 state, terminal commands, 100-part derived collision across seam, removed-leaf collision absent;
- live graphical story: 2 original clients + A/B authorities + gateway + fresh reconnect process are distinct; fresh ENet peer replaces original A peer; current terrain/material/Construction/collision received; authoritative fixed-tick movement continues;
- backend links never reconnect, timeout policy unchanged, backend disconnects zero during accepted run;
- inherited MVP6 13/13 falsifiers and MVP7 7/7 falsifiers rejected;
- all fatal markers absent and tracked source clean after execution.

The graphical manifest may say `server_restart_executed=false`: that is expected because process restart is proved by the separate native recovery families on the **same exact HEAD/TREE**. The combined predicate requires both surfaces.

## Existing evidence is corroboration, not your verdict

Implementer exact evidence:
- run `35447331651`, attempt-1 artifact `10586196268`, digest `sha256:799a2c2707e3a77bf2ace4615ae09141a4d4c24c84a34e0bacccaa9819cf0877`;
- fresh rerun artifact `10585912124`, digest `sha256:e14d190412999720257ffca0156e9efdc30236924d6e09437377e0473d7c093b`;
- both jobs SUCCESS, native summary 549 assertions/0 failures, graphical failed_checks empty.

## Verdict / durable output

Allowed verdicts: `VERIFIED`, `FIX_REQUIRED`, or `EVIDENCE_GAP`. `VERIFIED` only after your own independent checks/execution satisfy the required facts.

Use an independent branch such as `verify/v0-mvp7-ad48b24d-r1` based on `control/v0-mvp7-independent-handoff-r1` and result path:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP7-INDEPENDENT-VERIFICATION-AD48B24D-R1.v1.json`.

Record verifier identity/role separation, platform/Godot hash, commands/exits, fresh process IDs, assertion/check counts, artifact digests checked, evidence gaps, source cleanliness, verdict, and explicitly `merge_performed=false`, `predicate_verified=false`, `human_acceptance=false`.
