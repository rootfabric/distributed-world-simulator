# FABRIC R5.2 / T13 — Shared Compiled Instances

Статус: **IMPLEMENTED / EXACT GATE PENDING**. Research-only; canonical owners не меняются.
База: T12 merge `c60960bee48aa7cc68a9035cff86d5567f6c89fc`.

## Цель

T13 проверяет следующий уровень после Ship Matryoshka: один и тот же immutable
compiled model должен обслуживать много одинаковых физических экземпляров без
повторной компиляции модели на каждый object.

Acceptance обязан доказать лестницу **1 → 10 → 100** экземпляров, при этом:

- compiled T12 Ship создаётся fixture-компилятором ровно один раз;
- T13 runtime выполняет `prepare()` ровно один раз;
- каждый объект получает собственный `InstanceBinding` и caller-owned `InstanceState`;
- все binding указывают на один `compiled_model_checksum`;
- 100 binding имеют уникальные checksum и world slot;
- execution не обходит source leaves и не вызывает compiler;
- повреждение одного экземпляра не меняет compiled model;
- остальные 99 экземпляров дают byte-equivalent результат относительно healthy control.

## Разделение model / binding / state

`CompiledModel` — verified T12 Ship bundle и один prepared compact runtime.
При `prepare()` T13 делает **ровно одну deep copy** compiled bundle и дальше
использует её как внутренний frozen model. Identity задаётся T12 capsule checksum,
canonical hash этой frozen bundle и state signature. Instance hot path не копирует
и не canonical-hash'ит полный compile graph; полный hash используется как отдельный
integrity audit до/после масштабного прогона.

`InstanceBinding` содержит только instance identity, world slot, checksum общей
compiled model, state signature и собственный checksum. Он не копирует дерево
T12 и не создаёт фиктивные новые source identities.

`InstanceState` содержит binding checksum, model checksum, revision counters,
instance-only damage overlay и собственное T12 physical state. Физическое
состояние остаётся caller-owned: execute получает snapshot и возвращает новое
состояние, не мутируя переданный Dictionary.

## Damage isolation

Для T13 damage — намеренно ограниченный **instance-level disable overlay**.
Он не является новой моделью разрушения корпуса, брони или деталей. При disable
команды emitter маскируются в ноль, servo удерживает текущую позицию, а существующая
T12 физика продолжает считать battery/cooling/energy boundary.

Acceptance создаёт две ветви из одного baseline для 100 объектов:

1. healthy control;
2. тот же набор, но `instance-042` получает damage revision 1.

Для 99 незатронутых объектов next state и physical result должны совпасть с
control точно. Повреждённый объект обязан отличиться. `prepare_count` остаётся
1, `recompile_events` остаётся 0.

## Масштабный exact gate

Один процесс выполняет:

- prefix из 1 instance;
- prefix из 10 instances;
- prefix из 100 instances;
- затем 100 healthy control + 100 damage-isolation steps.

Итого 311 T13 instance execution steps на одной compiled model. Все они должны
сохранить `leaf_traversals = 0`. Runtime-work не скрывается: collector сохраняет
solver evaluations, child boundary calls и compact battery-group visits.

Три отдельных процесса canonical Linux double Godot должны вернуть один и тот же
result payload и deterministic SHA-256. Дополнительно неизменённый T12 acceptance
запускается как regression.

## Что T13 не заявляет

T13 не является production object registry, ECS, multithread scheduler,
network replication или полноценной damage physics. Он доказывает более узкий
архитектурный контракт: **compiled executable identity отделена от instance
binding/state**, поэтому одинаковая сложная вещь не требует отдельного compile
graph на каждый экземпляр.
