# FABRIC R5.6.2 R1 — Unified Physical Event Lifecycle / Process Restart

**Статус:** IMPLEMENTER CANDIDATE, не приёмка и не merge.
**Risk:** HIGH (journal / persistence / recovery semantics).
**Точный родитель:** R5.6.1 R2 PR #784, HEAD `60f193d6602d2d6ebb62393d3db6633b14623627`, TREE `1a92363e7cc159fef4c42e3443542ebb00a71464`.
**Реализация:** `research/fabric-r5-6-2-r1-unified-lifecycle-r1`, stacked на R2, до закрытия #784 не интегрировать.
**Собственность:** Construction/Matter/Authority — canonical; FABRIC — исключительно восстановимый derived consumer.
**R5.6.2 R1 не является продуктовым R6 и не меняет `main`.**

## Problem statement и Design Brief

В R5.6.1 R1 и R2 существуют раздельные рабочие сессии для bond mutation и part/mass mutation. Их event IDs живут в памяти и не восстанавливают общую историю после restart. Присоединение нового сеанса к последнему Construction snapshot восстанавливает численные значения, но не доказывает порядок событий и не разрешает неоднозначность «owner committed, observer crashed before ACK».

Выбрано: **bounded, checksummed, append-only derived journal** с полным replay каждого proposal через уже проверенные R1/R2 контракты. Изменения записывает исключительно внешний `ConstructionConstructStore.apply_mutation`. Журнал содержит начальный source, первоначальные применённые event IDs, список подтверждённых намерений, максимум одно pending-намерение и хеши неизменяемых Matter/Authority. После каждой физической мутации новый Fenwick строится из точного канонического источника, то есть R1 сознательно допускает **O(N)** rebuild. Ускорение совместного bond+part индекса — не данный срез.

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

Недопустимо применять owner mutation до шага 3 или публиковать derived physics до шага 7. Метод `mark_prepared_durable` проверяет переданный хеш, **но сам не подтверждает fsync**: барьер реализует и доказывает вызывающая сторона / storage adapter. Test fixture пишет отдельные JSON-файлы, вызывает `FileAccess.flush()` и заново создаёт `ConstructionConstructStore` через `load_dict`. Это проверяет сериализацию и восстановление приложения; не доказывает POSIX fsync директории, полную устойчивость к отключению питания или atomic transaction двух независимых хранилищ.

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
3. 42 файловых roundtrip: журналы PREPARE/ACK и owner Store BEFORE/AFTER; COUNT + replay journal полностью совпадают с canonical revision.
4. Независимый FULL-расчёт point-mass COM, массы и 9 элементов inertia после каждого изменения.
5. После owner update старый derived descriptor недоступен; idempotency/CAS, tampering, post-rehash ID forgery, чужой/missing owner и изменённый authority отклоняются.
6. 3 детерминированных прогона нового теста + R1/R2/COM/BRIDGE-4 регрессии на точном published HEAD, collected checksums/identity before-after; Linux exact и Windows exact отдельно.
7. Свежие независимые Reviewer и Verifier (не implementer), по необходимости repair → fresh retest, PC0/directional audit и явное разрешение на слияние исследовательской ветки.

## Nonclaims / следующий этап

Пока нет произвольных component splits и межвладельческих Matter транзакций, наблюдаемой 6DOF динамики, атомарной файловой схемы для production, гарантий от power loss, сервера exactly-once, мультиплеера, релиза, R5 CLOSE или R6. Следующий срез R5.6.2 R2: owner receipts/outbox, durable process-kill fault matrix с конкурентными mutations, при необходимости компактный journal/checkpoint compaction, затем R5.6.3 coupled physics. SHIP-LAB-1 остаётся отдельным полигоном: PR #730 — план, не физическая реализация.
