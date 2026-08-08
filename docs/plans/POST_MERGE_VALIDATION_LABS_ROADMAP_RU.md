# Post-Merge Validation Labs Roadmap — обязательная проверка объединённого runtime перед бесшовностью

**Статус:** PLANNED / AUTHORITATIVE TRAJECTORY INSERT  
**Назначение:** обязательный промежуточный цикл после завершения текущего сетевого базового минимума и перед дальнейшими этапами бесшовности, server-to-server handoff и крупными gameplay vertical slices.  
**Репозиторий:** `rootfabric/distributed-world-simulator`  
**Главный принцип:** сначала доказать руками и измерениями, что уже замерженные Network + Items + Construction + Matter/Representation действительно работают вместе; только потом наращивать бесшовный мир.

---

## 1. Почему этот цикл обязателен

После большого merge проект содержит несколько развитых доменов, каждый из которых имеет собственные focused и regression tests:

- realtime networking и prediction/interpolation;
- authoritative Item Graph, inventory и containers;
- Construction и C24 proxy/ArrayMesh presentation;
- Mutable Matter, regional state и cross-region transactions;
- RL coarse-to-fine representation и network streaming;
- persistence/recovery.

Прохождение доменных тестов ещё не доказывает, что из этих систем можно собрать устойчивую игровую сцену. Перед следующей большой архитектурной фазой нужен набор небольших диагностических сцен, где сложность увеличивается по одному измерению.

Этот цикл не является новой gameplay-веткой. Это **validation bridge** между уже замерженной архитектурой и дальнейшей бесшовностью.

Основной вопрос цикла:

> Можем ли мы запустить существующие подсистемы вместе, увидеть их реальное поведение в Godot, измерить масштабирование, найти недочёты и получить понятный production path для следующих этапов?

---

## 2. Точка входа

Roadmap активируется только после завершения текущей сетевой задачи базового минимума.

Входной gate должен подтвердить как минимум:

```text
1 dedicated server
2 graphical clients
local movement prediction works
remote interpolation works
inventory/container interaction works
pickup/drop works
predicted item interactions converge
reconnect works
no item duplication
clean unload/shutdown
```

До прохождения этого gate новые validation-lab ветки могут готовить документацию и fixtures, но не должны подменять или обходить текущую сетевую работу.

После принятия сетевого минимума создаётся frozen post-network baseline SHA. Все параллельные лабораторные ветки стартуют именно от него.

Рекомендуемое имя защитной точки:

```text
checkpoint/post-network-minimum-accepted
```

Фактический checkpoint/tag фиксируется по принятому SHA на момент старта цикла.

---

## 3. Общая траектория

```text
CURRENT NETWORK MINIMUM
          |
          v
T0  Item / Playground Acceptance
          |
          +-------------------------------+
          |                               |
          v                               v
T1  Construction Lab                T3  Matter Excavation Lab
          |                               |
          v                               v
T2  Construction Scale Lab          T4  Matter Streaming Lab
          |                               |
          +---------------+---------------+
                          |
                          v
T5  Matter + Construction Composition Lab
                          |
                          v
T6  Recovery / Reconnect Composition Lab
                          |
                          v
T7  Asteroid Surface Lab
                          |
                          v
VALIDATION LABS ACCEPTED
                          |
                          v
NEXT: SEAMLESSNESS / HANDOFF / LARGE-WORLD STAGES
```

T1/T2 и T3/T4 специально разнесены на параллельные tracks. Они не должны ждать друг друга, пока не потребуется T5.

---

# 4. Веточная модель

## 4.1 Frozen baseline

После принятия текущего network minimum:

```text
main / accepted integration head
        |
        +--> checkpoint/post-network-minimum-accepted
```

Все lab-ветки создаются от одного SHA. Нельзя тихо переносить одну ветку на более новый main и продолжать сравнивать результаты как будто база одна и та же.

---

## 4.2 Параллельные tracks

### Track A — Items / Playground

```text
lab/t0-item-playground-acceptance
```

Если текущая сетевая задача уже полностью закрывает T0, отдельная ветка не нужна: accepted network checkpoint становится входным T0.

### Track B — Construction

