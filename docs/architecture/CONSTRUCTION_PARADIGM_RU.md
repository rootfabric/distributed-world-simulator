# PlanetSimulator: парадигма стройки нового уровня

**Статус:** архитектурная линия и основа отдельного экспериментального трека
**Первый этап:** C1 Semantic Construction Kernel
**База:** `main @ 2879fdb7134032f645ffc5c98c0535aecfc09caf`
**Рекомендуемая ветка:** `feature/c1-semantic-construction-kernel`

## 1. Заявление парадигмы

PlanetSimulator предпринимает попытку создать **стройку нового уровня**, а не ещё один редактор блоков, prefab-объектов или свободного меша.

Главная линия всей системы:

> сочетание семантического масштаба, составных предметов, компиляции facets и capability-based поведения должно дать конструктор нового уровня — достаточно простой для обычной игры, достаточно глубокий для инженерной симуляции и достаточно формальный для сетевого авторитетного мира, агентов и горизонтального масштабирования.

Эта формулировка является не рекламным лозунгом, а архитектурным ограничением. Любое дальнейшее решение должно проверяться вопросами:

1. сохраняет ли оно предметную идентичность и внутренний состав;
2. позволяет ли скрывать неактивную сложность;
3. выводит ли поведение из состава и связей, а не только из prefab-класса;
4. компилируются ли presentation, physics и gameplay-представления из канонических данных;
5. проходит ли изменение через авторитетную командную границу;
6. может ли объект масштабироваться от стола до робота, дома, станка и корабля.

## 2. Проблема существующих строительных систем

Большинство игр выбирает одну гранулярность:

- готовые объекты дают простоту, но ограничивают изобретение;
- крупные блоки хорошо разрушаются, но ограничивают форму;
- микроблоки и воксели дают форму, но взрывают сложность;
- свободный меш сохраняет внешний вид, но теряет состав;
- физические joints хороши для механизмов, но не для миллионов неподвижных соединений.

PlanetSimulator не должен выбирать одно представление для всех задач.

## 3. Четыре опоры

### 3.1 Семантический масштаб

Один объект существует на нескольких уровнях: агрегат, секция, подузел, деталь, материальная область и визуальная микродеталь. Полная структура может храниться, но активируется только необходимый слой.

### 3.2 Составные предметы

Стол, робот или станок является item-backed construct. В обычной игре он воспринимается как один предмет, но при ремонте или редактировании раскрывает состав. Composite не уничтожает исходные части и связи.

### 3.3 Компиляция facets

Канонические данные не являются Node3D, мешем или rigid body. Из них независимо компилируются:

- geometry;
- collision;
- rigid islands;
- structural graph;
- joints;
- power/data/fluid networks;
- spaces;
- capabilities;
- navigation;
- manufacturing;
- network LOD.

Изменение программы контроллера не перестраивает геометрию. Пробоина панели не обязана пересобирать всю электросеть. Dirty facets обновляются отдельно.

### 3.4 Capability-based поведение

Объект получает игровые возможности из проверяемого состава и состояния. Стол предоставляет `SUPPORT_SURFACE`, робот — locomotion и control, сборщик — fabrication. Категория объекта может использоваться UI, но не должна быть единственным источником поведения.

## 4. Каноническая модель

```text
ConstructAggregate
├── root item identity
├── parts
├── bonds
├── joints
├── ports
├── material regions
├── spaces
├── build state
├── operation/revision boundary
└── compiled facets
```

На следующих этапах состав разделяется на графы:

```text
Assembly Graph
Bond / Structural Graph
Kinematic Graph
Power Graph
Data Graph
Fluid Graph
Item Flow Graph
Space Graph
Capability Graph
```

Графы связаны стабильными ID, но не смешиваются в один универсальный список отношений.

## 5. Связь с Item Graph

Item Graph остаётся источником истины для:

- глобальной идентичности предметов;
- владения;
- контейнеров;
- расположения;
- mounted/contained relations;
- revisions и Operation Ledger;
- транзакционного расхода и возврата компонентов.

ConstructAggregate хранит плотную внутреннюю топологию. Не каждая гайка обязана становиться Item Graph node.

