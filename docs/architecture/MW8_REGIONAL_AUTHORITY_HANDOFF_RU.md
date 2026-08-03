# MW8 — межсерверная передача authority и regional handoff

## Статус

```text
checkpoint: v17.8.0-simulation-mw8-regional-authority-handoff
base:       v17.7.0-simulation-mw7-matter-interest-replication (ACCEPTED)
branch:     feature/mw8-regional-authority-handoff
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

MW8 переводит принятый MW7 regional interest слой из режима «один writer на всё тело» в первый ограниченный multi-server authority-контур. Этап не является распределённой транзакцией общего назначения: одна mutation обязана полностью принадлежать одной зарегистрированной authority-region.

## Основной инвариант

Для каждой cell-region в каждый момент существует ровно один lease:

```text
(region_id, owner_id, authority_epoch, lease_revision, status)
```

Команда разрешена только когда lease имеет состояние `ACTIVE`, а owner/epoch совпадают с сервером, который собирается вызвать `MatterExcavationService.execute()`.

## Двухфазный handoff

```text
ACTIVE(source, epoch N)
        |
        | begin_handoff CAS
        v
PREPARING(source frozen, target not active)
        |
        | source package -> target shadow import -> proof
        v
ACTIVE(target, epoch N+1)
```

### Freeze

`MatterAuthorityDirectory.begin_handoff()` переводит lease в `PREPARING`. После этого:

- source gate отвечает `MATTER_AUTHORITY_HANDOFF_IN_PROGRESS`;
- target gate отвечает `MATTER_REGION_NOT_OWNED_BY_SERVER`;
- ни один сервер не может выполнить новую mutation региона;
- параллельный transfer для того же региона отклоняется.

### Prepare

Source endpoint формирует exact-transport пакет:

- все persistent snapshots региона с `state_revision >= 1`;
- journal records, чьи target bricks полностью лежат в регионе;
- связанные `MatterMaterialBatch`;
- source stream frontier;
- checksum определения тела и spatial-grid profile;
- checksum регионального состояния.

Target импортирует пакет в рабочие компоненты под компенсационным backup:

```text
store_state
receiver_state
journal_state
```

До directory commit target gate остаётся закрытым. При любой ошибке import/rebase восстанавливаются все три backup-компонента, а source lease возвращается в `ACTIVE`.

### Commit

Directory принимает prepared package checksum и target state hash, затем одним lease-переходом меняет:

```text
owner_id:        source -> target
authority_epoch: N -> N+1
status:          PREPARING -> ACTIVE
```

Source сохраняет старые данные как read-only исторический кэш, но больше не имеет command authority. Удаление/compaction старой копии не входит в MW8.

## Защита от split-brain

- authority regions не могут пересекаться;
- directory отклоняет смешанные cell levels до появления формальной иерархической overlap-политики;
- повтор transfer ID считается replay только при полном совпадении source/target fingerprint;
- смешанные cell levels в directory запрещены;
- второй одновременный transfer одного региона отклоняется;
- target epoch обязан быть строго больше source epoch;
- source и target gates каждый раз читают authoritative directory lease;
- после commit old owner немедленно теряет право записи;
- stale source epoch не может начать новый transfer.

## Региональный пакет

Контракт `planet_simulator.matter_handoff_package.v1` использует MW5 exact binary64 transport для всех float-bearing DTO. Внешний пакет содержит только строки transport, JSON-safe integers и hashes.

Target принимает пакет только при совпадении `body_definition_hash`, `grid_profile_hash`, frozen lease revision, source owner/epoch и region transport.

`regional_state_hash` покрывает:

- region checksum;
- sorted snapshot address/revision/checksum entries;
- sorted operation/request/result checksum entries;
- sorted material batch checksum entries.

Procedural revision-0 bricks не передаются.

## Journal frontier и exact replay

После import target authority выполняет `rebase_from_service_state()`:

```text
stream_sequence = imported journal size
replay_log = empty
state_hash = current target components
```

Поэтому операция, завершённая до freeze, после handoff разрешается из перенесённого journal как exact replay и не создаёт второй delta или Material Batch.

## Client regional handoff

После commit coordinator выпускает checksum-protected `MatterClientHandoffTicket`:

- source/target owner и epoch;
- target endpoint;
- region transport;
- package checksum;
- directory revision.

Клиент завершает старую session, создаёт MW7 replica с target owner/epoch и получает filtered `REGION_SNAPSHOT` нового сервера. Перенос transport session и автоматический socket redirect остаются integration-задачей следующего этапа.

## Ограничение cross-region mutations

Mutation, чьи `target_bricks` принадлежат нескольким authority-regions, отклоняется:

```text
MATTER_CROSS_REGION_MUTATION_REQUIRES_COORDINATION
```

Это намеренная граница. Distributed prepare/commit для одной операции, затрагивающей несколько серверов, не входит в MW8.

## Изменения существующего MW6/MW7 runtime

`MatterAuthoritativeServer` получил опциональный command gate, безопасный rebase из уже импортированного service state и идемпотентную отписку replication observer. Без установленного gate поведение MW6 остаётся прежним.

`MatterInterestServer.shutdown()` разрывает observer-связь с authority и очищает transient projection state. MW8 focused harness вызывает shutdown для source и target, закрывая lifecycle-рекомендацию MW7.

## Не входит в MW8

- consensus/RAFT для authority directory;
- durable directory и crash recovery между prepare/commit;
- cross-region mutation transaction;
- автоматический network socket redirect;
- перенос физически движущихся fragments;
- NATS adapter;
- production Moon integration;
- удаление исторической source-копии после handoff.
