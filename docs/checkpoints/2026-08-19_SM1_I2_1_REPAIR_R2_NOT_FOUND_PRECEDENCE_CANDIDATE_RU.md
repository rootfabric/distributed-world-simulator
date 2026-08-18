# SM1-I2.1 — Repair R2: NOT_FOUND precedence falsification

Status: `RESEARCH_ONLY_REPAIR_R2_CANDIDATE`

Branch: `research/sm1-i2-directory`

Architecture base:

`87a9ca12c38a9b15069fb49a57bfa344b8c25cfa`

Superseded Repair R1 HEAD:

`829e609a2cbf204c8cd3fed3481cc5ff112ec947`

Fresh independent verdict on Repair R1:

`SM1_I2_1_REPAIR_R1_FRESH_INDEPENDENT_REVIEW_FIX_REQUIRED`

## Причина Repair R2

Fresh Reviewer подтвердил, что compare-first реализация Directory уже корректна, `I2.1-R-002` закрыт и `I2.1-R-003` закрыт. Единственный оставшийся gap — Repair R1 не добавил второй falsification case, который был явно затребован исходным review для `I2.1-R-001`:

```text
canonical record absent
+
desired invalid relative to expected
=>
NOT_FOUND
```

`desired` не должен валидироваться, пока Directory не установил, что canonical record существует и точно равен `expected`.

## Scope

Repair R2 не меняет `tools/research/seamless/i2/directory.py` и не вводит новые runtime semantics.

Добавляется только test/evidence closure:

- `tests/research/seamless/i2/test_i2_1_directory_repair_r2.py`;
- `config/research/seamless/i2/i2-1-directory-repair-r2.v1.json`;
- этот checkpoint document.

## OD-CAS-17

Исходное состояние:

```text
Directory = empty
expected = A / epoch10 / fence100 / generation50
desired  = A / epoch9  / fence100 / generation51
```

`desired` намеренно invalid, потому что `authority_epoch` уменьшается.

Обязательный результат:

```text
status   = NOT_FOUND
observed = null
current  = null
snapshot = empty
```

Machine evidence также обязано фиксировать `NOT_FOUND` как первый CAS decision с `linearization_sequence = 1`.

Этот тест доказывает полный compare-first порядок классификации:

```text
load current
  absent            -> NOT_FOUND
  != expected       -> CAS_MISMATCH
  == expected       -> validate desired
                         valid   -> CAS_OK
                         invalid -> INVALID_TRANSITION
```

## Не меняется

Fresh Reviewer уже дал PASS для:

- `I2.1-R-002` — causal/linearization-safe CAS evidence;
- `I2.1-R-003` — exact winner/final-state binding;
- остальных заявленных I2.1 invariants;
- research-only scope.

Repair R2 не открывает I2.2 автоматически. После нового exact HEAD требуются component evidence, Project Control и новый genuinely fresh independent READ-ONLY review.