Элемент получает item identity, когда он имеет самостоятельное состояние, может быть заменён, продан, перемещён, установлен повторно, содержит порты или его происхождение важно.

## 6. Сетевая граница

Стройка с первого этапа проектируется под canonical command path:

```text
client intent
→ versioned command DTO
→ authoritative service
→ item/construct transaction
→ revision + operation ledger
→ snapshot/delta
→ client replica
```

Клиент не меняет канонический construct напрямую. Все команды имеют `operation_id`, `base_revision`, actor/session/authority fencing и детерминированный payload hash.

C1 пока не подключается к M4/M5 runtime. Он формирует изолированное доменное ядро, которое позднее будет подключено через существующие Generic Aggregate и multi-aggregate transaction boundaries.

## 7. Семантические уровни представления

| Уровень | Назначение |
|---|---|
| ItemPart | заменяемая предметная деталь |
| Subassembly | колесо, дверь, двигатель, манипулятор |
| StructuralMember | балка, панель, труба, профиль |
| MaterialRegion | сплошной объём материала |
| Bond | сварка, болт, клей, крепление |
| SurfaceLayer | краска, изоляция, покрытие |
| VisualDetail | несимулируемая заклёпка, фаска, царапина |

## 8. Контрольные примеры

### Стол

Проверяет части, bonds, массу, центр масс, устойчивость, composite и повреждение. Пять предметов и четыре связи компилируются в один rigid island и capabilities рабочей поверхности.

### Наземный робот

Проверяет несколько rigid islands, joints, питание, управление и частичные отказы. Один ConstructAggregate может содержать корпус, колёса, моторы, батарею, компьютер, датчик и контейнер.

### Дом

Проверяет секции, статическую структуру, Space Graph, комнаты, двери, герметичность, инженерные сети и activation LOD.

### Сборщик

Проверяет BuildPlan, input/output containers, tooling, power, управление и производство того же construct, который игрок способен собрать вручную.

### Корабельная секция

Проверяет оболочку, помещения, pressure topology, повреждения, утечки, split и создание нового сетевого aggregate при отделении части.

## 9. Принципы производительности

- меш и коллизия — кэш, не источник истины;
- неподвижные части компилируются в rigid clusters;
- joints создаются только для относительного движения;
- микрогеометрия активируется локально;
- сложность хранится отдельно от активности симуляции;
- одинаковые composite definitions разделяют immutable compiled assets;
- большие здания делятся на section aggregates;
- далёкие объекты работают в summary/network LOD.

## 10. Уровни активности

```text
DORMANT
SUMMARY
FUNCTIONAL
PHYSICAL
STRUCTURAL
EDITING
MICRODETAIL
```

Разные части одной конструкции могут находиться на разных уровнях одновременно.

## 11. Строительство как жизненный цикл

```text
DESIGN
PLANNED
MATERIALS_RESERVED
PARTIAL
STRUCTURALLY_COMPLETE
FUNCTIONALLY_COMPLETE
COMMISSIONING
OPERATIONAL
DAMAGED
DECONSTRUCTION
SALVAGED
```

C1 использует минимальное подмножество: `PLANNED`, `PARTIAL`, `OPERATIONAL`, `DAMAGED`, `DECONSTRUCTION`.

## 12. Неподвижные инварианты линии

1. Меш никогда не становится единственным каноническим состоянием.
2. Composite не уничтожает внутренний состав.
3. Клиентская presentation не получает authority.
4. Item identity не дублируется внутри нескольких construct.
5. Один operation ID с тем же payload replay-safe; с другим payload конфликтует.
6. Stale revision не мутирует состояние.
7. Ошибочный snapshot не мутирует активный aggregate.
8. Capability compiler детерминирован.
9. Сложная физика включается локально и по событию.
10. Новый тип объекта должен подключаться композиционно, без отдельной архитектуры для каждого класса.

## 13. Конечная цель

На выходе должна появиться не система «поставить блок», а универсальный **семантический конструктор мира**:

- новичок ставит готовый предмет;
- опытный игрок раскрывает composite и меняет части;
- инженер проектирует механизм и сети;
- фабрика исполняет BuildPlan;
- агент понимает capabilities и использует неизвестную конструкцию;
- сервер хранит строгий aggregate, а не произвольный клиентский меш;
- симуляция раскрывает детальность только там, где это действительно влияет на мир.