```text
lab/t1-construction-functional
        |
        v
lab/t2-construction-scale
```

T1 и T2 последовательны внутри Construction track, но весь track может выполняться параллельно Matter track.

### Track C — Matter / Excavation

```text
lab/t3-matter-excavation
        |
        v
lab/t4-matter-streaming-scale
```

T3 и T4 последовательны внутри Matter track.

### Integration track

После принятия T2 и T4:

```text
integration/t5-matter-construction-composition
        |
        v
integration/t6-composition-recovery
        |
        v
integration/t7-asteroid-surface-lab
```

T5–T7 уже не вести параллельно между собой: каждый следующий этап зависит от результата предыдущего.

---

## 4.3 Merge policy

Лабораторные ветки не должны по очереди вливать экспериментальные fixes непосредственно в `main` без общей проверки.

Рекомендуемая схема:

```text
frozen baseline
  |-- Construction track
  |-- Matter track
  |-- optional T0 fixes
          |
          v
integration/post-merge-validation-labs
          |
          v
T5/T6/T7 combined gates
          |
          v
independent acceptance
          |
          v
main
```

Если lab находит production defect:

1. defect фиксируется минимальным production patch;
2. добавляется focused regression test;
3. fix переносится во все активные lab branches, которые зависят от него;
4. frozen baseline revision для результатов явно отмечается;
5. старые результаты, выполненные до production fix, не выдаются за результаты новой композиции.

---

# 5. T0 — Item / Playground Acceptance

## Назначение

Закрыть самый простой игровой runtime до проверки тяжёлых представлений.

Сцена должна содержать только:

```text
player
remote player
inventory
hotbar
world items
external containers
basic item placement
network runtime
```

Construction-scale и Matter здесь не нужны.

## Ручной сценарий

Проверить двумя graphical clients:

- локальное движение;
- remote movement;
- pickup/drop;
- перенос item между backpack и external container;
- stack/split/swap;
- right-click semantics текущего inventory profile;
- quick transfer;
- два игрока одновременно работают с одним контейнером;
- contention за один world item;
- disconnect/reconnect;
- clean scene unload.

## Gate

```text
0 duplicate item identities
0 ghost items
0 permanently unresolved predictions
0 second player identity after reconnect
canonical Item Graph == observed final state
```

T0 является базовым минимумом всех следующих graphical labs.

---

# 6. T1 — Construction Functional Lab

## Ветка

```text
lab/t1-construction-functional
```

## Цель

Проверить Construction руками в максимально простой среде без Matter и без добычи ресурсов.

## Сцена

Рекомендуемое имя:

```text
scenes/testing/construction_lab.tscn
```

Состав:

```text
flat test ground
player
inventory with pre-created construction items/build permissions
construction runtime
construction debug overlay
```

Ресурсы выдаются тестовым fixture. Crafting на этом этапе запрещён как лишняя переменная.

## Проверки

Построить вручную:

```text
foundation
floor
walls
beams
second level
rooms
corridor
multiple disconnected constructs
```

Проверить:

- placement;
- snapping;
- remove;
- replace;
- edit inside existing construct;
- independent constructs;
- construction identity;
- authoritative state vs visible state;
- reload/re-enter scene where applicable.

## Инварианты

```text
Construction truth -> presentation
```

Не допускаются:

- visible part without canonical construction state;
- canonical part permanently missing from presentation;
- duplicate part identity;
- stale proxy after authoritative edit;
- presentation artifact becoming canonical truth.

## Gate

T1 PASS означает: небольшую/среднюю сложную постройку можно реально собрать и редактировать руками, а не только создать через unit fixture.

---

# 7. T2 — Construction Scale Lab

## Ветка

```text
lab/t2-construction-scale
```

Основание: accepted T1.

## Цель

Проверить уже замерженные C22/C24 representation и scale свойства на реальных сценах.

## Сцена

```text
scenes/testing/construction_scale_lab.tscn
```

## Детерминированные fixtures

```text
C-SMALL   ~100 parts
C-MEDIUM  ~1,000 parts
C-LARGE   ~10,000 parts
C-XL      ~25,000-50,000 synthetic parts
```

`C-LARGE` должен напоминать станцию:

