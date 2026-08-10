# T1A.7.4 — Scale / Soak Lab — ACCEPTED

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a7-runtime-recovery-interest-scale`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`

## Решение

`T1A.7.4 Scale / Soak Lab` принят.

```text
accepted production runtime dependency:
cab2e1cdcafd831ab9c0cb09123383bf96f5dfe0

accepted scale-lab boundary:
5231f83d52768437c9997d16bee9cff0594e0219

focused + full-regression checkout:
c0213f5edc078481c5705508244e6e556cd1945e
```

После принятого T1A.7.3 T1A.7.4 не менял production runtime. Были добавлены только headless scale acceptance и PowerShell runner.

## Scale contract

```text
100 constructs x 10 subjects   = 1,000 canonical runtime subjects
1,000 constructs x 10 subjects = 10,000 canonical runtime subjects
```

Проверяемые свойства:

```text
canonical subject count exact
no Node3D per subject requirement
selected baseline work < broadcast-all work
selected baseline bytes < broadcast-all bytes
single-subject mutation -> exactly one dirty runtime id
mutation targets only relevant active clients
unrelated active peers receive zero mutation delivery
planner failures = 0
reverse interest index cardinality remains bounded
connect/reconnect baseline is only selected construct set
reconnect fallback remains full authoritative baseline
Construction mutation replay history bound remains 0
replica projection apply measured
interest-move repeated-work/memory observations collected
timing is evidence, not a CPU-specific hard SLA
```

## Windows acceptance evidence

Windows focused runner был обязательным предшествующим шагом к full regression в выданной последовательности. Пользователь затем запустил и прислал успешный full world/core regression на том же checkout. Поэтому focused классифицирован как:

```text
PASS_BY_USER_EXECUTION_SEQUENCE
```

Число Windows assertions не восстанавливается из Linux preflight и не выдумывается.

## Full world/core regression

На checkout `c0213f5edc078481c5705508244e6e556cd1945e`:

```text
RL3 representation-aware network streaming    PASS 175
RL3 representation streaming processes        PASS 37
main_scene_cli_all                             6 PASS / 0 FAIL
lifecycle                                      STOPPED
exit_code                                      0
```

Финальный marker:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Linux preflight — только предварительное evidence

На exact Godot double build preflight прошёл:

```text
2 scale cases
2394 assertions
10,000 canonical subjects in large case
broadcast baseline messages 32,000
projected baseline messages 800
256 mutations
1,024 targeted deliveries
7,168 avoided peer deliveries
```

Эти числа не являются заменой Windows acceptance и не объявляют CPU-independent SLA.

## Не заявляется

```text
1M runtime subjects
compact runtime delta DTO
nonzero bounded mutation replay history
multi-node distributed interest execution
global work scheduler ownership
absolute millisecond SLA across hardware
```

## Status dimensions

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

## Следующий этап

`T1A.7.5 Composition Acceptance`.

T1A.7.5 не должен вводить новый subsystem. Его задача — агрегировать уже принятые recovery, interest/reconnect, selective replication и 10k scale contracts в один финальный T1A.7 acceptance gate, затем снова проверить world/core regression.