## 15. Навигация и дисциплина движения

Наглядная карта линии хранится в `docs/plans/CONSTRUCTION_MAP_RU.md`, а каждое фактическое продвижение записывается в `docs/plans/CONSTRUCTION_PROGRESS_LOG_RU.md`.

Начиная с C2, Item Graph integration разделена на два этапа:

- **C2A** формализует совместимые contracts, plans и invariants в изолированном sandbox;
- **C2B** подключает эти contracts к реальным Item Graph services и M0 multi-aggregate transaction coordinator после готовности multiplayer gate.

Установленная item-backed деталь в C2A выражается существующей relation `ATTACHMENT`:

```text
assembly_id    = construct_id
parent_item_id = construct root item
socket_id      = part_id
```

Резервирование не становится новым persistent relation. Оно остаётся частью ещё не зафиксированного transaction plan. Благодаря этому C2A не создаёт второй Item Graph и не вводит состояние, которое позднее пришлось бы мигрировать.

## 16. C2B: M0 как авторитетная строительная граница

C2B переводит принцип «стройка является сетевой с первого дня» в исполняемую архитектуру.

```text
ConstructionItemTransactionPlan
→ deterministic M0 MutationBatch
→ prepare/commit in AggregateTransactionRepository
→ authoritative operation record
→ production Item Graph materialization
```

M0 commit является точкой истины. Локальные `ItemRegistry`, `ContainerRegistry`, `ConstructStore` и `ItemOperationLedger` являются рабочей materialization этого состояния. При аварии после commit новый runtime обязан восстановить их из M0, а не повторять расход материалов.

Внутренняя `ConstructSnapshot.state_revision` описывает историю семантической конструкции. `aggregate_snapshot_envelope.authority.state_revision` описывает историю сетевого aggregate. Эти счётчики не взаимозаменяемы и сохраняются отдельно.

C2B также устанавливает правило persistence: файловый construction bundle может ускорять запуск и обеспечивать резервное хранение, но не имеет права откатывать или заменять отличающееся M0-authoritative состояние.

## 17. C3: BuildPlan как исполняемое намерение

C3 вводит новый слой между пользовательским намерением и C2B authority:

```text
BuildPlan
→ Ghost projection
→ ordered BuildStage
→ deterministic C2A transaction plan
→ C2B authoritative commit
→ partial/final ConstructSnapshot
```

`BuildPlan` не является prefab и не является новым Item Graph. Это immutable execution-plan конкретной стройки, уже связанный с реальными item IDs, исходными revisions и material allocations. Переиспользуемая definition появляется только в C4.

### Ghost не является предметом

До начала работ ghost существует только как намерение и presentation projection:

- нет `ItemInstance`;
- нет construct root;
- нет массы;
- нет collision;
- нет capabilities;
- нет права менять мир.

После первой стадии появляется реальный partial construct. Ghost продолжает показывать будущие части и прогресс, но не дублирует physical/capability state.

### Partial capabilities закрыты

Facet compiler может вычислить геометрическую устойчивость промежуточной конструкции, но C3 запрещает публиковать её как operational behavior до финальной commissioning-stage. Поэтому partial snapshots сохраняют diagnostic facets, но `capabilities = []` и `operational = false`.

### Progress является производной проекцией

Источник истины после stage commit:

1. C2B authoritative ConstructSnapshot;
2. общий Item Operation Ledger;
3. M0 repository.

`GhostState` может отстать при аварии, но не может переписать authoritative состояние. Reconciliation сопоставляет текущий construct с детерминированными stage snapshots и восстанавливает progress без повторного расхода.

### Builder agent не получает отдельный путь

Минимальный builder-agent C3 только выбирает следующую стадию и вызывает `ConstructionBuildProcess`. Игрок, робот, фабрика и серверный сценарий должны исполнять один BuildPlan через одну authority boundary.


## 18. C4: CompositeDefinition как семантический тип

C4 отделяет **тип конструкции** от конкретного экземпляра:

```text
CompositeDefinition
  semantic slots + bond topology + stage requirements
        ↓ late binding
CompositeInstantiation
  pinned definition version + concrete item bindings
        ↓ compile
C3 BuildPlan
        ↓
C2A/C2B authoritative execution
```

