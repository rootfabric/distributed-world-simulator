# FABRIC R5.2 / T7 — Gearbox

**Статус:** implementation; first exact gate pending.

## Цель

T7 компилирует реальный multi-stage gear train, а не готовый gameplay ratio:

```text
6 gear bodies
+ 232 explicit teeth
= 238 source components

Matter + geometry + tooth quality
        ↓
3 physical meshes
        ↓ compile
rigid Gearbox BehaviorCapsule
```

Base fixture:

```text
20:60
18:54
16:64

total speed ratio = -1/36
```

Знак получается из трёх external meshes; torque меняет знак и увеличивается в 36 раз, сохраняя mechanical power.

## Derived physics

Из tooth count/module выводится pitch radius. Из Matter density + body geometry — mass and rotational inertia. Из tensile/compressive strength + tooth-root area + gear/tooth quality — tangential force and torque envelope. Rim-speed limit выводится из tensile strength / density.

Equivalent input inertia включает каждую gear inertia, отражённую через фактический cumulative speed ratio.

## Reduction boundary

Compiler требует compatible module на каждой mesh и все зубья active. Missing tooth и incompatible mesh fail closed. Weak but still present tooth не выключает gearbox, а уменьшает torque envelope.

Runtime хранит только total ratio, reflected inertia и mechanical limits; source gears/teeth на execute не обходятся.

## Intentional floor

T7 пока lossless rigid gearbox. Он не выдумывает коэффициент КПД. Tribology, lubrication, backlash, tooth compliance, bearing losses, noise/vibration и thermal expansion — downstream fidelity layers.

Такой floor полезен тем, что кинематика, inertia и strength limits уже физически выводятся, а будущие losses можно добавить поверх стабильного mechanical boundary.
