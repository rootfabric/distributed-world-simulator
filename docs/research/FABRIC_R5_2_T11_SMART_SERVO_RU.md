# FABRIC R5.2 / T11 — Smart Servo

**Статус:** implementation; exact gate pending.

T11 собирает T5 Motor/Generator и T7 Gearbox в closed-loop position servo.

Главный контрактный момент: редуктор не вызывается как независимый dynamic solver. T7 экспортирует reflected inertia, поэтому T11 интегрирует один coupled motor-side state с:

```text
J_total = J_motor + J_gearbox_reflected
```

Caller-owned state:

- output position;
- motor angular velocity.

Output velocity всегда связан с motor velocity signed gear ratio.

PD law задаётся на output side:

```text
T_out_request =
Kp * position_error
+ Kd * velocity_error

T_motor_request = T_out_request * gear_ratio
I_request = T_motor_request / Kt
```

Current saturates по физически выведенному envelope:

```text
I_safe =
min(
  T5 motor current limit,
  T7 input torque limit / Kt
)
```

Saturation — нормальный bounded control behavior, а не обход limits.

Electrical boundary остаётся T5-style ideal-current-source floor: runtime возвращает required terminal voltage и electrical energy. T6 Power Stage / battery dynamics сюда намеренно не встроены; это будет composition level T12.

Energy audit включает motor electrical input, winding resistive heat, external output-shaft work и kinetic energy coupled inertia.

T11 не заявляет encoder quantization/noise, backlash, PWM/current-loop dynamics, controller sampling delay, flexible shaft or bearing friction. Эти fidelity layers могут быть добавлены поверх того же servo boundary.