`CompositeDefinition` не содержит реальных item, root, construct, BuildPlan или operation IDs. Это принципиальное отличие от prefab: definition описывает, **какие роли и связи нужны**, а каждый construct продолжает хранить собственные реальные parts и Item Graph identity.

Part slot v1 связывается по точному `definition_id` и optional subset компонентов. Это позволяет, например, требовать structural-grade beam и отклонять визуально похожую cosmetic beam. Resolver позднее может расшириться tags и substitution policies, не меняя C3 execution contract.

Материалы в definition задаются как требования по типу и количеству. Concrete stacks выбираются детерминированно при компиляции, а результат фиксируется в `CompositeInstantiation`. Поэтому replay использует уже конкретный checksum-protected BuildPlan и не выполняет повторный поиск ресурсов.

C4 также вводит typed parameters и exposed ports. Parameter definitions задают тип и default; каждый instantiation хранит полный нормализованный набор значений. В C4 параметры являются provenance и конфигурацией типа, а процедурная перестройка геометрии остаётся задачей C10. Exposed port привязан к semantic part slot и при компиляции превращается в связь с concrete part ID. В partial snapshot порт публикуется только после установки связанной детали.

Каждый partial/final ConstructSnapshot сохраняет provenance definition ID, version, checksum, instantiation ID, parameter values и доступные exposed ports. Новая версия definition не переписывает существующие объекты: каждый экземпляр навсегда pinned к версии, по которой был скомпилирован.


## 19. C5: поведение как компилируемый интерфейс

C5 вводит формальную границу между внутренним устройством конструкции и действиями, доступными внешним системам:

```text
parts + bonds + build state + compiled facets + exposed ports
        ↓
ConstructionBehaviorProfile
        ↓
capability/affordance query
        ↓
agent or gameplay system
```

### Capability не является строкой имени объекта

Capability descriptor содержит semantic kind, concrete provider parts, source exposed ports и свойства. Поэтому `SUPPORT_SURFACE` обеспечивается конкретной столешницей, а `MOUNTING_SURFACE` — конкретным service-anchor port.

### Affordance является конкретным действием

Capability отвечает «что объект умеет», affordance — «что актор может сделать сейчас и куда направить действие». Affordance содержит action kind, target part/port, actor requirements, parameters и deterministic priority.

### Профиль является производным cache

Authoritative checksum и revision берутся из ConstructSnapshot. Behavior profile можно сохранять, реплицировать или индексировать для поиска, но он не имеет права менять Item Graph, bonds или construct state. После потери cache профиль перестраивается.

### Build state закрывает преждевременные действия

C3 уже запрещает partial capabilities. C5 продолжает правило на уровне внешнего API: PARTIAL и DAMAGED получают валидный профиль с пустыми capabilities/affordances. Поэтому геометрически похожий, но незавершённый или разрушенный объект не рекламирует gameplay actions.

### CompositeDefinition не обязателен

Если C4 ports доступны, C5 использует их как preferred semantic targets. Для старых C1 constructs остаётся part-role fallback. Это позволяет внедрять capability layer постепенно и не мигрировать весь мир в prefabs или definitions.

### Агент не знает prefab

Агент формирует запрос вида:

```text
action = PLACE_ITEM
minimum load_rating_kg = 120
finish = painted
actor capabilities = MANIPULATE_ITEM
```

Resolver возвращает конкретный construct, capability, provider part и port. Имя сцены, prefab или пользовательское название в контракте отсутствуют. Это основной переход от объектно-специфических скриптов к семантической симуляции.


## 20. C6: мобильность как граф зависимых подсистем

C6 запрещает моделировать робота одним булевым флагом `can_move`. Мобильное поведение компилируется из concrete parts и bonds:

```text
parts + bond states + subsystem definitions
        ↓
POWER / CONTROL / DRIVE / SENSOR states
        ↓
provider quorum + dependency propagation
        ↓
mobile capabilities and affordances
```

### Повреждение не равно полному выключению

