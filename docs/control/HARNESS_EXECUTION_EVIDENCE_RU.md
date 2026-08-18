# Harness — canonical execution evidence и freshness

Статус: candidate policy layer `H0-EVIDENCE-2026-08-18-R1`.

Этот слой возник из реального verification finding: exact top-level implementation/test недостаточны, если transitive dependency carrier содержит stub, старую копию или подменённый executable. Поэтому Harness больше не рассматривает слово `fresh` как одно измерение.

## 1. Пять независимых измерений evidence

```text
execution_level
process_freshness
carrier_integrity
transport
role_authority
```

Примеры:

```text
PARSER_PRELOAD + FRESH_PROCESS
!= BEHAVIORAL_EXECUTION

BEHAVIORAL_EXECUTION + FRESH_PROCESS
!= INDEPENDENT_REVIEWER

exact implementation + exact test
!= canonical carrier
если transitive executable closure не exact

DECLARED_EQUIVALENT_EXECUTION
!= CANONICAL_RUNNER executed
```

Evidence не может автоматически повышать собственный класс.

## 2. Canonical behavioral gate

До behavioral execution Harness обязан построить полный transitive preload/execution closure:

```text
root executable/test
    ↓
direct preloads/imports
    ↓
transitive preloads/imports
    ↓
all executable dependencies
```

Для каждого файла фиксируются:

```text
path
git_blob_sha
identity_verified=true
```

PASS допустим только если **все** transitive files exact. Stub/substitute или top-level-only carrier — fail closed.

Closure discovery должна предшествовать execution. Нельзя сначала запустить тест, а потом объявить carrier canonical задним числом.

## 3. Parser != behavior

Parser/preload PASS доказывает только syntactic/load boundary.

Он не доказывает:

- behavioral assertions;
- state transitions;
- deterministic outputs;
- causal controls;
- fault/recovery behavior.

Поэтому `parser_pass=true` никогда не преобразуется в `behavioral_pass=true` без behavioral execution.

## 4. Fresh process != independent role

Fresh process означает новый процесс исполнения.

Clean/exact carrier означает новую проверенную execution environment.

Ни одно из них не создаёт independent Reviewer/Verifier authority.

```text
same implementer/session
+ new process
+ clean exact carrier
= fresh execution evidence
!= independent role evidence
```

Independent Reviewer/Verifier требует отдельного actor/session согласно review policy.

## 5. Canonical runner vs equivalent execution

Если canonical runner недоступен из-за platform/runtime limitation, Harness не имеет права молча считать это PASS.

Допустимы только два состояния:

```text
CANONICAL_RUNNER executed
```

или, если checkpoint **явно разрешает**:

```text
DECLARED_EQUIVALENT_EXECUTION
```

Equivalent execution обязана перечислить predicates canonical runner, доказать их воспроизведение и записать deviations. Поля `canonical_runner_executed` и `equivalent_execution_executed` всегда независимы.

## 6. Freeze и carrier drift

После фиксации code-under-test HEAD evidence/control carrier может двигаться только по non-executable evidence/control/docs paths.

Обязательно перечислять diff:

```text
code-under-test HEAD
    ↓
current evidence carrier HEAD
```

Если после freeze изменился executable или semantic dependency:

```text
old evidence = stale
new code-under-test HEAD required
full relevant verification rerun required
```

## 7. Continuation routing

```text
behavioral FAIL
→ RETURN_TO_IMPLEMENTER_REPAIR_AND_REFREEZE

behavioral GREEN but exact closure incomplete
→ EVIDENCE_CARRIER_REPAIR_REQUIRED

behavioral GREEN + exact carrier, independent role still required
→ ROLE_BOUNDARY

post-freeze executable drift
→ REBIND_TARGET_AND_REVERIFY

checkpoint accepted
→ FOLLOW_EXPLICIT_NEXT_AUTHORIZATION_ONLY
```

Green execution не разрешает самовольно открывать следующий этап, если acceptance policy или role boundary ещё не выполнены.

## 8. Machine enforcement

Canonical contracts:

```text
config/control/harness/execution-evidence-policy.v1.json
config/control/harness/execution-evidence.schema.v1.json
```

Validator:

```text
scripts/harness/execution_evidence.py
```

Negative/positive tests:

```text
tests/harness/test_harness_execution_evidence.py
```

Rule registry IDs:

```text
HC-EXACT-CLOSURE-001
HC-EVIDENCE-CLASS-001
HC-PROCESS-ROLE-FRESHNESS-001
HC-RUNNER-EQUIVALENCE-001
HC-POST-FREEZE-DRIFT-001
HC-NO-EVIDENCE-UPGRADE-001
```
