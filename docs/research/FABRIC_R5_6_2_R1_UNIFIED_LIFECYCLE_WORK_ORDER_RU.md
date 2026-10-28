# FABRIC R5.6.2 R1 — Unified Physical Event Lifecycle / Process Restart

**Статус:** IMPLEMENTER CANDIDATE, не приёмка и не merge.
**Risk:** HIGH (journal / persistence / recovery semantics).
**Точный родитель:** R5.6.1 R2 PR #784, HEAD `60f193d6602d2d6ebb62393d3db6633b14623627`, TREE `1a92363e7cc159fef4c42e3443542ebb00a71464`.
**Реализация:** `research/fabric-r5-6-2-r1-unified-lifecycle-r1`, stacked на R2, до закрытия #784 не интегрировать.
**Собственность:** Construction/Matter/Authority — canonical; FABRIC — исключительно восстановимый derived consumer.
**R5.6.2 R1 не является продуктовым R6 и не меняет `main`.**

## Problem statement и Design Brief

В R5.6.1 R1 и R2 существуют раздельные рабочие сессии для bond mutation и part/mass mutation. Их event IDs живут в памяти и не восстанавливают общую историю после restart. Присоединение нового сеанса к последнему Construction snapshot восстанавливает численные значения, но не доказывает порядок событий и не разрешает неоднозначность «owner committed, observer crashed before ACK».

Выбрано: **bounded, checksummed, append-only derived journal** с полным replay каждого proposal через уже проверенные R1/R2 контракты. Изменения записывает исключительно внешний `ConstructionConstructStore.apply_mutation`. Журнал содержит начальный source, первоначальные применённые event IDs, список подтверждённых намерений, максимум одно pending-намерение и хеши неизменяемых Matter/Authority.

**Уточнение R1.1:** логическая модель journal остаётся канонически хешируемым DTO; crash fixture сохраняет бинарное представление Godot Variant через `FileAccess.store_var(value, false)` / `get_var(false)`, а не JSON. Это необходимо для точного сохранения всех бит Float64. Binary Variant не заявлен как совместимый со всеми версиями движка/платформами протокол внешнего хранения. После каждой физической мутации новый Fenwick строится из точного канонического источника, то есть R1 сознательно допускает **O(N)** rebuild. Ускорение совместного bond+part индекса — не данный срез.

Отклонённые альтернативы:

- FABRIC-владелец мутаций или второй authoritative event registry — конфликт собственности.
- «Exactly once» только по event ID в оперативной памяти — неверно после restart.
- Автоматически принимать любой более новый snapshot после сбоя — стирание неизвестного damage / конкурентных изменений.
- Делать UNBAKE/REBAKE источником истины — угроза восстановлению уже committed повреждения.

## Обязательная последовательность вызывающей стороны

```text
1. bootstrap/recover(store, matter, authority)
2. prepare_bond / prepare_part  -> PREPARE_NOT_DURABLE, physics BLOCKED
3. durable save pending journal -> mark_prepared_durable
4. EXTERNAL Construction Store owner apply_mutation / durable owner checkpoint
5. make_ack_journal validates actual owner successor, prepares next record
6. durable save ACK journal
7. adopt_persisted_ack -> exact journal replay and index rebuild, physics READY
```

Недопустимо применять owner mutation до шага 3 или публиковать derived physics до шага 7. Метод `mark_prepared_durable` проверяет переданный хеш, **но сам не подтверждает fsync**: барьер реализует и доказывает вызывающая сторона / storage adapter. Test fixture пишет отдельные бинарные файлы DTO (без разрешения инстанцирования объектов), вызывает `FileAccess.flush()` и заново создаёт `ConstructionConstructStore` через `load_dict`. Это проверяет сериализацию и восстановление приложения; не доказывает POSIX fsync директории, полную устойчивость к отключению питания или atomic transaction двух независимых хранилищ.

Crash matrix:

