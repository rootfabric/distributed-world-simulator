# SM0 H4.1 — repeated alternating activation-outage campaign

Статус: DESIGN / TEST PREPARATION для experimental SM0 branch.

Не является production/global acceptance. `SERVER_HANDOFF` остаётся вне текущего V0-S1 checkpoint.

## Зачем H4.1

H3.3-H3.5 закрыли отдельные durable boundaries одного A -> B handoff:

- durable TARGET_PREPARED;
- durable SOURCE_RETIRED до первого COMMIT send;
- durable TARGET_COMMITTED до observation;
- durable ACTIVE_OWNER до ACTIVATE_ACK.

H3.5 также доказал total outage при outstanding activation.

Следующий риск — накопление recovery state после нескольких ownership epochs и симметрия направления. Одноразовый PASS может скрывать проблемы, возникающие только когда authority несколько раз меняет роли source/target и каждый новый process восстанавливается из каталога, уже содержащего историю предыдущих transfer.

## Campaign

Один и тот же automated client process выполняет N handoff. Каждый handoff проходит через H3.5-style boundary:

1. target commits transfer;
2. source receives COMMITTED, redirects client and completes source tracking;
3. client sends CLIENT_ACTIVATE;
4. target persists ACTIVE_OWNER before ACTIVATE_ACK;
5. fault profile suppresses the successful ACTIVATE_ACK for a **fresh** activation;
6. supervisor verifies client has not yet counted this crossing;
7. both authority processes are killed with kill-request gap <= 500 ms;
8. target restarts from ACTIVE_OWNER;
9. source restarts from its latest durable non-writer/source state;
10. duplicate outstanding activation completes without re-triggering the same fault;
11. client records exactly one new crossing;
12. both restarted authorities remain armed for the next fresh activation, now in the opposite direction.

Default campaign:

- 2 handoffs;
- 2 total outages;
- target sequence B, A;
- final directory epoch 3.

Final campaign:

- 6 handoffs;
- 6 total outages;
- target sequence B, A, B, A, B, A;
- final directory epoch 7.

## Fault semantics

New profile:

`h4-repeated-activation-dual-outage-v1`

It is test-only and extends the same transaction-recovery composition used by H3.5.

The profile suppresses ACTIVATE_ACK on either authority only when the activation is **fresh**.

A recovered ACTIVE_OWNER has `_active_recovery_metadata` populated while the outstanding activation is being rebound. For that replay the profile must pass the ACK through normally; otherwise the campaign would repeatedly crash on the same transfer instead of progressing to the next ownership epoch.

After the recovered activation completes and `_active_recovery_metadata` is cleared, the profile is armed again for the next fresh transfer.

## Required invariants for every cycle i

Before outage i:

- completed client crossings = i - 1;
- exactly one crash marker for the fresh transfer in the current target process;
- target phase = ACTIVE_OWNER;
- target directory owner = target authority;
- source emitted SM0_SOURCE_TRANSFER_COMPLETE for the same transfer;
- source has no writer for the transferred player;
- no invariant violation.

During outage:

- both old authority PIDs are dead;
- kill-request gap <= 500 ms;
- all four authority UDP ports become free before either restart;
- same client PID remains alive.

After recovery:

- target restores the exact ACTIVE_OWNER generation from that cycle;
- target emits recovery session rebound;
- source restores a non-writer recovery state;
- no second SM0_TARGET_AUTHORITY_COMMITTED for that transfer in restarted logs;
- no SM0_COMMIT_WITHOUT_PREPARE;
- client crossing count becomes exactly i;
- player identity remains player/a.

Whole-campaign invariants:

- same client PID from start to finish;
- target authorities alternate B/A exactly;
- transfer IDs are unique;
- crossing indices are contiguous 1..N;
- directory epochs are contiguous 2..N+1;
- no identity changes;
- no invariant violations;
- base SM0 analyzer passes exact N/N.

## Scope

H4.1 tests repeated process-loss/recovery composition on one machine and one logical player. It does not prove distributed consensus under arbitrary partitions, multi-player migration, cross-host clocks, storage corruption, or production readiness.
