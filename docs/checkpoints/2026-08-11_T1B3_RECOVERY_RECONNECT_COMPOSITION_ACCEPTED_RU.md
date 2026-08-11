# T1B.3 — Recovery / Reconnect Composition — ACCEPTED

Дата: 2026-08-11

Branch: `feature/t1b-composition-failure-recovery`

Accepted Windows checkout:

```text
3a2a6a3e14f97e070139a00402d0cf0e19238622
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

## Решение

`T1B.3 Recovery / Reconnect Composition` — **ACCEPTED** после FIX1 и обязательной последовательности focused -> full world/core regression на сохранённом checkout.

Первый candidate `373cdd477a0e9a29c245c22f40fe8d222ff6484a` не считается evidence: он остановился на inherited-member parse collision и дополнительно выявил false-positive `PASS (0 assertions)` в harness.

FIX1:

- `928b4a8b0e156b15038b26ffab8689293fadc37f` — reuse inherited `RuntimeExecutorScript`, local schema renamed to `T1B3_SCHEMA`;
- `6a7894baab0559bbc4e7e74aa879d82cbf037973` — acceptance fail-closed через `scenario_completed`.

После FIX1 required execution sequence прошла успешно. Точный assertion count standalone/focused T1B.3 не реконструируется из не показанной части вывода.

Показанный финальный full-regression tail:

```text
RL3 representation-aware network streaming: PASS (175 assertions)
RL3 representation streaming processes: PASS (37 assertions)
main_scene_cli_all: 6 PASS / 0 FAIL
lifecycle: STOPPED
exit_code: 0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Доказанная composition semantics

```text
failure projection
 -> canonical runtime state
 -> command rejection/ledger
 -> M0 checkpoint
 -> fresh runtime restart
 -> recovered failure truth
 -> external authoritative interest projection restore
 -> reconnect / late-interest baseline
 -> dependency restoration
 -> ONLINE convergence
 -> command re-enabled
 -> second checkpoint/restart
```

Принципиальные границы сохранены:

- failure truth живёт в существующих Construction runtime subjects;
- durable recovery использует существующий T1A.7/M0 path;
- client/session/interest identity не записывается в Construction persistence;
- reconnect/late interest используют существующий interest/session binding и snapshot/replica path;
- command replay остаётся terminal/idempotent через существующий ledger;
- новых persistence repository, transaction coordinator, authority registry, network channel, world-query identity и WORLD_WORK_BUDGET owner нет.

## Следующий этап

`T1B.4 Composition Acceptance` — production-shaped M3 process composition с реальными server/client adapters и derived presentation.

T2.0 остаётся закрыт глобальным PC0 gate:

```text
C22_MAIN_INTEGRATED_PLUS_T_RUNTIME_SCALE_EVIDENCE_PLUS_TS0_4_CEILING_CLASSIFICATION_AND_PC0_CONVERGENCE_REQUIRED
```