C5 намеренно fail-closed выключал поведение повреждённой мебели. Для mobile constructs нужна более точная модель: `DAMAGED` rover может продолжать движение или сканирование, если соответствующие provider parts и зависимости ещё работоспособны. Поэтому C6 профиль использует build state как контекст, но выводит каждую capability отдельно.

### Quorum вместо жёсткой целостности

Однотипная subsystem может иметь несколько providers и minimum quorum. Четырёхколёсный drive способен работать на двух или трёх колёсах с пониженным health ratio, но становится offline ниже minimum. Это даёт общий механизм для колёс, двигателей, батарей, sensors и redundant controllers.

### Dependency cascade

SubSystem может зависеть от других subsystems. `DRIVE` зависит от `POWER` и `CONTROL`; `SENSOR` может зависеть от тех же источников. Degraded dependency делает результат degraded, offline dependency выключает его. Циклы запрещены.

### Команда закреплена за профилем

`ConstructionMobileCommand` содержит expected profile checksum. После повреждения, ремонта или reconfiguration старая команда отклоняется и должна быть пересобрана против нового профиля. Это не physics command bus, а контракт авторизации действия. Реальное движение должно позднее пройти через server authority и spatial transaction boundary.

### Профиль можно потерять

Mobile profile store — производный cache. После restart он либо загружается транзакционно, либо полностью перестраивается из authoritative snapshots. Ни command, ни profile не меняют Item Graph, parts, bonds или physics state.


## 16. C7: пространственная семантика

C7 добавляет второй масштаб компиляции поверх parts/bonds: section → opening → space → building. Этот слой не заменяет item identity и не делает геометрию канонической.

```text
parts + bonds
→ structural sections
→ openings and closures
→ Space Graph
→ enclosure + utility availability
→ activation level
→ capabilities and affordances
```

Неподвижные правила:

1. Mesh и collision не доказывают наличие комнаты.
2. Space существует только через строгие section/opening references.
3. Utility failure и enclosure breach — разные виды деградации.
4. Exterior opening учитывается через состояние closure part и frame section.
5. Building activation является rebuildable projection authoritative construct.
6. Большие здания в будущем могут разделяться на section aggregates без изменения семантики Space Graph.


## 17. C8: производство как authoritative material flow

C8 не вводит отдельную систему «виртуальных ресурсов». Сырьё и продукт являются обычными item-backed сущностями, а machine — обычным construct. Recipe и queue описывают процесс, но не подменяют Item Graph.

```text
recipe + machine capability + utility availability
→ exact input bindings
→ authoritative reservation
→ idempotent work progress
→ authoritative consumption/output creation
→ normal Item Graph
```

### Recipe не является готовым предметом

Recipe хранит требования и output templates, но не содержит конкретных item IDs. Конкретные входы выбираются детерминированно при enqueue, а конкретные output IDs закрепляются в job до исполнения. Это делает replay и network acceptance проверяемыми.

### Reservation физически перемещает предметы

Входы не помечаются отдельным булевым флагом. Они переводятся в machine input container через C2A/C2B transaction. Поэтому контейнерное членство, масса, nested rules и persistence остаются едиными с остальным миром.

### Completion — одна атомарная граница

Завершение одной транзакцией:

1. удаляет полностью израсходованные stacks;
2. уменьшает partial stacks с revision increment;
3. создаёт fabricated outputs с immutable provenance;
4. обновляет machine `ConstructSnapshot`;
5. фиксируется shared operation ledger и M0 batch.

Если commit не состоялся, не меняется ничего. Если commit состоялся, повтор операции возвращает replay и не создаёт второй продукт.

### Queue слабее authoritative мира

Queue хранит schedule, priority и progress, но не доказывает расход или выпуск. После crash C8 сверяет job с `fabrication_runtime` machine snapshot. Authoritative completion сильнее отставшего queue state.

### Производство замыкает строительный цикл

Fabricated output возвращается в Item Graph и может быть выбран C4 compiler либо использоваться как source item C3 BuildPlan. Для игрока, агента и фабрики не создаются разные классы деталей.

### Деградация станка

Machine availability компилируется из concrete providers/bonds, C5 WORKSTATION capability и C7 POWER utility. Потеря power или quorum блокирует новые material mutations; восстановление позволяет продолжить тот же pinned job.


