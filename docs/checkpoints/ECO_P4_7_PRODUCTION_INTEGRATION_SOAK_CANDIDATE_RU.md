# ECO P4.7 — Production Integration Soak — CANONICAL CANDIDATE

Статус: `BOUNDED_ROTATING_OBSERVABLE_CANONICAL_RUNNER_READY / EXACT_COMMITTED_A_B_PENDING`.

Parent P4.6 уже принят как `ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION`. P4.7 не вводит новый scheduler или authority layer: это bounded deterministic integration harness для уже принятых P4.1–P4.6 контрактов.

## Текущий R8 scenario

```text
8 authoritative regions
12 deterministic cycles
1 rotating active region per cycle
8 real deep ecology generations total
12 P4.4 serialize/deserialize round-trips
12 P4.5 CAS snapshot commits
4 P4.5 ownership handoffs
3 persistence restart -> ownership reconstructions
12 P4.6 monotonic client-cache updates
12 active-region interest projections
2 full 8-region fanout projections (forward/reversed authoritative input order)
```

Каждый регион при initialization проходит ровно один реальный ecology generation через P3.8. После этого каждый цикл выбирает один rotating active region и проходит полный production composition path:

```text
P4.3 restore/extend/bounded catch-up
→ P4.4 snapshot + serialize/deserialize
→ P4.5 CAS commit
→ optional handoff / restart reconstruction
→ P4.6 summary + monotonic client cache
→ bounded active interest projection
```

После 12 циклов выполняются две полные 8-region interest projections с одинаковым requested set, но противоположным порядком authoritative ownership array. `interest_hash` обязан совпасть.

## Exact bounds

```text
region_count                 = 8
cycles                       = 12
ecology_generation_steps     = 8
handoff_count                = 4
save_load_count              = 12
client_update_count          = 12
interest_projection_count    = 14
restart_count                = 3
max_remaining_due_steps     <= 1
```

Fresh-process A/B logs обязаны быть byte-identical. Hard timeout остаётся 600 секунд на Godot process; timeout не увеличивался.

## Repair history

### R5 — GDScript type inference

Exact Windows parser на Godot `4.7.1.stable.double.custom_build.a13da4feb` обнаружил, что `SERVERS` был untyped Array и `target_server := SERVERS[...]` нельзя вывести статически. Исправлено только в acceptance test: `SERVERS: Array[String]`, server-rotation locals явно типизированы.

### R6 — первый 600s timeout

Первый full 8×12 forward/reverse soak оказался слишком дорогим из-за частых глубоких P3.8 generation transitions. Ecology interval был увеличен до `10.0`, а deep generations ограничены восемью — по одному на регион. Production kernels не менялись.

### R7 — второй 600s timeout и root cause

Даже при восьми deep generations exact Windows run на HEAD `ee8e3f09173cd10c921d8c90ed50ffe5a29592b3` снова достиг hard timeout 600 секунд. Code-path inspection показал amplification через повторные recursive `validate_snapshot` / `validate_ownership` / `project_interest` и deep duplicate/serialize одного большого canonical ecology state.

R7 сохраняет 8 регионов, 12 циклов, real ecology advance каждого региона, persistence, CAS, handoff, restart, read-cache, missing-interest, full fanout и determinism, но дорогой full mutation path выполняется один раз на цикл для rotating active region. Полный 8-region fanout остаётся отдельной cross-layer проверкой в конце.

### R8 — phase heartbeat

Два предыдущих timeout-run показывали только внешний heartbeat. R8 добавляет non-canonical progress channel через `ECO_P4_7_PROGRESS_FILE`. Godot пишет туда текущую фазу, а PowerShell runner печатает её на каждом 10-second heartbeat:

```text
initialize region N/8
cycle N/12 active_region=NN
full fanout forward
full fanout reverse
canonicalize final identities
```

Progress file не входит в canonical hash и не меняет stdout A/B determinism.

## Candidate pins R8

```text
soak test blob = 49821079787479212feb78a10a4703bc52ba89b3
runner blob    = 5d44dead6bf9bcb5f921e3baf4852acc54adff2c
validation     = 8d1f96f34cf5b4095323ac5d1a99d8053280a255
```

## Lifecycle boundary

`RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1` сохраняет legacy filename, но текущая семантика canonical. P4.7 нельзя принять до exact committed Windows A/B PASS с byte-identical logs, `ecology_generation_steps=8`, full-fanout order identity и замороженными `soak_hash` / `final_interest_hash`.

P4.8 control preparation перепинована на R8, но финальный P4 acceptance остаётся fail-closed до P4.7 lifecycle acceptance.
