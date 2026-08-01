# V17.5.0 — MW5 Matter Persistence fix5

## Статус

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery:   fix5
build_id:   mw5-matter-persistence-fix5
branch:     feature/mw5-matter-persistence
base:       MW5 fix4 candidate
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Независимый результат до fix5

```text
MW5 focused: FAIL
20 failures / 62 assertions / 30.538 s
```

Подтверждённый blocker: Godot JSON decimal roundtrip не сохранял некоторые binary64 values побитово.

```text
до JSON:     2026174.8885708766
после JSON:  2026174.8885708768
```

Из-за изменения одного ULP пересозданные snapshot, ledger и result имели корректную структуру, но другой checksum. Первый pending checkpoint завершался `MATTER_PENDING_VERIFY_FAILED`.

## Решение fix5

Введён transport schema:

```text
planet_simulator.matter_persistence_transport.v1
float_encoding: ieee754-binary64-le-hex
```

Scalar `TYPE_FLOAT` рекурсивно заменяется на:

```json
{"$matter_f64":"<16 lower-case hex digits>"}
```

Hex содержит точные восемь байт binary64. Integer-valued float также кодируется тегом, поэтому `1.0` не превращается в `int`. Непустые однородные float-массивы сохраняются одним `{"$matter_f64_array":"<16×N hex>","count":N}` для ограниченного размера snapshot-файла.

Файл содержит envelope:

```text
schema
float_encoding
payload
typed_checksum
checksum
```

`checksum` защищает transport envelope. `typed_checksum` — исходный checksum checkpoint/DTO; после decode exact binary64 values восстанавливаются и typed checksum вычисляется повторно.

Untagged fractional JSON numbers внутри payload запрещены. Старый untagged MW5 candidate format отклоняется fail-closed.

## Изменения runtime

- `MatterPersistenceCodec.encode_persistence_json()` строит exact binary64 transport envelope.
- `MatterPersistenceCodec.decode_persistence_json()` проверяет envelope checksum, декодирует float tags и проверяет typed checksum.
- `MatterStateRepository` читает checkpoint только через transport decoder.
- Process-level worker переносит replay request через тот же transport codec.
- Checksum-domain MW0–MW4 не изменён.

## Focused coverage

Добавлены проверки:

- exact roundtrip значения `2026174.8885708766`;
- сохранение `TYPE_FLOAT` для `1.0`;
- отсутствие decimal float в persistence bytes;
- stale envelope checksum;
- изменённые float bits с пересчитанным envelope checksum;
- запрет untagged fractional JSON numbers;
- exact ledger total после process-safe transport;
- snapshot/result/ledger/batch rehydration;
- raw active-file bytes равны output encoder;
- process restart и exact replay.

Фактическая assertion topology должна быть зафиксирована по первому successful independent run.

## Не изменено

- MW4 mutation semantics;
- sparse brick/revision contracts;
- generation chain;
- active/previous/pending atomic publication;
- Moon runtime;
- production world catalog;
- network authority.

## Требуемая regression-матрица

```text
MW5 focused:     PASS до watchdog
MW4 regression:  187/187 PASS
MW3 regression:  7519/7519 PASS
MW2 regression:  7470/7470 PASS
MW1 regression:  3685/3685 PASS
MW0 regression:  2011/2011 PASS
A3 regression:   PASS
M6 regression:   10/10 PASS
git diff --check: PASS
```
