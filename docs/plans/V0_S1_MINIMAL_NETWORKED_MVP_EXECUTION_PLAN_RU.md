# V0-S1: план сведения минимального сетевого MVP

## Цель

Сформировать одну короткоживущую интеграционную ветку, в которой доказан один
цельный сценарий:

```text
dedicated server
  -> процедурное планетарное тело
  -> каноническая точка спавна
  -> два клиента в одном мире
  -> управление игроком или локальным spectator
  -> сетевой pickup / move / drop предмета
  -> каноническая Construction placement / commit
  -> репликация предмета и постройки второму клиенту
  -> reconnect к тому же живому миру
```

Для минимального среза фиксируется существующая лунная поверхность как первое
процедурное планетарное тело. Это позволяет использовать уже существующие
`lunar_app.gd`, локальный spectator, процедурную поверхность и M7/M4 runtime,
не создавая параллельную Earth-only архитектуру. Перенос той же композиции на
Earth остаётся следующим checkpoint после MVP.

Сетевой baseline фиксируется как существующий `SERVER_PREDICTED`: сервер владеет
каноническими Character, Item Graph и Construction, клиенты отправляют команды и
показывают реплики. `OWNER_AUTHORITATIVE_VALIDATED` из H0.2 не является
предусловием этого MVP и не должен подменять baseline.

## Интеграционная граница

- canonical base: `09714b6f2681e3b5cf3f2f9e28416cf9a7378304`;
- V0 control candidate: `f8184472d5245afd29ef7502d150eaa127944164`;
- рабочая ветка: `feature/v0-s1-networked-planetary-outpost-mvp`;
- worktree: `C:\Godot\mvp-networked-planetary-outpost`.

В MVP целиком не вливаются:

- `feature/h0-2-nx-c1-owner-authority-r3`: exact runtime suite пока падает;
- ECO research line: сильно разошлась с `main` и не нужна вертикальному срезу;
- First Person Embodiment research line: переносится только после MVP точечными
  проверенными коммитами;
- старая `feature/nx-m7-owner-authority-convergence`: отстаёт от `main` и содержит
  локальные untracked UID/asset-файлы.

## Последовательность работ

### M0. Закрыть control-plane блокеры V0

1. Ввести глобальный fail-closed арбитр pre-H0.3 runtime-mutation slot.
2. Разрешать только registry generations 79 и 80; generation 81+ отклонять без
   явного нового правила.
3. Машинно классифицировать V0 Work Order и diff. Изменения protocol, authority,
   ownership epoch, reconciliation или Character ownership должны возвращать
   `V0_S1_BLOCKED_REQUIRES_NX` до runtime mutation.
4. Воспроизвести standard и directional Project Control, затем получить новый
   independent review на exact head.

### M1. Собрать planet runtime без новой истины

1. Поднять один dedicated server и два graphical client процесса.
2. Подключить существующую процедурную лунную сцену к generic multiplayer world
   attachment.
3. Убрать playground-only ограничение только на уровне композиции; не менять
   протокол и модель authority.
4. Привязать канонический spawn к поверхности/координатной системе мира вместо
   hardcoded M3 точек `(-2, 0, 0)` и `(2, 0, 0)`.
5. Сохранить локальный spectator как режим presentation/control без authority над
   Character или миром.

### M2. Довести сетевые предметы

1. Переиспользовать M7/M4 Item Graph command/state path в planetary app.
2. Доказать pickup, перенос и drop через серверную каноническую истину.
3. Доказать, что второй клиент видит те же item id, revision, location и
   transform; client-private Item Graph запрещён.

### M3. Довести сетевую стройку

1. Подключить существующий `ConstructionMultiplayerGateway` к production
   transport как NX-owned foundation closure.
2. Клиент отправляет Construction command; сервер выполняет canonical commit;
   оба клиента получают одну revision/checksum.
3. Запретить V0-owned protocol, Construction service, persistence store и terrain
   truth.

### M4. Один end-to-end acceptance harness

Создать один runner и один сценарный тест:

```text
RUN_V0_S1_NETWORKED_PLANETARY_OUTPOST_TESTS.ps1/.sh
tests/runtime/test_v0_s1_networked_planetary_outpost.gd
```

Сценарий обязан последовательно доказать server boot, planet readiness, spawn,
двух клиентов, двустороннее движение, item pickup/move/drop, Construction
commit/replication, collision convergence, reconnect и 30-минутный soak.

Артефакты сохраняются в
`artifacts/test-results/v0-s1-networked-planetary-outpost-${process_id}/` и
содержат exact Git SHA, Godot identity, world/player/session identity, epochs,
все predicate results, revisions/checksums, логи процессов и exit codes.

## Definition of Done

MVP считается готовым только при одновременном PASS:

- procedural planetary body и canonical spawn point;
- player либо spectator control без второй authority path;
- два клиента видят движение друг друга;
- canonical item pickup/move/drop и репликация второму клиенту;
- canonical Construction placement/commit и репликация второму клиенту;
- reconnect к тому же живому server/world с сохранением Item/Construction state;
- отсутствие duplicate Character/Item/Construction/terrain truth;
- focused runner, full world/core regression и 30-minute soak;
- fresh evidence map, independent Reviewer/Verifier и standard/directional PC.

До выполнения всех пунктов ветка остаётся candidate и не является новой
канонической базой проекта.