| Последний внешний эффект | Owner snapshot | Восстановление | Physics |
| --- | --- | --- | --- |
| Pending сохранён, owner ещё не изменился | BEFORE | `PENDING_OWNER` | BLOCKED |
| Owner применил mutation, ACK не записан | AFTER | `OWNER_COMMITTED_PENDING_ACK` | BLOCKED |
| ACK записан, consumer ещё не опубликовал | AFTER | replay `READY` | разрешена после проверки |
| Owner применил другой successor | NEITHER | `R562_OWNER_DIVERGED` | BLOCKED |
| Повтор того же mutation | CAS precondition fail | никакого второго commit | без повторной публикации |
| Journal изменён/переделан event ID | checksum/replay fail | отказ | BLOCKED |

## Входные операции и границы

Общий поток `BOND`: `BREAK_BOND`, `REPAIR_BOND`, `SET_BOND_STRENGTH`; `PART`: `MOVE_PART`, `TRANSFER_MASS`. Допускается до 16 событий и не более 512 деталей. Сохраняется исходный MatterBatch: перенос массы внутри конструкции, не создание/уничтожение вещества. Авторитет/epoch неизменен внутри журнала. Поддержаны повторное повреждение после ремонта и нумерически непрезентабельный COM без публикации unsafe descriptor. Конкретная стоимость полной canon validation, graph compilation, replay и indexed rebuild НЕ O(log N).

Journal checksum — **deterministic integrity, not cryptographic proof of owner intent**. Без externally durable owner transaction/receipt с уникальным event ID нельзя объявлять end-to-end exactly-once при произвольной конкуренции/сбоев серверного хранилища. В данном R1 гарантируются replay refusal, Construction CAS, exact-successor reconciliation и fail-closed semantics внутри заявленной модели доверия. R5.6.2 R2 должен разработать связанный durable owner receipt + fault-injection power/process crash протокол до появления production claims.

## Files / разрешённый scope

- `scripts/research/fabric_bake0/r5_6_2_r1_event_lifecycle_v1.gd`
- `tests/research/fabric_bake0/fabric_r5_6_2_r1_lifecycle_acceptance.gd`
- `scripts/research/fabric_bake0/collect_r5_6_2_r1_evidence.py`
- `RUN_FABRIC_R5_6_2_R1_TESTS.{sh,ps1}`
- Этот Work Order и отдельная evidence-документация.

Запрещены изменения Construction/Matter/BRIDGE-4, R5.1–R5.5, продуктовой сети, `main`, canonical owner и engine pins. Движок для exact: Godot `4.7.1.stable.double.custom_build.a13da4feb`, Linux SHA `bfa7ce...7d`, Windows console SHA `3633c3...5a15a7a5`.

## Acceptance и falsification

1. Два независимых расположения (18/25 деталей), исходная Construction Store операция CREATE.
2. По каждому layout последовательность **BREAK → MOVE → TRANSFER_MASS → REPAIR → BREAK** (всего 10 owner mutations) и восстановление из файла до owner commit, после owner commit / до ACK и после ACK (30 derived restart, 20 Cold Store reconstructions).
3. 42 файловых побитно-сохраняющих roundtrip: журналы PREPARE/ACK и owner Store BEFORE/AFTER; COUNT + replay journal полностью совпадают с canonical revision.
4. Независимый FULL-расчёт point-mass COM, массы и 9 элементов inertia после каждого изменения.
5. После owner update старый derived descriptor недоступен; idempotency/CAS, tampering, post-rehash ID forgery, чужой/missing owner и изменённый authority отклоняются.
6. 3 детерминированных прогона нового теста + R1/R2/COM/BRIDGE-4 регрессии на точном published HEAD, collected checksums/identity before-after; Linux exact и Windows exact отдельно.
7. Свежие независимые Reviewer и Verifier (не implementer), по необходимости repair → fresh retest, PC0/directional audit и явное разрешение на слияние исследовательской ветки.

## Nonclaims / следующий этап

Пока нет произвольных component splits и межвладельческих Matter транзакций, наблюдаемой 6DOF динамики, атомарной файловой схемы для production, гарантий от power loss, сервера exactly-once, мультиплеера, релиза, R5 CLOSE или R6. Следующий срез R5.6.2 R2: owner receipts/outbox, durable process-kill fault matrix с конкурентными mutations, при необходимости компактный journal/checkpoint compaction, затем R5.6.3 coupled physics. SHIP-LAB-1 остаётся отдельным полигоном: PR #730 — план, не физическая реализация.


