# C15 — Executable Utilities and Machines

**Статус:** ACCEPTED
**База:** принятый C14 Structural Integrity and Load Paths
**Рекомендуемая ветка:** `feature/c15-executable-utilities-machines`

## Цель

Перевести семантические utility-состояния C7 в исполнимые потоки ресурсов. C7 отвечает на вопрос, существует ли и структурно доступна ли сеть. C15 отвечает на вопрос, сколько ресурса реально дошло до конкретного потребителя в текущем simulation tick.

```text
C7 semantic utility topology
+ sources / consumers / storage / links
+ demands and priorities
        ↓
C15 deterministic allocation
        ↓
losses / storage / load shedding
        ↓
checksum-pinned machine utility lease
        ↓
C8 reserve / progress / complete
```

## Поддержанные utility kinds

- `POWER`, единица `KWH` на tick;
- `WATER`, единица `L` на tick;
- `AIR`, единица `M3` на tick;
- `HEAT`, единица `MJ` на tick;
- `DATA`, единица `MB` на tick.

Единицы нормализованы на simulation tick. Физическая длительность tick задаётся более высоким runtime-слоем и не входит в C15 DTO.

## Network model

Сеть содержит строгие JSON-safe определения:

- `SOURCE` — генератор или внешний ввод;
- `CONSUMER` — конкретная точка потребления;
- `STORAGE` — аккумулятор, бак, буфер или кэш;
- `JUNCTION` — шина, коллектор или маршрутизатор;
- двусторонние links с capacity и loss fraction.

Каждая сеть pin-ит `construct_id`, revision и checksum исходной конструкции. Изменение topology требует новой версии network definition.

## Allocation

Demand задаёт:

- requested amount;
- minimum required amount;
- priority;
- shed group;
- consumer node.

Demand обрабатываются по убыванию priority и затем по ID. Если реально достижимая доставка меньше minimum, пробная маршрутизация откатывается полностью и demand получает `SHED`. Это исключает скрытый расход ресурса на потребителя, который всё равно не способен работать.

Статусы allocation:

- `FULL` — доставлен весь request;
- `PARTIAL` — minimum выполнен, request выполнен не полностью;
- `SHED` — minimum не выполнен, доставка равна нулю.

## Losses и routing

Для каждого source-consumer path рассчитывается произведение эффективностей links. Capacity применяется к потоку на входе каждого link, поэтому downstream links получают уже уменьшенный поток. Profile хранит:

- source injection;
- delivered amount;
- path efficiency;
- flow и loss каждого link;
- суммарный loss сети.

При нескольких маршрутах выбирается детерминированный наиболее эффективный путь, затем более короткий и затем лексикографически минимальный.

## Storage

Storage state хранит amount, capacity, tick и revision. На tick:

1. storage может разряжаться после обычных sources;
2. расход учитывает discharge efficiency;
3. после обслуживания demands остаток source capacity заряжает storage;
4. заряд ограничен link capacity, max charge и charge efficiency;
5. следующий state получает новую revision.

Storage state входит в execution profile и может быть транзакционно сохранён profile store.

## Execution profile

`ConstructionUtilityExecutionProfile` содержит:

- source construct и network checksums;
- tick;
- allocations;
- source dispatch;
- link flows;
- новые storage states;
- total requested/delivered/loss/unserved;
- статус `BALANCED`, `DEGRADED`, `SHEDDING` или `OFFLINE`.

Profile является rebuildable simulation projection. Он не меняет C7 snapshot и не создаёт отдельную identity ресурса.

## C8 machine lease

C15 не переписывает C8 fabrication transactions. Вместо этого перед вызовом C8 создаётся `ConstructionMachineUtilityLease`, pin-ящий:

- C8 machine profile checksum;
- recipe checksum;
- job ID;
- utility execution profile checksums;
- конкретные allocation checksums;
- tick;
- maximum work units.

`max_work_units` выводится из фактически доставленного ресурса и `units_per_work_unit`. Если allocation shed или ниже minimum ratio, lease имеет `OFFLINE` и нулевую производительность.

## Executable fabrication runtime

C15 wrapper разрешает C8:

- reserve только при online/degraded lease;
- progress не больше capacity lease;
- complete только при валидном lease.

Operation ID progress pin-ит lease checksum. Exact replay возвращает terminal result без второго увеличения progress. Другой payload с тем же operation ID отклоняется.

После restart runtime state восстанавливает:

- использованные work units каждого lease;
- terminal operation results;
- generation.

Authoritative расход сырья и выпуск результата по-прежнему выполняются C8 через C2A/C2B.

## Контрольный сценарий

Power network содержит generator, battery, bus, CNC machine и lighting:

```text
generator --5%--> bus --5%--> machine
battery   --2%--> bus --10%-> lighting
```

Высокоприоритетный CNC demand получает полный ресурс. Остаток generator и battery обеспечивает lighting частично. При недостатке minimum demand атомарно shed. При отключённом generator battery поддерживает critical load, затем сеть переходит OFFLINE после разряда.

C8 job получает два utility lease по двум tick: первый разрешает 6 work units, второй оставшиеся 4. Попытка выполнить 5 units при остатке capacity 4 отклоняется без изменения job. При отсутствии реального POWER allocation материалы не резервируются.

## Acceptance profile

```text
C15 contracts:    PASS — 92 assertions
C15 integration:  PASS — 123 assertions
C15 total:        PASS — 215 assertions
```

Локально повторно пройдены C1–C8 и C10–C14. Полные C2B, C9, Network N0–M4, world regression и main scene остаются внешним acceptance gate.

Ожидаемый world profile после добавления двух тестов C15:

```text
131/131 tests
134 steps
```
