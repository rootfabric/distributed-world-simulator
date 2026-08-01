# MW5 — сохранение и восстановление persistent matter-состояния

## Статус

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
base:       v17.4.0-simulation-mw4-matter-mutations / fix3
branch:     feature/mw5-matter-persistence
```

MW5 переводит изменения вещества из session-local состояния MW4 в durable checkpoint, который переживает полное завершение процесса Godot и восстанавливается без повторного применения операций.

## Сохраняемое каноническое состояние

Один checkpoint содержит согласованный снимок трёх компонентов:

1. `MatterSparseBrickStore` — только изменённые bricks с `state_revision >= 1` и полными checksum-protected snapshots; процедурные revision-0 caches не сериализуются и восстанавливаются из генератора;
2. `MatterMutationJournal` — исходные mutation requests и результаты, необходимые для точного replay и защиты от повторного применения;
3. `MatterMaterialReceiver` — committed `MatterMaterialBatch`, но не transient reservations.

Checkpoint дополнительно фиксирует:

- `body_id` и checksum определения тела;
- версию и seed генератора;
- checksum spatial grid;
- cell level;
- контейнер назначения;
- generation и server tick;
- checksum предыдущего checkpoint.

## Почему snapshot, journal и batch сохраняются вместе

Сохранение только SDF snapshots восстанавливает геометрию тоннеля, но теряет происхождение добытого вещества и идемпотентность операции. Сохранение только журнала потребовало бы заново выполнять каждое бурение при старте. MW5 сохраняет оба слоя:

```text
compacted current snapshots
+ exact mutation journal
+ extracted material batches
```

После восстановления:

- запрос к поверхности сразу видит сохранённый тоннель;
- повтор прежнего `operation_id` возвращает сохранённый результат;
- revision не увеличивается второй раз;
- Material Batch не дублируется;
- масса не создаётся повторно.

## Round-trip-safe transport и типизированное восстановление

Godot JSON не является побитовым transport для `float`: даже при full precision некоторые decimal values восстанавливаются в соседний binary64. Подтверждённый MW5 review-пример:

```text
до JSON:     2026174.8885708766
после JSON:  2026174.8885708768
```

Поэтому fix5 вводит отдельный versioned transport envelope:

```text
planet_simulator.matter_persistence_transport.v1
├── float_encoding: ieee754-binary64-le-hex
├── payload
│   ├── scalar TYPE_FLOAT → {"$matter_f64": "<16 lower hex digits>"}
│   └── homogeneous float array → {"$matter_f64_array": "<16×N hex>", "count": N}
├── typed_checksum
└── checksum                 envelope checksum
```

`PackedByteArray.encode_double()` кодирует исходный binary64 в восемь байт; scalar хранится как 16 hex-цифр. Непустые однородные массивы `float` упаковываются в один counted tag из `8 × count` байт, чтобы snapshot channels не разрастались до тысяч маленьких JSON-объектов. Integer-valued float `1.0` также получает float tag и после восстановления остаётся `TYPE_FLOAT`. Обычные integer fields сохраняются JSON numbers и по-прежнему ограничены безопасным диапазоном `2^53 - 1`. Untagged fractional JSON numbers внутри payload запрещены.

Порядок записи:

```text
strict typed DTO + valid typed checksum
→ recursively replace every float with exact bit tag
→ build transport envelope
→ compute envelope checksum over tagged payload
→ canonical JSON bytes
```

Порядок чтения:

```text
parse JSON envelope
→ validate envelope schema/encoding/checksum
→ decode every exact binary64 tag
→ require original typed checksum
→ strict checkpoint/component/DTO validation
```

Это разделяет две явно определённые границы:

- transport checksum защищает exact persistence representation и framing;
- существующий DTO checksum защищает восстановленное canonical matter state.


Межпроцессный context также не имеет права переносить координаты через decimal JSON. Но геометрический центр swept capsule не является доказательством существования полости: narrow-band mutation может оставить SDF в этой точке отрицательным. После commit acceptance-контур сканирует interior lattice изменённых snapshots, выбирает детерминированный sample с `occupancy_ratio = 0` и `signed_distance_m > 0`, затем подтверждает его через canonical continuous query. Его позиция и pre-save SDF упаковываются в checksummed payload `planet_simulator.mw5_process_witness.v1` и сохраняются в `AtomicJson` как строка `witness_transport`, созданная тем же `MatterPersistenceCodec`. Decimal coordinates и прежний недоказанный `center_transport` запрещены.

Transport не меняет checksum-domain MW0–MW4 и не требует пересчёта существующих matter checksums. Он гарантирует, что до typed checksum verification доходят ровно те же binary64 values, которые участвовали в исходном checksum. Старый untagged MW5 candidate format fail-closed отклоняется; checkpoint MW5 ещё не принят, поэтому migration path не требуется.

`MatterPersistenceCodec` после transport decode продолжает восстанавливать DTO через canonical constructors:

- composition;
- brick snapshot;
- mutation request;
- mutation result и mass ledger;
- material batch.

`MatterBrickSnapshot` восстанавливается непосредственно в persisted columnar representation. Codec не разлагает его на samples и не пересобирает palette, поэтому channel arrays, palette order и binary64 bits остаются неизменными.

Focused acceptance включает конкретный regression probe `2026174.8885708766` с фактическим результатом Godot `PackedByteArray.encode_double()` `886179e3beea3e41`, integer-valued float `1.0`, actual ledger totals, snapshot channels, result, batch и checkpoint. Проверяются также: stale envelope checksum, модифицированные float bits при пересчитанном envelope checksum, запрет untagged fractional numbers и byte-identical равенство файла результату `encode_persistence_json(checkpoint).to_utf8_buffer()`.

## Формат durable checkpoint

```text
planet_simulator.matter_persistence_checkpoint.v1
├── generation
├── previous_checkpoint_checksum
├── body/generator/grid identity
├── store_state
│   └── sorted mutated snapshots
├── receiver_state
│   └── sorted committed batches
├── journal_state
│   └── sorted request/result records
└── checksum
```

Cross-link validation требует:

- каждый changed brick committed-результата существует в store на той же или более новой revision;
- каждый созданный batch существует в receiver;
- `source_operation_id` batch совпадает с journal record;
- orphan batches запрещены;
- transient reservations запрещены в checkpoint.

## Атомарный repository

Repository использует три класса файлов:

```text
matter-state.json                     active committed checkpoint
matter-state.previous.json            предыдущий committed checkpoint
.matter-state.<pid>.<ticks>.pending.json prepared, но ещё не committed
```

Публикация:

1. checkpoint сериализуется в уникальный pending-файл;
2. pending перечитывается и полностью валидируется;
3. active переименовывается в previous;
4. pending атомарно переименовывается в active;
5. active повторно перечитывается и проверяется.

Незавершённый pending не становится авторитетным. При повреждении или отсутствии active repository загружает последний валидный previous checkpoint, а coordinator до изменения in-memory компонентов восстанавливает из него новый authoritative `matter-state.json`. После такого recovery generation chain может продолжать запись; система не остаётся навсегда привязанной к fallback-файлу. Источник восстановления явно сообщается как `PREVIOUS` или `PREVIOUS_RECOVERY`.

## Generation chain

Каждый новый checkpoint обязан иметь:

```text
generation = previous.generation + 1
previous_checkpoint_checksum = previous.checksum
server_tick >= previous.server_tick
```

Identity тела, генератора, spatial grid, cell level и контейнера внутри одной цепочки менять нельзя. Изменение генератора требует явной миграции, а не неявной загрузки старого мира.

## Recovery coordinator

`MatterStateCoordinator`:

1. загружает последний committed checkpoint;
2. проверяет body/generator/grid identity относительно текущего runtime;
3. предварительно валидирует все три component states;
4. при fallback восстанавливает authoritative active-файл из валидного previous;
5. сохраняет резервные component states;
6. восстанавливает snapshots, batches и journal;
7. при неожиданном отказе применения выполняет компенсирующий rollback всех трёх компонентов;
8. сверяет component content hashes;
9. возвращает generation, источник и pending diagnostics.

Операции не reexecute-ятся. Mutation service после восстановления получает уже заполненные store/receiver/journal и обслуживает точный replay обычным MW4-путём.

## Интеграция лаборатории

Существующая сцена `matter_asteroid_excavation_lab.tscn` теперь использует MW5 repository по адресу:

```text
user://matter-labs/asteroid-mw5
```

Порядок запуска лаборатории:

1. создать MW4 mutation service;
2. восстановить последний committed checkpoint до конфигурации query/streamer;
3. при несовместимости или повреждении без валидного previous остановиться fail-closed;
4. после каждого committed drill сохранить следующую generation;
5. только затем считать операцию durable в UI.

Если disk publication не удалась, каноническая операция остаётся committed в текущей памяти, но UI явно помечает её как `not durable`. Это не маскируется как успешное сохранение. Полностью объединённый mutation+disk transaction относится к последующему authoritative persistence layer.

## Process-level acceptance

Focused-профиль запускает два независимых процесса Godot:

```text
process A:
    create asteroid → drill → save checkpoint → exit

process B:
    fresh components → load checkpoint → query tunnel → replay operation
```

Приёмка требует:

- сразу после mutation найден и canonical query подтверждает детерминированный witness с `signed_distance_m > 0`;
- witness position и pre-save SDF проходят exact binary64 process transport;
- после полного restart query в той же точке возвращает точно тот же SDF;
- только после exact equality положительный witness считается доказательством сохранённого тоннеля;
- replay checksum совпадает;
- store, receiver и journal hashes до/после replay неизменны;
- batch count и journal size не увеличиваются;
- generator mismatch отклоняется до изменения in-memory state;
- pending checkpoint не становится active;
- corrupted active восстанавливается из previous.

## Граница этапа

MW5 не добавляет:

- сетевой authority или cross-server commit;
- incremental append-only journal files;
- background compaction scheduler;
- частичную загрузку отдельных planetary regions;
- production Item Graph persistence adapter;
- интеграцию изменяемой породы в Луну;
- deposition, fracture и loose matter.

Checkpoint пока записывается одним JSON transport-envelope. Это intentionally bounded решение для лабораторного астероида и проверки семантики recovery. Шардинг, binary/columnar brick files и compaction относятся к следующему storage-scaling этапу.
