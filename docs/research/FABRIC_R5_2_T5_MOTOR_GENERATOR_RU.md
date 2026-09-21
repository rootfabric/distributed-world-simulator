# FABRIC R5.2 / T5 — Motor / Generator

**Статус:** Fresh Review Repair R1 — state reconstruction coverage; exact rerun pending.

## Цель

T5 компилирует один и тот же физический assembly как bidirectional motor/generator:

```text
192 winding segments
+ 64 rigid rotor sectors
= 256 source components

Matter + characterized EM profile + geometry + quality
        ↓ compile
R, kT=kE, current limit, inertia, speed envelope
        ↓
1 caller-owned angular velocity state
        ↓
Motor/Generator BehaviorCapsule
```

Здесь нет отдельных magic stats "motor power" и "generator power". Направление передачи энергии определяется знаками current, angular velocity и external shaft torque.

## Physical floor

Generic Matter сейчас содержит density, strength и thermal/structural fields, но не resistivity/remanence. Поэтому T5 использует versioned characterized electromagnetic profile, привязанный checksum-ами к canonical conductor/magnet Matter materials:

- conductor resistivity;
- effective flux density;
- maximum current density.

Это bounded physical primitive, аналогично electrochemical floor T3, а не gameplay bonus.

## Derived behavior

Для каждого winding segment:

```text
R = resistivity × wire_length / wire_area / quality

kT = kE =
2 × turns × B × active_length × lever_arm × quality

Imax = current_density_limit × wire_area × quality

wire mass = conductor density × wire volume
```

Для каждого rotor sector:

```text
mass = density × volume
J = mass × radius²

max ω =
sqrt(tensile_strength × quality / density)
/
radius
```

Assembly aggregates series winding R/coupling and rigid-body inertia.

## Bidirectional energy semantics

Runtime state:

```text
angular_velocity_rad_s
```

Caller owns it. Capsule does not hold a second canonical rotor state.

Midpoint discrete step:

```text
τ_em = kT × I
ω_next = ω + (τ_em + τ_external) × dt / J

V = I×R + kE×ω_mid
```

Energy audit:

```text
electrical energy
=
resistive heat
+
electromagnetic mechanical energy

kinetic ΔE
=
electromagnetic mechanical energy
+
external shaft energy
```

Positive current at low speed is motor mode. Positive shaft speed with negative current can export electrical energy: the same capsule is then a generator.

## Initial acceptance

Fixture covers:

- 192 windings + 64 rotor sectors;
- 2048 mixed motor / coast / generator steps;
- full-source reference vs compiled capsule;
- electrical + total energy audits;
- state/history dependence through back-EMF;
- caller-owned snapshot replay;
- winding-quality variant;
- steel vs aluminum rotor Matter variant;
- open winding / incomplete rotor fail-closed;
- over-current, non-finite state, STALE, invalidation, authority and graph drift.

Timing is observational only.

## Non-claims

T5 does not yet model:

- inductive winding transient/current state;
- magnetic saturation;
- commutation ripple;
- bearings/friction;
- temperature-dependent resistivity;
- hysteresis/eddy-current losses;
- atom-level magnetic behavior.

Those belong to later fidelity layers. T5 proves that a component/material/geometry assembly can compile into compact bidirectional electromechanical behavior without pack-level gameplay stats.


## Fresh Review Repair R1 — state reconstruction

После первого exact PASS fresh review потребовал явно доказать перенос caller-owned rotor state через rebuild.

Для winding-only mutation:

```text
R / kT / kE / current limit change
rotor inertia unchanged
        ↓
ω can be preserved exactly
angular momentum unchanged
kinetic energy unchanged
        ↓
rebuilt capsule + detailed reference parity
```

Для mutation, которая меняет rotor inertia, projector намеренно fail-closed:

```text
MOTOR_STATE_RECONSTRUCTION_INERTIA_CHANGE_UNSUPPORTED
```

Такой mutation требует более богатого canonical event: сохранение angular momentum, detached/attached rotor state и механический impulse нельзя придумывать внутри capsule.

Также добавлен явный overspeed-state negative gate.