## 18. C9: повреждение как изменение topology, а не удаление prefab

C9 рассматривает повреждение как authoritative изменение part/bond graph. Mesh fracture может визуализировать результат, но не определяет identity обломков и не решает, какие предметы сохранились.

```text
source ConstructSnapshot
→ part conditions + broken bonds
→ connected components
→ retained aggregate / split aggregates / salvage items
→ inverse repair transaction
```

### Identity сохраняется

Split не клонирует parts. Исходный `ItemInstance` либо остаётся в source aggregate, либо меняет attachment на новый split aggregate, либо получает world/container salvage relation. Repair использует те же item IDs.

### Aggregate split атомарен

Source update, child creates, root item creates и relation changes входят в один multi-aggregate M0 batch. Частично созданного обломка быть не может. Exact replay не повторяет split.

### Repair является обратной authoritative транзакцией

Repair plan pin-ит original snapshot и требуемые parts. Repair удаляет временные child roots/aggregates, возвращает реальные детали, восстанавливает bonds и пересобирает derived C5–C8 profiles уже из нового source checksum.

### Salvage policy отделена от topology

Connected component определяет состав обломка, а policy определяет outcome: новый construct или salvage. Это позволяет менять правила мира без изменения алгоритма связности.

### Damage history слабее authoritative мира

History и repair ghost помогают UI/agent workflow, но состояние конструкции доказывается `ConstructSnapshot`, Item Graph и shared operation ledger. History можно восстановить или потерять без дублирования частей.


## 19. C10: параметры сильнее mesh

C10 отделяет семантический строительный элемент от его визуальной tessellation. Балка существует как definition, параметры, material usage и item identity; mesh можно удалить и восстановить без потери конструкции.

```text
material physics + parameter schema
→ canonical member instance
→ item-backed projection / part record
→ renderer and collision projection
```

### Масса является производной

Для параметрической детали нельзя независимо записать размеры, volume и mass. Compiler выводит их из одной версии параметров и плотности материала. Instance проверяет conservation между общей mass/volume и суммой material usage.

### Layered assemblies не являются одним материалом

Многослойная стена сохраняет ordered semantic layers, но расход агрегируется по material identity. Это позволяет отдельно считать массу, производство, salvage, thermal/fire properties и последующую локальную обработку каждого слоя.

### Fabrication не создаёт специальный класс детали

C10 преобразует instance в обычный C8 recipe. После authoritative completion результат является тем же `ItemInstance`, который можно положить в контейнер, установить C3 BuildPlan, отделить C9 damage transaction или передать другому серверу.

### Cut и aggregate split — разные уровни

Parametric segmentation делит геометрический member вдоль его оси и создаёт pinned child member identities с conservation. C9 aggregate split делит topology конструкции. Они совместимы, но не подменяют друг друга.

### C11 меняет локальную форму, но не отменяет C10

Отверстие, bevel или локальный SDF edit должны быть overlay над parametric base и обязаны обновлять mass/material deltas. Базовая parameter definition остаётся provenance, а mesh по-прежнему не становится источником истины.


## 20. C11: локальная форма является семантическим overlay

C11 вводит ordered control-point path и constraints поверх C10 member instance. Это не mesh editing: authoritative state по-прежнему состоит из definition provenance, параметров, control points, ограничений и checksum.

```text
parametric base
+ semantic local path
+ deterministic constraints
→ recomputed C10 metrics
→ item/part/construct atomic update
```

### Один источник вычисляемой массы

Geometry editor не имеет права отдельно менять массу. Он вычисляет новый effective path и параметры, затем вызывает C10 compiler. Поэтому Item Graph, fabrication requirements и gameplay capabilities используют одну и ту же производную массу.

### Constraints принадлежат миру

Grid snap, locked axes и minimum segment length сохраняются в DTO и checksum. Это позволяет серверу, клиенту и агенту одинаково проверить edit, а не доверять поведению локального UI gizmo.

### Edit является транзакцией домена

ItemProjection, semantic part и ConstructSnapshot должны измениться вместе. Если commit не завершён, ни одна downstream projection не должна видеть новую форму. Exact replay восстанавливает результат по operation ledger и snapshot audit record.

### Произвольная mesh-операция остаётся за границей

