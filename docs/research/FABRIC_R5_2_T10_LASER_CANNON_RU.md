# FABRIC R5.2 / T10 — Laser Cannon

**Статус:** implementation; first exact gate pending.

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

Leaf complexity не разворачивается обратно в runtime. Базовая сборка содержит 642 leaf source components:

- 256 power-stage switch dies;
- 128 laser gain cells;
- 256 cooling thermal nodes;
- 2 optical elements.

При этом fire-step работает только через подготовленные subcapsules и имеет zero source traversals.

## Fire path

```text
DC bus
  ↓ T6
laser electrical boundary
  ↓ T9
coherent optical energy + emitter heat
  ↓ 4 optical surfaces / 4x beam expander
muzzle optical energy
  ↓
range spot / fluence boundary

T6 heat + T9 heat + optics absorption
  ↓
T8 active cooling
```

Persistent state принадлежит только caller: четыре температуры T8 cooling loop. T6 и T9 остаются stateless.

## Optical floor

Optics profile связан с canonical optical Matter checksum и задаёт только отсутствующие в generic Matter characterized свойства:

- transmission per surface;
- maximum surface fluence;
- temperature domain.

Две линзы дают четыре surface transmissions. Beam expander ratio выводится из focal lengths. Input clear aperture обязана покрывать emitter aperture; иначе compile fail-closed. Runtime отдельно проверяет surface fluence.

Spot fluence — только оптическая boundary quantity. T10 не переводит её в target damage.

## Energy closure

Whole-cannon audit учитывает:

- T6 bus electrical input;
- T6 conduction/switching heat;
- T9 optical output and waste heat;
- optics absorption heat;
- T8 hydraulic pump energy;
- cooling state-energy change;
- ambient heat rejection;
- muzzle optical energy.

Acceptance сравнивает hierarchical runtime с прямой ручной композицией T6→T9→T8 на каждом из 2048 ticks.

## Bounded claim

T10 не заявляет target damage, atmospheric absorption, adaptive optics, lens aberrations, structural recoil, pointing servo или battery/source dynamics. Это hierarchical powered optical assembly floor; T11 Smart Servo и T12 Ship Matryoshka расширяют композицию дальше.
