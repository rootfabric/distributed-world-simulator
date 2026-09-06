# DWS Harness — автономное исполнение задач агентом

**Revision:** `H0-AUTONOMY-2026-09-05-R2`  
**Scope:** execution/validation/evidence routing внутри уже разрешённой checkpoint mission.  
**Не меняет:** архитектурное ownership, canonical main authority, human merge gates и запрет Implementer self-accept.

## 1. Основной принцип

Harness должен максимизировать долю работы, которую текущий агент выполняет самостоятельно.
Отсутствие предпочтительного внешнего агента, отдельной Codex Cloud VM или конкретного
runner-а само по себе **не является** `HARD_BLOCKED`.

```text
SELF-EXECUTE AUTOMATABLE WORK FIRST
        ↓
use available local / VM / container tools
        ↓
use clean worktree or detached exact checkout
        ↓
use repository-owned CI when local execution is insufficient
        ↓
persist exact-head machine evidence
        ↓
route only the independent verdict to a fresh role when required
```

Человек не используется как оператор команд, переносчик логов или подтверждение рутинных Git-действий.

## 2. Что агент делает сам без нового подтверждения человека

В пределах active mission, Work Order и autonomy ceiling агент обязан самостоятельно,
если средство технически доступно:

```text
fetch / inspect / compare refs
create branch / worktree / detached checkout
edit scoped files
install project-declared non-secret dependencies in its disposable environment
run linters / schemas / unit / integration / repository-owned validation
launch project-approved Godot/runtime checks when Work Order их требует и среда доступна
collect logs / exit codes / hashes / screenshots / reports
classify failure
repair confirmed in-scope defects
rerun focused tests and required regressions
commit
non-force push
trigger repository-owned CI
collect CI artifacts
publish append-only evidence
open/update draft PR
post PR evidence/comments
request Reviewer / Verifier
rerun Drive / CloseRole / CloseMission
```

Не нужно спрашивать человека «можно ли запустить тесты», «можно ли сделать commit»,
«можно ли push», «можно ли открыть draft PR» или «можно ли попробовать другой доступный runner».

## 3. Executor fallback ladder

Если предпочтительный способ исполнения недоступен, агент не останавливает mission,
а использует следующий разрешённый способ:

1. `CURRENT_AGENT_VM_OR_CONTAINER` — текущая рабочая VM/container.
2. `CLEAN_LOCAL_WORKTREE_OR_DETACHED_CHECKOUT` — чистый exact-head checkout на той же машине.
3. `REPOSITORY_OWNED_CI` — существующий workflow/runner проекта.
4. `FRESH_ISOLATED_ROLE_CONTEXT_WITH_AVAILABLE_TOOLS` — отдельный контекст роли с доступными средствами.
5. `OPTIONAL_EXTERNAL_AGENT_ENVIRONMENT` — Codex Cloud или другой внешний executor, если он настроен.

Порядок может быть сокращён, если Work Order требует конкретную среду (например exact Godot build,
Windows-only runtime или внешний hardware gate), но такое требование должно быть записано явно.

## 4. Отдельная VM Verifier больше не является неявным требованием

Независимость роли и независимость физической/облачной машины — разные свойства.

```text
MECHANICAL EXECUTION
  команды, тесты, hashes, logs, artifacts
  → может выполнить Implementer или trusted repository-owned CI

INDEPENDENT VERDICT
  оценка достаточности/свежести/применимости evidence
  → отдельный Reviewer/Verifier role, когда его требует risk policy
```

Implementer может создать полное machine evidence, но не может превратить собственный результат
в независимый `PASS`, checkpoint `ACCEPTED` или human approval.

Fresh Verifier может принять exact-head durable evidence без полного повторного запуска каждой команды,
если provenance доверенный и Work Order/risk contract явно не требует independent re-execution.

Отдельный machine rerun обязателен только если существует хотя бы одно из условий:

```text
WORK_ORDER_EXPLICITLY_REQUIRES_INDEPENDENT_EXECUTION
RISK_CONTRACT_EXPLICITLY_REQUIRES_INDEPENDENT_EXECUTION
EVIDENCE_PROVENANCE_IS_NOT_TRUSTWORTHY
REVIEWER_OR_DIRECTOR_RECORDS_A_CONCRETE_REEXECUTION_NEED
```

## 5. Trusted machine evidence

Machine evidence можно передать независимой роли без повторного исполнения только если зафиксированы:

```text
exact frozen HEAD and TREE
commands
exit codes
tracked checkout before/after
full or durable logs
assertion/test summary
fatal/error scan where applicable
runner/workflow provenance
SHA-256 или более сильный digest каждого повторно используемого log/artifact
manifest, связывающий digest с exact HEAD, TREE, runner/workflow run ID и artifact ID/path
no undeclared skip
no PASS rewrite
```

**Reuse без digest запрещён.** Если хотя бы один повторно используемый log/artifact не имеет
SHA-256-or-stronger digest либо manifest не связывает его с exact subject и provenance,
независимая роль обязана вернуть `INSUFFICIENT_EVIDENCE` или выполнить fresh re-execution.
Нельзя считать имя artifact, URL, run `success` или текстовый summary заменой content digest.

Если candidate меняет сам verifier workflow или тестовую инфраструктуру, Reviewer/Verifier обязан
оценить этот diff. Такой CI не становится доверенным только потому, что workflow завершился `success`.

## 6. Когда внешний environment отсутствует

Пример:

```text
Codex Verifier request
    ↓
"create an environment for this repo"
```

Правильный route:

```text
PREFERRED_EXECUTOR_UNAVAILABLE
    ↓
NOT HARD BLOCKED
    ↓
run/retain exact local or repository-CI machine evidence
    ↓
route evidence to fresh independent role
    ↓
request separate machine only if explicitly required
```

Нельзя повторно вызывать тот же недоступный executor вместо использования fallback ladder.

## 7. HARD_BLOCKED

`HARD_BLOCKED` допустим только когда одновременно доказано:

```text
1. capability действительно обязательна для текущего Work Order;
2. все разрешённые автоматические executor fallbacks исчерпаны;
3. нет scope-preserving repair/replan;
4. создан durable blocker proof и указан его evidence path;
5. указан точный непустой resume condition.
```

Machine route обязан проверить все эти условия. Старый флаг
`proven_non_automatable=true` без остальных полей **не является terminal proof** и должен
маршрутизироваться обратно в диагностику/автоматическое восстановление. Неизвестное новое
условие policy также fail-closed: пока его machine predicate не определён, `HARD_BLOCKED` запрещён.

Отсутствие конкретной VM, CLI, внешнего агента или одного GitHub integration route не выполняет эти
условия, если та же работа доступна через другой разрешённый автоматический канал.

## 8. Human gates остаются без изменений

Эта поправка **не** разрешает агенту самостоятельно:

```text
merge в canonical main, когда merge объявлен human gate
direct push в canonical main
force-push / history rewrite
destructive deletion of unmerged remote work
architecture/foundation ownership transfer
явный product decision
checkpoint acceptance, если policy требует Human/Director decision вне полномочий текущей роли
```

Цель поправки — убрать человеческое участие из механической работы, а не убрать контроль принятия решений.
