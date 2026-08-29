# SM0-H2.3 — durable source retirement runtime evidence

Дата: 2026-08-15

Статус: **BOUNDED RUNTIME PASS**

Это доказательство относится только к ветке `feature/sm0-two-authority-seamless-handoff-lab` и не объявляет SM0/V0 globally accepted.

## Exact candidate

- HEAD: `c702b8987601d2dfa4e19a41905ce54751ef9b25`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- runner: `RUN_V0_SM0_SOURCE_CRASH_ACCEPTANCE.ps1`
- crash profile: `h2-source-crash-after-retire-persist-v1`

## Focused recovery regression

`test_sm0_source_retire_recovery.gd`:

- `PASS (37 assertions)`
- `SOURCE_RETIRED` generation `1` persisted;
- recovered source restores the same transfer in `COMMIT_SENT`;
- recovered source remains `writer_count=0`;
- canonical player remains disconnected on the retired source;
- late move classification regression is included.

## Windows process-level final run

Command:

```powershell
.\RUN_V0_SM0_SOURCE_CRASH_ACCEPTANCE.ps1 -Final -Restart
```

Observed:

- healthy preflight: PASS;
- base SM0: `2 / 2`;
- source crash point: `SOURCE_AFTER_RETIRE_PERSIST_BEFORE_COMMIT`;
- crashed source PID: `25592`;
- restarted source PID: `4992`;
- recovered transfer: `handoff/sm0/a/2/1`;
- recovery generation: `1`;
- post-recovery handoffs: `6 / 6`;
- identity changes: `0`;
- SM0 log analysis: PASS;
- structured events: `106`.

Runtime summary path from the operator run:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH23\logs\20260815-184737\h23-summary.json`

Durable snapshot path:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH23\logs\20260815-184737\recovery\authority-a\recovery-00000001.json`

## Proven boundary

The old source can crash after it has:

1. canonically retired the player writer;
2. advanced directory ownership to the target;
3. persisted the `SOURCE_RETIRED` recovery decision;

but before the target/client has completed the commit/redirect exchange.

A new source process restores only transaction tracking and remains non-writer. It resumes COMMIT/redirect and the system continues to six handoffs without changing player identity.

## Not proven by H2.3

- active-owner crash outside a handoff;
- durability of the most recently acknowledged movement before an arbitrary owner crash;
- simultaneous loss of both authorities;
- host/OS power-loss/fsync guarantees;
- multi-machine network partition/lease semantics.
