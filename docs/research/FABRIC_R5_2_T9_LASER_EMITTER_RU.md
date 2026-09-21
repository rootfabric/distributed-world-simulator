# FABRIC R5.2 / T9 — Laser Emitter

**Статус:** implementation; first exact gate pending.

## Цель

T9 строит optical emitter из physical gain cells вместо gameplay-параметров damage/power:

```text
128 gain cells in a common emitter aperture
active semiconductor Matter + characterized photonic profile
cell area / current path / manufacturing quality
        ↓ compile
LaserEmitter BehaviorCapsule
```

Electrical current и junction temperature приходят через boundary. Capsule возвращает terminal voltage, electrical energy, optical energy, waste heat, wavelength, photon count и diffraction-limited beam-divergence floor.

## Electro-optical law

Для каждой active gain cell geometry выводит resistance, threshold current, max current, aperture area и physical mass. Characterized profile задаёт только свойства, отсутствующие в generic Matter: threshold/max current density, effective resistivity, forward voltage, optical efficiency floor, temperature derating, wavelength и M².

Ни pack-level efficiency, ни damage-per-second вручную не задаются. Ниже total threshold current optical energy равна нулю; выше threshold electrical energy консервативно делится на optical output и waste heat.

## Exact reduction

Compact reduction разрешён только для active cells с одинаковой derived electro-optical signature. Mixed profiles или geometry mismatch дают fail-closed NO_SAFE_BAKE. Электрически disabled cell остаётся физической массой, но больше не участвует в active aperture/current envelope.

Common-aperture divergence floor рассчитывается как M² × wavelength / (π × waist radius), где effective aperture area выводится из активных cells. Это bounded common-cavity/aperture floor, а не полный coherent-array phase solver.

## T6 composition

T6 Power Stage получает current boundary и duty выбирается так, чтобы stage load voltage совпал с требуемым T9 terminal voltage. Acceptance отдельно сравнивает output electrical energy stage и emitter electrical energy, а также сохраняет отдельно:

- T6 conduction/switching heat;
- T9 optical energy;
- T9 emitter waste heat.

## Bounded claim

T9 не заявляет free-space propagation, lens focusing, atmospheric absorption, target coupling/damage, cavity longitudinal modes, phase-lock dynamics, saturation, spontaneous-emission noise или detailed semiconductor band-structure validation. Эти уровни относятся к T10 Laser Cannon и последующим fidelity layers.
