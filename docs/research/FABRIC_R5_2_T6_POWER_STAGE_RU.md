# FABRIC R5.2 / T6 — Power Stage

**Статус:** Repair R2 authoritative exact 3/3 PASS; exact-head closure/review/verifier pending.

## Цель

T6 добавляет физически выводимый промежуточный уровень между Battery и Motor/Generator:

```text
Battery DC bus
   ↓
256 semiconductor switch dies
4 banks × 64 parallel dies
   ↓ compile
bidirectional H-bridge BehaviorCapsule
   ↓
Motor / Generator electrical boundary
```

Pack-level efficiency не задаётся вручную. ON resistance, current capability и switching transition loss выводятся из characterized semiconductor profile, canonical Matter binding, die geometry и manufacturing quality.

## Repair R2 authoritative exact result

```text
subject = 63872eb0cc4dc64cc5468e348915a047c6bf9fd8
tree    = d75e3092e1267243b4d00384ad985b0b191b0360
run     = 35612395529
samples = 3/3 PASS
assertions/sample = 3627

deterministic hash =
d95c0b44507de9e0bcb3f1de5440986b7e63f0b5c575687371575d5f4011f1b7

evidence hash =
4479b50e43eb26e52813f47625160df919d0fa6acd9d1bec4d8600c83a6ff718

aggregate artifact = 10644921532
digest = sha256:223b69875fe40b0f961b9db250063a58eae2a533772dfcfd2c95a499a5dbd180
```

## Compression

```text
256 switch dies
1536 source operations
        ↓
18 compiled operations
85.33x structural compression

runtime source-die traversals / execute = 0
```

2048-step detailed reference:

```text
full-reference die traversals = 524,288
max load-voltage error        = 0
max bus-current error         = 2.84e-14 A
max conduction-heat error     = 2.78e-17 J
max switching-heat error      = 4.72e-16 J
max energy residual           = 7.02e-15 J
```

## Repair R2 — trust boundary

R2 закрыл два review-разрыва без изменения публичной модели и без ослабления thresholds.

Descriptor теперь не доверяет одному checksum: он заново проверяет, что path-level R/current/transition действительно выводятся из соответствующих четырёх bank-level агрегатов. Даже заново захешированный внутренне противоречивый descriptor отвергается:

```text
POWER_STAGE_DESCRIPTOR_PATH_RELATION_MISMATCH
```

Detailed reference теперь сохраняет точный per-die current-sharing envelope:

```text
bank current limit =
G_total × min_i(Imax_i / G_i)
```

Поэтому несимметричная parallel geometry может оставаться физически исполняемой в detailed reference, но compiler корректно отказывается её сжимать:

```text
detailed physics = EXECUTES
compiled reduction =
POWER_STAGE_PARALLEL_CURRENT_SYNCHRONY_UNSAFE
```

Это NO_SAFE_BAKE, а не ложное утверждение, что исходная физическая система невалидна.

## Runtime boundary

Inputs: DC bus voltage, signed duty ratio, signed load current, PWM frequency, junction temperature и dt.

Outputs: signed load voltage, signed bus current, conduction heat, switching heat, signed electrical input/output energy и energy residual.

Negative bus current — валидная regeneration обратно к DC source.

## Material / damage

Для одинаковой topology/geometry silicon-like profile выводит большее сопротивление и более медленное switching, чем SiC-like:

```text
SiC R_path ≈ 0.648 mΩ
Si  R_path ≈ 0.972 mΩ

SiC transition ≈ 166 ns
Si  transition ≈ 311 ns
```

Один отключённый die даёт 255 active dies, повышает сопротивление затронутого пути, сохраняет физическую массу и инвалидирует старую capsule.

## T5 compatibility gate

T6 напрямую композируется со смёрженным T5 Motor/Generator. T5 вычисляет требуемое terminal voltage из winding resistance + back EMF; T6 duty воспроизводит его от DC bus.

```text
max T6→T5 terminal-voltage error = 2.84e-14 V
max electrical boundary energy error = 8.88e-16 J
regeneration preserved = true
```

## Bounded claim

Semiconductor resistivity/current-density/switching-time — characterized versioned primitives, привязанные к canonical Matter checksums. T6 не заявляет transistor-level charge transport, parasitic inductance, EMI, dead-time, gate-driver dynamics или thermal runaway.
