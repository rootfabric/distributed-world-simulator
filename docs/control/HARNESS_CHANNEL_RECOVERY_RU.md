# DWS Harness — восстановление после сбоев tool / transport / session channel

**Revision:** `H0-CHANNEL-RECOVERY-2026-09-12-R1`  
**Scope:** любой активный checkpoint mission и любой bounded Work Order.  
**Не меняет:** product scope, review independence, acceptance criteria, human merge gates и architecture ownership.

## 1. Главный инвариант

Сбой инструмента, transport route, ephemeral resource handle или reasoning/session channel не является состоянием проекта и не завершает mission.

```text
TOOL / TRANSPORT / SESSION FAILURE
        ↓
TRANSIENT EXECUTION-CHANNEL FAILURE
        ↓
recover exact subject from durable Git state
        ↓
switch allowed route / refetch durable locator
        ↓
resume from last durable predicate
        ↓
Drive / CloseMission again
```

Разрешённые terminal states checkpoint mission не меняются:

```text
MISSION_COMPLETE
HUMAN_DECISION_REQUIRED
HARD_BLOCKED with complete durable proof
```

`ResourceNotReadable`, `Resource not found`, DNS failure, failed ad-hoc `git clone`, download security rejection, expired tool result, потеря длинной reasoning/tool chain и отсутствие preferred executor **никогда сами по себе не являются terminal reason**.

## 2. Durable locator сильнее ephemeral handle

Tool result id, временный resource id, cached response, локальный temp path и содержимое chat являются ephemeral cache.

После потери такого handle запрещено продолжать, предполагая, что старый result всё ещё читаем. Нужно:

```text
DISCARD_STALE_RESOURCE_HANDLE
REFETCH_BY_DURABLE_LOCATOR
VERIFY_EXACT_SUBJECT_IDENTITY
RESUME_FROM_LAST_DURABLE_PREDICATE
```

Durable locator — это, в зависимости от операции:

```text
repository + exact commit SHA / branch
repository path + exact ref
PR number + exact HEAD
workflow run id / artifact id
published evidence path + digest
Work Order / execution id from Git-owned control state
```

После refetch обязательно заново проверить exact HEAD/TREE или другой subject identity, прежде чем использовать evidence.

## 3. GitHub route policy

Для repository read/write агент использует доступный GitHub connector/API либо обычный Git только там, где network + auth этого executor-а уже доказаны.

Правила:

- DNS/network failure внутри текущего container/VM означает `EXECUTOR_LOCAL_ROUTE_FAILURE`, а не «GitHub недоступен».
- Если GitHub connector доступен, не нужно bootstrap-ить новый checkout через `git clone github.com` из network-restricted container только ради чтения/редактирования GitHub.
- `container.download` и аналогичные URL-download обходы не являются Git transport и не используются как замена connector/normal Git.
- Если runtime execution требует checkout, используется уже доступный exact checkout, разрешённый clean worktree или repository-owned CI/self-hosted runner.
- Один сломанный GitHub access route не является `HARD_BLOCKED`, пока существует другой разрешённый route.

Это дополняет, но не ослабляет запрет использовать GitHub Actions как обход normal Git transport.

## 4. Recovery route для network / clone failure

При `Could not resolve host`, transport timeout, TLS/auth route failure или другом executor-local network failure:

```text
CAPTURE_FAILURE_SIGNATURE
CLASSIFY_AS_EXECUTOR_LOCAL_ROUTE_FAILURE
DO_NOT_INFER_REMOTE_SERVICE_OUTAGE
DO_NOT_REPEAT_IDENTICAL_FAILED_ROUTE
TRY_GITHUB_CONNECTOR_OR_EXISTING_EXACT_CHECKOUT
TRY_REPOSITORY_OWNED_CI_IF_EXECUTION_IS_REQUIRED
REANCHOR_EXACT_SUBJECT
RESUME_WORK
```

После двух одинаковых failures стратегия обязана поменяться согласно session stall guard.

## 5. Recovery route для ResourceNotReadable / NotFound

Если temporary resource/result больше не читается:

```text
DO NOT retry the stale id loop
        ↓
recover repository/ref/path/run/artifact identity from durable state
        ↓
fetch a fresh resource
        ↓
verify exact identity
        ↓
continue
```

Нельзя объявлять потерю evidence, если evidence durably существует в Git/CI и может быть перечитано по устойчивому locator.

## 6. Long tool-chain guard

Длинная цепочка инструментов не должна быть единственным носителем прогресса.

Обязательные правила:

1. Каждый завершённый predicate сначала публикуется durably, затем начинается следующий длинный slice.
2. Перед high-fanout tool phase должен существовать resume anchor: exact subject, last completed predicate, next action и recovery route.
3. После transient tool failure нужно re-anchor exact HEAD/subject перед продолжением.
4. Старые ephemeral resource ids не переносятся через recovery boundary.
5. Chat-only summary не считается handoff или recovery anchor.
6. Если mission остаётся non-terminal, обычная ошибка tool/session не разрешает финальный ответ вида «работу продолжить не удалось».
7. Если внешний лимит физически оборвал parent session, следующий агент/session обязан восстановиться из Git и продолжить тот же checkpoint mission; новая реализация уже закрытых predicates запрещена.

