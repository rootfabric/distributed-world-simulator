# Checkpoint v17.6.0 — MW6 matter network replication fix1

```text
checkpoint: v17.6.0-simulation-mw6-matter-network-replication
delivery: fix1
build_id: mw6-matter-network-replication-fix1
base_delivery: initial MW6 candidate
branch: feature/mw6-matter-network-replication
status: CANDIDATE FOR INDEPENDENT REVIEW
```

## Причина fix1

Исходный MW6 focused прошёл `130 assertions` за `34.415 s`, но обязательный полный A3-профиль дважды завершился в M6 process test с `MULTIPLAYER_DELTA_BASE_MISMATCH`. Standalone M6 при этом проходил `10/10`, что указывает на timing-sensitive ordering между gameplay delta и следующим полным snapshot.

## Исправлено

- delta, чей `target_revision` уже меньше current replica revision, fenced как `superseded replay`;
- same-revision checksum divergence получает явный `MULTIPLAYER_SAME_REVISION_MUTATION`;
- future base gap generic replica продолжает отклонять;
- M3/M6 graphical client на base gap входит в bounded `pending_replica_resync`;
- следующий валидный authoritative snapshot завершает resync и очищает transient error;
- client report публикует mismatch/resync counters;
- H3, M3 и M6 contracts покрывают superseded delta, настоящий gap и snapshot repair;
- M6 process acceptance проверяет отсутствие sticky mismatch и pending resync у обоих recovered clients.

## Не изменено

- MW6 matter command/replication contracts;
- `MatterAuthoritativeServer`;
- matter replication stream и reconnect protocol;
- MW5 binary64 transport;
- server M6 persistence/replay semantics;
- production Moon и world catalog.

## Требуемая проверка

```text
MW6 focused: 130/130 PASS
MW5: 142/142 PASS
MW4: 187/187 PASS
MW3: 7519/7519 PASS
MW2: 7470/7470 PASS
MW1: 3685/3685 PASS
MW0: 2011/2011 PASS
M6 standalone: 10/10 PASS
M6 process: expected 128 assertions PASS
A3 full profile: PASS три последовательных запуска
git diff --check: PASS
```

Три последовательных A3 PASS нужны, поскольку исходный дефект был timing-sensitive и не воспроизводился standalone M6 в каждом запуске.
