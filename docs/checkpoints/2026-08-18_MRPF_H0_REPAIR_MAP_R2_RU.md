# MRPF-H0 — Reviewer Repair Map R2

**Дата:** 2026-08-18  
**Ветка:** `research/mrpf-h0-contracts`  
**Pre-repair reviewed HEAD:** `d82546ccd54cbe8f5551788196ac831ce172b7c8`  
**Risk:** `MEDIUM`  
**State:** `FIX_REQUIRED / REPAIR R2`

## 0. Источник findings

Fresh independent Reviewer вернул `FAIL` на exact pre-repair HEAD и выявил два blocking contract defects:

```text
MRPF-H0-R-001
removal уничтожает resident identity/revision fence;
after remove возможны stale resurrection и higher-revision identity rebind.

MRPF-H0-R-002
"|"-concatenation не является однозначным canonical encoding;
unknown input fields проходят validation, попадают в output, но не участвуют в checksum/view hash.
```

Verifier после этого корректно вернул `INSUFFICIENT_EVIDENCE`, так как Reviewer PASS отсутствовал; verifier runtime не является repair evidence.

## 1. Repair R2 goal

Закрыть оба класса дефектов в canonical H0 contract/ingest surfaces, а не только добавить тесты.

## 2. R-001 root cause map

### Affected module

`scripts/runtime/seamless/mrpf/mrpf_h0_hierarchical_composer.gd`

### Canonical ingest path

`accept_representation()`

### Lifecycle path

`remove_representation()`

### Root cause

Immutable binding и revision fence извлекались только из `_representations`, то есть из active payload storage.

```text
accept -> resident payload contains identity/revision memory
remove -> payload erased
next accept -> representation_id appears new
```

Поэтому removal случайно удалял не только presentation payload, но и protocol memory.

### Canonical repair

Разделить:

```text
active payload storage
        !=
identity/revision ledger
```

Добавить sticky H0-lifetime ledger per `representation_id`:

```text
immutable_identity_binding
max_accepted_source_revision
last_accepted_checksum
```

Правила:

```text
identity binding mismatch -> reject always, resident or removed
revision < max_seen       -> reject
revision == max_seen:
    resident + exact checksum -> idempotent replay
    resident + changed payload -> same-revision mutation reject
    removed/tombstoned         -> reject; removal must not be undone by delayed replay
revision > max_seen + same immutable identity -> legitimate reactivation/update allowed
```

`remove_representation()` удаляет только active payload; ledger остаётся.

Replacement-group contract в H0 также остаётся sticky на lifetime composer instance. Это намеренно fail-closed и предотвращает group identity reuse после удаления всех members. GC/generation semantics — H1+ contract, не H0 implicit behavior.

## 3. R-002 root cause map

### Affected modules

```text
mrpf_h0_projection_contract.gd
mrpf_h0_hierarchical_composer.gd::_view_hash
```

### Root cause A — ambiguous encoding

Полевая tuple сериализовалась через delimiter concatenation:

```text
"|".join(fields)
```

Поскольку string fields допускают `|`, разные tuples могут иметь одинаковую pre-hash byte/string representation.

### Root cause B — open DTO surface

`validate()` проверял required known fields, но не запрещал unknown keys. Composer сохранял `value.duplicate(true)`, следовательно неизвестный field мог менять composed output без изменения checksum/view hash.

### Canonical repair

1. Сделать DTO **closed**: exact allowed input keys only.
2. Проверять exact scalar types для contract fields.
3. Заменить delimiter encoding на однозначное typed length-prefixed encoding.
4. `checksum()` должен покрывать весь semantic input DTO кроме самого `checksum`.
5. `view_hash` должен строиться из детерминированно sorted selected representations через тот же canonical representation encoding/checksum semantics, а не собственную delimiter tuple.
6. Composer-generated `selected_specificity` является deterministic derived output от hashed `domain_level`; он не является independent input field.

## 4. Focused regression additions

Обязательные новые тесты:

```text
accept rev2 -> remove -> stale rev1 rejected
accept original -> remove -> forged higher revision same id rejected
rejected post-remove attempts preserve coarse fallback
same revision delayed replay after remove cannot resurrect
legitimate newer revision with same binding after remove accepted
unknown field rejected
pipe-boundary collision pair produces different checksums
canonical encoding remains stable for delimiters/newlines/unicode
view hash differs when semantic representation differs
```

## 5. Non-goals / scope guard

Repair R2 не добавляет:

```text
network protocol
source epoch/restart protocol
persistence
authority transfer
ClientConnectionSet
H1 processes
production V0 integration
```

`source_epoch`/publisher restart semantics остаются explicit H1+ design item. H0 только гарантирует monotonic revision within one composer/identity-ledger lifetime.

## 6. Acceptance after repair

После runtime repair:

```text
new exact candidate HEAD
fresh Godot focused PASS on exact branch blobs
Project Control SUCCESS/non-RED
fresh independent Reviewer from scratch
then fresh independent Verifier
```

Review на `d82546c...` считается stale for repaired runtime by definition and не переносится на новый HEAD.
