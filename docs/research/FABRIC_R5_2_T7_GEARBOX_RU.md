# FABRIC R5.2 / T7 — Gearbox

**Статус:** Repair R2 authoritative exact 3/3 PASS; exact-head closure/review/verifier pending.

## Цель

T7 компилирует multi-stage gear train, а не готовый gameplay ratio:

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

total signed speed ratio = -1/36
torque multiplication magnitude = 36x
```

## Repair R2 authoritative result

```text
subject = 939a31f8d5b140adc075e7a35bd5fb531926bfc1
tree    = 5659a2d81ec210483f517b4833538641fa321a2b
run     = 35614946267
samples = 3/3 PASS
assertions/sample = 3114

deterministic hash =
50870621cc1ca8fcf76312ba803e2e6a8061cfb8414e133c20b8ca7d46995286

evidence hash =
891e6c88811df00ec59b8a33cc9746215bc366bb6c83185860925ac1287fab97

aggregate artifact = 10646355991
digest = sha256:88a2198b53dbeb0c598648023d355fe1e45e5b7c64b7ab2a328209ead99839a4
```

Compression:

```text
238 source components
1428 source operations
        ↓
16 compiled operations
89.25x operation compression

runtime source traversal / execute = 0
```

Detailed reference over 2048 samples:

```text
component traversals = 487,424
max omega error      = 0
max torque error     = 0
max inertia error    = 0
max instantaneous boundary energy residual = 4.44e-16 J
```

## Derived physics

Pitch radius идёт из tooth count × module. Mass and rotational inertia — из canonical Matter density и body geometry. Tangential force / torque envelope — из tensile/compressive strength, tooth-root area, gear quality и minimum active tooth quality. Rim-speed envelope — из tensile-strength/density scale.

```text
equivalent input inertia = 8.64e-4 kg·m²
gearbox mass             = 5.146 kg
max input torque         = 43.58 N·m
max input omega          = 9256 rad/s
```

Gear-body mass — equivalent whole-gear body approximation. Явные tooth rows — topology/local-quality carriers; они не добавляются второй раз как отдельные mass volumes.

## Repair R1

Первый тестовый weak tooth находился на stage 1, тогда как глобальный torque envelope ограничивался stage 2. Модель корректно не изменила pack limit. Fixture исправлен: weak tooth перенесён на реальный limiting mesh.

```text
base input torque limit = 43.58 N·m
weak-tooth limit        = 24.97 N·m
```

Thresholds не ослаблялись.

## Repair R2 — reflected inertia как контракт

Первый зелёный вариант вычислял reflected inertia, но interface её явно не объявлял. R2 добавил:

```text
EQUIVALENT_INPUT_INERTIA_KG_M2
```

в официальный mechanical boundary.

Это важно для композиции с T5: gearbox не является вторым независимым rotor-state owner. Он остаётся algebraic rigid element, а downstream coupled solver суммирует motor rotor inertia и reflected gearbox inertia.

В acceptance:

```text
alpha(T5 + gearbox) / alpha(bare T5) = 0.92443
```

То есть inertia не просто вычислена для отчёта — она меняет coupled mechanical response.

## Material consequence

При той же topology aluminum-like gear material даёт:

```text
mass              5.146 → 1.770 kg
reflected inertia 8.64e-4 → 2.97e-4 kg·m²
input torque limit 43.58 → 20.11 N·m
```

## Fail-closed boundary

```text
disabled tooth
→ GEARBOX_TOOTH_DISABLED

incompatible gear module
→ GEARBOX_MESH_MODULE_MISMATCH

rehash of inconsistent output torque relation
→ GEARBOX_DESCRIPTOR_OUTPUT_TORQUE_MISMATCH
```

Old capsule также отвергает canonical source mutation.

## T5 compatibility

T5 Motor/Generator mechanical output можно напрямую подать на T7 boundary. Exact samples подтверждают speed ratio, torque multiplication и instantaneous rigid-boundary power conservation. Отдельный coupled-inertia check подтверждает, что полноценный assembly solver должен использовать J_motor + J_gearbox.

## Intentional floor

T7 — lossless rigid gearbox floor. Tribology/lubrication losses, backlash, tooth compliance, bearings, thermal expansion, noise/vibration пока не заявлены. В частности, последовательность algebraic boundary samples не считается самостоятельной dynamic integration gearbox inertia; для динамики используется exported reflected inertia во внешнем coupled solver.
