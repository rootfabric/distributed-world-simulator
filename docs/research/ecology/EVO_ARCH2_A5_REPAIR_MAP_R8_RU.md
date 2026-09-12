# EVO ARCH2 A5 — Repair Map R8

Дата: 2026-09-08  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; accepted A0–A4, production/main/network/Matter authority не изменяются.

Fresh Independent Reviewer exact subject `3f390bdebbfae8a6f3e8397939badaf7ae59eb15` обнаружил три blocking findings. Этот repair map фиксирует bounded source repairs RM-A5-12..14 и executable counterexamples. Все Reviewer/Verifier verdicts на `3f390bde...` после публикации этого source являются historical/stale.

## RM-A5-12 — reserve-aware intake headroom

Проблема: A4 demands строились из inherited uptake policy без учёта свободного места в `metabolic_reserves`. Поэтому допустимое состояние с заполненным compartment могло получить новый grant и завершить lifecycle через `A5_RESERVE_OVERFLOW` до maintenance/growth.

Исправление в `resource_lifecycle_runtime_v1.gd`:

```text
material_headroom = B.MAX_STOCK - metabolic_reserves.material_mg
water_headroom    = B.MAX_STOCK - metabolic_reserves.water_mg
energy_headroom   = B.MAX_STOCK - metabolic_reserves.energy_mj
```

`water_mg` demand ограничивается `water_headroom`.

`nutrient_mg` и `organic_mg` совместно используют один `material_headroom`. Если desired sum превышает headroom, выполняется deterministic proportional integer clipping. Обе floor-доли вычисляются от одного общего budget; оставшийся максимум один integer unit получает nutrient first как фиксированное remainder rule. Поэтому всегда:

```text
requested_nutrient + requested_organic <= material_headroom
requested_water <= water_headroom
```

A4 grant не может превышать demand, следовательно те же inequalities математически сохраняются для фактического intake.

Photosynthesis сначала вычисляет текущий `energy_headroom`, после чего external light energy клиппируется этим headroom до любых ledger/reserve writes. Одно и то же clipped значение записывается в:

```text
resource_ledger.external_energy_mj
resource_ledger.assimilated.energy_mj
metabolic_reserves.energy_mj
```

External source остаётся явным; порядок `sample -> allocation -> assimilation -> maintenance -> growth -> reproduction` не меняется.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_12_reserve_headroom.gd
```

Он покрывает saturated material, exact shared headroom=7, saturated water, saturated energy + real collector/strong light, actual A4 grants, conservation и deterministic split.

## RM-A5-13 — alive/starvation policy binding

Проблема: persisted A5 state мог объявить `alive=false, starvation_ticks=0` либо `alive=true` при достижении inherited starvation limit.

`OrganismLifeStateV1.validate()` теперь связывает state с `blueprint.life_history.survival.starvation_limit_ticks`:

```text
starvation_ticks <= age_ticks
alive  => starvation_ticks < starvation_limit_ticks
dead   => starvation_ticks == starvation_limit_ticks
```

Новый death reason не вводится. Единственный реализованный A5 death transition остаётся starvation; corpse/decomposition остаётся A6.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_13_starvation_policy.gd
```

Он содержит reject/accept controls, canonical serialize/deserialize, semantic tamper deserialize rejection и dead-inert restart.

## RM-A5-14 — reproduction state bound to inherited policy

Для inherited:

```text
O = offspring_per_event
M = maturity_ticks
I = interval_ticks
C = reproduction_count
E = C / O
```

validator теперь требует:

```text
C % O == 0
propagule_seq == C
```

При `E == 0`:

```text
next_reproduction_tick == M
```

При `E > 0`:

```text
last_reproduction_tick = next_reproduction_tick - I
M <= last_reproduction_tick <= age_ticks
E <= 1 + floor((last_reproduction_tick - M) / I)
E <= max_events(age_ticks, M, I)
```

где `max_events=0` до maturity и `1 + floor((age-M)/I)` после maturity. Это проверяет возможность persisted history, но не требует reproduction на каждом возможном interval: resource-delayed events остаются валидными.

Прежний RM-A5-07 million-offspring witness сохраняется, но его synthetic schedule приведён в физически возможное состояние: при `O=4, M=1, I=1, C=1_000_000` используется `next_reproduction_tick=250001`. После следующего 4-offspring event counters `1_000_004` и schedule остаются валидными.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_14_reproduction_policy.gd
```

Он покрывает count/event misalignment, premature events, zero-event schedule tamper, too-close aggregate history, delayed-valid histories, serialize/deserialize/restart и canonical propagule sequence continuity.

## Fresh acceptance fence

После RM-A5-12..14 требуется новый immutable implementation HEAD/TREE и fresh exact verifier, включающий:

```text
A5 core x2 + byte-identical
A5 reviewer repairs x2 + byte-identical
RM-A5-11 x2 + byte-identical
RM-A5-12 x2 + byte-identical
RM-A5-13 x2 + byte-identical
RM-A5-14 x2 + byte-identical
A4 exact
A0-A3 exact
VIS5.0-VIS5.5
final tracked tree clean
```

Затем нужен новый независимый `@codex review` на PR #573, явно привязанный к этому exact HEAD/TREE. Acceptance ref запрещён до `0 new blocking findings`.