## 7. Forbidden stop reasons

Следующие причины классифицируются как recovery triggers, а не mission terminals:

```text
CONNECTOR_RESOURCE_NOT_READABLE
CONNECTOR_RESOURCE_NOT_FOUND
TOOL_RESULT_HANDLE_EXPIRED
CURRENT_EXECUTOR_DNS_FAILURE
CURRENT_EXECUTOR_GITHUB_CLONE_FAILURE
DOWNLOAD_ROUTE_SECURITY_REJECTION
TRANSIENT_CONNECTOR_FAILURE
LONG_REASONING_OR_TOOL_CHAIN_FAILURE
PREFERRED_EXECUTOR_UNAVAILABLE
CURRENT_EXECUTOR_WORKSPACE_LOSS
```

Они могут стать частью `HARD_BLOCKED` только если отдельно доказано, что обязательная capability отсутствует у **всех** разрешённых fallbacks, scope-preserving recovery исчерпан и опубликован полный hard-block proof с resume condition.

## 8. Минимальный recovery anchor

Перед длинным slice и после любого существенного channel failure durable state должен позволять восстановить минимум:

```text
checkpoint / mission / Work Order
exact candidate branch + HEAD (+ TREE where applicable)
last completed durable predicate
known failed route and failure signature
next action
allowed next recovery route
required validation command or CI workflow
open review/verifier state
```

Если это нельзя восстановить из Git-only state, Harness должен считать это дефектом recovery contract.

## 9. Обязательство перед завершением ответа

Перед финальным завершением работы по активной mission агент обязан:

1. восстановить live exact subject после transient channel failure;
2. продолжить доступную automatable работу по fallback ladder;
3. записать durable progress/evidence;
4. снова выполнить `CONTROL_DEVELOPMENT.ps1 -Drive` и mission close gate там, где runner/checkout доступен;
5. не объявлять stop только из-за потери temporary tool state.

Итоговый принцип:

```text
EPHEMERAL CHANNEL MAY FAIL
DURABLE PROJECT STATE MUST SURVIVE
NON-TERMINAL MISSION MUST FAIL FORWARD
```

## 10. Repair R1: совместимость без отключения защиты

Основание: независимое review PR #607 на `78fb91cc1047461b2e333e6cdc293c692d6993f5`, замечания `3994885215` (P1) и `3994885224` (P2).

```text
IMMUTABLE_LEGACY_SNAPSHOT_REQUIRED
MISSING REVISION IS NOT HISTORICAL PROVENANCE
EMPTY ANCHOR REQUIREMENTS ARE INVALID
```

Отсутствие `execution_channel_recovery_revision` теперь допускается только при доказанном старом snapshot. `ContractBundle.source_commit` должен быть полным SHA существующего Git-коммита — предка либо самого `127c732a56cc5c25d5712f24a7627ed4bb877374`, последнего canonical main до появления этой защиты. Все контракты bundle, включая registry, scheduler, catalog, schemas и обе policies, сравниваются с содержимым именно этого коммита. Сравнение полного parsed JSON сохраняет различие boolean и integer; совпадение одного номера generation недостаточно. Git replace refs не участвуют в этой проверке.

Обычный файловый loader старого checkout проверяет его настоящий `HEAD`. Pinned reader обязан явно передать `source_commit`; canonical loader передаёт уже разрешённый exact canonical HEAD, а не берёт его из candidate policy. Произвольный dictionary без такой provenance не получает legacy-исключение. Новый коммит с удалёнными полями не может пройти ancestry fence. Это проверка совместимости чтения, а не разрешение использовать историческую mission как текущую: существующие canonical authority, epoch и dispatch guards остаются обязательными.

Синтетические тестовые репозитории не объявляются историческими только потому, что в них скопированы старые поля. P7 routing fixture сохраняет старый product contract и ожидания `Drive`/`CloseMission`, но использует текущую Harness safety policy. Настоящий legacy replay отдельно проверяется по immutable commits `3d7672cba293d8e7bd72427b803f73fc8fcee5da` и `127c732a56cc5c25d5712f24a7627ed4bb877374`.

В R1 `recovery_anchor_requires` должен содержать ровно пять уникальных строк (порядок несущественен):

```text
EXACT_SUBJECT
LAST_COMPLETED_DURABLE_PREDICATE
KNOWN_FAILED_ROUTE_OR_FAILURE_SIGNATURE
NEXT_ACTION
ALLOWED_RECOVERY_ROUTE
```

Удаление списка, пустой список, пропуск требования, дубль, неизвестное требование или неверный тип отклоняются с `CHANNEL_RECOVERY_ANCHOR_REQUIREMENTS_INVALID`. Замена boolean на `0`/`1` также не считается соблюдением policy. Изменение набора требований требует отдельного согласованного изменения контракта и validator, не молчаливого ослабления JSON.

Проверка policy не является watchdog внешней платформы и не доказывает существование конкретного runtime resume anchor: его durable publication и identity verification остаются обязанностью исполнителя. Завершение отдельного ответа не означает приёмку mission; нельзя обещать автоматическое продолжение без реально запущенного разрешённого исполнителя. Явная отмена или остановка пользователем и ограничения безопасности сохраняют приоритет.
