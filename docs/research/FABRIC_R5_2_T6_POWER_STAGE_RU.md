# FABRIC R5.2 / T6 — Power Stage

**Статус:** implementation / exact gate pending.

## Цель

T6 добавляет реальный промежуточный уровень между Battery и Motor/Generator:

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

## Runtime boundary

Inputs:

- DC bus voltage;
- signed duty ratio;
- signed load current;
- PWM frequency;
- junction temperature;
- dt.

Outputs:

- signed load voltage;
- signed bus current;
- conduction heat;
- switching heat;
- signed electrical input/output energy;
- energy residual.

Negative bus current is valid regeneration back toward the DC source.

## Exact reduction

Parallel dies aggregate by conductance. The compiler only accepts the current limit as a bank sum when current-limit/conductance scaling is synchronized across the parallel geometry. Unsafe geometry fails closed.

The runtime stores only aggregate bank/path coefficients and traverses zero source dies per execute. Detailed reference recomputes all 256 dies each step.

## T5 compatibility gate

T6 directly composes with merged T5 Motor/Generator. For a chosen motor current, T5 computes the terminal voltage required by winding resistance + back EMF. T6 duty is then chosen to reproduce that exact voltage from the DC bus.

Acceptance requires:

- terminal voltage parity;
- electrical boundary energy parity;
- regeneration preserved through both layers.

## Bounded claim

Semiconductor resistivity/current-density/switching-time values are characterized versioned physical primitives bound to canonical Matter checksums. T6 does not claim transistor-level charge transport, parasitic inductance, EMI, dead-time, gate-driver dynamics or thermal runaway. Those can be later fidelity layers without changing the boundary contract.