- hull sections;
- corridors;
- rooms;
- multiple material/part types;
- interior voids;
- semantic interactive anchors отдельно от объединяемого mesh.

C-XL нужен только как synthetic scale fixture; художественная завершённость не требуется.

## Сценарий A — far observation

Игрок находится далеко.

Проверить:

```text
10k canonical parts != 10k rendered scene nodes
```

Снимать:

- visible exact part count;
- proxy mesh count;
- generated vertices/triangles;
- representation bytes;
- frame time;
- build time.

## Сценарий B — approach / retreat

```text
5 km -> 1 km -> 250 m -> 50 m -> interior
interior -> 50 m -> 1 km -> 5 km
```

Проверить:

- transitions;
- no exact+proxy duplicate visual ownership;
- cache reuse;
- unload of unnecessary detail;
- bounded memory after retreat.

## Сценарий C — one-part mutation

На 10k construct изменить ровно одну part.

Обязательные метрики:

```text
changed_parts
invalidated_sections
rebuilt_sections
rebuilt_meshes
uploaded_vertices
build_time_ms
```

Главный диагностический вопрос:

> приводит ли изменение одной детали к локальному rebuild или к перестройке всей станции?

## Сценарий D — rapid traversal

```text
far -> near -> far -> near
```

Измерять:

```text
cache_hits
cache_misses
queued_builds
cancelled_builds
stale_build_results
representation_memory
frame_spikes
```

## Gate

T2 не требует заранее заданных идеальных performance numbers. Он требует:

1. корректной визуальной семантики;
2. отсутствия unbounded growth;
3. измеримых и понятных rebuild boundaries;
4. зафиксированного bottleneck report.

Если C24 уже перекрывает часть старого RL4, не реализовывать дублирующий RL4 по старому плану. Результаты T2 используются для `DONE/PARTIAL/MISSING` gap-аудита.

---

# 8. T3 — Matter Excavation Lab

## Ветка

```text
lab/t3-matter-excavation
```

## Цель

Проверить Mutable Matter непосредственно как изменяемую геометрию мира, пока без Construction.

## Почему сначала не астероид

Первое тело должно быть максимально диагностируемым: фиксированная простая геологическая форма или небольшой детерминированный body. Это позволяет отделить Matter bugs от gravity/body-frame/planet presentation bugs.

## Сцена

```text
scenes/testing/matter_excavation_lab.tscn
```

Состав:

```text
fixed Matter test body
player / spectator / jetpack as needed
debug excavation tool
Matter overlay
collision debug
2-client mode
```

## Сценарий A — simple pit

Создать небольшую яму.

Проверить одновременно:

```text
canonical Matter revision changed
mesh changed
collision changed
second client converged
```

## Сценарий B — shaft

```text
3-5 m diameter
30-50 m depth
```

Проверяет внутренние поверхности, region boundaries и collision updates.

## Сценарий C — tunnel

```text
surface -> horizontal tunnel -> chamber
```

Это обязательный fixture: обычная внешняя поверхность не доказывает способность RL/Matter представлять внутреннюю геометрию.

## Сценарий D — cavity

Создать крупную внутреннюю полость порядка `20 x 20 x 10 m` scripted mutation или последовательными excavation commands.

Проверить:

- seams;
- normals;
- missing surfaces;
- collision holes;
- transition artifacts.

## Сценарий E — mutation storm

Не менее 1000 малых детерминированных mutations.

Измерять:

```text
revision_count
invalidated_regions
mesh_rebuilds
cache_churn
memory
pending_jobs
```

## Gate

T3 PASS означает, что яма, шахта, тоннель и полость корректно существуют в canonical Matter, presentation и collision, а другой клиент приходит к тому же состоянию.

---

# 9. T4 — Matter Streaming / Scale Lab

## Ветка

```text
lab/t4-matter-streaming-scale
```

Основание: accepted T3.

## Цель

Проверить RL2/RL3 как систему представления большого Matter body, а не только отдельных регионов.

## Сцена

```text
scenes/testing/matter_streaming_lab.tscn
```

Body ориентировочно:

```text
radius / scale: 500-1000 m
fixed deterministic seed
static body frame for first acceptance
```

## Сценарий A — approach

