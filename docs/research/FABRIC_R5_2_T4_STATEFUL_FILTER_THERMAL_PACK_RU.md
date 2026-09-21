# FABRIC R5.2 / T4 — Stateful Filter / Thermal Pack

**Статус:** FRESH REVIEW REPAIR R1 — fail-closed state validation; exact rerun pending.

## Цель

T4 проверяет класс поведения, который нельзя свести к статической функции вход→выход: система обязана хранить историю в физическом состоянии.

Fixture:

```text
512 physical thermal cells
8 layers × 64 symmetric lanes
Matter density + heat capacity + thermal conductivity
        ↓ exact symmetry proof
8 caller-owned layer temperatures
        ↓
stateful Thermal Filter BehaviorCapsule
```

Это не "готовый коэффициент охлаждения". Теплоёмкость и проводимость выводятся из canonical Matter materials + geometry.

## Почему редукция точная

64 lanes независимы и геометрически/материально одинаковы внутри каждого слоя. При одинаковой начальной температуре и симметричном входном тепловом потоке каждая lane остаётся на одном и том же trajectory.

Поэтому:

```text
64 cell temperatures in layer
→ exactly one layer temperature
```

Групповая теплоёмкость и межслойная проводимость являются суммой lane-вкладов.

Compiler отказывается от reduction, если хотя бы одна lane отличается по material/volume/enable state.

## Stateful filter semantics

Input:

- heat input W;
- ambient temperature K;
- dt.

State:

- 8 layer temperatures, caller-owned.

Output:

- temperature outer layer;
- signed ambient heat exchange;
- state energy delta;
- energy residual.

Динамическая сеть работает как физический multi-pole low-pass filter: быстрые изменения источника тепла не мгновенно появляются на внешней поверхности.

## Reference gate

Detailed reference обновляет все 512 source cells на каждом tick.

Compiled runtime обновляет только 8 layer states и имеет:

```text
runtime source-cell traversals / execute = 0
```

Acceptance sequence: 2048 heat/ambient steps с проверкой detailed-vs-capsule parity, energy audit, state projection, fail-closed symmetry boundary и canonical live fences. Дополнительно один и тот же instantaneous input подаётся после двух разных thermal histories: output обязан различаться. Caller-owned snapshot затем проигрывается двумя независимыми replay-траекториями, которые обязаны совпасть bit-exact, что запрещает скрытое persistent state внутри runtime.

## Bounded claim

T4 доказывает exact symmetry lumping только для данного structural class. Он не утверждает, что произвольную неоднородную 3D тепловую сеть можно безопасно сжать в 8 состояний. Если symmetry proof не проходит, compiler обязан оставить более детальное представление или вернуть fail-closed.


## Authoritative exact result

```text
RUNTIME SUBJECT = 5ee40be0d19f9d5746d13d63743e9b31577d4b78
RUNTIME TREE    = 1f97293b2958480e0b8fe4bb687c5b2a5c92a4ef

push run        = 35603629267
samples         = 3/3 PASS
assertions      = 2206 / sample
aggregate job   = 106345605893
artifact        = 10640870366
artifact digest = sha256:85fc0dfe6c880570c3db1dfe03d2fe1506682a7545e217bd95eeab9d22dcd505

deterministic hash =
8ef84f3818cc37ff50037bbaa7d22b76cc65276b576fcfdda31e82045a170c79

evidence hash =
eec44e97811abcdad57113c84cc285ac39ae23476e78c172503fd62f710d517a
```

Quantitative result:

```text
512 source cells
8 layer state scalars

source operations = 3072
compiled operations = 36
operation compression = 85.333333x
runtime source-cell traversals / execute = 0

2048 sequence ticks
1,048,576 detailed source-cell traversals

max output-temperature error = 5.11590769747272e-13 K
max layer-state error        = 0
max energy residual          = 7.32562455141306e-10 J

same instantaneous input after different histories:
output delta = 0.628210830977537 K

caller-owned snapshot replay:
output error = 0
state error  = 0
```

Fail-closed boundary:

```text
asymmetric physical lane
→ THERMAL_PACK_LAYER_SYMMETRY_BROKEN

detailed state outside exact symmetry manifold
→ THERMAL_STATE_NOT_IN_REDUCTION_MANIFOLD
```

Wall time/RSS remain observational and are not acceptance thresholds.


## Fresh Review Repair R1

Fresh review обнаружил fail-closed gap в adversarial state validation: detailed reference и state projector не должны принимать non-finite либо thermal-domain-invalid source state даже если canonical fixture таких значений не создаёт.

Repair R1 добавляет явную проверку каждого detailed temperature перед вычислением и отдельные negative gates:

```text
NaN detailed state
→ THERMAL_STATE_PROJECTOR_STATE_INVALID
→ THERMAL_REFERENCE_STATE_INVALID

finite temperature above descriptor domain
→ THERMAL_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN
→ THERMAL_REFERENCE_TEMPERATURE_OUT_OF_DOMAIN
```

Acceptance thresholds не ослаблялись.
