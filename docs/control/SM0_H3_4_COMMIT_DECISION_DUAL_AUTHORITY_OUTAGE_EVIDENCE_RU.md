# SM0-H3.4 — exact runtime evidence: durable commit-decision dual-authority outage

Дата: 2026-08-15

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`

Exact runtime-tested implementation HEAD:

`ddbd1f10e84496f9e9af2fc18a11bb530e1c2f1b`

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

## Scope

H3.4 проверяет cross-server handoff boundary, в котором target уже принял COMMIT и durable зафиксировал `TARGET_COMMITTED`, но source/client ещё не успели получить подтверждение решения transaction.

Перед total outage для одного exact `transfer_id` одновременно требуется:

- source A: `SOURCE_RETIRED`, directory уже указывает на B, writer count = 0;
- source ещё не наблюдал successful target COMMITTED ACK;
- client redirect ещё не подтверждён;
- target B: `TARGET_COMMITTED`, directory указывает на B, writer count = 1;
- successful `PLAYER_HANDOFF_COMMITTED` ACK намеренно удерживается fault layer;
- client ещё не завершил crossing.

Затем оба authority process force-kill почти одновременно. Один и тот же client process остаётся жив. После restart:

- B обязан восстановить exact durable `TARGET_COMMITTED` decision;
- A обязан восстановить exact `SOURCE_RETIRED` state и повторить тот же COMMIT;
- повторный COMMIT обязан быть идемпотентным: без второго import, без второго `SM0_TARGET_AUTHORITY_COMMITTED`, без второй durable `TARGET_COMMITTED` generation;
- client должен завершить тот же handoff и продолжить обычные handoff.

Этот evidence branch-local и experimental. Он не объявляет `SERVER_HANDOFF` accepted для V0-S1, production HA или global project state.

## Finding, обнаруженный первым H3.4 run

Первый H3.4 run на:

`356a49d92b0a82a3cdda9b30f148e29914de658e`

остановился fail-closed с:

`SM0-H3.4 FAIL: A matching SOURCE_RETIRED snapshot missing.`

Причина была runtime-semantic, а не harness-only:

1. recovery layer вызывал `super._commit_source_transfer()`;
2. base implementation внутри этого вызова уже мог отправить реальный `PLAYER_HANDOFF_COMMIT`;
3. target успевал импортировать player и durable записать `TARGET_COMMITTED`;
4. source только после возврата из `super` записывал `SOURCE_RETIRED`.

Это оставляло опасное durability-ordering окно: B уже имел durable commit decision, а A ещё не имел durable retirement.

Repair:

`ddbd1f10e84496f9e9af2fc18a11bb530e1c2f1b`

`fix(sm0): persist source retirement before commit send`

После repair source retirement persistence гарантируется до первого реального COMMIT send. Повторные COMMIT retry не создают лишнюю source generation; restored `SOURCE_RETIRED` также считается уже persisted.

Project Control для repair HEAD: PASS (`run #560`).

## Default runtime run

Команда:

`./RUN_V0_SM0_COMMIT_DECISION_DUAL_OUTAGE_ACCEPTANCE.ps1 -Restart`

Exact HEAD:

`ddbd1f10e84496f9e9af2fc18a11bb530e1c2f1b`

Результаты preflight/regression:

- compile-smoke: PASS, 9 scripts;
- handoff motion import regression: PASS, 22 assertions;
- SM0 contracts: PASS, 15 assertions;
- healthy SM0 acceptance: PASS, 2/2;
- transaction recovery regression (`TARGET_PREPARED`/`TARGET_COMMITTED`): PASS, 32 assertions.

Process evidence:

- same client PID: `2468`;
- transfer: `handoff/sm0/a/2/1`;
- killed A PID: `17392`;
- killed B PID: `16072`;
- restarted A PID: `27428`;
- restarted B PID: `25620`;
- kill request gap: `0 ms`;
- A durable `SOURCE_RETIRED` generation: `12`;
- B durable `TARGET_COMMITTED` generation: `2`;
- duplicate target commit after recovery: `0`;
- handoffs: `2 / 2`;
- final directory epoch: `3`;
- identity changes: `0`;
- merged log analysis: PASS, 94 events.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH34\logs\20260815-235458`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH34\logs\20260815-235458\h34-summary.json`

## Final runtime run

Команда:

`./RUN_V0_SM0_COMMIT_DECISION_DUAL_OUTAGE_ACCEPTANCE.ps1 -Final -Restart`

Exact HEAD:

`ddbd1f10e84496f9e9af2fc18a11bb530e1c2f1b`

Результаты preflight/regression:

- compile-smoke: PASS, 9 scripts;
- handoff motion import regression: PASS, 22 assertions;
- SM0 contracts: PASS, 15 assertions;
- healthy SM0 acceptance: PASS, 2/2;
- transaction recovery regression: PASS, 32 assertions.

Process evidence:

- same client PID: `7636`;
- transfer: `handoff/sm0/a/2/1`;
- killed A PID: `26892`;
- killed B PID: `1372`;
- restarted A PID: `1332`;
- restarted B PID: `6320`;
- kill request gap: `0 ms`;
- A durable `SOURCE_RETIRED` generation: `12`;
- B durable `TARGET_COMMITTED` generation: `2`;
- duplicate target commit after recovery: `0`;
- handoffs: `6 / 6`;
- final directory epoch: `7`;
- identity changes: `0`;
- merged log analysis: PASS, 174 events.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH34\logs\20260815-235750`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH34\logs\20260815-235750\h34-summary.json`

## Decision

H3.4 branch-local gate: PASS on exact implementation HEAD `ddbd1f10e84496f9e9af2fc18a11bb530e1c2f1b`.

Proven within bounded SM0 lab scope:

- source retirement is durable before target can observe first real COMMIT;
- target durable commit decision survives simultaneous loss of both authority processes;
- recovered source can replay the same COMMIT;
- recovered target treats that COMMIT idempotently;
- no duplicate target commit/import is created;
- one uninterrupted client process resumes and continues handoffs;
- directory epochs remain monotonic;
- player identity remains unchanged.

Not proven / out of scope:

- disk/media loss or corrupted latest snapshot on both hosts;
- multi-replica consensus/quorum;
- simultaneous machine or datacenter failure with independent storage semantics;
- more than two authorities;
- adversarial network partition producing independently live conflicting writers;
- production durability/WAL performance guarantees;
- global V0 acceptance or activation of `SERVER_HANDOFF` in V0-S1.