## R1.1 Repair Map — 21 октября 2026: import / lossless cold recovery

### Воспроизведённые RED и независимые факты

- Windows exact на исходном HEAD `65975d7bc58a2999d661d0d83f023c5cac6f854a` и TREE `3916f4e4aa49689cadb168e3091cce41e04274fa`: **FAIL** на первом `--editor --import`. Счётчик инвентарных global classes ещё не готов, тогда как ранний игровой/editor startup уже требует `InventoryContainerPanel` и другие типы; старое `user://worlds/moon-experiment-001` не изолировано. Доказательство: [Windows report](https://github.com/rootfabric/distributed-world-simulator/pull/800#issuecomment-6315422895). Все последующие стадии не выполнялись.
- Linux exact на исходном HEAD: `import=PASS`, `parse-lifecycle=PASS`, `lifecycle-1=FAIL` ([run 39557187488](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39557187488), artifact 12333362746). Первый owner cold-load: `CONSTRUCT_STORE_CHECKSUM_MISMATCH`; следующий отказ — `R562_PHYSICS_NOT_READY`.
- Воспроизведено на локально распакованном canonical Linux Godot (SHA256 `bfa7ce...57d7`). Причина checksum: даже полный вывод `JSON.stringify(..., full_precision=true)` не гарантирует Godot JSON.parse_string 1:1 для Float64 (конкретно `9.600000000000001` восстанавливается как `9.6`). Источник — R1 test storage adapter, **не** Construction canonical owner.
- После перехода crash-fixture на safe Variant binary + подтверждения точной хеш-парности: локальный focused Godot `616/0`, 10 owner commits, 30 reconstructed sessions, 42 file roundtrips, 14 FULL independent oracles, 72 negatives; **это implementer local smoke, не canonical CI exact и не независимый verdict**.
- Дополнительный leak/root cause: `_seal_pending` хранил внутри себя Callable, захватывавший `self`, что создавало цикл RefCounted при промежуточном restart. Захват изменён на immutable params без ссылки на `self`; повторная локальная проверка `616/0`, без leak-warning на exit.
- Linux import `--recovery-mode` затем обычный `--import` на чистом кэше: оба завершились с exit=0, без SCRIPT ERROR; затем тот же новый focused test `616/0`. На Windows такой двухфазный bootstrap пока **не подтверждён**.

### Канонический узкий repair

| Модуль | Владелец и граница | Правка |
| --- | --- | --- |
| R5.6.2 R1 test | derived research-only evidence | Binary Variant write/read, no arbitrary Object construction, exact owner hash validation |
| R5.6.2 R1 runtime | derived-only pending provenance | Захват только immutable prepare identity, без RefCounted cycle |
| Windows runner | test environment only | Fresh `.godot`, strict recovery-mode import, strict ordinary import, временные `APPDATA`/`LOCALAPPDATA` под evidence-dir, restored in finally |
| Linux runner | test environment only | Fresh `.godot`, strict 2-stage import, isolated `XDG_DATA_HOME`/`CONFIG_HOME`/`CACHE_HOME` |
| Strict collector | independent evidence parsing | Оба import logs теперь обязательны и проверяются на ошибки |

НЕ изменены: `project.godot`, inventory UI, network runtime, game boot, Construction/Matter, R1/R2 base, исходные тестовые пороги и разрешения на merge.

### R1.1 acceptance / ограничения

Новый точный HEAD/TREE, strict Windows и Linux — отдельные свежие прогоны; старый FAIL не переименовывать. Если Windows даже после recovery-bootstrap продолжает запускать игру или открывать реальный профиль, это **FAIL** и узкий следующий repair должен запретить side-effects, а не скрыть их. Публикация result/hash/exact runner до обновления decision. Reviewer отдельно проверяет сериализацию, циклы self-capture, компрометацию pending, scheduler, TOCTOU и факт изоляции user://.
