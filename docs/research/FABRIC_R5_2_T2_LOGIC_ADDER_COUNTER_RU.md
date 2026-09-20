# FABRIC R5.2 / T2 — Logic Adder / Counter

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
