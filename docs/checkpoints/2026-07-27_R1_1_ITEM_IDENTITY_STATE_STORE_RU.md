# Чекпоинт R1.1 — постоянная идентичность и ItemStateStore

Дата: 27 июля 2026 года
Версия: `v15.6.2-r1.1-fix2`

## Цель

R1.1 создаёт первый слой постоянного предметного aggregate до добавления
операционного журнала, физической политики разных миров и полного контейнерного
сохранения R1.4.

Главный контракт этапа:

> Новый предмет получает глобальный неизменяемый ID, его состояние имеет
> версию схемы, полный SpatialRef переживает JSON round-trip, а Item Registry
> можно сохранить и загрузить через абстракцию ItemStateStore.

## Реализовано

### Глобальные ID

Новые экземпляры получают криптографический UUID v4:

```text
item/xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
```

где `y` принадлежит диапазону `8..b`.

ID больше не зависит от локального счётчика, типа предмета, порядка запуска,
конкретного runtime или сервера. Человекочитаемое имя хранится отдельно в
`ItemInstance.display_name`.

Старые ID вида `rock_000001` при загрузке legacy snapshot сохраняются без
перенумерации. Это предотвращает разрушение существующих ссылок контейнеров и
сборок. Новые предметы после такой загрузки уже получают UUID. Полная атомарная
миграция всех внешних ссылок запланирована на R1.4.

### Версионирование

Добавлены схемы:

```text
planet_simulator.item_instance.v2
planet_simulator.item_registry.v2
planet_simulator.item_state_file.v1
```

`ItemRegistry.load_dict()` теперь:

- проверяет схему и точную версию;
- отклоняет неизвестную старую или будущую versioned-схему;
- проверяет дубли ID, определения, количество, revision, relation, components и SpatialRef;
- загружает данные транзакционно;
- не меняет активный registry при ошибке;
- сообщает список legacy ID.

Локальное поле `sequence` больше не сохраняется и не используется.

### ItemStateStore

Добавлен порт:

```text
scripts/items/persistence/item_state_store.gd
```

и файловая JSON-реализация:

```text
scripts/items/persistence/json_item_state_store.gd
```

Поддерживаются:

- `save_state`;
- `load_state`;
- `delete_state`;
- `has_state`;
- временный файл, full-precision JSON и rename при записи;
- создание каталога;
- защита ключей от path traversal;
- fail-closed ошибки для отсутствующего, повреждённого или несовместимого файла.

Хранилище пока сохраняет переданный versioned state. Полный предметный граф с
Container Registry, attachment/socket state и operation ledger будет собран в
единый snapshot на R1.4.

### SpatialRef

WORLD relation теперь сохраняет:

- `frame_id`;
- `universe_id`;
- `space_id`;
- `instance_id`;
- позицию;
- ориентацию;
- линейную скорость;
- угловую скорость;
- `sample_time_s`.

`capture_world_state()` обновляет физическое состояние, но не сбрасывает
контекст системы отсчёта в `scenario/local`. Представление при восстановлении
также получает угловую скорость.

### Совместимость представления

UUID содержит `/`, поэтому ID больше не назначается Node name напрямую.
Presentation system создаёт безопасное локальное имя узла, сохраняя исходный ID
в metadata и доменном registry.

При разделении стека новый экземпляр наследует `display_name` источника.
Стеки с разными индивидуальными именами не объединяются автоматически.

## Тестовый барьер

Добавлен тест:

```text
res://tests/items/test_item_identity_and_state_store.gd
```

Он проверяет:

1. 256 глобальных UUID и отсутствие коллизий;
2. канонический UUID v4 format;
3. отдельное display name;
4. JSON round-trip Item Registry v2;
5. сохранение ID, revision, components и relation;
6. чтение legacy snapshot;
7. отказ от генерации последовательных ID после legacy load;
8. транзакционный отказ для старой/будущей версии и невалидного v2 ID;
9. отказ от нулевого quantity, отрицательной revision и повреждённого definition;
10. fail-closed проверку SpatialRef в versioned WORLD relation;
11. полный SpatialRef JSON round-trip;
12. сохранение coordinate context при capture physics state;
13. безопасное Node name;
14. ItemStateStore save/load/delete/exists и overwrite;
15. корректный путь для корня `user://`;
16. блокировку path traversal и скрытых файловых ключей;
17. fail-closed поведение повреждённого JSON.

Тест включён в:

```powershell
.\RUN_ITEM_SYSTEM_TESTS.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Общий regression manifest теперь содержит 26 тестов.

## Не входит в R1.1

Сознательно оставлено следующим этапам:

- `expected_revision` и persistent operation ledger — R1.2;
- gravity environment и рекурсивная физическая масса — R1.3;
- единый snapshot Items + Containers + Attachments + Entities — R1.4;
- автоматическая перенумерация legacy ID во всём графе — R1.4;
- gameplay inventory и ray interaction — R2.

## Критерий приёмки

R1.1 принят, когда:

```powershell
.\RUN_ITEM_SYSTEM_TESTS.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

завершаются успешно на double-precision Godot, а повторная загрузка сохранённого
registry возвращает тот же UUID, display name, revision и полный SpatialRef.

## Корректировка v15.6.1-r1.1-fix1

После первого запуска полного regression-runner обнаружено, что числовые массивы
`SpatialRef` создавались как типизированные `Array[float]`. После JSON-декодирования
Godot возвращает обычные `Array`; значения оставались теми же, но полное сравнение
словаря relation корректно обнаруживало несовпадение метаданных контейнера.

Исправление:

- persistence payload `SpatialRef` теперь использует только нетипизированные JSON-safe массивы;
- строгая проверка полного relation payload сохранена;
- тест дополнительно фиксирует контракт типа массивов;
- `RUN_ITEM_SYSTEM_TESTS.ps1` предпочитает console-сборку Godot и автоматически
  выбирает соседний `.console.exe`, даже если передан путь к GUI executable.


## Корректировка v15.6.2-r1.1-fix2

Fix1 устранил типизацию трёх векторных массивов, но строгий round-trip тест
продолжал находить неканоничное значение в полном `relation` payload. Причина
оказалась шире одного поля: доменный aggregate принимал Variant-контейнеры в
форме, которая могла содержать типизированные массивы и другие метаданные, не
сохраняемые JSON.

Исправление fix2:

- введён единый `ItemRelations.canonicalize()` через full-precision JSON round-trip;
- любой relation при входе в `ItemInstance` становится JSON-каноничным;
- операции перемещения сравнивают и сохраняют канонический relation;
- `capture_world_state()` проходит через тот же доменный boundary;
- `rotation_xyzw` формируется отдельным JSON-safe `Array`;
- тест проверяет все массивы `SpatialRef` и compatibility-поля;
- при любом будущем несовпадении тест печатает рекурсивный путь, типы и значения;
- строгая проверка полного relation payload не ослаблена.

R1.1 считается принятым только после зелёного запуска item-runner и полного
regression-runner с checkpoint `v15.6.2-r1.1-fix2`.
