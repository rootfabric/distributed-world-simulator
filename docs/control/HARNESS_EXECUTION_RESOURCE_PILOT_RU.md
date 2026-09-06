# DWS Harness — Execution Resource Pilot R1

Статус: control pilot. Дата: 2026-09-06.

## Цель

Проверить, станет ли Harness лучше использовать собственный Linux self-hosted runner как штатный вычислительный ресурс для independent exact verification, не смешивая его с ролью Verifier и не превращая GitHub Actions в Git transport.

## Базовая проблема до пилота

Наблюдались следующие классы поведения:

- агент знает, что нужна независимая проверка, но не знает, где именно её выполнять;
- разные ветки создают/используют self-hosted workflows без единого resource contract;
- queued jobs могут пережить смену exact subject HEAD и стать stale;
- единственный runner может получить накопленную очередь старых exact jobs;
- физическое имя/ID runner ошибочно может начать восприниматься как архитектурная истина;
- наличие отдельной машины может ошибочно трактоваться как независимость роли;
- при проблемах обычного Git запрещено использовать Actions как transport workaround.

## Изменение R1

Введён machine-owned contract:

```text
config/control/harness/execution-resources.v1.json
```

Основной ресурс:

```text
DWS_LINUX_EXACT
```

Текущий proven selector:

```text
self-hosted
Linux
X64
```

После отдельного live-подтверждения custom labels selector может быть усилен до:

```text
self-hosted
Linux
X64
dws-linux
dws-godot-double
```

До такого подтверждения Harness не должен требовать custom labels и тем самым случайно остановить уже работающий runner.

## Trust boundary

Self-hosted exact resource разрешён только при:

```text
actor = rootfabric
head repository = rootfabric/distributed-world-simulator
event = push | workflow_dispatch
```

Не разрешены:

```text
pull_request execution
external fork execution
source commit/ref publication from Actions
Git transport fallback
workflow mutation inside product implementation scope for obtaining runner access
```

Validation permission:

```text
contents: read
```

## Capacity / stale queue

Ресурс имеет capacity `1`.

Правила:

```text
queued != PASS
in_progress != PASS
exact subject HEAD changed
    -> previous queued exact job = SUPERSEDED
    -> CANCEL before it consumes the runner
```

## Как агент должен увидеть ресурс

`CONTROL_DEVELOPMENT.ps1 -Drive` обязан выдавать:

```text
next.execution_resource
```

Для Verifier ожидается:

```text
required = true
resource = DWS_LINUX_EXACT
provider = GITHUB_ACTIONS_SELF_HOSTED
subject_head = exact implementation HEAD
```

Для Implementer ожидается:

```text
required = false
resource = LOCAL
```

То есть runner не становится обязательным для обычной реализации и focused self-validation.

## Что проверить после активации

Пилот оценивается минимум на следующих 5 реальных verifier handoff либо на всех verifier handoff за ближайший рабочий цикл, если их меньше.

Для каждого случая фиксировать:

1. Выдал ли `Drive` `next_actor=VERIFIER` и `next.execution_resource.resource=DWS_LINUX_EXACT`.
2. Использовал ли агент объявленный resource без дополнительного вопроса человеку.
3. Не создавал/не менял ли агент product workflow только ради доступа к runner.
4. Был ли subject HEAD точным и актуальным на момент dispatch.
5. Был ли старый queued exact job отменён после смены HEAD.
6. Не превышалось ли намеренно более одного heavyweight dispatch при capacity=1.
7. Не был ли `queued`/`in_progress` ошибочно назван PASS.
8. Не был ли runner использован как Git transport.
9. Не была ли независимость Verifier выведена только из факта отдельной машины.
10. Продолжил ли Implementer локальную работу при временной недоступности runner.

## Метрики сравнения

До/после сравнивать:

```text
manual human prompts for where/how to verify
ad-hoc workflow creation for verifier access
stale queued exact jobs
wrong-head verifier runs
verifier handoffs that stop the parent mission unnecessarily
cases where agent reports waiting instead of continuing automatable implementation
successful exact verifier dispatches to declared resource
```

## PASS пилота

Пилот считается улучшением, если после достаточного количества реальных handoff одновременно выполняется:

```text
>= 90% verifier handoff используют declared resource correctly
0 external-fork/self-hosted executions
0 Actions-as-Git-transport attempts
0 queued/in-progress-as-PASS truth violations
0 deliberate capacity>1 heavyweight dispatches
stale exact queue is reduced instead of accumulated
no regression in local implementer continuation
```

## FAIL / корректировка

Если появляются новые подвисания или агенты начинают слишком часто отправлять работу на runner, сначала менять только:

```text
config/control/harness/execution-resources.v1.json
scripts/harness/execution_resources.py
```

Не менять core role/mission semantics без отдельного доказательства.

## Rollback

Изменение изолировано control-веткой `control/harness-execution-resources-r1`.

До merge достаточно закрыть PR и удалить/оставить ветку как historical evidence.

После merge rollback должен отменить execution-resource pilot как отдельный control change, возвращая:

```text
AGENTS/HARNESS_CONTROL resource guidance
execution-resources.v1.json
execution_resources.py
cli next.execution_resource wiring
focused tests / Project Control wiring
```

Git transport policy, checkpoint-session semantics, risk/review policy и product roadmaps при этом не должны откатываться.
