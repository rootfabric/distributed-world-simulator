# FABRIC R5.2 / T10 — Laser Cannon

**Статус:** Repair R2 exact 3× PASS на frozen Source Carrier; exact-head closure/review/verifier pending.

## Цель

T10 — первый прямой hierarchical assembly test:

```text
T6 Power Stage capsule
+ T9 Laser Emitter capsule
+ T8 Cooling capsule
+ 2 optical elements
        ↓ hierarchical compile
Laser Cannon capsule
```

Leaf complexity не разворачивается обратно в runtime:

```text
256 power-stage switch dies
128 laser gain cells
256 cooling thermal nodes
2 optics
----------------------------
642 leaf source components

3848 leaf source operations
        ↓
24 assembly operations

operation compression = 160.33×
runtime leaf traversals = 0
```

## Repair R2 exact evidence

```text
SUBJECT_HEAD = 8e0916384e302d1ec1e8dbcb60a32db2c7977731
SUBJECT_TREE = 60c4f44911c855eb1c82d989f0487a92517075de

source carrier run      = 35747914442
source carrier artifact = 10703657075
digest = sha256:027324bfa3a6798ad525fd89382a6c2a8b9d66d0f9db61a3f4f26f4c458c9af0

Godot = 4.7.1.stable.double.custom_build.a13da4feb
SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

local exact processes = 3/3 PASS
assertions/sample = 6311

deterministic hash =
5905b9102685455853595e246be60fe89c835f8c53814f47a04f3aad220332fd

evidence hash =
104506a20025a786bfb4558f3de99f4496189b39ebb866a1a80298b6b74c03b9
```

Self-hosted Actions carrier в этот момент был заблокирован старым T7 job `35614335791 / 106381057011`. Поэтому exact product evidence выполнено из fresh GitHub Exact Source Carrier bundle на том же byte-exact canonical Godot. Это infrastructure workaround, не изменение acceptance.

## Fire path

```text
DC bus
  ↓ T6
laser electrical boundary
  ↓ T9
coherent optical energy + emitter heat
  ↓ 4 optical surfaces / 4× beam expander
muzzle optical energy
  ↓
range spot / fluence boundary

T6 heat + T9 heat + optics absorption
  ↓
T8 active cooling
```

Persistent state принадлежит только caller: четыре температуры T8 cooling loop. T6 и T9 остаются stateless.

## Exact hierarchical parity

Acceptance сравнивает hierarchical runtime с прямой ручной композицией T6→T9→T8 на каждом из 2048 ticks:

```text
max muzzle-energy error = 0
max heat error          = 0
max spot-radius error   = 0
max cooling-state error = 0

max whole energy residual =
8.13e-11 J

snapshot replay error = 0
```

За последовательность:

```text
muzzle optical energy = 122.525 J
pump hydraulic energy = 2.862 J
max plate temperature = 300.254 K
```

## Optical trust boundary

Optics profile связан с canonical optical Matter checksum и задаёт characterized transmission/fluence/temperature domain.

Две линзы дают четыре surface transmissions. Beam expansion обязан повторно выводиться из focal lengths:

```text
expansion = f_out / f_in = 4×
divergence / bare-emitter divergence = 0.25
```

Repair R2 добавил независимую descriptor-проверку focal-length relation и binding дочерних capsules. Rehashed tamper теперь fail-closed:

```text
bad transmission relation
→ LASER_CANNON_DESCRIPTOR_TRANSMISSION_RELATION_MISMATCH

bad focal-length / expansion relation
→ LASER_CANNON_DESCRIPTOR_EXPANSION_RELATION_MISMATCH

changed T9 child capsule + old descriptor
→ LASER_CANNON_EMITTER_DESCRIPTOR_BINDING_MISMATCH
```

Input clear aperture обязана покрывать emitter aperture:

```text
clipping
→ LASER_CANNON_INPUT_APERTURE_CLIPS_EMITTER
```

Runtime отдельно проверяет optics surface fluence:

```text
fluence limit exceeded
→ LASER_CANNON_RUNTIME_OPTICS_FLUENCE_LIMIT
```

Lossier optics действительно уменьшают muzzle energy; наблюдаемый ratio = 0.94105.

## Energy closure

Whole-cannon audit учитывает T6 bus input, T6 losses, T9 optical/waste heat, optics absorption, T8 pump hydraulic work, cooling state-energy delta, ambient rejection и muzzle optical energy.

## Bounded claim

T10 не заявляет target damage, atmospheric absorption, adaptive optics, lens aberrations, structural recoil, pointing servo или battery/source dynamics. Spot fluence остаётся optical boundary quantity. T11 Smart Servo и T12 Ship Matryoshka расширяют композицию дальше.
