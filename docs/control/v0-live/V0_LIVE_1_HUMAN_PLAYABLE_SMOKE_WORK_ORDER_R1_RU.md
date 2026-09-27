# V0-LIVE.1 — Human Playable Client/Server Smoke — Work Order R1

## Mission

Получить и руками проверить первый реально работающий client/server вариант текущего main без test driver.

Baseline:
- main: eadb2b99320439a608cd6fdc3561993513baf0c0;
- mode: --network-mvp;
- world: earth;
- roles: one dedicated-server + two graphical game-client processes;
- logical players: a and b.

## Boundaries

На первом проходе код продукта не чинить во время самой smoke-сессии. Сначала собрать честный gap report.

Не засчитываются:
- automated acceptance driver;
- headless-only evidence;
- Python test acting вместо человека;
- прямое изменение canonical state из debug fixture;
- отдельный demo owner.

## Launch target

Процессы:
1. dedicated server;
2. graphical client A;
3. graphical client B.

Все три должны работать на одном exact product HEAD.

## Human smoke sequence

### Phase A — startup and presence
1. Запустить server.
2. Запустить A.
3. Запустить B.
4. Подтвердить, что оба клиента загрузили один world.
5. Подтвердить, что A и B имеют разные logical identities.
6. Подтвердить, что каждый видит второго игрока.

### Phase B — movement and seam
1. Двигать A обычным WASD.
2. Двигать B обычным WASD.
3. Проверить camera feel.
4. Провести A через authority seam.
5. Вернуть A обратно.
6. Проверить отсутствие видимого respawn/teleport/disconnect.
7. Проверить, что B всё время наблюдает A.

### Phase C — discover actual playable surface
Попробовать обычными input/UI:
- inventory;
- hotbar;
- interact;
- pickup/drop;
- mining/dig;
- resource/material output;
- shared container;
- build/construction.

Для каждой возможности записать один статус:
- WORKS — человек выполняет её через обычный UI/input;
- PARTIAL — путь существует, но неполный/непонятный;
- API_ONLY — runtime capability есть, но пользовательского input path нет;
- BROKEN — пользовательский path есть, но не работает;
- NOT_PRESENT — capability не представлена в текущем product mode.

### Phase D — reconnect
1. Закрыть client A штатно.
2. Не останавливать server и B.
3. Запустить A снова с той же logical identity.
4. Проверить соединение, позицию/состояние и видимость второго игрока.

### Phase E — session feel
После reconnect ещё 5–10 минут походить двумя клиентами и отметить:
- input latency;
- jitter;
- camera issues;
- UI blockers;
- непонятные состояния;
- ошибки/варнинги;
- необходимость developer console для gameplay.

## Required evidence

Сохранить:
- exact HEAD/TREE;
- Godot version/SHA;
- команды запуска трёх процессов;
- server log;
- client A log;
- client B log;
- минимум по одному screenshot каждого клиента;
- короткий Human Smoke Report.

Не требуется превращать ручную сессию в новый regression suite.

## Human Smoke Report template

    V0-LIVE.1 HUMAN PLAYABLE SMOKE

    SUBJECT_HEAD =
    SUBJECT_TREE =
    HOST =
    GODOT =

    SERVER_START = PASS/FAIL
    CLIENT_A_JOIN = PASS/FAIL
    CLIENT_B_JOIN = PASS/FAIL
    TWO_PLAYERS_VISIBLE = PASS/FAIL
    HUMAN_MOVEMENT_A = PASS/FAIL
    HUMAN_MOVEMENT_B = PASS/FAIL
    SEAM_ROUNDTRIP = PASS/FAIL
    VISIBLE_RESPAWN_OR_RECONNECT = YES/NO

    INVENTORY = WORKS/PARTIAL/API_ONLY/BROKEN/NOT_PRESENT
    INTERACT = ...
    PICKUP_DROP = ...
    MINING = ...
    MATERIAL_OUTPUT = ...
    SHARED_CONTAINER = ...
    CONSTRUCTION = ...

    CLIENT_RECONNECT = PASS/FAIL

    UX_BLOCKERS =
    GAMEPLAY_BLOCKERS =
    PERFORMANCE_NOTES =
    LOG_ERRORS =

    RECOMMENDED_LIVE2_REPAIRS =

## LIVE.1 exit

LIVE.1 считается завершённым, когда:
- ручная сессия реально проведена;
- сервер + два GUI-клиента доказаны человеком;
- movement/seam проверены руками;
- полный список user-exposed/API-only gaps зафиксирован;
- сформирован bounded список LIVE.2 repairs.

LIVE.1 не требует, чтобы mining/Construction уже были удобны. Если они API_ONLY, это валидный результат и прямой вход в LIVE.2.

## Следующий gate

V0-LIVE.2 PLAYABLE GAMEPLAY BRIDGE.
