# ECO.EVO7 STREAM1 R1 — Bounded Deterministic Generation Stream

Статус: **LOCAL CANDIDATE / EXACT-WINDOWS VERIFICATION REQUIRED**.

Predecessor:

```text
PAR3 R3.2
8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf
```

Ветка:

```text
feature/eco-evo7-stream1-bounded-generation-stream-r1
```

## Зачем нужен STREAM1

После PAR2 и PAR3 два самых дорогих LS3.3-этапа уже имеют параллельные
исполнители, но поколение всё ещё собирается как один монолитный барьер:

```text
all parents
→ all candidates
→ all routes
→ all recruitment events
→ materialize
→ publish generation
```

STREAM1 вводит **детерминированное bounded streaming представление этого
pipeline**, не меняя биологию и не создавая chunk-level authority:

```text
immutable base generation
→ canonical parent chunks
   → candidate kernel
   → route kernel
   → recruitment kernel
→ full-generation proposal
→ LS3.3 authority validation
→ materialize recruits
→ ONE atomic generation publication
```

Ключевая граница: **chunk никогда не коммитится отдельно**.

## Authority model

### STREAM1 executor

Может:

- читать immutable копию родителей и physical environment context;
- вычислять candidate / route / recruitment evidence;
- собирать один full-generation proposal;
- отдавать proposal + noncanonical telemetry.

Не может:

- менять `LS3.3.records`;
- повышать generation;
- писать persistence/network/world state;
- публиковать частичный chunk;
- становиться вторым источником истины.

### LS3.3

Остаётся единственной authority для поколения. Перед commit он проверяет:

- `base_generation == current_generation`;
- `base_population_hash == current population_hash`;
- generation ровно `current + 1`;
- полные counts;
- canonical candidate order;
- каждый `candidate_hash` через единый PAR3 kernel;
- candidate → **current parent record** binding: record id, reproductive identity,
  cell, offspring ordinal и deterministic mutation seed;
- каждый child hereditary bundle проходит полный LS3.2 identity/checksum
  validator, даже если candidate затем не будет recruited;
- каждый route целиком пересчитывается через единый STREAM1 route kernel;
- связь route → candidate;
- каждый `recruitment_event_hash` через единый PAR0 kernel;
- связь recruitment → route;
- candidate / dispersal / recruitment pool hashes;
- `proposal_hash`.

Только после этого LS3.3 материализует recruits и публикует поколение.

## Single-implementation repair

Чтобы streaming не создал альтернативную биологию:

1. route formulas вынесены из LS3.3 в
   `eco_evo7_stream1_route_kernel_v1.gd`;
2. legacy LS3.3 и STREAM1 вызывают один и тот же route kernel;
3. whole-generation recruitment hash вынесен в PAR0 recruitment kernel;
4. candidate construction остаётся единственным PAR3 candidate kernel.

Таким образом chunk size, completion order и будущий transport не входят ни в
candidate identity, ни в route identity, ни в canonical pool hashes.

## Bounded execution

R1 использует deterministic contiguous parent chunks.

Default:

```text
parents_per_chunk = 64
audit = generation 1 + every 10th generation
```

Proposal identity **не содержит chunk size или chunk count**. Один и тот же
base generation обязан дать один и тот же `proposal_hash` при chunk=1,
chunk=7, chunk=64 и любом будущем эквивалентном scheduler.

Важно: canonical snapshot LS3.3 по-прежнему хранит full
`last_candidates/routes/recruitment` evidence. Поэтому R1 ограничивает
**working set pipeline**, но сознательно не меняет frozen snapshot contract.
Удаление full evidence materialization — отдельный будущий checkpoint.

## Fail-closed

Именованные STREAM1 отказы:

- `STREAM1_INPUT_MISMATCH`;
- `STREAM1_CHUNK_FAILURE`;
- `STREAM1_ROUTE_FAILURE`;
- `STREAM1_RECRUITMENT_FAILURE`;
- `STREAM1_AUDIT_PARITY_FAILURE`;
- `STREAM1_PROPOSAL_INVALID`;
- authority-side `STREAM1_STALE_BASE`;
- `STREAM1_COUNT_MISMATCH`;
- `STREAM1_NONCANONICAL_ORDER`;
- `STREAM1_CANDIDATE_HASH_INVALID`;
- `STREAM1_CANDIDATE_PARENT_BINDING_INVALID`;
- `STREAM1_CANDIDATE_BUNDLE_INVALID`;
- `STREAM1_ROUTE_HASH_INVALID`;
- `STREAM1_RECRUITMENT_HASH_INVALID`;
- `STREAM1_RECRUITMENT_ENV_BINDING_INVALID`;
- `STREAM1_PROPOSAL_HASH_MISMATCH`.

