# SM0-H2.3 — durable source retirement recovery

Статус: implementation design / bounded SM0 hardening

Base after H2.2 runtime evidence:

`b3fdd68ba363ba7aa19a70126192098078a780fd`

## Цель

Проверить crash source authority в окне, где source уже перестал быть canonical writer и directory уже передан target, но target ещё не получил/не подтвердил COMMIT.

Детерминированная точка H2.3:

`SOURCE_AFTER_RETIRE_PERSIST_BEFORE_COMMIT`

Последовательность:

1. source получает successful PREPARED;
2. source выполняет canonical `leave`;
3. source публикует directory с target owner;
4. source durable-пишет фазу `SOURCE_RETIRED` вместе с handoff decision metadata;
5. fault profile подавляет исходящие COMMIT и client redirect;
6. внешний supervisor force-kill source process;
7. новый source process восстанавливает exact `SOURCE_RETIRED` generation;
8. source остаётся non-writer;
9. source возобновляет COMMIT/redirect retry;
10. target принимает COMMIT, становится writer и активирует client;
11. source получает target COMMITTED + client redirect ACK и завершает tracking.

## Инварианты

- После persisted `SOURCE_RETIRED` source не имеет права снова подключить player как writer.
- Directory в recovery snapshot обязан указывать peer/target authority.
- Canonical gameplay durable state source обязан содержать player в disconnected состоянии.
- Recovery journal не хранит вторую копию canonical player state.
- Journal хранит только transaction metadata, необходимую для продолжения протокола: transfer id, package, stage, client endpoint и ACK flags.
- После рестарта source восстанавливает только pending source transfer tracking и retries; player state берётся из существующего gameplay durable state.
- До crash target не должен видеть COMMIT в детерминированном H2.3 профиле.
- После recovery одновременно не должно существовать двух writers.
- `player_entity_id` остаётся `player/a`; identity changes = 0.

## Изменение recovery snapshot

Новый snapshot продолжает использовать schema `distributed_world_simulator.sm0_handoff_recovery_snapshot.v1` и добавляет поле:

`source_transfer`

Для `TARGET_COMMITTED` оно пустое.

Для `SOURCE_RETIRED` оно содержит только pending protocol state:

- `transfer_id`;
- exact handoff `package`;
- `stage = COMMIT_SENT`;
- `client_ip`;
- `client_port`;
- `target_committed`;
- `client_redirect_acked`.

Runtime-only retry timestamps/counters при restore сбрасываются, чтобы новый process начал bounded retry заново.

## Fault profile

`h2-source-crash-after-retire-persist-v1`

Fault действует только на source process с explicit `--fault-profile` и `--recovery-dir`.

До crash marker он подавляет:

- `PLAYER_HANDOFF_COMMIT` send;
- `HANDOFF_REDIRECT` send.

Это гарантирует, что crash действительно приходится на durable source-retired decision до target COMMIT, а не на случайную гонку supervisor с localhost UDP.

## Acceptance

Новый runner:

`RUN_V0_SM0_SOURCE_CRASH_ACCEPTANCE.ps1`

Обычный gate: 2 handoffs.

Final gate: 6 handoffs.

PASS требует:

- healthy preflight PASS;
- H2.3 scripts compile PASS;
- exactly one source crash point;
- persisted `SOURCE_RETIRED` generation существует до kill;
- old source PID прекращён, new source PID отличается;
- new source восстанавливает exact generation/transfer;
- restored source event имеет writer_count=0;
- target COMMIT отсутствует до crash и появляется после source recovery;
- target activation присутствует;
- source transfer complete присутствует после restart;
- base SM0 analyzer PASS;
- requested handoffs completed exactly;
- identity changes = 0;
- no `SM0_INVARIANT_VIOLATION`.

## Не входит в H2.3

H2.3 не объявляет решёнными power-loss/fsync, arbitrary active-owner crash между durable snapshots, quorum/consensus, split-brain между физическими хостами или global V0 acceptance.
