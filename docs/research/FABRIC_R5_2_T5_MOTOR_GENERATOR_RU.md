# FABRIC R5.2 / T5 — Motor / Generator

**Статус:** REPAIR R1 AUTHORITATIVE EXACT PASS / exact-head closure rerun pending.

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


## Repair R1 authoritative exact result

```text
SUBJECT_HEAD = dc31849760d94a8ace76aecc8e17bdd4991b9441
SUBJECT_TREE = 5f77c70d156b5959e913d95ae61694843afb5b9d

run             = 35606491334
samples         = 3/3 PASS
assertions      = 2234 / sample
aggregate job   = 106354999859
artifact        = 10642385491
artifact digest = sha256:a27d858316224a746cf59b5f614739c0edd64c5e4a8c9cb80501d1fcc75f1d34

deterministic hash =
3e99d3add53d800016395235245e5a24f24bbd0921c72af7bdcb295f9d1ca61a

evidence hash =
f92c6011470f78f78b1a7ccf8a2624903c9c006a82407b002f4fecfa762c269e
```

Key quantitative result:

```text
source components = 256
  192 winding segments
  64 rotor sectors

runtime state = 1 scalar (ω)

source operations = 1408
compiled operations = 14
operation compression ≈ 100.57x
runtime source traversal = 0

2048 detailed-reference ticks
source traversals = 524,288

max V error      = 0
max torque error = 0
max ω error      = 0

max electrical energy residual = 8.88e-16 J
max total energy residual      = 2.41e-13 J
```

Generator mode is directly observed:

```text
terminal voltage ≈ 230.23 V
electromagnetic torque ≈ -2.609 N·m
electrical energy / observed step ≈ -1.842 J
```

Negative electrical energy means energy leaves the electromechanical assembly into the electrical boundary under the declared sign convention.

Stateful proof:

```text
same instantaneous zero-current command:
stationary vs spinning rotor
→ terminal-voltage delta ≈ 78.26 V

snapshot replay:
voltage error = 0
state error   = 0
```

Repair R1 reconstruction:

```text
winding-only coefficient mutation
→ COEFFICIENT_CHANGE_SAME_ROTOR_INERTIA
→ projected/rebuilt detailed parity = 0

rotor inertia mutation
→ MOTOR_STATE_RECONSTRUCTION_INERTIA_CHANGE_UNSUPPORTED
```

Wall-time/RSS are observations only.