Boolean holes, bevels, SDF/voxel patches требуют отдельного conservative material-delta контракта. C11 закладывает для него authoritative boundary, но не объявляет triangle mesh источником истины.


## 21. C12: multiplayer не создаёт второй строительный домен

C12 принимает только команды намерений и маршрутизирует их в существующие C3, C9 и C11 processes. Permission/session/event слой не имеет права напрямую изменять Item Graph или ConstructSnapshot.

```text
client command
→ permission/session/precondition gate
→ existing domain process
→ C2A/C2B/M0 authority
→ canonical event bundle
```

### Optimistic concurrency

Клиент pin-ит известный construct checksum и при необходимости server generation. Первый конкурентный commit меняет authority; второй command со старым precondition отклоняется до mutation. Advisory UI locks могут существовать, но корректность не зависит от них.

### Replay сильнее reconnect

Повтор command ID с тем же checksum возвращает terminal result. После gateway crash authoritative operation ledger позволяет определить уже выполненную domain operation и закончить публикацию одного event без повторного расхода или edit.

### Convergence проверяется данными, а не сообщением UI

Replica считается синхронизированной только если checksum canonical item+construct bundle совпадает с authoritative checksum. Event order, generation rollback и повреждённый payload отклоняются.


## C13: presentation/physics не являются authority

C13 вводит жёсткую границу между семантическим миром и Godot SceneTree. `ConstructSnapshot`, реальные item identities и compiled profiles остаются источником истины. `Mesh`, `Shape3D`, `PhysicsBody3D`, Node paths и RID — удаляемые runtime-проекции.

```text
domain JSON DTO
→ RuntimeConstructDescriptor
→ Godot Node/Resource projection

обратного пути Node → domain mutation нет
```

Любая потеря сцены, streaming unload или reconnect должны восстанавливаться из descriptors без изменения authoritative checksum. Локальная оптимизация mesh/collision допустима только при сохранении part/item provenance и source checksum.

## Structural authority после C14

Несущая способность не хранится в mesh, collision или Godot physics body. C14 выводит load graph из authoritative `ConstructSnapshot`, масс частей, semantic capacities, bonds и load case. Structural profile является удаляемым cache. Любой реальный отказ применяется только через C9 `DamageRequest`, поэтому split, salvage, repair и item identity conservation остаются едиными для физического, игрового и агентного источника повреждения.


## Executable utility authority после C15

C7 доказывает наличие и структурную доступность utility topology, но не обещает ресурс потребителю. C15 вводит отдельную rebuildable execution projection, где каждый tick рассчитываются source dispatch, link losses, storage и allocations.

```text
semantic utility ONLINE
≠ гарантированная доставка ресурса

C15 allocation FULL/PARTIAL/SHED
= фактическое право процесса работать в этом tick
```

Machine gameplay не должен вызывать C8 progress напрямую, когда включён C15 runtime. Сначала создаётся checksum-pinned lease по конкретным execution profiles и allocations. Lease ограничивает work units, но authoritative расход материалов и выпуск предметов остаются в C8/C2A/C2B. Ни utility profile, ни storage cache не создают второй Item Graph или вторую identity ресурса.

## C16 — UI является клиентом authority, а не частью authority

Construction interaction layer может выполнять raycast, snapping, selection, ghost rendering и локальный gizmo preview. Любое устойчивое изменение мира оформляется checksum-pinned командой и проходит через C12 gateway. UI-side constraints улучшают взаимодействие, но сервер повторно проверяет C3/C9/C11 contracts. Godot `Control`, `Node3D`, `Mesh` и input state запрещены в authoritative DTO.


## Distributed authority invariant — C17

Каждый небольшой `ConstructAggregate` имеет ровно одного authoritative writer и монотонный authority epoch. Neighbor/section servers держат только read-only projections. Migration всегда включает fence, state/terminal-operation handoff и epoch increment. Owner failure не позволяет немедленный competing write: takeover возможен только после lease expiry и при наличии checksum-verified replica. Cross-zone item movement остаётся C2B/M0 transaction, а C17 только выбирает и проверяет coordinator/owner route.


## Streaming authority invariant — C18

