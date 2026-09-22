# FABRIC R5.2 / T9 — Laser Emitter

**Статус:** Repair R2 exact product PASS локально 3/3; GitHub self-hosted carrier queued.

## Цель

T9 строит optical emitter из physical gain cells вместо gameplay-параметров damage/power:

```text
128 gain cells in a common emitter aperture
active semiconductor Matter + characterized photonic profile
cell area / current path / manufacturing quality
        ↓ compile
LaserEmitter BehaviorCapsule
```

Electrical current и junction temperature приходят через boundary. Capsule возвращает terminal voltage, electrical energy, optical energy, waste heat, wavelength, photon count и bounded common-aperture diffraction floor.

## Repair R2

Fresh review физической формулы выявил проблему: предыдущая формула optical power использовала всю electrical power, включая I²R. При росте series current это позволяло омическому нагреву искусственно увеличивать photon output.

R2 разделяет carrier и resistive power:

```text
electrical power =
V_forward * I + I²R

coherent optical power =
V_forward * max(0, I - I_threshold) * eta(T)

waste heat =
electrical power - optical power
```

Дополнительно profile fail-closed, если reference carrier→photon yield превышает 1. Runtime повторно проверяет этот bound.

Для base GaAs-like fixture:

```text
reference carrier quantum yield = 0.64234
unsafe >1 profile               = REJECTED
```

## Exact R2 evidence

GitHub-hosted R2 run не дошёл до продукта: исторический canonical-engine artifact истёк. Self-hosted exact carrier поставлен в очередь.

Чтобы не блокировать product verification, использован свежий GitHub Exact Source Carrier artifact с base HEAD 7d8cc3, поверх которого наложены четыре R2 product/evidence blob. Их blob SHA byte-exact совпадают с GitHub current subject.

Exact Godot:

```text
version = 4.7.1.stable.double.custom_build.a13da4feb
SHA256  = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Три независимых процесса:

```text
samples = 3/3 PASS
assertions/sample = 3118

deterministic hash =
3767c1b478c022f5a7684083dfa6f587bad90519dbfc46b564d1591bc073af67

local evidence hash =
dbd896094bafbb8372163dda12d1f60c2228cb4f38a0c04bc1593a710302adf5
```

Detailed-vs-compiled:

```text
128 source cells
262,144 detailed traversals over 2048 ticks
768 source operations → 20 compiled operations
38.4x operation compression
runtime source traversal = 0

max terminal voltage error = 0
max optical energy error   = 6.94e-16 J
max waste heat error       = 2.22e-15 J
max photon relative error  = 3.51e-15
max energy residual        = 3.66e-15 J
```

## Damage and material consequences

One disabled cell remains physical mass but leaves the active electrical/optical aperture:

```text
active cells = 128 → 127
beam divergence floor increases by ~1.00393x
old capsule rejects mutated canonical source
```

GaN-like characterized profile produces a shorter 450 nm wavelength and higher 3.2 V forward voltage than the GaAs-like 905 nm floor.

## T6 composition

Merged T6 Power Stage reproduces T9 terminal voltage and electrical boundary energy exactly in the acceptance composition. The accounting keeps separate:

```text
T6 conduction + switching loss = 381.953 J
T9 coherent optical output     = 60.026 J
T9 emitter waste heat          = 283.981 J
```

## Optical scope

Common-aperture divergence uses M² × wavelength / (π × waist radius) with aperture area derived from active cells. This is an explicitly bounded common-cavity/aperture floor, not a coherent phased-array solver.

T9 does not claim free-space propagation, lens focusing, atmospheric absorption, target coupling/damage, cavity longitudinal modes, phase-lock dynamics, saturation, spontaneous-emission noise or detailed semiconductor band-structure validation.

## Remaining gate

Product R2 is exact-tested. Merge remains blocked on closure/fresh independent verification while the canonical self-hosted GitHub runner is unavailable/queued.
