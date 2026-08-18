# SM1-I2.1 — Ownership Directory atomic CAS candidate

Status: `RESEARCH_ONLY_REPAIR_R1_CANDIDATE`

Branch: `research/sm1-i2-directory`

Reviewed architecture base:

`87a9ca12c38a9b15069fb49a57bfa344b8c25cfa`

Architecture gate:

`SEAMLESS_R2_REPAIR_R1_FRESH_INDEPENDENT_REVIEW_PASS`

Review ID: `4961220624`

## Цель

I2.1 реализует самый маленький исполнимый фундамент Ownership Directory: один канонический `OwnershipRecord`, отдельный read-only `lookup()` и атомарный expected-state `compare_and_swap()`.

Этот checkpoint отвечает только на вопрос: если несколько претендентов пытаются изменить ownership от одного и того же observed state, может ли Directory разрешить ровно один переход и сделать все stale попытки mutation-free.

## Реализовано

`OwnershipRecord` фиксирует:

- `subject_or_domain_id`;
- `owner_authority_id`;
- `authority_epoch`;
- `fencing_token`;
- `directory_generation`;
- `authority_incarnation`;
- `state_revision`;
- `lease_state`;
- `route_revision`.

`OwnershipDirectory` предоставляет:

- `lookup(subject_or_domain_id)` — чтение без ownership mutation;
- `create(record)` — create-if-absent, без overwrite существующей записи;
- `compare_and_swap(expected, desired)` — полный expected-record match;
- machine-readable evidence для create/lookup/CAS результатов.

CAS возвращает один из:

- `CAS_OK`;
- `CAS_MISMATCH`;
- `INVALID_TRANSITION`;
- `NOT_FOUND`.

## Замороженные I2.1 invariants

- `subject_or_domain_id` не меняется CAS-переходом;
- `directory_generation` строго растёт на успешном переходе;
- epoch/fence/state/route revisions не могут откатываться;
- смена owner требует роста `AuthorityEpoch` и `FencingToken`;
- смена incarnation того же owner требует нового `FencingToken`;
- failed/stale CAS не изменяет canonical record;
- два конкурентных CAS от одного expected state не могут оба завершиться `CAS_OK`;
- lookup и mutation являются разными операциями.

## Критическая гонка

Начало:

```text
D = A / epoch 10 / fence 100 / generation 50
```

Два конкурентных предложения:

```text
A/10/100/50 -> B/11/101/51
A/10/100/50 -> C/11/102/52
```

Требование:

```text
exactly one = CAS_OK
exactly one = CAS_MISMATCH
final record = winner
```

Тест использует два реальных Python thread, синхронизированных `Barrier`, и один lock-protected Directory record.

## Validation

До публикации candidate:

```text
python3 -m unittest discover \
  -s tests/research/seamless/i2 \
  -p 'test_i2_1_directory.py'
```

Результат исходного candidate: `15/15 PASS`.

После Repair R1 component suite расширен и должен пройти `17/17 PASS`.

Demo runner:

```text
PYTHONPATH=. python3 scripts/research/run_sm1_i2_1_directory.py
```

Ожидаемый итог:

```text
first_cas = CAS_OK
stale_cas = CAS_MISMATCH
final owner = authority-b
result = PASS
```


## Repair R1 после critical review PR #149

Superseded candidate HEAD:

`bdca076dd5ea6fc4e304cfcac58e7d1523863bbd`

Review ID: `4961827768`

Repair закрывает три finding:

- `I2.1-R-001`: CAS теперь классифицирует current state **до** validation desired transition. Если `expected` stale, результат всегда `CAS_MISMATCH`, даже если `desired` сам по себе invalid. `INVALID_TRANSITION` возможен только когда `expected == current`.
- `I2.1-R-002`: каждый `CAS_RESULT` получает `linearization_sequence` под тем же ownership lock, в котором принимается CAS decision; evidence append выполняется до освобождения этого lock, поэтому concurrent CAS evidence не может инвертировать serialization order.
- `I2.1-R-003`: contention test теперь связывает final canonical record с конкретным contender, получившим `CAS_OK`, и требует, чтобы loser видел winner state в `observed/current`.

Repair добавляет falsification tests:

```text
OD-CAS-14 stale expected + invalid desired -> CAS_MISMATCH
OD-CAS-15 concurrent CAS evidence -> linearization_sequence [1,2]
          and status order [CAS_OK,CAS_MISMATCH]
OD-CAS-16 machine contract matches repaired semantics
```

`linearization_sequence` — это не wall-clock timestamp. Это монотонный порядок CAS decision/linearization points внутри одного Directory instance. Durability и cross-process ordering по-прежнему остаются за пределами I2.1.

## Что сознательно НЕ реализовано

I2.1 не заявляет доказанными:

- durable storage;
- Directory restart recovery;
- network partition recovery;
- canonical gameplay mutation authorization;
- lease expiry;
- gateway routing;
- AuthorityDomain handoff;
- Item Graph/player runtime integration.

Это важно: in-memory backend здесь заменяем. Продукт checkpoint — CAS/fencing transition semantics и их machine evidence, а не выбор production storage technology.

## Следующий checkpoint

`SM1-I2.2 — Epoch / Fence / Incarnation authorization`

Он должен использовать I2.1 record/CAS и доказать, что canonical mutation допускается только для текущего `(owner, epoch, fence, incarnation)` и что старый writer получает `FENCED`.