```text
10 km -> 2 km -> 500 m -> surface -> tunnel
```

Проверяется:

```text
coarse -> medium -> fine/exact local representation
```

## Сценарий B — retreat

Обратный путь должен освобождать fine-detail state и не оставлять постоянно растущую память/очереди.

## Сценарий C — two observers

```text
Client A: inside tunnel
Client B: 5 km away
```

Ожидание:

```text
A receives fine/exact local region
B receives coarse body representation
```

Нельзя отправлять B всю детальную геометрию только потому, что A находится возле поверхности.

## Сценарий D — reconnect during progressive load

Во время coarse-to-fine загрузки клиент disconnect/reconnect.

Проверить:

- stale artifact rejection;
- valid cache reuse;
- canonical state unchanged;
- resumed progressive presentation;
- no duplicate streams.

## Gate

T4 PASS означает, что большой Matter body может иметь разные уровни detail для разных observers, а progressive streaming и invalidation остаются bounded.

---

# 10. T5 — Matter + Construction Composition Lab

## Ветка

```text
integration/t5-matter-construction-composition
```

## Жёсткие зависимости

```text
T0 ACCEPTED
T2 ACCEPTED
T4 ACCEPTED
```

T5 нельзя начинать полноценной интеграцией до выполнения этих трёх условий.

## Цель

Впервые проверить Matter и Construction в одной production-like scene без добавления mining economy, crafting, ship или NPC.

## Сцена

```text
scenes/testing/matter_construction_composition_lab.tscn
```

## Сценарий

Игроку заранее выдаются строительные parts.

```text
excavate pit
-> excavate tunnel
-> place foundation nearby
-> build small structure
-> edit structure
-> excavate near/under structure
```

На этом этапе Construction **не обязана** физически обрушаться при удалении опорной породы. Это отдельная будущая семантика.

Первый обязательный invariant:

```text
Matter mutation must not corrupt Construction identity/state
Construction mutation must not corrupt Matter canonical/presentation state
```

## Обязательный fixture

```text
small base on surface
+
tunnel beneath base
```

Он остаётся долгоживущим regression fixture для будущих support/fracture mechanics.

## Scale composition

Дополнительно проверить:

```text
large 10k construct
+
large Matter body
+
2 players at different distances
```

Снимать общие метрики CPU, GPU-facing representation, memory, network streams, invalidation fan-out и queue depth.

## Gate

```text
0 canonical cross-domain corruption
0 duplicate spatial/presentation ownership
0 stale representation accepted as current
bounded queues
bounded memory after approach/retreat
2 clients converge
```

---

# 11. T6 — Recovery / Reconnect Composition Lab

## Ветка

```text
integration/t6-composition-recovery
```

Основание: accepted T5.

## Цель

Доказать recovery четырёх истин в одной сцене:

```text
Player state
Item Graph
Matter state
Construction state
```

## Сценарий

```text
1. two clients connect
2. excavate tunnel
3. build small base
4. move items into external container
5. client disconnect/reconnect
6. continue editing
7. stop/restart authoritative server
8. reconnect clients
```

После recovery сравнить exact canonical identities/revisions, а не только картинку.

## Gate

```text
same player identities
same Item Graph committed state
same Matter committed revisions/mutations
same Construction committed state
no duplicate entities
presentation rebuild may differ internally but final visible semantics equivalent
```

---

# 12. T7 — Asteroid Surface Lab

## Ветка

```text
integration/t7-asteroid-surface-lab
```

Основание: accepted T6.

## Цель

Перенести уже доказанную композицию на настоящий изолированный asteroid body, но **ещё без корабля, mining economy и crafting**.

Игрок spawn непосредственно на поверхности/рядом с поверхностью.

Сцена использует существующий fixed-seed asteroid Matter stack и должна содержать:

```text
asteroid body frame
gravity
Matter representation
excavation tool
Construction
inventory/containers
2-player networking
persistence/recovery
```

## Сценарий

```text
walk/jetpack around asteroid
-> choose site
-> excavate pit
-> excavate tunnel
-> receive pre-created construction parts
-> build a small base
-> store items
-> disconnect/reconnect
-> server restart
```

## Gate

