# V0 PLAYABLE SEAMLESS PLANET — progress snapshot R1

**Дата фиксации:** 2026-08-28  
**Назначение:** immutable human-readable baseline для сравнения прогресса следующих сессий.  
**Canonical main на момент фиксации:** `e14f8b6e5b07709d18273cc7886fe660bc353ebf`.

> Этот документ фиксирует наблюдаемое состояние веток и принятых checkpoint'ов. Он не заменяет machine truth в `config/control/**`, не принимает SM1 и не меняет runtime authority.

## 1. Большая продуктовая цель

Следующий большой продуктовый рубеж:

**V0 PLAYABLE SEAMLESS PLANET**

Минимальная пользовательская вертикаль:

```text
dedicated server
+ 2 graphical clients
+ persistent shared world
+ seamless Authority A <-> B crossing
+ bounded planetary surface
+ inventory / containers
+ equipment / tools
+ resource mining
+ real-resource Construction
+ authoritative terrain digging/material mutation
+ reconnect
+ server restart recovery
```

Человек должен иметь возможность зайти двумя клиентами, добывать ресурс, копать поверхность, строить, пересекать authority boundary без respawn/reconnect/loading, выйти/зайти снова и после server restart увидеть то же canonical состояние.

## 2. Принятый продуктовый фундамент

На момент снапшота machine product policy фиксирует:

- **P4 Real Resource Construction — ACCEPTED**
  - accepted runtime: `2a6721cdf02fa1134c59d1ab98bb7b597c66821d`
  - уже доказана canonical resource mining -> Item Graph -> resource-backed Construction вертикаль.
- **P5 Equipment / Tools — ACCEPTED**
  - accepted runtime: `491ca7d058690d3de5fcea5e41aaee230a31b3ab`
  - server-authoritative equipment/tools встроены в playable loop.
- **P6 Persistent Shared Outpost — ACCEPTED**
  - accepted runtime: `7a77c048caa680871d4895c09eca89e84136b154`
  - persistent two-client outpost, reconnect, restart reconstruction, repeated E2E и soak.
- **Edge Gateway Foundation — ACCEPTED**
  - consumed by P6 and SM1.

Практический вывод: mining и Construction не являются будущими системами для большого рубежа — они уже продуктовый фундамент. Главный недостающий gameplay capability после seamless closure — **P7 terrain/material mutation**.

## 3. Seamless SM1 — текущее наблюдаемое состояние

Canonical production branch:

`feature/v0-sm1-seamless-product-integration`

Наблюдаемый validated head:

`716ed913f9835593a31d142a556d78833c7088b1`

PR #242 остаётся Draft и SM1 **ещё не принят / не merged**, но runtime implementation дошёл до:

- SM1.1 owner-port map;
- SM1.2 one-writer transfer;
- SM1.3 Player Carrying Domain continuity;
- SM1.4 Gateway-preserving route pivot;
- SM1.5 canonical world-state continuity;
- SM1.6 five-process graphical A<->B;
- SM1.7.1-7.6 fault/replay/stale-source cases;
- SM1.7.7 concurrent crossings;
- SM1.7.8 reconnect after handoff;
- SM1.7.9 Gateway process restart;
- SM1.7.10 Authority recovery;
- SM1.7.11 canonical Item / Construction / outpost mutations around handoff.

Exact-head evidence на `716ed913...`:

```text
SM1 L0                  339/339 PASS
SM1.6 graphical          58/58 PASS
SM1.7.1-7.6             157/157 PASS
SM1.7.7                  79/79 PASS
SM1.7.8                  71/71 PASS
SM1.7.9                  81/81 PASS
SM1.7.10                 89/89 PASS
SM1.7.11        145 x 10 = 1450 PASS
Project Control                    SUCCESS
```

Особенно важно: 7.11 уже проверяет реальные canonical Item Graph / Construction / outpost mutations до, во время и после A<->B handoff, включая fail-closed transfer gap.

Следующий runtime slice: **SM1.7.12 repeated crossings under impaired network**. Staging для exact publication уже существует.

## 4. Что реально осталось до большого рубежа

Критический путь должен быть коротким:

```text
SM1.7.12 impaired-network repeated crossings
        ↓
SM1 full world/core regression
        ↓
post-build critique + Evidence Map
        ↓
fresh Reviewer + fresh Verifier
        ↓
SM1 checkpoint proposal / human merge gate
        ↓
SM1 ACCEPTED
        ↓
P7 BOUNDED TERRAIN MUTATION
        ↓
dig/remove terrain material
        ↓
material -> canonical Item Graph
        ↓
terrain replication + persistence
        ↓
reconnect / server restart reconstruction
        ↓
terrain mutation near / across A<->B seam
        ↓
two-client graphical E2E acceptance
        ↓
V0 PLAYABLE SEAMLESS PLANET
```

## 5. Прогресс по capability

Оценка нужна как navigation metric, а не как acceptance truth:

| Capability | Оценка |
|---|---:|
| Dedicated server / clients | 100% |
| Server-authoritative Item Graph / inventory | 100% |
| Resource mining | 100% |
| Equipment/tools | 100% |
| Resource-backed Construction | 100% |
| Persistence / reconnect / restart | 100% |
| Edge Gateway foundation | 100% |
| Seamless static A<->B product integration | ~90% |
| Bounded playable planetary surface | ~70% |
| Terrain digging / material mutation | ~20% |
| Final cross-system integration | ~50% |

**Итоговая навигационная оценка до V0 PLAYABLE SEAMLESS PLANET: ~80%.**

По оставшемуся engineering risk: примерно **65-75% пути пройдено**, потому что P7 terrain persistence/authority boundary ещё способен вскрыть интеграционные дефекты.

## 6. Временная оценка на этой точке

При сохранении текущего темпа и без расширения scope:

- optimistic: **7-10 активных рабочих дней**;
- realistic: **2-3 недели активной разработки**;
- adverse P7 architecture case: **3-5 недель**.

Это оценка, не обязательство и не machine checkpoint.

## 7. Что сознательно НЕ блокирует рубеж

До V0 PLAYABLE SEAMLESS PLANET не должны становиться обязательными:

- завершение всей ECO;
- P8 mobile construct / ship;
- arbitrary-N authority balancing;
- dynamic shard split/merge;
- новый transport foundation;
- новый Gateway;
- глобальный planet HLOD/MRPF completion;
- полноценная глобальная симуляция всей планеты.

ECO продолжает идти параллельно и остаётся non-blocking, пока main явно не зарегистрирует dependency.

## 8. Следующая точка сравнения

При следующем progress review сравнивать минимум:

1. принят ли SM1;
2. какой exact accepted SM1 head;
3. активирован ли P7;
4. реализована ли authoritative terrain mutation;
5. есть ли material -> Item Graph loop;
6. переживает ли terrain reconnect/restart;
7. проходит ли terrain mutation через seamless boundary;
8. пройден ли двухклиентский graphical V0 PLAYABLE SEAMLESS PLANET acceptance.
