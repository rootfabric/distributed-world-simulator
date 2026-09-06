# DWS Harness — профили execution slice для агентов

Дата пилота: 2026-09-06

Ветка пилота:

```text
control/harness-session-continuation-repair-r1
```

Базовый `main` перед пилотом:

```text
fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91
```

## Цель

Уменьшить зависания длинных reasoning-сессий без изменения истины проекта.

Этот пилот НЕ меняет:

- canonical checkpoint acceptance;
- `MISSION_COMPLETE`;
- review / verifier requirements;
- Project Epoch;
- Work Order semantics;
- Git authority A0-A3;
- `CONTROL_DEVELOPMENT.ps1 -CloseMission`;
- запрет self-accept для Implementer.

Пилот добавляет отдельную модель управления только длительностью одного agent execution slice.

Ключевое различие:

```text
CHECKPOINT MISSION != ONE CONTINUOUS MODEL EXECUTION
```

Mission остаётся открытой и восстанавливается из Git. Execution slice может завершиться на безопасной durable boundary.

## Профили

### ADAPTIVE

Профиль по умолчанию. Предпочитает свежий execution slice перед fresh Reviewer/Verifier context и во время безопасного `VERIFYING`.

### BOUNDED_DEEP_REASONING

Предназначен для агентов, у которых длинный very-high reasoning loop начинает деградировать или зависать.

Текущая эксплуатационная привязка пилота:

```text
GPT-5.6 Sol / Very High -> BOUNDED_DEEP_REASONING
```

Это не архитектурное свойство модели и не часть project truth. Привязку можно менять независимо от Harness.

Профиль предпочитает завершать execution slice на чистой durable role boundary, в `VERIFYING` и `FIX_REQUIRED`, но не перед непосредственной финальной оценкой checkpoint acceptance.

### LONG_HORIZON_CONTINUOUS

Предназначен для агента, который устойчиво проходит несколько ролей в одном execution context.

Текущая эксплуатационная привязка пилота:

```text
Astra -> LONG_HORIZON_CONTINUOUS
```

На обычной role boundary продолжение предпочтительно. Однако внешний asynchronous wait остаётся причиной завершить slice и для этого профиля.

## Новый control surface

```powershell
.\CONTROL_DEVELOPMENT_AGENT.ps1 -Drive -Profile BOUNDED_DEEP_REASONING
.\CONTROL_DEVELOPMENT_AGENT.ps1 -Resume -Profile BOUNDED_DEEP_REASONING
.\CONTROL_DEVELOPMENT_AGENT.ps1 -Yield -Profile BOUNDED_DEEP_REASONING
```

Для длинного профиля:

```powershell
.\CONTROL_DEVELOPMENT_AGENT.ps1 -Drive -Profile LONG_HORIZON_CONTINUOUS
```

После подтверждённого внешнего ожидания:

```powershell
.\CONTROL_DEVELOPMENT_AGENT.ps1 -Yield -Profile BOUNDED_DEEP_REASONING -ExternalPending -ExternalRef "github-actions:<run-id>"
```

`-ExternalPending` разрешено использовать только после одного фактического чтения состояния внешнего dependency. Оно не означает PASS и не закрывает mission.

## Anti-loop правила

1. `session_yield_allowed=true` означает только возможность безопасно завершить текущий execution slice.
2. `mission_exit_allowed` остаётся значением canonical Harness и не переопределяется.
3. При `worktree_dirty=true` или неправильной Work Order branch nonterminal yield запрещается.
4. После обычного `-Resume` агент обязан выполнить следующий action до повторной оценки normal yield.
5. Внешний `queued` / `in_progress` dependency не нужно polling'овать повторно в том же execution slice.
6. Финальное `EVALUATE_CHECKPOINT_ACCEPTANCE_OR_REQUIRED_HUMAN_GATE` не является рекомендуемой yield boundary.

## Проверка

Новый unit gate:

```text
python -m unittest tests.harness.test_agent_execution_policy -v
```

Полная harness regression остаётся прежней:

```text
python -m unittest discover -s tests/harness -v
```

## Rollback

До merge в `main` самый простой rollback:

```text
закрыть draft PR
или удалить/забросить control/harness-session-continuation-repair-r1
```

Базовая точка восстановления:

```text
fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91
```

Если пилот когда-либо будет смержен, его нужно сохранять отдельным commit, чтобы вернуть прежнее поведение одним `git revert <pilot-commit>` без отката других Harness repairs.

Если проблема проявится только у одного класса агента, сначала меняется только:

```text
config/control/harness/agent-execution-profiles.v1.json
```

Core Harness при этом не трогается.

## Критерии успеха пилота

Для одинаковой checkpoint mission сравниваются Sol Very High и Astra:

```text
0 lost commits
0 false MISSION_COMPLETE
0 yield with dirty worktree
0 duplicate external polling loops
100% Git-only resume
same project truth
same exact-head acceptance requirements
```

Количество execution slices может отличаться и само по себе не является ошибкой.
