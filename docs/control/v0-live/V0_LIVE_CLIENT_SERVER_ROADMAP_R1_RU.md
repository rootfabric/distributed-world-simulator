# V0-LIVE — Client/Server Product Roadmap R1

## Статус

- Основание: V0 = COMPLETE_MERGED.
- Post-V0 main: eadb2b99320439a608cd6fdc3561993513baf0c0.
- Product entry point: main.tscn -> scripts/app/v0_simulator_app.gd.
- Существующий product mode: --network-mvp.

V0-LIVE — следующий product train поверх закрытого V0. Его задача — превратить доказанную тестами distributed composition в реально используемый client/server simulator.

Это не новый canonical owner и не замена HS/FABRIC/ECO. Это product/usability слой, который обязан потреблять существующие canonical owners.

## Главная цель

Получить рабочий вариант:

    start server
      -> client A joins
      -> client B joins
      -> both see the same world and each other
      -> normal movement and camera
      -> seam traversal
      -> canonical mining
      -> canonical material/item
      -> inventory / pickup / drop / shared container
      -> canonical Construction
      -> reconnect one client
      -> planned server/world restart
      -> continue in the same canonical state

Ключевой критерий: основной сценарий выполняется человеком без Python acceptance driver и без прямого вызова внутренних runtime API.

Developer console остаётся диагностическим инструментом, но не считается основным gameplay UI.

---

## LIVE.1 — Human Playable Client/Server Smoke

Цель: доказать текущий product entry point живой ручной сессией.

Запуск:
- один dedicated server;
- два независимых graphical game clients;
- разные logical player identities;
- один earth world;
- --network-mvp;
- без automated acceptance phase.

Ручная проверка:
1. server запускается и остаётся жив;
2. A подключается;
3. B подключается;
4. оба видят мир;
5. оба видят друг друга;
6. WASD/камера работают;
7. движение другого игрока обновляется;
8. A проходит seam и возвращается;
9. connection/session identity сохраняется;
10. меню, inventory и interact доступны;
11. фиксируются gameplay возможности, которые существуют только через debug/API;
12. фиксируются UX blockers и проблемы ощущения управления.

Результат LIVE.1 — Human Smoke Report:
- WORKS;
- PARTIAL;
- NOT USER-EXPOSED;
- BUGS;
- UX BLOCKERS;
- PERFORMANCE / FEEL;
- NEXT REPAIRS.

LIVE.1 может завершиться с найденными usability gaps. Его задача — получить честную картину живого продукта.

---

## LIVE.2 — Playable Gameplay Bridge

Цель: сделать обязательные V0 gameplay capabilities доступными через обычный пользовательский input.

Схема:

    Human input
      -> Playable Client Gameplay Facade
      -> existing graphical/network runtime
      -> Gateway / canonical service
      -> canonical owner
      -> replicated result
      -> HUD / world presentation

Запрещено создавать:
- второй Item Graph;
- второй Construction owner/store;
- private client truth;
- отдельную demo economy;
- локальный client-only terrain mutation.

Минимальные действия R1:
- WASD / Shift — movement;
- Mouse — camera;
- E — interact / pickup / container action;
- LMB с mining tool — canonical mine/dig;
- Tab — inventory;
- 1–0 — hotbar;
- G — drop;
- B — build mode;
- R — rotate build ghost;
- LMB в build mode — submit canonical Construction command.

LIVE.2 Definition of Done:
- выбрать/использовать mining tool;
- выполнить canonical resource action;
- увидеть результат у обоих клиентов;
- получить canonical item;
- pickup/drop;
- shared container put/take;
- carry item across seam;
- создать Construction из canonical resources;
- второй клиент видит тот же Construction и collision.

---

## LIVE.3 — Recovery as Product Behavior

Цель: reconnect/restart перестают быть только integration test и становятся обычным поведением приложения.

Нужно:
- пользователь закрывает client A;
- запускает его снова с той же logical identity;
- client получает CURRENT canonical state;
- server/world штатно останавливается;
- server/world повторно запускается;
- два клиента продолжают работу с восстановленными terrain, player identity, inventory/equipment, world items, container, Construction и dedup/replay state.

R1 не требует arbitrary mid-write power-loss. Достаточен planned/quiescent restart.

---

## UX0 — Product Shell

Цель: убрать необходимость ручного ввода runtime CLI для обычного пользователя.

Первый экран:

    [ Continue ]
    [ Host World ]
    [ Join World ]
    [ Settings ]
    [ Developer ]

Host World:
- World;
- Player name;
- Port;
- persistence slot.

Join World:
- Server address;
- Port;
- Player name.

Минимальный HUD:
- connection status;
- logical player;
- selected tool;
- interaction hint;
- inventory summary;
- selected hotbar item;
- build mode state;
- short reconnect/network state.

F1/Developer остаётся для диагностики.

---

## USER1 — First Usable Vertical Slice

Цель: новый человек без внутренних знаний проходит 10–20 минут gameplay.

    Host world
      -> second client Join
      -> see each other
      -> move
      -> seam traversal
      -> find resource
      -> equip mining tool
      -> mine
      -> receive material
      -> pickup/drop/share
      -> shared container
      -> carry item across seam
      -> build one object
      -> both see/collide with it
      -> reconnect one client
      -> continue
      -> restart server/world
      -> continue

Критерий: для основного сценария не нужен developer console и не нужен test driver.

---

## DEMO1 — Packaged Client/Server Build

Цель: запуск вне dev environment.

Минимум:
- packaged Windows server;
- packaged Windows client;
- reproducible config;
- logs/diagnostics folder;
- version/build identity visible in UI;
- launch scripts/shortcuts;
- clean persistence directory;
- bounded recovery behavior;
- short operator README.

Позже:
- Linux dedicated server;
- LAN discovery;
- updater;
- launcher;
- account/auth layer;
- public Internet networking.

---

## Параллельная архитектурная ветка

После LIVE.1 можно параллельно начинать HS1:

                     V0 COMPLETE
                          |
                          v
                  LIVE.1 Human Smoke
                          |
             +------------+------------+
             |                         |
             v                         v
        PRODUCT TRACK             ARCH TRACK
          LIVE.2                     HS1
            |                         |
           UX0                       HS2
            |                         |
          USER1                      HS3
             \                       /
              +----------+-----------+
                         v
                usable distributed world

HS не должен снова оторвать архитектуру от живого product loop.

## Product principles

1. Один canonical truth path.
2. Manual usability является gate, а не необязательной демонстрацией.
3. Каждая новая architecture capability должна быть потребляема product entry point.
4. Developer console не считается gameplay UI.
5. Тесты остаются обязательными, но не заменяют human smoke.
6. Сначала local/LAN usable version, затем Internet/service complexity.
7. Никакого второго demo runtime ради красивого vertical slice.

## Ближайший порядок работы

    NOW
      -> LIVE.1 Human Playable Smoke
      -> зафиксировать реальные gaps
      -> LIVE.2 Playable Gameplay Bridge
      -> повторить Human Smoke
      -> LIVE.3 Recovery
      -> UX0 Launcher/HUD
      -> USER1 Vertical Slice
      -> DEMO1 packaged build

Первый текущий gate: V0-LIVE.1 HUMAN PLAYABLE CLIENT/SERVER SMOKE.
