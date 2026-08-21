# SM0-H2.2 — runtime evidence: durable target COMMIT recovery

Дата: 2026-08-15

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`

Exact runtime-tested HEAD:

`8f32b922e26a9c264a7f6a218e807bb34ddd7796`

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

## Что было проверено

H2.2 намеренно убивает target authority после того, как target уже:

1. принял COMMIT;
2. импортировал canonical player state;
3. записал durable recovery snapshot фазы `TARGET_COMMITTED`;

но до успешного завершения COMMITTED ACK / client activation.

После force-kill процесс target запускается с новым PID и обязан восстановить exact durable generation, повторно привязать transport session к тому же `player/a` и продолжить handoff без второго writer и без смены identity.

## Обычный runtime run

Команда:

`./RUN_V0_SM0_DURABLE_CRASH_ACCEPTANCE.ps1 -Restart`

Результат:

- healthy preflight: PASS;
- compile-smoke: PASS, 9 scripts;
- handoff motion import regression: PASS, 22 assertions;
- base SM0 acceptance: PASS, 2/2;
- crashed target PID: `19112`;
- restarted target PID: `24328`;
- crash transfer: `handoff/sm0/a/2/1`;
- recovered generation: `1`;
- handoffs: `2 / 2`;
- identity changes: `0`;
- result: `SM0-H2.2 durable target commit recovery: PASS`.

## Final runtime run

Команда:

`./RUN_V0_SM0_DURABLE_CRASH_ACCEPTANCE.ps1 -Final -Restart`

Результат:

- healthy preflight: PASS;
- compile-smoke: PASS, 9 scripts;
- handoff motion import regression: PASS, 22 assertions;
- base SM0 acceptance: PASS;
- crashed target PID: `13684`;
- restarted target PID: `8980`;
- crash transfer: `handoff/sm0/a/2/1`;
- recovered generation: `1`;
- handoffs: `6 / 6`;
- identity changes: `0`;
- merged SM0 log analysis: PASS, 100 events;
- result: `SM0-H2.2 durable target commit recovery: PASS`.

Durable snapshot path from final run:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH22\logs\20260815-181510\recovery\authority-b\recovery-00000001.json`

## Дополнительная regression evidence

Перед crash test выполняется отдельный canonical handoff motion regression. Он проверяет, что перенос fresh target из spawn к границе не превращает relocation distance в velocity. Результат final run:

`SM0 handoff import: PASS (22 assertions)`

Таким образом source `position`, `velocity`, `orientation_yaw` и input sequence проходят через canonical handoff import, а не через обычный movement delta.

## Scope

Этот evidence закрывает bounded SM0-H2.2: target process crash после durable target COMMIT и восстановление target owner.

Он НЕ доказывает автоматически:

- source crash после retirement;
- arbitrary crash активного owner между durable generations;
- fsync/power-loss guarantees;
- multi-host deployment;
- global V0 acceptance или merge в main.
