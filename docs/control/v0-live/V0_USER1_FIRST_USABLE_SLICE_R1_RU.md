# V0-USER1 R1 — First Usable Vertical Slice

## Статус

IMPLEMENTATION CANDIDATE.

Base main:

`f531499fb5efb17fd2ff8087bd5c3a65d8be3fa0`

Branch:

`feature/v0-user1-first-usable-slice-r1`

## Цель

Новый пользователь без знания внутренних runtime-команд должен пройти основной
10–20-минутный product loop:

```text
Host World
  → second client Join
  → see each other
  → move
  → seam traversal
  → find resource
  → equip mining tool
  → mine
  → receive canonical ore
  → pickup + drop
  → open shared container
  → transfer item into shared container
  → build canonical object
  → restart one client with same identity
  → continue
  → restart server/world with same persistence slot
  → continue
```

Developer console и test driver не являются частью пользовательского маршрута.

## USER1 Journey

Earth product client получает новый read-only onboarding overlay:

`USER1 · FIRST USABLE SESSION`

Он не выполняет действия за пользователя и не владеет gameplay state.

Overlay наблюдает только уже реплицированные данные:

- connection state;
- logical player / ownership epoch;
- canonical player position;
- gameplay region;
- remote player presentations;
- ResourceMining generation;
- расстояние до ближайшего canonical resource;
- canonical Item Graph;
- ore в player inventory;
- WORLD item count;
- authoritative open-container relation;
- shared crate slots;
- Construction server generation.

Прогресс UI сохраняется локально под:

`user://v0-live/user1/<player-hash>.json`

Это только onboarding state. Он не содержит canonical world state и не участвует в
recovery.

## Fail-closed baseline

Journey не начинает засчитывать gameplay steps, пока одновременно не доступны:

- CONNECTED;
- player identity / ownership epoch;
- gameplay region;
- Item Graph revision;
- ResourceMining generation;
- WORLD item projection;
- shared-container projection;
- Construction generation.

Таким образом поздний initial sync не может превратить `-1 → 0` в ложный mining/build
success.

## Client restart / server restart

Для шага client reconnect onboarding сохраняет первый process id локально. Новый
process с тем же logical player после уже выполненной Construction части засчитывает
client restart только после CONNECTED.

После этого server restart засчитывается только если тот же client реально наблюдал:

`CONNECTED → RECONNECTING/CONNECTING/DISCONNECTED → CONNECTED`.

Новый reconnect mechanism не создаётся; используется LIVE.3.

## UX0 polish, включённый в USER1

### Continue player identity

Product Shell теперь хранит отдельно:

- `default_player_name` — последнее локальное имя для новых Host/Join форм;
- `last_host_player_name` — identity последней hosted session.

Join больше не меняет identity, которую Continue использует для восстановления
последнего hosted world.

### Dual-stack port preflight

Host проверяет wildcard UDP ownership. На Windows проверяются:

- `0.0.0.0:<port>`;
- `[::]:<port>`.

Это закрывает observed случай, когда ENet server владел `[::]:24580`, а probe только
на `127.0.0.1` ошибочно считал порт свободным.

После spawn shell также проверяет, что dedicated server process пережил startup window,
до запуска client.

Runtime bind остаётся финальной authority.

## Canonical ownership

USER1 не создаёт:

- новый Item Graph;
- новый shared container;
- новый ResourceMining owner;
- новый Construction owner;
- новый network transport;
- новый reconnect path;
- новый persistence store.

Маршрут только делает существующие LIVE.2/LIVE.3 возможности понятными и наблюдаемыми.

## Machine gate

R1 machine gate обязан доказать:

- bounded source diff;
- cold Godot import;
- USER1 journey deterministic tests;
- UX0 Product Shell regression;
- LaunchOptions regression;
- LIVE.2 gameplay/reliability regression;
- P4 reconnect regression;
- LIVE.3 planned-restart product process regression;
- no tracked source modifications / Godot leaks.

Machine gate не заменяет финальный human USER1 smoke.

## Human gate

Перед merge новый человек/свежий verifier должен пройти маршрут через обычные UI/input
поверх Product Shell.

Особенно falsify:

1. seam step реально достижим из обычного Earth product;
2. shared crate transfer выполняется мышью через inventory UI;
3. Construction виден второму клиенту;
4. client restart продолжает journey;
5. planned server restart возвращает тот же world state;
6. ни на одном шаге не требуется F1/developer console.

Если любой из этих пунктов требует внутреннюю команду, USER1 ещё не завершён.
