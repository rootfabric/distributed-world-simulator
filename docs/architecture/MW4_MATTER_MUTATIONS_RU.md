# MW4 — транзакционное бурение и локальные persistent mutations

## 1. Назначение

MW4 впервые переводит каноническое вещество из режима только чтения в режим авторитетного изменения. Этап остаётся изолированным лабораторным потоком астероида и не изменяет текущую поверхность Луны, production world catalog или сетевой runtime.

Checkpoint:

```text
v17.4.0-simulation-mw4-matter-mutations
```

Ветка:

```text
feature/mw4-matter-mutations
```

База:

```text
v17.3.0-simulation-mw3-local-meshing / fix2
```

## 2. Граница этапа

MW4 добавляет:

- swept-capsule excavation;
- точное планирование affected bricks;
- expected-revision fences;
- атомарную запись нескольких sparse snapshots;
- локальное сохранение mutations в активной world session;
- идемпотентный operation journal;
- Material Batch как выход добычи;
- mass/energy/capacity validation;
- continuous query и SDF raycast поверх сохранённых snapshots;
- выборочную пересборку MW3 mesh/collision;
- отдельную playable laboratory scene.

MW4 не добавляет:

- сохранение на диск и restart recovery — MW5;
- network authority и cross-server commit — MP0/MP1;
- deposition, compaction, fracture и loose matter;
- раскалывание астероида — MW6;
- интеграцию с Moon runtime;
- production Item Graph adapter.

`MatterMaterialBatch` уже является каноническим DTO будущего Item Graph adapter, но в MW4 хранится локальным material receiver.

## 3. Каноническая операция

Инструмент не отправляет последовательность сфер, зависящую от FPS. Запрос содержит swept capsule:

```text
start_position_m
end_position_m
radius_m
```

Для точки `p` вычисляется расстояние до сегмента инструмента. Внутри инструмента и в локальной полосе шириной в один sample spacing применяется булево вычитание:

```text
if tool_sdf <= sample_spacing:
    new_sdf = max(old_sdf, -tool_sdf)
else:
    new_sdf = old_sdf
```

Полоса согласована с ghost-expansion target planner. Она сохраняет точную поверхность полости, не переписывая глубинные distance-значения далеко от бура. Одна команда одинаково обрабатывает медленное и высокоскоростное движение между двумя состояниями инструмента.

## 4. Планирование bricks

`MatterSweptShape`:

1. строит AABB swept shape;
2. расширяет его на одну mutation-полосу и ещё на одну ghost-полосу;
3. переводит диапазон в индексы cells выбранного уровня;
4. создаёт stable `SimulationCellAddress`;
5. создаёт и сортирует `MatterBrickAddress`.

Сервис повторно вычисляет набор адресов и требует полного совпадения с запросом. Клиент не может скрыть затронутый brick или добавить посторонний.

## 5. Транзакционный pipeline

```text
MatterMutationRequest
        ↓
exact replay / fingerprint conflict
        ↓
body + operation + target-set validation
        ↓
expected revisions
        ↓
procedural or stored source snapshots
        ↓
SDF difference for all affected samples
        ↓
removed mass/composition integration
        ↓
energy and receiver capacity preview
        ↓
receiver reservation
        ↓
MatterMassLedger
        ↓
atomic multi-brick snapshot commit
        ↓
Material Batch commit
        ↓
operation journal commit
        ↓
MatterMutationResult
```

Любая ошибка до commit оставляет store, receiver и journal неизменными. Ошибка receiver/journal после snapshot write вызывает компенсирующий rollback. Если сам rollback не подтверждён, сервис возвращает отдельный terminal error вместо сокрытия частичного состояния.

## 6. Revision rules

Для каждого changed brick:

```text
current_revision == expected_revision
new_revision == expected_revision + 1
```

Несовпадение хотя бы одного brick отклоняет всю операцию.

`MatterSparseBrickStore.put_many_atomic()` сначала валидирует весь набор и только потом изменяет состояние. Частичная запись отсутствует.

## 7. Stable replay

`MatterMutationJournal` хранит:

```text
operation_id
exact request DTO
request checksum
exact result DTO
```

Поведение:

```text
same operation_id + exact request → exact prior result
same operation_id + different DTO → MATTER_OPERATION_FINGERPRINT_CONFLICT
```

Replay не увеличивает revision, не создаёт второй batch и не меняет content hash.

## 8. Масса

Удалённая масса оценивается только по interior cubes каждого brick. Ghost samples участвуют в геометрии и нормалях, но не создают двойной материальный учёт.

Для каждой interior cube используется corner integration SDF occupancy. Масса распределяется по исходному composition каждого corner sample.

Ledger:

```text
input:  asteroid matter account, per material
output: destination container, per material
```

Операция может получить статус `COMMITTED` только при закрытом per-material ledger.

## 9. Энергия

Для каждого материала каталог задаёт:

```text
mining_energy_j_kg
```

Требуемая энергия:

```text
sum(material_mass_kg × mining_energy_j_kg)
```

Недостаточный budget отклоняет операцию до изменения snapshots и receiver.

## 10. Material Batch

```text
MatterMaterialBatch:
    batch_id
    container_id
    source_body_id
    source_operation_id
    total_mass_kg
    bulk_volume_m3
    composition
    temperature_k
```

Receiver v1 использует политику `FULL_OR_REJECT` и два лимита:

- mass capacity;
- bulk volume capacity.

Partial acceptance намеренно не реализована: она потребует отдельной семантики частичного swept cut и нового transaction contract.

## 11. Local persistence

