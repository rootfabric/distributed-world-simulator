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