Streaming может удалять только derived state. `DORMANT` не означает удаление конструкции: сохраняются authoritative identity, snapshot checksum, authority epoch, C8 job IDs и operation IDs. `SUMMARY`, `SIMULATED` и `PRESENTED` являются локальными activity projections. Только C17 owner может выполнять authoritative catch-up; read-only replica может иметь summary и presentation, но не получает write-capable simulation. Budget eviction, LOD и SceneTree lifecycle не изменяют Item Graph или ConstructSnapshot.


## Agent automation invariant — C19

Агент является клиентом строительной authority. Его goal, BOM, reservation и work queue не являются вторым Item Graph и не дают права напрямую менять construct. Любой устойчивый build/repair/salvage результат проходит через C12 command и C17 owner route. Fabrication output заранее получает identity, но становится реальным предметом только после C8 authoritative completion. Exact operation replay обязателен для reservation, fabrication, logistics и domain command, поэтому restart агента не создаёт второй расход материала или второй commit.

## Logistics/economy authority invariant — C20

Цена, заказ, маршрут, escrow и contractor contract являются workflow/economic state, но не заменяют Item Graph. Продажа не создаёт новый предмет: shipment переносит тот же `item_instance_id`. Stock reservation и escrow образуют атомарную бизнес-границу; при невозможности закрепить товар деньги возвращаются. Settlement допускается только после фактического transfer result, а C19 BOM line становится fulfilled только после доставки. Production chain pin-ит C8 recipes и output identities, но предмет появляется лишь после authoritative fabrication completion.


## Масштабная приёмка

Масштаб не считается доказанным количеством созданных объектов само по себе. C21 принимает систему только при одновременном выполнении authority, replay, identity, material-conservation и budget-инвариантов. Нагрузочный harness не имеет собственного mutation path и наблюдает те же границы C8/C12/C17/C19/C20, что игроки и агенты.


## Compiled proxy authority invariant — C22

Крупная станция может содержать тысячи item-backed parts, но количество authoritative частей не должно определять объём каждого network packet или SceneTree клиента. C22 компилирует удаляемые shell/section/interior artifacts из checksum-pinned snapshot.

```text
10 000 authoritative parts
≠ 10 000 всегда передаваемых и отображаемых nodes

far interest
= root identity + transform + summary + one shell artifact
```

Proxy artifact не является предметом, не получает item identity и не может быть источником damage, inventory или utility state. Manifest закрепляет source checksum и authority epoch. Read-only C17 replica может компилировать и передавать proxy, но не получает write authority.

Дальний shell обязан **заменять** presentation дочерних частей. Одновременное отображение shell поверх полного child runtime нарушает инвариант. При приближении shell заменяется bounded section HLOD, затем локальными/interior proxies и только необходимыми interactive C13 descriptors.

Incremental rebuild следует authoritative изменению: C9 damage меняет snapshot, C22 инвалидирует dirty sections и shell при изменении exposed boundary. Неизменившиеся geometric bytes переиспользуются по content hash, при этом item identities и canonical construct composition остаются неизменными.


## Production hardening invariant — C23

Production hardening не является новой authority-моделью. C23 оборачивает уже существующий C2B/M0/C12/C17 authoritative executor эксплуатационными гарантиями, но не получает права напрямую менять Item Graph или `ConstructAggregate`.

```text
C23 may validate, fence, replay, observe and recover
C23 must not invent identity or bypass authoritative transaction commit
```

Operation ID и checksum образуют immutable idempotency key. Повтор идентичной terminal операции должен вернуть прежний результат, а тот же ID с другим checksum отклоняется. Для crash-window после authoritative commit сам нижележащий executor также обязан поддерживать exact idempotence.

Save compatibility выражается versioned envelope, а не эвристическим чтением частично совпадающих полей. Повреждение любого уровня checksum останавливает загрузку этого slot. Recovery допускает только полный предыдущий валидный checkpoint.

Rolling upgrade negotiation доказывает только wire/state compatibility. Право записи всё равно передаётся через C17 authority migration и epoch fencing; совместимость версий никогда не разрешает multi-writer.

Observability ограничена фиксированными metric names. Audit не содержит payload и связан checksum chain, поэтому эксплуатационная диагностика не превращается во второй источник item state или утечку содержимого операций.
