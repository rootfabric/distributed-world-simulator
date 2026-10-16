# FABRIC R5.5 R4 — Narrow Source-Binding Repair

## Причина блокировки R3

На frozen R3 `325e5986…` независимый Reviewer обнаружил обход source admission.
Злоумышленник мог изменить runtime `_prepared_successor.spec.expanded_bond_digest`,
пересчитать `spec.checksum` и одновременно изменить `_prepared_successor_hash`.
Предыдущая проверка сравнивала два изменяемых значения друг с другом.
`Source.is_successor()` валидирует корректность дешёвого checksum, но не
пересчитывает все 100000 bonds на каждом локальном событии. Поэтому R3 принимал
поддельный successor: событие завершалось commit, а `Source.validate_subject(committed, true)`
возвращал `COMPLEX3_BOND_DIGEST_MISMATCH`.

Исходный RED falsifier находится в ветке
`review/fabric-r55-r3-successor-binding-falsifier-r1` (не в продуктовой ветке).

## Узкое исправление R4

Для строго фиксированной канонической машины (100000 частей, один разрыв)
в R5.5 GDScript source закреплены три независимых от runtime-кэша свидетеля:

- Полный canonical successor subject hash: `30579f4208d5a033d3c6ad616702c44a271a6a4c1226d149ff05a325de7a7f3b`.
- Canonical successor spec checksum: `c6378b862ce376f9e32ad671701b10ce7ca5896d549fd6df21893f094bc633c3`.
- Canonical expanded bond digest: `c515ae265c9a236d428b2a0db9075b049596adfbd170b2ab94688274d9132080`.

Инициализация проверяет **сгенерированный** successor на соответствие всем трём
эталонам. На каждом локальном событии, до capture/attach/UNBAKE, R5.5
проверяет и фактический subject hash, и изменяемый cached hash относительно
**отдельного константного** canonical subject hash. Совместная подмена
payload + runtime witness теперь приводит к отказу
`R5_5_SUCCESSOR_PROVENANCE_MISMATCH`, а одноимённая подмена только payload
по-прежнему возвращает `R5_5_SUCCESSOR_CACHE_MUTATED`.

Расширенный digest 100000 связей не пересчитывается на пути локального
события. Полная проверка `Source.validate_subject(..., true)` существует
**в R4 regression-тесте после successful commit**, но не в production event.

## Red→Green contract

Новый `fabric_r5_5_r4_source_binding_acceptance.gd` покрывает:

1. Подделку expanded bond digest + пересчёт spec checksum + cached hash.
2. Подделку frontier и согласованного mutable cached hash.
3. Подделку bond_count и связанных checksum/hash.
4. Независимую подделку cached hash.
5. Отказ до создания структурного stage и полную сохранность live
   structural source/capsule, recursive root/sessions/bundles/hashes/counters.
6. Полное восстановление: ровно один commit, канонический bond digest и
   успешная независимая full 100k digest rederivation.
7. Запрет повторного local commit, нулевое полное построение successor
   на event-path.

R4 native runners (`RUN_FABRIC_R5_5_TESTS.ps1`/`.sh`) требуют R4 тест
наряду с существующими R5.5 3×35/0, adversarial 36/0, prefix matrix 208/0.
Закрытые ядра R5.1/R5.3/R5.4 и их штатные runner'ы не изменены.

## Границы гарантии

Это **только code-backed source provenance** фиксированной research 100k
one-bond машины. Изменение исполняемого кода, произвольная последовательность
topology-событий, гонки со злонамеренным одновременным изменением памяти,
универсальная immutable ROM, multi-event causal safety и production gameplay
остаются вне утверждений. В исходной реализации всё ещё есть инициализационные
O(N) расходы, глубокие копирования и прочие возможные неучтённые операции;
нет оснований объявлять универсальную O(local) стоимость всего event.

Перед merge обязательно: canonical Linux/Windows exact на опубликованном
новом HEAD/TREE, свежий Reviewer/Verifier, явное разрешение на merge только
в исследовательскую ветку. `main` не изменять.