Любой отказ до publication оставляет generation и population state
неизменными.

## Mutual exclusion

R1 намеренно запрещает одновременно инжектировать:

```text
STREAM1 generation executor
+
PAR3 candidate stage executor
или
PAR2 recruitment stage executor
```

Иначе часть stage-executor логики была бы молча bypassed STREAM1-путём.
STREAM1 — альтернативная orchestration boundary поверх тех же pure kernels,
а не скрытый третий backend.

## Public composition

Публичный seam проведён целиком:

```text
Rule Workbench
→ LS3.4 Local Competition
→ LS3.3 Dispersal / Recruitment
→ STREAM1 proposal executor
```

Workbench и LS3.4 остаются backend-ignorant и не получают commit authority.

## Acceptance suite

Добавлен:

```text
tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd
```

Он проверяет:

1. proposal chunk-size invariance: 1 / 7 / 64;
2. byte-exact candidate/route/recruitment evidence across chunk sizes;
3. bounded max parent/candidate chunk;
4. serial-vs-STREAM1 end-to-end parity:
   3 environment recipes × 3 chunk sizes × 12 generations = **108 exact
   canonical comparisons**;
5. deterministic audits gen1 + gen10;
6. chunk failure / audit mismatch / stale base / forged parent binding /
   corrupted proposal hash;
7. generation/state hashes не меняются при fail-closed;
8. mutual exclusion с PAR2/PAR3 executor seams;
9. публичный Workbench → LS3.4 → LS3.3 путь.

Транзитивный Windows runner:

```text
RUN_ECO_EVO7_STREAM1_TESTS.ps1
```

Он жёстко требует:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

и прогоняет LS3.3/LS3.4/PERF1/PAR0/PAR0.2/PAR1/PAR2/PAR3/STREAM1/VIS3/PLAY0.

## Что R1 сознательно НЕ делает

STREAM1 R1 — **не remote distributed compute**.

Он пока не:

- отправляет chunks через broker;
- не запускает отдельный S1 remote worker;
- не вводит worker registration/capability negotiation;
- не меняет production persistence;
- не меняет network replication;
- не повышает ECO shadow runtime до production authority.

R1 сначала замораживает правильную proposal/commit semantics. Следующий
transport step сможет заменить in-process chunk runner на S1-compatible
workers, не меняя canonical proposal identity.

## Acceptance condition

R1 можно считать accepted только после fresh exact-Windows прогона на
точном HEAD с:

```text
STREAM1 focused/transitive suite PASS
+
108/108 canonical parity
+
all fail-closed gates PASS
+
worktree clean
+
exact HEAD/TREE recorded
```

До этого статус остаётся **LOCAL CANDIDATE**, даже если code review зелёный.


## R1 authority hardening review

В финальном source-review до Windows gate дополнительно закрыты два риска:

1. **Parent binding hole.** `candidate_hash` по frozen PAR3 contract не включает
   `parent_record_id`/cell. Поэтому STREAM1 authority отдельно привязывает
   candidate к текущему parent record и проверяет canonical mutation seed.
   Acceptance содержит специально hash-consistent forged-parent fault.
2. **Validate-before-mutate.** LS3.3 теперь валидирует proposed evidence и
   materialized `next_records` до изменения `generation/records`. Это
   убирает старое окно validate-after-assignment и делает failed validation
   атомарно fail-closed для всех LS3.3 execution paths.

3. **Unrecruited bundle validation.** STREAM1 проверяет полный hereditary
   bundle каждого candidate до materialization; валидность не зависит от того,
   попал ли candidate в next population. Отдельный fault удаляет обязательный
   nested field, сохраняя declared checksum/candidate hash, и должен быть
   отвергнут authority.


## Freeze anchors before exact-Windows gate

```text
runtime_code_head:         8636a525c47b524e0ef597e46f37ffe6204d27ee
verification_harness_head: e0d2cda22a431c69a1b3eb4c650d79627d8aea40
```

Final metadata tip содержит только roadmap/checkpoint/mission фиксацию поверх
этих anchors. Fresh verifier обязан брать текущий origin/feature/eco-evo7-stream1-bounded-generation-stream-r1
целиком и записать фактические HEAD/TREE.

Source-review guards перед freeze:

```text
candidate reproduce literal: kernel=1, LS3.3=0
route formula literal:       kernel=1, LS3.3=0
recruitment hash definition: PAR0 kernel=1, LS3.3=0
STREAM1 public facade:       LS3.3=1, LS3.4=1, LS3.6=1
validation before mutation:  YES
```

Windows mission:
`docs/checkpoints/2026-08-30_ECO_EVO7_STREAM1_R1_WINDOWS_VERIFICATION_MISSION_RU.md`.
