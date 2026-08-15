# SM0-H3.2 — simultaneous dual-authority total outage after handoff

Дата: 2026-08-15

Статус: DESIGN / IMPLEMENTATION GATE

Risk class: CRITICAL (cross-server authority/recovery lab).

Это branch-local experimental hardening. Не global acceptance и не разрешение на SERVER_HANDOFF в V0-S1.

## 1. Goal

Проверить новый failure model, не покрытый H2/H3.1:

- клиент делает реальный A -> B handoff;
- B становится canonical owner в EAST;
- клиент делает один settle MOVE внутрь EAST (`x > 0`);
- B делает этот MOVE durable до ACK;
- в этот момент supervisor принудительно убивает **оба** Godot authority process, A и B, создавая период полного отсутствия authority servers;
- тот же client process остаётся жив и продолжает retry;
- оба server process запускаются заново из тех же recovery directories;
- A должен восстановить retired/non-writer viewpoint;
- B должен восстановить ACTIVE_OWNER viewpoint;
- exact outstanding MOVE должен быть rebound на B без двойного применения;
- после восстановления система продолжает handoff.

## 2. Why this is distinct from H3.1

H3.1 последовательно падал только один server process за раз; peer всегда оставался жив.

H3.2 создаёт настоящий total outage window: одновременно нет ни A, ни B. Поэтому recovery не может опираться на постоянно живой peer как на единственный источник текущего directory state.

## 3. Required pre-crash durable viewpoints

Перед kill supervisor обязан доказать:

### Authority B

Latest selected crash generation:

- phase = `ACTIVE_OWNER`;
- authority = `authority/sm0/b`;
- zone = `zone/earth/sm0/east`;
- directory owner = B;
- directory epoch >= 2;
- durable player = `player/a`;
- durable player is disconnected in snapshot;
- durable input sequence matches crash marker;
- durable x matches crash marker and is `> 0`.

### Authority A

После completed A -> B handoff A обязан уже иметь durable `SOURCE_RETIRED` snapshot для crossing #1:

- directory owner = B;
- same directory epoch as the completed A -> B transfer;
- source transfer points A -> B;
- writer_count at retire = 0.

Это специально создаёт два разных recovery viewpoints одного committed ownership transition:

- A: retired source / non-writer;
- B: active current owner.

## 4. Crash mechanics

Fault profile остаётся существующий:

`h2-active-owner-crash-after-move-persist-v1`

Он включён только на B и удерживает первый successful MOVE_ACK после durable ACTIVE_OWNER persistence.

После exact crash marker supervisor:

1. записывает monotonic supervisor timestamps;
2. `Stop-Process -Force` для B;
3. немедленно `Stop-Process -Force` для A;
4. требует смерти обоих PIDs;
5. требует освобождения обоих gameplay/control port pairs.

Порядок вызовов kill технически последовательный, но semantic test требует, чтобы ни один authority process не был перезапущен до смерти обоих. Это создаёт bounded total-outage interval.

## 5. Restart mechanics

После подтверждённой смерти обоих:

- стартует healthy recovery B на старых B ports/recovery dir;
- стартует healthy recovery A на старых A ports/recovery dir;
- оба получают новые PID;
- тот же client PID не перезапускается.

Restart order не является authority decision. Canonical ownership должен следовать durable directory/recovery state.

## 6. Required recovery invariants

### Recovered A

Обязательно:

- restore не делает A writer;
- восстановленный directory owner = B;
- `writer_count = 0` на restored/resumed source events;
- A не выполняет `SM0_RECOVERY_ACTIVE_OWNER_REBOUND` для player/a;
- если SOURCE_RETIRED transfer tracking ещё требует retry, retry остаётся idempotent и не меняет ownership назад на A.

### Recovered B

Обязательно:

- exact ACTIVE_OWNER generation restored;
- `SM0_RECOVERY_ACTIVE_OWNER_PENDING`;
- exact client retry matches durable input;
- `duplicate_durable_input = true`;
- ownership epoch advances exactly by one on rebind;
- durable position does not change on duplicate replay;
- after rebound B is the only active writer for player/a.

## 7. Client continuity

Один client PID должен жить от начала до конца.

Client must not:

- change logical player identity;
- restart;
- reset input sequence;
- accept stale directory epoch;
- apply the durable MOVE twice.

## 8. Acceptance

Default:

- total-outage recovery succeeds;
- `2 / 2` handoffs;
- identity changes = 0.

Final:

- same simultaneous outage/recovery;
- `6 / 6` handoffs;
- monotonic directory epochs ending at 7;
- identity changes = 0.

## 9. Explicit non-goals

H3.2 does not prove:

- simultaneous crash *inside the same handoff transaction*;
- split-brain resolution under true network partition;
- physical two-host failure;
- host/power/storage loss;
- fsync semantics beyond current snapshot write/flush/rename behavior;
- quorum/consensus/lease architecture;
- production HA;
- performance suitability of per-ACK snapshots;
- global V0 acceptance.

The next harder frontier after H3.2 is simultaneous dual-authority failure during a single handoff transaction, where durable transaction viewpoints may be genuinely ambiguous.