В MW4 persistent означает:

> Изменённый snapshot остаётся источником истины после выгрузки и повторной сборки presentation bricks в пределах активной world session.

Не сохраняются:

- generated mesh;
- collision shape;
- камера и presenter nodes.

После повторной загрузки MW3 streamer читает сохранённый snapshot и пересоздаёт mesh/collision. Дисковый journal и restart recovery относятся к MW5.

## 12. Continuous query

MW2 сохраняет строгий lattice query без скрытого snapping. MW4 добавляет отдельный API:

```text
MatterContinuousQueryService.sample(position, level)
MatterContinuousQueryService.raycast(...)
```

Если brick сохранён, используется trilinear interpolation его samples. Иначе остаётся процедурный MW1 fallback.

Этот API позволяет:

- найти изменённую поверхность;
- направить следующий проход бура;
- проверить, что тоннель является vacuum;
- не зависеть от presentation collision lag.

## 13. Presentation integration

`MatterLocalMeshStreamer` получил необязательный snapshot store.

При build:

```text
stored snapshot exists → mesh stored revision
otherwise              → materialize procedural revision 0
```

После commit сервис передаёт changed brick addresses в:

```text
invalidate_brick_addresses()
```

Только затронутые presenters удаляются и ставятся в очередь повторной сборки.

## 14. Лаборатория

```text
res://scenes/labs/matter_asteroid_excavation_lab.tscn
```

Управление:

```text
Left mouse  canonical swept drill
WASD        движение
Q / E       вниз / вверх
Shift       ускорение
Esc         мышь
F           взгляд на +X поверхность
```

Лаборатория отображает:

- количество stored mutated bricks;
- извлечённую массу;
- operation count;
- состояние streamer;
- последний commit/rejection.

## 15. Инварианты приёмки

1. One-brick и cross-brick dig фиксируются атомарно.
2. High-speed path представлен одной capsule.
3. Exact replay не мутирует состояние.
4. Fingerprint conflict отклоняется.
5. Stale revision отклоняет всю транзакцию.
6. Недостаток энергии и capacity не изменяет snapshots.
7. Mass ledger закрыт по каждому материалу.
8. Tunnel center возвращает vacuum через continuous query.
9. Rebuild использует stored snapshot, а не procedural base.
10. Fault-injected post-commit journal failure полностью откатывает snapshots, batch и reservations.
11. MW0–MW3, A3 и M6 regressions остаются PASS.


## 16. Fix1: performance boundary focused-профиля

Первичная independent review остановила MW4 focused-процесс после 600 секунд: процесс продолжал использовать CPU, но не достиг следующего результата. Причина оказалась алгоритмической, а не физической сложностью сценариев.

Старый `MatterBrickSnapshot.sample_at()` при каждом чтении sample выполнял полную валидацию всего snapshot из 1331 samples, включая canonical JSON и SHA-256. В результате проход excavation имел фактическую форму:

```text
1331 lattice reads × full 1331-sample snapshot validation
```

Continuous raycast умножал этот расход ещё на восемь corner reads каждого trilinear sample.

Fix1 вводит явную границу доверия:

```text
untrusted DTO
    → one full MatterBrickSnapshot.validate()
    → sample_at_validated() / sample_payload_at_validated()
    → hot linear lattice loop
```

Гарантии сохраняются:

- публичный `sample_at()` остаётся fail-closed и полностью валидирует snapshot;
- validated-accessors разрешены только после явной полной проверки snapshot;
- columnar validator повторяет ratio, property, vacuum/occupied и composition semantics; flags остаются массивом и канонизируются при выдаче `MatterSample`;
- новый snapshot после mutation снова проходит полную checksum-protected валидацию;
- raycast кэширует и валидирует каждый stored brick один раз на операцию.

Focused fixture также устранён от дублирующей работы без потери сценариев:

- cross-brick capsule детерминированно планирует четыре bricks вместо случайного 16-brick центрального пересечения;
- streamer повторно использует уже committed cross-brick tunnel, а не исполняет вторую такую же транзакцию;
- streamer загружает одну целевую cell и сравнивает stored/procedural mesh именно для центра тоннеля;
- single-cell fixture кэшируется;
- каждый тестовый этап печатает `START`, `DONE` и длительность.

Runner имеет внешний watchdog: 300 секунд по умолчанию, exit code `124` при timeout. Значение можно увеличить явно, но зависший gate больше не остаётся бесконечным процессом.

## 13. Каноническая граница больших чисел

Все числовые поля mutation DTO проходят `MatterContractUtils.validate_json_safe()`.
Для integer-valued `float` действует предел IEEE-754/JSON:

```text
maximum_safe_integer = 9007199254740991 = 2^53 - 1
```

Поэтому MW4 не использует `1e18` или `1e19` как энергию команды: такие значения
выглядят конечными в double precision, но не имеют безопасного целочисленного
JSON-представления и отклоняются с `NON_CANONICAL_JSON_VALUE`.

Текущие лабораторные значения:

```text
energy_budget_j:         9000000000000000
receiver maximum_mass:   9000000000000000
unsafe boundary fixture: 9007199254740992 → reject
```

Отрицательный focused-тест дополнительно проверяет точный путь ошибки:

```text
$.matter_mutation_request.energy_budget_j
```

Это ограничение относится к транспортному и хэшируемому представлению, а не к
физическому максимуму будущей энергетической системы. Если simulation потребует
значений выше безопасного диапазона, контракт должен перейти на явное
масштабированное целое, десятичную строку или составную единицу — но не на
небезопасный integer-valued JSON number.
