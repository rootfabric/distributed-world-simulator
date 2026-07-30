# H2 — host/client join-leave и replicated player ownership

Checkpoint: `v16.9.2-runtime-h2-host-client-ownership`  
Base: `v16.9.1-runtime-h1-playable-listen-host`

## Цель

H2 добавляет первый реальный отдельный ENet client к authoritative host и фиксирует ownership игрока независимо от transport connection. Transport session может завершиться и быть создана заново, но `player_entity_id` остаётся стабильным.

## Модель

`PlayerOwnershipRegistry` хранит logical player identity, стабильный player entity ID, текущую transport session, ownership epoch и connected state. Join/leave являются replay-safe операциями. Повторное подключение использует ту же сущность игрока и увеличивает ownership epoch.

Клиент получает JSON-safe ownership snapshot через T1 transport и применяет его только в `PlayerOwnershipReplicaStore`. Replica store запрещает revision rollback, same-revision mutation и смену authority owner/epoch.

## Инварианты

- host и client имеют разные logical player identities;
- один logical player одновременно принадлежит не более чем одной transport session;
- stale или spoofed session не может выполнить leave;
- повтор операции с другим payload отклоняется;
- reconnect не создаёт вторую player entity;
- ownership epoch монотонно растёт при новом присоединении;
- client не получает ссылок на authority objects;
- уход remote client не отключает host listener и host player.

## Проверяемый процесс

1. Headless host создаёт local host player.
2. Отдельный ENet client присоединяется как `remote`.
3. Host реплицирует ownership snapshot.
4. Client выполняет leave.
5. Client открывает новую transport session и повторно присоединяется.
6. Host возвращает тот же `player/remote` с ownership epoch `2`.
7. После завершения client host player остаётся подключённым.

## Scope boundary

H2 не реализует одновременную игру двух remote graphical clients, contention за item и remote-player interpolation — это H3. Gameplay state H1 не дублируется: ownership registry является отдельным session/identity boundary, который далее подключается к общей H1 client composition.
