# FABRIC R5.2 / T11 — Smart Servo

**Статус:** Repair R2 exact 3× PASS; exact-head closure/review/verifier pending.

T11 собирает T5 Motor/Generator и T7 Gearbox в closed-loop position servo.

## Coupled mechanics

Редуктор не вызывается как отдельный dynamic state owner. T7 экспортирует reflected inertia, поэтому T11 интегрирует один coupled motor-side state:

```text
J_total =
J_motor
+ J_gearbox_reflected

= 0.011434711 kg·m²
```

Caller-owned state:

- output position;
- motor angular velocity.

Gear ratio остаётся signed и выводится из T7:

```text
ratio = -1/36
```

## Controller

Output-side PD law:

```text
T_out_request =
Kp * position_error
+ Kd * velocity_error

T_motor_request = T_out_request * gear_ratio
I_request = T_motor_request / Kt
```

Safe current envelope выводится из обоих child components:

```text
I_safe =
min(
  T5 current limit,
  T7 input torque limit / Kt
)

= 14.88 A
```

Получаем max output torque ≈ 349.36 N·m.

Saturation — нормальный bounded controller behavior; отдельный 10-rad probe доказывает saturation без превышения child envelope.

## Repair R2 exact evidence

```text
SUBJECT_HEAD = 397f7acc76239cf6bac6dec399cfcaed53245634
SUBJECT_TREE = b2001c807b4e6ccb8158e57fef2c63030614db4a

source carrier run = 35864380300
artifact = 10752155366
artifact digest =
sha256:4bb11c3976af4dabd63d426419ea7ffce46308452ac26f957661d67844430a55

Godot =
4.7.1.stable.double.custom_build.a13da4feb
SHA256 =
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

3/3 PASS
4386 assertions/sample

deterministic hash =
2a618449007f3ca6a1799852af17db1980118549a3c049cf4c56826aa45a8176

evidence hash =
5a7edc22cfcff8c5843359e0474087ce8690ace3dbec14a6eec7bd31583ce567
```

## Exact reference parity

Over 4096 control steps:

```text
current command error = 0
terminal voltage error = 0
position state error = 0
velocity state error = 0
max energy residual = 2.57e-15 J
snapshot replay error = 0
```

## Reflected inertia is active physics

For the same small command:

```text
alpha(coupled T5+T7) / alpha(bare T5)
= 0.92443
```

Replacing steel gears with the already-supported aluminum material reduces reflected inertia and gives:

```text
alpha(light gearbox) / alpha(base gearbox)
= 1.05217
```

То есть gearbox inertia влияет на response, а не хранится только как metadata.

## Repairs

R1: preload alias Control конфликтовал с native Godot class Control. Alias переименован в ServoControl; physics unchanged.

R2: основной moderate trajectory физически не входил в saturation, но acceptance требовал saturation до explicit large-step probe. Assertion привязан к специально предназначенному 10-rad probe. Controller law и thresholds не менялись.

## Bounded claim

Electrical boundary остаётся T5-style ideal current source: Smart Servo возвращает required terminal voltage и electrical energy. T6 Power Stage / battery dynamics входят в следующий composition level, а не скрываются внутри T11.

T11 не заявляет encoder noise/quantization, PWM/current-loop dynamics, backlash, flexible shaft, bearing friction или controller delay.