T7 PASS означает, что все уже замерженные домены способны работать на одном малом celestial body в production-like runtime.

После этого можно начинать новый gameplay layer:

```text
Matter -> mined resource Item
resource processing
fabrication
ship / EVA / moving SpatialFrames
```

---

# 13. Что можно разрабатывать параллельно

## Безопасно параллельно после frozen baseline

```text
TRACK B: T1 -> T2 Construction
TRACK C: T3 -> T4 Matter
```

Также параллельно им допустим отдельный instrumentation track:

```text
lab/validation-telemetry-overlay
```

если он не меняет authoritative semantics.

Он может добавить общий read-only overlay/API метрик:

```text
server_tick_ms
client_frame_ms
network bytes by channel
pending predictions
construction exact/proxy counts
construction rebuild counts
Matter visible regions
Matter rebuild counts
artifact cache hits/misses
pending/cancelled artifact jobs
representation memory estimate
```

## Нельзя вести независимо

T5 зависит от T2 + T4.  
T6 зависит от T5.  
T7 зависит от T6.

Иначе ошибки композиции будут маскироваться дополнительной сложностью.

---

# 14. Рекомендуемый branch dependency graph

```text
checkpoint/post-network-minimum-accepted
   |
   |---- lab/t1-construction-functional
   |          |
   |          `---- lab/t2-construction-scale
   |
   |---- lab/t3-matter-excavation
   |          |
   |          `---- lab/t4-matter-streaming-scale
   |
   `---- lab/validation-telemetry-overlay    [optional parallel]

T2 + T4 + telemetry
        |
        v
integration/post-merge-validation-labs
        |
        +---- integration/t5-matter-construction-composition
                  |
                  v
              integration/t6-composition-recovery
                  |
                  v
              integration/t7-asteroid-surface-lab
                  |
                  v
          VALIDATION LABS ACCEPTED
```

---

# 15. Правила fixtures и test scenes

Каждая lab scene обязана иметь два режима:

1. **manual graphical mode** — человек может реально запустить сцену и понять поведение глазами;
2. **deterministic acceptance mode** — тот же ключевой сценарий запускается автоматически с фиксированным seed/input.

Lab не должна становиться альтернативным runtime. Она собирает production components через adapters/configuration.

Запрещено:

- дублировать Item Graph специально для сцены;
- делать отдельную `test construction truth`;
- рисовать fake Matter вместо canonical Matter;
- обходить network authority прямым изменением client state;
- считать presentation mesh источником состояния.

Разрешено:

- deterministic fixture generation;
- admin/test spawn для заранее подготовленных ресурсов;
- debug overlays;
- scripted camera/observer paths;
- fault injection;
- synthetic C-XL fixture.

---

# 16. Общий measurement contract

До T2/T4 должен существовать минимальный общий telemetry surface.

Обязательные группы:

## Runtime

```text
server_tick_ms
client_frame_ms
active_nodes / relevant presentation objects
```

## Network

```text
RTT
jitter
loss
bytes/sec by logical channel
queue depth
snapshot age
```

## Prediction / Items

```text
pending_predictions
prediction_rejections
corrections
Item Graph revision / pending commands
```

## Construction

```text
canonical_part_count
exact_visible_part_count
proxy_count
invalidated_sections
rebuilt_meshes
build_time_ms
estimated_representation_bytes
```

## Matter / RL

```text
visible_cells/regions
fine_regions
artifact_builds
artifact_cancellations
cache_hits
cache_misses
pending_build_jobs
stale_artifact_rejections
estimated_representation_memory
```

Точные названия telemetry keys могут отличаться от этих рабочих терминов, но смысл должен быть сохранён и документирован.

---

# 17. Acceptance layers

Каждый lab checkpoint проверяется слоями:

```text
L0 contracts/unit
L1 property/fuzz where relevant
L2 single-process runtime
L3 multi-process dedicated/client
L4 graphical manual acceptance
L5 soak/fault/recovery where relevant
```

Для T1/T3 допустимо закрытие до L4 с коротким soak.  
Для T2/T4 обязательны scale + rapid traversal tests.  
Для T5–T7 обязательны multi-process, graphical acceptance, reconnect и bounded-state проверки.

---

# 18. Stop conditions

Текущий этап блокируется при любом из условий:

```text
canonical identity duplication
unbounded queue growth
unbounded memory growth during repeat traversal
stale representation accepted as current
one-part edit rebuilds unexplained global state
remote observer receives unnecessary full detail without documented reason
Matter canonical mutation differs between clients/server
Construction authoritative state differs from recovered state
reconnect creates second logical player/entity
presentation object leaks into canonical snapshot
server restart loses committed world mutation
```

Любой такой дефект сначала локализуется и закрывается на минимальной lab-сцене. Не переходить в более сложный checkpoint, чтобы проверить, исчезнет ли он сам.

---

# 19. Переход к бесшовности

Эта вставка намеренно ставится **до** следующих этапов бесшовного большого мира.

До `VALIDATION LABS ACCEPTED` не начинать крупную production-интеграцию:

- seamless server-to-server gameplay handoff;
- player/ship migration между authority zones;
- production multi-body seamless traversal;
- Moon/planet Matter replacement на больших территориях;
- сложные moving nested frames;
- полноценный orbital ship vertical slice.

После T7 мы будем знать:

1. как реально запускать общий merged runtime;
2. выдерживает ли Construction сложные/крупные постройки;
3. выдерживает ли Matter шахты, тоннели, cavities и mutation storms;
4. работает ли coarse-to-fine streaming у разных наблюдателей;
5. могут ли Matter и Construction жить вместе;
6. переживают ли все домены reconnect/restart;
7. какие фактические bottlenecks требуют RL/NX/production work перед бесшовностью.

Только после этого формируется следующий seamlessness checkpoint на основании измерений, а не предположений.

---

# 20. Что идёт после лабораторий

После принятия T7 roadmap раздваивается на две большие линии, которые снова можно частично вести параллельно:

```text
A. SEAMLESSNESS
   authority zones
   server-to-server handoff
   replication interest/budgets
   moving/reference frames
   multi-body traversal

