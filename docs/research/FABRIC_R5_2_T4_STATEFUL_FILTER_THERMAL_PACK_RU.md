# FABRIC R5.2 / T4 — Stateful Filter / Thermal Pack

**Статус:** implementation started; first exact CI gate pending.

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
