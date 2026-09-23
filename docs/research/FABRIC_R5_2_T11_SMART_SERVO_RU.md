# FABRIC R5.2 / T11 — Smart Servo

**Статус:** Repair R3 exact 3× PASS; exact-head closure/review/verifier pending.

T11 собирает T5 Motor/Generator и T7 Gearbox в closed-loop position servo.

## Coupled mechanics

Редуктор не становится отдельным dynamic state owner. T11 интегрирует единый motor-side coupled state:

```text
J_total =
J_motor + J_gearbox_reflected
= 0.011434711 kg·m²

gear ratio = -1/36
```

Caller-owned state:

- output position;
- motor angular velocity.

## Controller and physical envelopes

Output-side PD law:

```text
T_out_request = Kp * position_error + Kd * velocity_error
T_motor_request = T_out_request * gear_ratio
I_request = T_motor_request / Kt
```

Safe current and speed are rederived from both frozen children:

```text
I_safe =
min(
  T5 motor max current,
  T7 max input torque / Kt
)
= 14.88 A

omega_motor_safe =
min(
  T5 max motor omega,
  T7 max gearbox input omega
)
```

R3 stores those raw child limits in the servo descriptor and validates the min-relations independently. A fully rehashed descriptor therefore cannot enlarge the current or speed envelope.

## Repair R3 exact evidence

```text
SUBJECT_HEAD = 6b8cc7e5f81a3b1c9020177a027c1a82d3f6e9b8
SUBJECT_TREE = 163287319fa7efc03142214b058f550b37b67630

source carrier run = 35865338962
artifact = 10752137458
artifact digest =
sha256:22d0a4b493ded168008e2a576f8c7c6f3f469de136b0d4df92c37d4aa2b6f9b4

Godot =
4.7.1.stable.double.custom_build.a13da4feb
SHA256 =
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

3/3 PASS
4388 assertions/sample

deterministic hash =
8e60a85aa92333fd4f347c8e3e08c9031844d7b1c7579b981182e6603d7afc17

evidence hash =
497bedc975db17477ef96a0cef2f1c0bd8db3b670f2bdf85adfe9096370fe15a
```

## Exact behavior

Over 4096 control steps:

```text
current command error = 0
terminal voltage error = 0
position state error = 0
velocity state error = 0
max energy residual = 2.57e-15 J
snapshot replay error = 0
```

Saturation и linear controller regimes оба доказаны. Dedicated large-step probe saturates at the derived current envelope; normal trajectory remains in the linear regime.

## Reflected inertia is active physics

```text
alpha(T5 + steel gearbox) / alpha(bare T5)
= 0.92443

alpha(aluminum gearbox servo) / alpha(steel gearbox servo)
= 1.05217
```

Изменение материала шестерён реально меняет response через reflected inertia.

## Trust-boundary failures

```text
rehash bad J_total
→ SMART_SERVO_DESCRIPTOR_INERTIA_RELATION_MISMATCH

rehash expanded current envelope
→ SMART_SERVO_DESCRIPTOR_CURRENT_ENVELOPE_MISMATCH

rehash expanded speed envelope
→ SMART_SERVO_DESCRIPTOR_SPEED_ENVELOPE_MISMATCH

wrong T7 descriptor for frozen child capsule
→ SMART_SERVO_GEARBOX_DESCRIPTOR_BINDING_MISMATCH
```

## Repairs

R1: preload alias Control конфликтовал с native Godot Control; переименован в ServoControl.

R2: saturation assertion перенесён на dedicated 10-rad probe, где saturation физически действительно происходит.

R3: descriptor теперь хранит raw T5/T7 current/speed/torque envelopes и сам rederive'ит safe limits; checksum alone не считается достаточным trust boundary.

Во всех repair physics law и thresholds не ослаблялись.

## Bounded claim

Electrical boundary остаётся ideal-current-source floor и возвращает required terminal voltage/electrical energy. T6 Power Stage и battery/source dynamics входят в T12 composition.

Не заявлены encoder noise/quantization, PWM/current-loop dynamics, backlash, flexible shaft, bearing friction и controller delay.
