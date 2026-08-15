# SM0-H3.1 — SEQUENTIAL DUAL-AUTHORITY CRASH CHAIN

Дата: 2026-08-15

Статус: **DESIGN / BRANCH-LOCAL EXPERIMENT**

Риск: **CRITICAL — cross-server authority / recovery**

H3.1 не объявляет V0-S1 acceptance и не изменяет правило `SERVER_HANDOFF` stop-before в canonical project control.

## Исходная доказанная база

H2.4 доказал одиночный active-owner crash/recovery первоначального authority A.

H2.5 доказал одиночный active-owner crash/recovery authority B после настоящего A -> B handoff.

Оба сценария пока проверялись в разных client sessions. H3.1 объединяет их в одну непрерывную logical client session.

## Цель

Доказать последовательность:

1. A — initial active owner;
2. первый acknowledged-boundary MOVE на A становится durable;
3. A принудительно падает до ACK;
4. новый A восстанавливает exact ACTIVE_OWNER generation и rebinding exact duplicate MOVE без double-apply;
5. тот же client продолжает работу;
6. тот же `player/a` выполняет real A -> B handoff;
7. после активации B client делает один settle MOVE глубже в EAST;
8. interior MOVE на B становится durable;
9. B принудительно падает до ACK;
10. новый B восстанавливает exact ACTIVE_OWNER generation и rebinding exact duplicate MOVE без double-apply;
11. тот же client продолжает работу и завершает требуемое число A <-> B handoff.

## Главный инвариант

В одной logical client session допускаются два последовательных process crash, но в каждый момент остаётся не более одного canonical writer одного player state.

Recovery не создаёт второй player truth. Используется существующий canonical gameplay durable state + replay state.

## Runtime не расширяем

H3.1 должен использовать уже существующие:

- `sm0_authority_server_node_active_recovery.gd`;
- `sm0_authority_server_node_active_recovery_fault.gd`;
- `h2-active-owner-crash-after-move-persist-v1`;
- `post_handoff_settle_steps=1` test-only client option.

Новый production/recovery формат для H3.1 запрещён без отдельного нового finding.

## Process topology

Начало:

- A1: active recovery + active-owner crash fault;
- B1: active recovery + active-owner crash fault;
- client C: одна непрерывная process/session execution.

После первого crash:

- A1 killed;
- A2 starts from authority-A recovery directory **without fault profile**;
- B1 остаётся жив.

После A -> B:

- B1 становится active owner;
- первый interior EAST MOVE (`x > 0`) становится B crash boundary;
- B1 killed;
- B2 starts from authority-B recovery directory **without fault profile**;
- A2 остаётся жив.

## Fail-closed evidence для A crash

До kill A1 gate обязан доказать:

- `ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK` emitted ровно один раз;
- ни одного completed crossing ещё нет;
- exact ACTIVE_OWNER generation существует;
- snapshot authority=A, owner directory=A;
- durable player=`player/a`;
- durable input sequence/position совпадают с crash marker;
- A1 действительно убит и A2 имеет другой PID;
- A2 restores exact generation;
- A2 emits `SM0_RECOVERY_ACTIVE_OWNER_PENDING`;
- exact client retry gives `SM0_RECOVERY_ACTIVE_OWNER_REBOUND`;
- `duplicate_durable_input=true`;
- rebound position равна durable crash position;
- ownership epoch увеличивается ровно на один.

## Fail-closed evidence для B crash

После recovery A gate обязан сначала доказать настоящий crossing #1 A -> B.

До kill B1:

- crossing #1 owner=B, zone=EAST, directory epoch>=2;
- B crash point происходит при `x > 0`;
- B ещё не начал B -> A handoff;
- completed crossings на этот момент ровно 1;
- exact B ACTIVE_OWNER generation существует;
- snapshot authority=B, directory owner=B;
- durable player=`player/a`;
- B1 действительно убит и B2 имеет другой PID;
- A2 остаётся жив;
- B2 restores exact generation;
- B2 emits ACTIVE_OWNER_PENDING and ACTIVE_OWNER_REBOUND;
- duplicate durable input не применяется второй раз;
- ownership epoch увеличивается ровно на один.

## Final convergence

После обоих recovery:

- client result = PASS;
- expected handoffs completed;
- identity changes = 0;
- no `SM0_INVARIANT_VIOLATION` в authority/client logs;
- player entity остаётся `player/a`;
- crossing directory authority epochs строго возрастают;
- оба crash PID отличаются от соответствующих restarted PID;
- A crash происходит раньше first crossing;
- B crash происходит после crossing #1 и до crossing #2.

Default gate: минимум 2 completed handoff после двух crash.

Final gate: минимум 6 completed handoff после двух crash.

## Что H3.1 не доказывает

- одновременный crash A+B;
- loss общей recovery storage;
- physical power-loss / fsync semantics;
- corrupt/partial snapshot recovery;
- WAL/group commit throughput;
- production supervisor semantics;
- large-player/load scaling.

Следующий уровень после успешного H3.1 — отдельно спроектировать near-simultaneous / simultaneous authority failure, а затем durability-performance (WAL/group commit), не смешивая correctness и throughput в один work order.
