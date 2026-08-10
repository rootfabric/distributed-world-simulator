# T1A.7.4 — Scale / Soak Lab — CANDIDATE

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a7-runtime-recovery-interest-scale`  
**Base:** T1A.7.3 Dirty / Selective Runtime Replication ACCEPTED  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`

## Статус

`IMPLEMENTED_CANDIDATE_WINDOWS_FOCUSED_PENDING`

Accepted runtime dependency:

```text
cab2e1cdcafd831ab9c0cb09123383bf96f5dfe0
```

Accepted T1A.7.3 Windows checkout:

```text
c6544100564d2fa55d96b607ccd9ea61c01387b1
```

T1A.7.4 lab/test boundary before validation metadata:

```text
5231f83d52768437c9997d16bee9cff0594e0219
```

## Главное архитектурное решение

T1A.7.4 **не меняет production runtime**. После T1A.7.3 добавлены только:

```text
tests/construction/t1a7_4_scale_soak_acceptance.gd
RUN_T1A7_4_SCALE_SOAK_TESTS.ps1
```

То есть scale gate измеряет уже принятую selective architecture, а не меняет её во время benchmark.

## Scale cases

```text
case A
100 constructs x 10 subjects = 1,000 canonical subjects
16 logical clients
20 selected constructs/client
2 clients interested in mutation target
128 sequential mutations
256 interest moves

case B
1,000 constructs x 10 subjects = 10,000 canonical subjects
32 logical clients
25 selected constructs/client
4 clients interested in mutation target
256 sequential mutations
512 interest moves
```

Lab полностью headless. Один `Node3D` на runtime subject не создаётся и не требуется.

## Что измеряется

Для каждого scale case summary содержит:

```text
canonical subject count
selected subject count per probe client
full-world baseline bytes
broadcast baseline messages/bytes
projected baseline messages/bytes
avoided baseline messages/bytes
single-construct mutation target count
avoided active-peer deliveries
sequential dirty mutation count
selection/reverse-index cardinality after interest-move soak
selection build time
mutation planning time
interest movement time
projected replica baseline apply time
reconnect replica baseline apply time
static memory observation before/after interest movement
```

Timings и memory monitor являются evidence/diagnostics, а не CPU-specific hard SLA. Acceptance основан на deterministic bounded-work/cardinality invariants.

## Explicit replay bound

T1A.7.4 не создаёт новый replay subsystem.

Текущий Construction mutation replay history:

```text
bound = 0
reconnect = FULL_AUTHORITATIVE_BASELINE
```

Это явный bounded policy. T1A.7.2/T1A.7.3 correctness fallback сохраняется. Ненулевой bounded delta replay может появиться позже только как отдельное архитектурное решение, если он действительно понадобится.

## Acceptance invariants

Обязательные свойства:

```text
canonical count exact
projected baseline messages < broadcast baseline messages
projected baseline bytes < broadcast baseline bytes
one changed subject -> exactly one dirty runtime id
only relevant active clients are mutation targets
unrelated active peer receives 0 mutation
planner failures = 0
retained client-selection count stays bounded by configured clients
reverse construct index stays bounded by world construct count
connect/reconnect baseline applies only selected constructs
full baseline remains reconnect fallback
no Node3D-per-subject requirement
```

## Linux double-build preflight

Перед публикацией candidate новый test был parse/runtime-prechecked на:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
Linux double build
```

Результат:

```text
2 scale cases
2394 assertions
PASS
```

Large-case structural observation из preflight:

```text
canonical subjects          10,000
broadcast baseline messages 32,000
projected baseline messages    800
mutations                      256
targeted deliveries          1,024
avoided peer deliveries      7,168
```

Это **не Windows acceptance evidence** и не абсолютный performance SLA; это только ранняя проверка корректности GDScript/lab composition.

## Что не заявляется

```text
1M runtime subjects
absolute cross-machine millisecond SLA
compact runtime delta DTO
nonzero mutation replay history
multi-node distributed interest execution
WORLD_WORK_BUDGET ownership
WORLD_QUERY_FABRIC ownership
new scheduler foundation
```

TS0.4 может параллельно исследовать structural/representation 1M ceiling; T1A.7.4 остаётся runtime/interest scale evidence. Их результаты должны сходиться через PC0 до T2.0.

## Required Windows gate

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$env:GODOT_BIN = $Godot

.\RUN_T1A7_4_SCALE_SOAK_TESTS.ps1 -GodotPath $Godot
```

Runner сначала повторно прогоняет accepted T1A.7.3 focused gate, затем новый scale/soak lab.

После focused PASS нужен свежий:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

на том же checkout без fetch/reset.

## Следующий этап

После ACCEPTED T1A.7.4:

```text
T1A.7.5 Composition Acceptance
```

Там recovery + interest + selective routing + scale evidence закрываются одним составным T1A.7 checkpoint.