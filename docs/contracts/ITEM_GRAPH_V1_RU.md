# Item Graph v1

## Snapshot

`planet_simulator.item_graph.v1` сохраняет одним атомарным bundle:

```text
Item Registry v2
Container Registry v2
Attachment sockets v1
Operation Ledger v1
Metadata runtime
```

Это единица восстановления предметного мира. Отдельная загрузка только контейнеров или только предметов запрещена, поскольку временно создаёт dangling references.

## Транзакционная загрузка

Загрузка выполняется в новом staged domain. В нём последовательно проверяются схемы, ID, контейнеры, слоты, attachment sockets, operation ledger и полный relation graph. Live domain заменяется только после прохождения всех проверок.

Ошибки, включая отсутствующий item, двойное membership, relation cycle, parent-container cycle и несовместимый слот, оставляют live state неизменным.

## Fail-closed recovery

Если сохранение существует, но повреждено, R2 может создать временный демонстрационный graph для запуска UI. Такой runtime помечается `persistence_blocked` и работает только для чтения сохранения: автоматическое или ручное сохранение не может перезаписать исходный повреждённый файл.

## Метаданные

Metadata содержит только данные представления runtime, например выбранный hotbar index и profile ID. Поля с семантикой `_index`, `_count`, `_revision` нормализуются обратно в integer после JSON parse.

## Физическое представление

Item graph хранит доменное состояние. `ItemRepresentationSystem` выводит из relation:

- `WORLD` → `RigidBody3D` и GravityBodyDriver;
- `CONTAINER` → физический узел отсутствует;
- `ATTACHMENT` → presentation на зарегистрированном socket anchor;
- `DESTROYED` → presentation отсутствует.

Поэтому физическое тело никогда не является вторым источником истины.
