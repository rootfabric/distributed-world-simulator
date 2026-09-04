# FABRIC COMPLEX2-E — Settle → Rebake → Re-impact

**Статус:** ✅ PHYSICAL EXACT VERIFIED  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**Exact subject:** `b618c449b6dae5a25a14d24bfed87dbc2832d125`  
**TREE:** `ed5450dc71f4b0fb707b18af5c6b1584f73199ef`  
**Evidence:** `validation/FABRIC_COMPLEX2_E_SETTLE_REBAKE_REIMPACT_EXACT_EVIDENCE.md`

## Цель

После COMPLEX2-D машина уже пережила независимый structural failure и сохранила связность. E проверяет следующий более сложный lifecycle: умеем ли мы отличать физическое затухание от canonical mutation, пересобрать derived dynamic representation из settled state и затем снова корректно возбудить уже перестроенную машину.

```text
D structural failure complete
        ↓
first dynamic impact
        ↓
ringdown
        ↓
SETTLED
        ↓
DYNAMIC_ROM REBAKE
        ↓
new exactly-once RE-IMPACT
        ↓
coupled response resumes
```

## Почему settle не source mutation

Положение и скорость системы меняются каждый timestep, но это runtime physical state, а не изменение canonical Construction/Matter topology. Поэтому E запрещает увеличивать source revision только потому, что система успокоилась.

При rebake сохраняются:

```text
region/complex2-dynamic
DYNAMIC_ROM
state owner
source slice
canonical source revision
```

Меняются:

```text
backend_contract_hash
PhysicalBakeArtifact checksum
build_generation -> 6
registry identity
```

Новый backend identity включает hash settled q/v и уже существующей D-topology. Это derived cache lifecycle, а не второй canonical truth.

## State machine

```text
TRANSIENT
   ↓ mark_settled
SETTLED
   ↓ mark_rebaked
REBAKED
   ↓ commit_reimpact
REIMPACTED
```

Wrong-order операции fail closed:

```text
COMPLEX2E_REBAKE_REQUIRES_SETTLED
COMPLEX2E_REIMPACT_REQUIRES_REBAKED
COMPLEX2E_REIMPACT_ALREADY_APPLIED
```

## Settle envelope

Первый impact действует на shoulder path 20 steps, затем drive снимается. Используется тот же four-DOF coupled backend из COMPLEX2-C:

```text
shoulder ↔ elbow ↔ shaft ↔ carriage
```

Settled состояние допускается только если одновременно:

```text
energy <= 0.0025 J
max path speed <= 0.020 m/s
```

Exact:

```text
settle step    = 549
settled energy = 0.0024826531871402274 J
```

ACTIVE DYNAMIC и FULL reference проходят одинаковую траекторию; energy balance и passive damping проверяются на всём ringdown.

Перед rebake q/v сериализуется через C state packet и восстанавливается с zero error.

## Rebake

E не создаёт шестой representation owner и не переключает kind. Он перестраивает существующий DYNAMIC_ROM artifact:

```text
old DYNAMIC_ROM
   │ same source slice
   │ same scalar region state owner
   │ settled q/v state hash
   ↓
new DYNAMIC_ROM generation 6
```

Runtime rebuild возвращает:

```text
state handoff error = 0
```

После rebake выполняются quiet mixed/FULL steps, прежде чем разрешить новый impact.

## Re-impact after rebake

Новый event:

```text
event/complex2e-reimpact-after-settled-rebake
```

Он не является повтором D-event и принимается exactly once.

Physical re-impact прикладывается к shaft DOF и через reciprocal couplings возбуждает остальные части:

```text
shaft -> elbow / carriage -> shoulder
```

Exact peak energy:

```text
0.612677432 J
```

Это больше чем в 100 раз выше settled energy. Acceptance также требует заметного движения всех четырёх DOF и соблюдения C certification bounds.

Параллельно mixed runtime получает CONTACT + DYNAMIC flow. CONTACT state меняется на:

```text
0.008322890093712065
```

Mixed и FULL runtime остаются эквивалентны.

## Что E не делает

E намеренно не добавляет скрытый structural break или functional mutation. Проверяется:

```text
structural topology before rebake == after re-impact
HYBRID compliant backend unchanged
functional topology identity retained
five representation owners unchanged
```

Это важно: повторный impact может менять physical state, не обязан автоматически менять topology.

## Visual lab

```text
res://scenes/labs/fabric/complex2e_settle_rebake_reimpact_lab.tscn
```

`Space` показывает четыре evidence stages:

```text
FIRST IMPACT PEAK
SETTLED
REBAKED DYNAMIC_ROM
RE-IMPACT PEAK
```

Visual observer read-only.

## Exact result

```text
FABRIC COMPLEX2-E Settle Rebake Re-impact Acceptance:
PASS (47 assertions)

hash:
77c3c1e792d082391c8901d9c61946b0655c4abd332f71dc4554ef479fc9a5f8
```

Два независимых exact bundle checkout дали один hash.

## Control-plane status

Project Control на E-head остаётся RED в общем architecture/ownership passport compatibility regression из-за уже существующего drift G/ECO/V0/Matter/P7. Exact D/E files не названы причиной RED. Поэтому E отмечается как `PHYSICAL EXACT VERIFIED`, а global control-plane status сохраняется отдельно.

Следующая необходимая ступень для COMPLEX2 — `COMPLEX2-PERF 500 / 1000 / 2000`, после неё `COMPLEX2-CLOSE`.