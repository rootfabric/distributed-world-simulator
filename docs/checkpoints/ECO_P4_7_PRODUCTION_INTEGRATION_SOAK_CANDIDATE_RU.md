# ECO P4.7 — Production Integration Soak — CANONICAL CANDIDATE

Статус: `BOUNDED_ROTATING_CANONICAL_RUNNER_READY / EXACT_COMMITTED_A_B_PENDING`.

Parent P4.6 уже принят как `ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION`. P4.7 не вводит новый scheduler или authority layer: это bounded deterministic integration harness для уже принятых P4.1–P4.6 контрактов.

## Текущий R7 scenario

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

Даже при восьми deep generations exact Windows run на HEAD `ee8e3f09173cd10c921d8c90ed50ffe5a29592b3` снова достиг hard timeout 600 секунд. Значит bottleneck был не только в `Coexistence.step()`.

Code-path inspection показал основной amplification:

```text
P4.4 validate_snapshot
  → P4.3 validate_state
    → P4.1 validate_region_state
      → P3.8 validate_state

P4.5 validate_ownership / handoff
  → повторная P4.4 snapshot validation

P4.6 project_interest
  → validate_ownership для каждого state
  → build_region_summary
      → validate_ownership повторно
```

Старый 96-operation soak поэтому многократно повторял полную рекурсивную validation/deep-duplicate/serialization chain одного крупного canonical ecology state. Это уже не добавляло нового integration coverage, потому что P4.4/P4.5/P4.6 имеют отдельные accepted gates.

R7 сохраняет 8 регионов, 12 циклов, real ecology advance каждого региона, persistence, CAS, handoff, restart, read-cache, missing-interest, full fanout и determinism, но дорогой full mutation path выполняется один раз на цикл для rotating active region. Полный 8-region fanout остаётся отдельной cross-layer проверкой в конце.

## Candidate pins R7

```text
soak test blob = 35ec48936f53b924a462d5cbf0b55036d6eec51d
runner blob    = 243ae60935a50e03bfb88efad4d1c22088541aca
validation     = c53f01650bb73d13308590231bd20e57c3a21b3d
```

## Lifecycle boundary

`RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1` сохраняет legacy filename, но текущая семантика canonical. P4.7 нельзя принять до exact committed Windows A/B PASS с byte-identical logs, `ecology_generation_steps=8`, full-fanout order identity и замороженными `soak_hash` / `final_interest_hash`.

P4.8 control preparation перепинована на R7, но финальный P4 acceptance остаётся fail-closed до P4.7 lifecycle acceptance.
