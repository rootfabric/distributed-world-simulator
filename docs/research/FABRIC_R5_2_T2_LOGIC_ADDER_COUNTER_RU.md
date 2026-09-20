# FABRIC R5.2 / T2 — Logic Adder / Counter

**Статус:** EXACT T2 PASS / fresh review + verifier pending.

## Цель

T2 проверяет второй класс qualitative compression:

```text
generic gates + wires + registers
        ↓ compile
truth / transition relation
        ↓
compact lookup executable
```

Kernel не знает понятий `Adder` или `Counter`. Fixtures — только falsification oracles.

## Generic substrate

`LogicComponentGraph` содержит только:

- external Boolean signals;
- AND / OR / XOR / NOT / BUF;
- synchronous REGISTER;
- explicit output signals.

Combinational cycles fail closed. REGISTER разрывает cycle и задаёт state boundary.

`BehaviorCapsule v2` обобщает capsule contract: executable artifact больше не обязан быть PhysicalBake. T1 v1 остаётся frozen.

## T2 fixtures

### 8-bit ripple adder

```text
17 input bits
40 generic gates
0 state bits
        ↓ exhaustive compile
131072-entry exact LUT
        ↓
pack + lookup + unpack
```

Acceptance проверяет все `256 × 256 × 2 = 131072` входа против арифметического oracle.

### 8-bit synchronous counter

```text
enable + reset
24 combinational gates
8 registers
8 state bits
        ↓ exhaustive compile
1024-entry transition/output LUT
```

Semantics:

```text
OUTPUT_EVALUATED
REGISTER_COMMIT
```

State не принадлежит runtime capsule: execute принимает current state и возвращает next state. Canonical persistence/state ownership не дублируется.

Проверяются все `256 × 2 × 2 = 1024` state/input комбинации и 2048-tick deterministic sequence.

## Runtime compression

Prepared lookup runtime не получает source graph и не обходит gates/registers на каждом tick.

Measured separately:

- full interpreter gate traversal;
- prepared LUT runtime;
- compile cost;
- lookup memory cost.

Важно: lookup может обменивать memory на runtime cost. Поэтому T2 обязан публиковать LUT entry count/bytes, а не только speedup.

## Fail-closed

- one-gate mutation меняет table/capsule и инвалидирует old runtime;
- graph/frontier mismatch rejected;
- STALE / invalidation / authority drift rejected;
- combinational cycle rejected;
- address state space > compiler bound rejected.

## Non-claims

T2 не доказывает:

- analog transistor equivalence;
- timing propagation / metastability;
- asynchronous logic;
- persistent canonical register ownership;
- dynamic physical ROM;
- optimal/minimal logic synthesis.

T2 доказывает только exact synchronous Boolean behavior compression for the declared bounded domain.


## Exact T2 result — run 35516297356

```text
SUBJECT_HEAD = ac6fd2102a460baf617764d19bfa7af639a1bfbb
SUBJECT_TREE = 9d72a0a47d75f9620260f71e4dbcf622eeb3b727

samples = 3/3 PASS
aggregate job = 106092924124
artifact = 10606434175
digest = sha256:10812c48d514f00ef4a35371ef368ae299ca72eed5286d0639873967fb3d421c

deterministic hash =
a7bb61c19ddda61527155d3ed405b22b6260cce807a3e958558a13b1a50b8d05
```

### 8-bit adder

```text
40 generic gates
17 input bits
0 state bits
131072 exhaustive cases PASS

compile median      ≈ 8.83 s
LUT                 = 131072 entries
runtime LUT memory  ≈ 512 KiB

gate interpreter    ≈ 66.6 µs/call
prepared lookup     ≈ 19.3 µs/call
observed speedup    ≈ 3.45×
source traversals   = 0
```

### 8-bit counter

```text
24 combinational gates
8 registers
2 external input bits
8 explicit state bits

1024/1024 state/input cases PASS
2048-tick sequence PASS
event order:
  OUTPUT_EVALUATED
  REGISTER_COMMIT

LUT                 = 1024 entries
runtime LUT memory  ≈ 4 KiB
per-instance state  = 8 bits minimum

gate interpreter    ≈ 37.3 µs/call
prepared lookup     ≈ 8.28 µs/call
observed speedup    ≈ 4.51×
source traversals   = 0
```

### Важный tradeoff

T2 lookup не является универсальным ответом для любой микросхемы.

```text
runtime cost
depends weakly on hidden gate count

but LUT size
depends exponentially on:
external input bits + explicit state bits
```

Поэтому compiler fail-closed при address space > 17 bits. Позднее generic compiler может выбирать symbolic/BDD/bytecode/word-level representation, но T2 не подменяет это device-specific распознаванием Adder/Counter.

Главный доказанный принцип T2:

> Внутренний gate/register graph может быть полностью canonical-derived, один раз скомпилирован и затем исполняться без обхода исходных компонентов; state остаётся явным и не захватывается capsule как новая canonical truth.
