# H0.0 — Restart-Safe Harness Scaffold

**Project Epoch:** `E2026-08-11-H0-0-R1`  
**Work Order:** `H0-0-WO-001`  
**Base:** `790fd79f8055fefa19cf9d7263441fc9f4326ebd`  
**Branch:** `control/h0-closed-loop-development`  
**Risk:** `HIGH`
**Target:** `H0_0_SCAFFOLD_READY`

## Решение Director

H0.0 реализует только исполняемый control scaffold поверх уже канонических контрактов `H0-2026-08-11-R1` и `H0-REVIEW-2026-08-11-R1`.

Pre-build Reviewer поднял риск с `MEDIUM` до `HIGH`: новый публичный control interface задаёт recovery semantics, а это minimum HIGH trigger. Реализация была остановлена до фиксации reclassification.

```text
CONTROL_DEVELOPMENT.ps1
  ├─ Status
  ├─ Plan
  └─ Resume
        ↓
canonical contract loader
event reducer / state builder
epoch validator
checkpoint planner
review/evidence/human-attention state
```

До `H0_0_SCAFFOLD_READY` нельзя создавать автономные runtime-ветки C22/NX и нельзя менять gameplay/runtime paths.

## Design Brief

### Проблема

`main` уже хранит цели, checkpoints, risk/review/evidence policies и schemas, но после потери сессии агент всё ещё вынужден вручную интерпретировать их. Единой исполняемой команды восстановления нет.

### Выбранный дизайн

Тонкий PowerShell entrypoint вызывает небольшие Python modules. Derived state всегда перестраивается из Git и canonical JSON. `artifacts/harness/**` остаётся удаляемым кешем.

Append-only events являются авторитетной execution history. Поле `Work Order.state` рассматривается только как сверяемый derived snapshot.

```text
event-derived state != Work Order.state
  → WORK_ORDER_SNAPSHOT_STATE_MISMATCH
  → EXECUTION_STATE_INVALID
  → Plan/Resume continuation blocked
```

Mutable snapshot никогда не побеждает events.

`event.head_sha` обозначает subject head, к которому относится событие. CLI публикует три независимых поля:

```text
event_subject_head_sha
event_ledger_head_sha
current_branch_head_sha
```

`event_ledger_head_sha` — первый commit, добавивший конкретный immutable event path. `current_branch_head_sha` — атомарно захваченный фактический branch/ref head. Subject head никогда не используется как recoverable current head.

### Почему не монолитный PowerShell

Reducer, schema validation, epoch comparison и planner требуют независимых negative/replay tests. Отдельные Python modules дают более узкие ownership boundaries и позволяют проверять их без запуска runtime.

### Non-goals

- `-Execute` и autonomous dispatch;
- C22/NX runtime implementation;
- изменение canonical harness schemas/policies;
- architecture promotion или ownership transfer;
- gameplay/runtime files.

### Главные риски

- неправильный порядок/переходы событий;
- dual truth между events и mutable Work Order snapshot;
- смешение event subject head и ledger/ref head;
- ложная свежесть epoch после движения `main`;
- скрытая зависимость Resume от artifacts или истории чата;
- потеря Reviewer/Evidence Map/Human Attention state;
- обход pilot override и преждевременный выбор C22.

### Fail-closed epoch semantics

```text
origin/main == epoch.base_sha
  → EXACT_BASE

origin/main moved, audit decision absent
  → MAIN_MOVED_REVIEW_REQUIRED
  → continuation blocked

AUDIT_COMPLETED event explicitly permits continuation
  → CONTINUE

EPOCH_INVALIDATED event or explicit refresh decision
  → REFRESH_REQUIRED
```

Движение `main` само по себе не доказывает ни безопасность продолжения, ни необходимость refresh. Без PC0/directional evidence planner обязан закрыться.

### Semantic validation

Помимо Draft 2020-12 schema validation проверяются:

- совпадение epoch/work-order/event identity и base SHA;
- risk minimum и required roles;
- полный Design Brief для `MEDIUM+`;
- непрерывная уникальная event sequence с явной transition table;
- authoritative reducer state против `Work Order.state` snapshot;
- membership checkpoint/predicates в canonical catalog;
- Git reachability base/subject/ledger/current heads;
- normalized allowlist без absolute path, `..` и выхода через symlink;
- fail-closed поведение для malformed/duplicate-key JSON и partial ledger.

Полная machine-readable transition table находится в:

```text
config/control/harness/executions/E2026-08-11-H0-0-R1/transition-table.v1.json
```

Она определяет event-type/state pairs, все допустимые transitions, terminal states и evidence guards для redispatch после `FIX_REQUIRED`, `BLOCKED` и `WAITING_HUMAN`.

### Versioned CLI contract

Каждая команда печатает читаемые stage-сообщения через host/information stream и завершает success stream одним JSON envelope:

```text
schema: distributed_world_simulator.control_development_output.v1
command: STATUS | PLAN | RESUME
ok: true | false
error_code: null | stable machine code
repository: captured ref/head/dirty state
epoch: reconstructed epoch and freshness
work_order: event-derived state plus snapshot consistency
review: risk/reviewer/evidence freshness
human_attention: open/resolved items
findings: deterministic diagnostics
next: checkpoint/work order/verification/human gate
```

Обязательные поля `repository`:

```text
event_subject_head_sha
event_ledger_head_sha
current_branch_head_sha
origin_main_head_sha
worktree_dirty
```

Exit codes:

```text
0  command executed and state was reconstructed (workflow may still be BLOCKED)
2  INVALID_INVOCATION
3  CONTRACT_OR_DEPENDENCY_INVALID
4  GIT_STATE_INVALID
5  EXECUTION_STATE_INVALID
6  INTERNAL_ERROR
```

Ошибки идут в stderr без Python traceback. `PowerShell` явно проверяет `$LASTEXITCODE`.

### Dependency strategy

`scripts/harness/requirements.txt` фиксирует используемую версию `jsonschema`. Harness не устанавливает пакеты и не обращается в сеть автоматически. Отсутствующая/несовместимая dependency даёт стабильный `CONTRACT_OR_DEPENDENCY_INVALID`.

### Governance correction

Event `0006` преждевременно объявил redispatch до Reviewer PASS. Он не переписывается. Event `0007` немедленно вернул execution в `FIX_REQUIRED`, до него не было `IMPLEMENTATION_COMMITTED`. Transition table классифицирует это как `PREMATURE_TRANSITION_CORRECTED_BY_APPEND_ONLY_FIX_REQUIRED`. Новый dispatch разрешён только после свежего Reviewer PASS.

### Evidence review circularity

До review создаётся candidate Evidence Map с `INSUFFICIENT_EVIDENCE`. Reviewer выпускает отдельный review result. После verdict Director формирует отдельную reviewed Evidence Map; исходный candidate не переписывается.

### Проверка

Нужны schema/semantic negative tests, reducer replay, moved-main fixtures, dry-run C22 block, clean-checkout `Resume`, post-build critique, Evidence Map, независимые Reviewer и Verifier, затем PC0.

## Stop rules

При необходимости изменить canonical contract, runtime path, ownership или расширить риск до `HIGH/CRITICAL` работа останавливается для Director replan. Любой `FIX_REQUIRED` сначала требует Repair Map.
