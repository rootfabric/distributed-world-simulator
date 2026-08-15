# SM0-H2.5 — RUNTIME EVIDENCE: HANDOFF-TARGET ACTIVE OWNER RECOVERY

Дата: 2026-08-15

Статус: **BRANCH-LOCAL RUNTIME-TESTED PASS**

Это evidence экспериментальной ветки SM0. Документ **не объявляет** глобальный checkpoint acceptance, V0-S1 acceptance или готовность server handoff к merge в main.

## Проверенный implementation HEAD

`0e679a87a833989ead2750e7a406a3c6c4014369`

Ветка:

`feature/sm0-two-authority-seamless-handoff-lab`

Exact Godot runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Windows worktree:

`C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab`

## Цель H2.5

Проверить, что active-owner recovery работает не только для первоначального authority A, но и для authority B, который получил того же игрока через настоящий A -> B seamless handoff.

Crash point изолирован **после завершённого A -> B handoff и до начала следующего B -> A handoff**.

Для этого H2.5 использует один test-only `post_handoff_settle_step`: после активации B клиент сначала выполняет MOVE глубже в EAST (`x: 0.0 -> +0.5`), и только этот обычный active-owner MOVE может стать crash boundary.

Default client behavior не изменён: `post_handoff_settle_steps=0` вне H2.5.

## Fail-closed условия crash point

H2.5 gate требует одновременно:

- завершён ровно один crossing A -> B до crash;
- текущий owner в directory — `authority/sm0/b`;
- текущая zone — EAST;
- `directory.authority_epoch >= 2`;
- durable crash position имеет `x > 0`;
- B ещё не emitted `SM0_HANDOFF_BEGIN` для B -> A;
- exact `ACTIVE_OWNER` generation записана до crash marker;
- durable player остаётся `player/a`;
- live transport session не считается durable player truth;
- external supervisor выполняет настоящий `Stop-Process -Force` до MOVE_ACK;
- новый B имеет другой PID;
- restart восстанавливает exact `ACTIVE_OWNER` generation;
- exact retried MOVE классифицируется как `duplicate_durable_input=true` и не применяется второй раз;
- ownership epoch увеличивается контролируемо на один при session rebind;
- после recovery клиент завершает требуемое число handoff без identity change.

## Default runtime evidence

Команда:

`RUN_V0_SM0_HANDOFF_TARGET_OWNER_CRASH_ACCEPTANCE.ps1 -Restart`

Результат:

- healthy SM0 preflight: PASS, 2 / 2;
- handoff import regression: PASS, 22 assertions;
- shared active-owner recovery regression: PASS, 41 assertions;
- A -> B crossing completed before crash;
- crash authority: `authority/sm0/b`;
- crash B PID: `3400`;
- restarted B PID: `23796`;
- recovery generation: `3`;
- directory authority epoch: `2`;
- durable input sequence: `12`;
- durable position x: `0.5`;
- ownership epoch: `1 -> 2`;
- base SM0 log analysis: PASS;
- handoffs: `2 / 2`;
- identity changes: `0`.

Runtime evidence directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH25\logs\20260815-194829`

Durable snapshot:

`...\recovery\authority-b\recovery-00000003.json`

## Final runtime evidence

Команда:

`RUN_V0_SM0_HANDOFF_TARGET_OWNER_CRASH_ACCEPTANCE.ps1 -Final -Restart`

Результат:

- healthy SM0 preflight: PASS;
- handoff import regression: PASS, 22 assertions;
- shared active-owner recovery regression: PASS, 41 assertions;
- A -> B crossing completed before crash;
- crash occurred on interior EAST MOVE at `x=0.5`;
- crash B PID: `6716`;
- restarted B PID: `13248`;
- recovery generation: `3`;
- directory authority epoch: `2`;
- durable input sequence: `12`;
- ownership epoch: `1 -> 2`;
- base SM0 log analysis: PASS;
- events: `178`;
- handoffs: `6 / 6`;
- identity changes: `0`.

Runtime evidence directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH25\logs\20260815-195123`

Durable snapshot:

`...\recovery\authority-b\recovery-00000003.json`

## Что H2.5 доказывает

В рамках SM0 lab доказано, что уже существующий `ACTIVE_OWNER` recovery path authority-agnostic для одиночного process crash:

1. player может перейти A -> B через real handoff;
2. B становится обычным canonical writer;
3. acknowledged-boundary MOVE становится durable до ACK;
4. B может быть принудительно убит;
5. новый B восстанавливает canonical player state и durable replay;
6. exact duplicate MOVE не двигает player второй раз;
7. transport session rebind не меняет `player_entity_id`;
8. после recovery продолжаются последующие A <-> B handoff.

## Что H2.5 НЕ доказывает

Остаются за пределами H2.5:

- одновременный crash A и B;
- последовательные crash A и B в одной непрерывной клиентской сессии;
- физический power-loss / filesystem `fsync` semantics;
- corrupted / partial snapshot recovery;
- shared/network storage availability;
- supervisor/deployment orchestration production semantics;
- snapshot retention/compaction;
- WAL/group commit performance implementation;
- LOAD/TA scale и production latency budget.

Следующий безопасный шаг: **H3.1 sequential dual-authority crash chain** — сначала active-owner crash/recovery A, затем в той же logical client session настоящий A -> B handoff и active-owner crash/recovery B, после чего продолжить handoff до финального convergence gate.
