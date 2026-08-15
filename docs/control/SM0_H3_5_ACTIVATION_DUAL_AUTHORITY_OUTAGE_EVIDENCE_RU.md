# SM0 H3.5 — runtime evidence: dual-authority outage after durable activation before ACTIVATE_ACK

Статус: **BRANCH-LOCAL EXPERIMENTAL RUNTIME EVIDENCE**.

Это не global acceptance, не production acceptance и не разрешение включать `SERVER_HANDOFF` в V0-S1. Cross-server authority остаётся CRITICAL-risk областью, а текущий V0-S1 checkpoint по-прежнему останавливается до server handoff.

## Проверенный runtime SHA

Exact implementation/test SHA, на котором выполнены оба Windows-прогона H3.5:

`d0110b0163fbe1a845ea9df602fcec1c1b88bd0d`

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

Godot:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Windows executable:

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Runner:

`RUN_V0_SM0_ACTIVATION_DUAL_OUTAGE_ACCEPTANCE.ps1`

Fault profile:

`h3-activation-dual-outage-before-ack-v1`

Boundary:

`after-active-owner-persist-before-activate-ack`

## Что проверяет H3.5

H3.5 закрывает переход между transaction recovery и active-owner recovery.

До total outage выполняется один реальный A -> B handoff, но client ещё не получает успешный `ACTIVATE_ACK`:

1. target B уже durably committed transfer;
2. source A уже получил target commit, отправил redirect и получил redirect ACK;
3. source transfer tracking завершён в живом A;
4. client отправил `CLIENT_ACTIVATE` на B;
5. B связал active session;
6. перед успешным `ACTIVATE_ACK` B сохранил `ACTIVE_OWNER` snapshot;
7. successful `ACTIVATE_ACK` намеренно подавлен fault profile;
8. до outage client ещё не имеет `SM0_CROSSING_COMPLETED`;
9. оба authority process принудительно завершаются с bounded kill-request gap;
10. тот же client process остаётся жив и продолжает retry activation.

После restart требуется:

- B восстановить exact `ACTIVE_OWNER` generation и завершить outstanding activation;
- A восстановить старый durable `SOURCE_RETIRED` checkpoint как non-writer и безопасно replay старого transfer tracking;
- replay не должен создавать второй target import/commit;
- client должен завершить crossing ровно один раз;
- identity должна остаться неизменной;
- последующие handoff должны продолжиться до заданного количества.

## Focused regressions

Перед live scenario exact Windows runner успешно выполнил:

- compile-smoke базового SM0: PASS (9 scripts);
- handoff motion import regression: PASS (22 assertions);
- SM0 contracts: PASS (15 assertions);
- transaction recovery / target prepare recovery: PASS (32 assertions);
- active-owner recovery: PASS (41 assertions);
- source-retire recovery: PASS (37 assertions).

Cold editor metadata import создавал отсутствующие `.uid` sidecars из cache; runner удалил только созданные этим запуском sidecars. Это не runtime failure и worktree после gate оставался чистым.

## DEFAULT 2/2 — PASS

Дата локального Windows запуска: 2026-08-16.

Exact HEAD:

`d0110b0163fbe1a845ea9df602fcec1c1b88bd0d`

Основные runtime facts:

- same client PID: `27268`;
- transfer: `handoff/sm0/a/2/1`;
- killed A PID: `1912`;
- killed B PID: `27112`;
- restarted A PID: `25004`;
- restarted B PID: `26672`;
- kill request gap: `0 ms`;
- A durable checkpoint: `SOURCE_RETIRED`, generation `12`;
- B durable checkpoint: `ACTIVE_OWNER`, generation `3`;
- client state at outage: still `ACTIVATING`;
- duplicate target commit after recovery: `0`;
- handoffs: `2 / 2`;
- final directory epoch: `3`;
- identity changes: `0`;
- base SM0 log analysis: PASS, `99` events.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH35\logs\20260816-000646`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH35\logs\20260816-000646\h35-summary.json`

Observed recovery statement from the runner:

`Recovered B completed the outstanding activation from durable ACTIVE_OWNER; recovered A replayed stale SOURCE_RETIRED tracking idempotently; same client completed crossing #1.`

## FINAL 6/6 — PASS

Дата локального Windows запуска: 2026-08-16.

Exact HEAD:

`d0110b0163fbe1a845ea9df602fcec1c1b88bd0d`

Основные runtime facts:

- same client PID: `13584`;
- transfer: `handoff/sm0/a/2/1`;
- killed A PID: `13632`;
- killed B PID: `26944`;
- restarted A PID: `10480`;
- restarted B PID: `11720`;
- kill request gap: `0 ms`;
- A durable checkpoint: `SOURCE_RETIRED`, generation `12`;
- B durable checkpoint: `ACTIVE_OWNER`, generation `3`;
- client state at outage: still `ACTIVATING`;
- duplicate target commit after recovery: `0`;
- handoffs: `6 / 6`;
- final directory epoch: `7`;
- identity changes: `0`;
- base SM0 log analysis: PASS, `179` events.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH35\logs\20260816-001346`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH35\logs\20260816-001346\h35-summary.json`

## Вывод

На exact SHA `d0110b0163fbe1a845ea9df602fcec1c1b88bd0d` H3.5 подтвердил branch-local composition guarantee:

`TARGET_COMMITTED -> source transfer complete -> CLIENT_ACTIVATE -> ACTIVE_OWNER durable -> ACTIVATE_ACK lost -> simultaneous authority outage -> restore -> exactly-once crossing -> continued handoffs`.

При проверенном boundary не наблюдалось второго target commit/import, смены player identity или нарушения directory epoch progression.

Это evidence относится только к текущему SM0 experimental branch и не является самостоятельным основанием для production/global acceptance cross-server handoff.
