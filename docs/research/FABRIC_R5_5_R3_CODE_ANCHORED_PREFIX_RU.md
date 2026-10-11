# FABRIC R5.5 R3 — Code-anchored canonical prefix witness

## Мотивация

На R5.5 R2 (f6ef2070) проверка `_r5_query()` сверяла физический
prefix-индекс с `_trusted_endpoint_seals`, которые были обычным изменяемым
GDScript-словарём. Независимый Linux falsifier подтвердил: одновременная
подмена `prefix.mass[50007]` и соответствующего SHA-256 seal допускала commit;
`machine_hash` оставался равен каноническому, но физический derived capsule
отличался. R2 `100/100 prefix-only PASS` не покрывал эту атаку.

## Узкий repair R3

1. Для *конкретного* фиксированного генератора COMPLEX3 (ровно 100 000
   частей, один canonical break) значения **пяти используемых** endpoint-seals
   (0, 50000, 50007, 50020, 100000) зафиксированы непосредственно в
   исполняемых строковых литералах `Guard.canonical_endpoint_seal()`.
   Значения рассчитаны независимым canonical Godot 4.7.1 double через
   `Source.create_subject(100000,false)` + `RangeIndex.build()` и
   `Guard.endpoint_seal()` на неизменённом frozen R2.
2. Там же зафиксированы исходный `Source.spec.checksum` и канонический
   `expanded_part_digest` для защиты от ошибочного применения к другому
   source model. Неизвестные endpoint и несовместимый source **fail closed**.
3. В `initialize()` реальный источник и все пять вычисленных index seals
   должны совпасть с **независимыми литералами**, иначе инициализация
   отклоняется. Нет скрытого O(N) на пути локального события.
4. В guarded `_r5_query()` фактический endpoint seal и предоставленный
   mutable runtime-seal **оба** сравниваются с code-anchored свидетелем.
   Совместная подмена данных и runtime-seal более не обходит проверку.
5. Falsifier coverage: `10` физических моментов × `5` endpoint × две
   дельты = `100` prefix-only + `100` prefix+runtime-seal случаев.
   Прямой end-to-end тест требует полного отказа **до commit**, сохранения
   live/recursive state и успешного повторного commit после полного восстановления.
   Windows runner обязан проверять оба счётчика и отсутствие failures.

## Граница утверждения

Это **фиксированный code-backed witness** для точно известного физического
сценария, а не универсальная immutable-ROM реализация. Если злоумышленник
может менять исполняемый GDScript, оба якоря — код и данные — находятся в
одном домене доверия. Произвольные структуры, события, многопоточную гонку
между guard и чтением, повреждение неиспользуемых диапазонов и подмену
самих физических kernel-контрактов R3 не покрывает. Для новых геометрий
нужна отдельная аутентифицированная модель и независимые canonical anchors
либо формально проверяемый incremental Merkle root с доверенным владением.

Ограничение хранения структуры: хотя проверка двух endpoint делает
константное число чтений для этого события, precompute successor/index и
их копирование на стадии инициализации не становятся O(1).

### Acceptance

- Canonical R5.5 scripts: cold import / parse; focused ×3, adversarial,
  strict prefix matrix, deterministic hash и raw logs;
- неизменённые R5.4/R5.3 standalone exact suites + R5.1 regressions;
- fresh Windows exact на **новом R3 HEAD** после Linux;
- fresh независимый semantic review и verifier;
- PR остаётся DRAFT, merge — отдельный human gate. Main не изменять.
