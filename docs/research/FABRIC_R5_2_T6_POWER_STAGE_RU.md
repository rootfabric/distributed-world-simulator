# FABRIC R5.2 / T6 — Power Stage

**Статус:** authoritative exact 3/3 PASS; exact-head closure/review/verifier pending.

## Цель

T6 добавляет физически выводимый промежуточный уровень между Battery и Motor/Generator:

```text
Battery DC bus
   ↓
256 semiconductor switch dies
4 banks × 64 parallel dies
   ↓ compile
bidirectional H-bridge BehaviorCapsule
   ↓
Motor / Generator electrical boundary
```

Pack-level efficiency не задаётся вручную. ON resistance, current capability and switching transition loss выводятся из characterized semiconductor profile, canonical Matter binding, die geometry and manufacturing quality.

## Authoritative exact result

```text
subject = 1b988a48d705fdacc46d08b01fcea83c4f4cf333
run     = 35611600187
samples = 3/3 PASS
assertions/sample = 3624

deterministic hash =
7ee97e775d3b99c99d6deab90dccd4371ee5b0f07d9ebb07afc0ba4ec287d48d

evidence hash =
62ab6a30a4c2febb08088ae3259d7d40c2b18011a4dda922429a34d9b82b2cdc
```

Compression:

```text
256 switch dies
1536 source operations
        ↓
18 compiled operations
85.33x structural compression

runtime source-die traversals / execute = 0
```

2048-step detailed reference:

```text
full-reference die traversals = 524,288
max load-voltage error        = 0
max bus-current error         = 2.84e-14 A
max conduction-heat error     = 2.78e-17 J
max switching-heat error      = 4.72e-16 J
max energy residual           = 7.02e-15 J
```

## Runtime boundary

Inputs: DC bus voltage, signed duty ratio, signed load current, PWM frequency, junction temperature and dt.

Outputs: signed load voltage, signed bus current, conduction heat, switching heat, signed electrical input/output energy and energy residual.

Negative bus current is valid regeneration back toward the DC source.

## Exact reduction and fail-closed boundary

Parallel dies aggregate by conductance. Current limit is allowed to aggregate only when current-limit/conductance scaling is synchronized across the parallel geometry.

```text
unsafe geometry
→ POWER_STAGE_PARALLEL_CURRENT_SYNCHRONY_UNSAFE

mixed semiconductor profile
→ POWER_STAGE_PROFILE_MISMATCH

open switch bank
→ POWER_STAGE_BANK_OPEN
```

One electrically-disabled die recompiles to 255 active dies, increases the affected path resistance, keeps physical semiconductor mass, and invalidates the old capsule.

## Material consequence

For the same topology/geometry the silicon-like characterized profile derives larger path resistance and slower switching than the SiC-like profile:

```text
SiC R_path ≈ 0.648 mΩ
Si  R_path ≈ 0.972 mΩ

SiC transition ≈ 166 ns
Si  transition ≈ 311 ns
```

## T5 compatibility gate

T6 composes directly with merged T5 Motor/Generator. T5 computes the terminal voltage required by winding resistance + back EMF; T6 duty is chosen to reproduce it from the DC bus.

```text
max T6→T5 terminal-voltage error = 2.84e-14 V
max electrical boundary energy error = 8.88e-16 J
regeneration preserved = true
```

## Bounded claim

Semiconductor resistivity/current-density/switching-time values are characterized versioned physical primitives bound to canonical Matter checksums. T6 does not claim transistor-level charge transport, parasitic inductance, EMI, dead-time, gate-driver dynamics or thermal runaway.
