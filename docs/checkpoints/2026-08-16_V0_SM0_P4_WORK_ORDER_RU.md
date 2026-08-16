# V0-SM0 P4 — bounded implementation work order

**Дата:** 2026-08-16  
**Статус:** AUTHORIZED FOR BOUNDED IMPLEMENTATION / NOT ACCEPTED  
**Ветка:** `feature/sm0-two-authority-seamless-handoff-lab`  
**PR:** `#102 — SM0: two-authority seamless handoff lab`  
**Exact parent HEAD:** `91d057c8ba42669f0bd09f04b4a9c73e6e9d209f`  
**Risk:** `CRITICAL — cross-server authority transition`

## 1. Human gate

В интерактивной сессии 2026-08-16 пользователь после фиксации `V0_SM0_EXPERIMENTAL_MULTISERVER_ROADMAP_RU.md` явно дал команду: **«реализуй следующий пункт разработки»**.

В experimental roadmap ближайший пункт помечен как `P4 — Prewarmed Fast Handoff [CURRENT]`. Эта команда является human authorization на **ограниченную реализацию P4**. Она не является acceptance, merge approval или разрешением расширять scope на следующие P5+.

## 2. Разрешённый scope

P4 может изменить только bounded SM0 experimental path:

- metadata-only target prewarm reservation до crossing;
- checksum/fence/TTL contract для reservation;
- source-side prewarm lifecycle;
- fast final commit при наличии валидной prewarm reservation;
- target-side validation/import только после реального crossing;
- сохранение существующего `PREPARE -> PREPARED -> COMMIT` как legacy fallback;
- focused tests и evidence plumbing для нового protocol path.

## 3. Явно вне scope

В этот work order не входят:

- NX4/NX5 movement prediction/interpolation convergence;
- исправление stop-and-wait MOVE режима;
- cross-authority player/item projections;
- третий authority server;
- nested authority zones;
- production World Directory/NATS/JetStream;
- generic object handoff;
- изменение single-server V0 path.

## 4. Неприкосновенные инварианты

P4 обязан сохранить:

```text
exactly one canonical writer
stable logical_player_id
stable player_entity_id
monotonic authority_epoch
monotonic directory revision
source owns/writes until real crossing
prewarm does not import canonical player state
prewarm does not call authority.join()
prewarm does not mutate directory ownership
source writer retires before target writer becomes active
ACTIVATE cannot be ACKed before final target commit
legacy fallback remains usable when prewarm is missing/stale/rejected
replay/conflict paths fail closed
```

## 5. TTL correction относительно design brief

`Time.get_ticks_msec()` является process-local monotonic clock. Поэтому absolute `expires_at_msec`, переданный между отдельными Godot processes, не является безопасным межпроцессным временем.

P4 runtime contract должен транспортировать bounded `ttl_ms`. Source и target вычисляют свои локальные expiration deadlines из собственного monotonic clock. Это не создаёт требования синхронизировать monotonic epochs процессов.

## 6. Acceptance boundary

Implementation commit сам по себе **не принимает P4**.

После реализации обязательны:

1. focused protocol/contract regression;
2. exact-head Windows multi-process run;
3. fast-path evidence, что prewarm действительно использован;
4. legacy fallback evidence;
5. controlled WAN comparison минимум на существующих WAN-10/20/30/45 profiles;
6. проверка single-writer/identity/epoch invariants;
7. независимый review CRITICAL candidate.

До этих доказательств статус P4: `IMPLEMENTED CANDIDATE / NOT ACCEPTED`.