B. GAMEPLAY VERTICAL SLICE
   Matter -> resource items
   mining tool
   processor/fabricator
   item-backed construction
   ship/EVA
   orbital asteroid base scenario
```

Но gameplay vertical slice не должен обходить те seamless/frame contracts, которые нужны кораблю и перемещению между пространствами.

Дальний контрольный сценарий остаётся:

```text
ship near asteroid
-> approach
-> leave ship
-> excavate/mine
-> load resources
-> process/fabricate building parts
-> build simple surface base
-> persist/reconnect/recover
```

Он является **результатом** предыдущих ступеней, а не первой сценой после merge.

---

# 21. Definition of Done всего Validation Labs цикла

Цикл считается принятым, когда на одном frozen/integration lineage подтверждено:

```text
T0 items/network gameplay PASS
T1 manual Construction PASS
T2 10k Construction scale/proxy PASS
T3 pit/shaft/tunnel/cavity Matter PASS
T4 large Matter coarse-to-fine/two-observer PASS
T5 Matter + Construction composition PASS
T6 reconnect/server recovery composition PASS
T7 asteroid surface composition PASS
```

Дополнительно:

```text
all production defects have regression tests
known performance bottlenecks are measured and recorded
no unresolved P1 cross-domain correctness issue
no unbounded runtime growth in repeatable lab scenarios
manual launch instructions exist for every scene
all accepted lab checkpoints point to exact SHAs
```

После этого ставится общий checkpoint вида:

```text
v18.x-post-merge-validation-labs-accepted
```

Фактический version определяется состоянием main на момент принятия.

---

# 22. Непосредственный следующий шаг

Сразу после завершения текущего network minimum:

```text
1. freeze accepted SHA
2. подтвердить/закрыть T0 Playground
3. создать параллельно:
   - lab/t1-construction-functional
   - lab/t3-matter-excavation
   - optional lab/validation-telemetry-overlay
4. после T1 -> T2
5. после T3 -> T4
6. объединить результаты в integration/post-merge-validation-labs
7. пройти T5 -> T6 -> T7
8. только после общего acceptance перейти к seamlessness roadmap
```

Это является рекомендуемой рабочей траекторией проекта после текущей сетевой задачи.