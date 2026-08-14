# V0 CHECKPOINT STABILIZATION PLAN

## Статус

V0 является постоянным integration/composition checkpoint проекта.

Его задача — не создавать новые private truth/authority реализации, а постепенно свести в одну запускаемую точку уже принятые подсистемы и только после этого расширять product surface.

Текущий V0 уже доказал:

- procedural Earth boot;
- dedicated server;
- graphical client join;
- server-authoritative player identity/state;
- canonical M4 Item Graph snapshot;
- Inventory Convergence через M5 bridge/shell;
- canonical MOVE fallback как диагностическое доказательство server movement authority.

При этом текущий runtime ещё не считается стабильным контрольным checkpoint из-за presentation/control debt.

## Правило стабилизации

Перед подключением следующей большой capability V0 должен иметь удобный базовый игровой control loop:

`mouse-look -> camera-relative WASD -> local prediction -> server authority -> reconciliation -> smooth presentation`

и ненавязчивый UI:

`gameplay HUD -> hotbar always visible -> inventory on demand -> debug UI optional/collapsible`.

Никакая V0-полировка не может вводить второй Item Graph, Construction authority, movement authority или отдельный persistence truth.

---

# V0-P0 — CONTROL / PRESENTATION STABILIZATION

## P0.1 Debug HUD hygiene

Цель:

- debug HUD можно свернуть кнопкой;
- F1 полностью скрывает/возвращает HUD;
- HUD не перекрывает основной inventory/workspace;
- скрытый HUD не ловит gameplay input.

## P0.2 Surface-locked camera

Цель:

- network player mouse-look остаётся локальным;
- yaw вращается относительно нормали планеты;
- pitch ограничен диапазоном около +/-89 градусов;
- roll не накапливается;
- горизонт визуально не заваливается при обычном mouse-look;
- H остаётся explicit level-to-horizon recovery action.

## P0.3 Stable gameplay input ownership

Цель:

- inventory open блокирует character movement и отдаёт мышь UI;
- inventory close возвращает mouse capture и gameplay controls;
- spectator и gameplay имеют явно разные input states;
- один owner пишет presentation orientation.

---

# V0-N1 — RESTORE PRODUCTION PREDICTED MOVEMENT

Текущий reliable M3 MOVE path является только временным диагностическим fallback.

Он НЕ является целевым V0 movement loop, потому что при 20 Hz и скорости около 6 m/s создаёт видимые шаги порядка 0.3 m, а reliable command/result traffic создаёт control-channel backlog.

## N1.1 Reproduce actual NX INPUT transport defect

На LOCAL profile доказать отдельно:

- client `PLAYER_INPUT_BATCH` generated;
- INPUT channel frame created;
- ENet channel 1 packet physically sent;
- server ENet receives packet;
- transport boundary accepts packet;
- server `_handle_player_input_batch` invoked;
- FixedTickInputBuffer accepts entry;
- fixed tick applies input.

Добавить counters/logging только на этих boundaries, а не общий verbose log.

## N1.2 Fix transport/boundary defect

Исправлять минимальный установленный слой.

Запрещено подменять проблему новым V0 network protocol.

## N1.3 Restore NX4 client prediction

После фактического прохождения input path вернуть:

- local prediction every render/fixed frame;
- input send 20-30 Hz;
- server fixed tick 60 Hz;
- snapshots 15-30 Hz;
- reconciliation;
- visual smoothing;
- remote interpolation.

## N1.4 Remove reliable MOVE fallback

После NX path PASS удалить fallback из Earth MVP.

Acceptance:

- continuous W hold выглядит плавно;
- camera-relative movement;
- no 0.3-0.5 m stepping;
- no growing pending operation timers;
- no control-channel movement flood;
- two clients converge;
- reconnect remains valid.

---

# V0-I1P — INVENTORY PRODUCT PRESENTATION

После P0/N1, не меняя M5 backend:

- убрать `M5 GRAPHICAL ACCEPTANCE` chrome;
- вернуть production inventory visual hierarchy;
- player inventory primary;
- external container only when actually opened;
- mounts/context panes secondary/collapsible;
- hotbar persistent;
- Tab opens/closes inventory;
- debug HUD не перекрывает inventory;
- сохранить seven_days_like interaction profile.

Backend остаётся:

`Inventory UI -> M5InventoryUiBridge -> M3 runtime -> canonical server M4 Item Graph`.

---

# ДАЛЬШЕ ПО GLOBAL V0 CHECKPOINT

После stabilization lane:

1. V0-I2 — world item / raycast / E / external containers;
2. V0-C1 — canonical Construction placement/commit;
3. V0-C2 — replicated C22/C24 mesh/collision;
4. V0-C3 — Construction resource consumption через canonical Item Graph;
5. V0-R1 — reconnect same live world;
6. V0-A1 — end-to-end acceptance + 30 minute soak;
7. GLOBAL V0 PRODUCT BASELINE.

## Promotion rule

GLOBAL V0 PRODUCT BASELINE разрешён только когда один обычный пользовательский запуск позволяет без debug/manual repair:

- подключиться к dedicated server;
- нормально осматриваться мышью без roll drift;
- плавно перемещаться camera-relative WASD;
- видеть второго игрока;
- пользоваться hotbar/inventory;
- взаимодействовать с world items/containers;
- строить canonical outpost;
- видеть ту же постройку вторым клиентом;
- reconnect в тот же live world;
- пройти bounded soak без queue/timer growth.
