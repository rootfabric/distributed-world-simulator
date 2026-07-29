# Checkpoint v16.9.0 fix1 — S1 Distributed Compute hardening

Статус: **candidate**
Checkpoint: `v16.9.0-simulation-s1-distributed-compute-fix1`
Build ID: `s1-distributed-compute-contracts-fix1`
Ветка: `feature/s1-distributed-compute-contracts`
База разработки: `v16.8.5-domain-m0-aggregate-transactions`

## Контракт поставки

Для checkpoint публикуется консолидированный архив:

- `v16.9.0-simulation-s1-distributed-compute-fix1-full-patch.zip`;
- apply base: `v16.8.5-domain-m0-aggregate-transactions`;
- архив содержит весь S1 и hardening fix1;
- архив должен самостоятельно накладываться на чистую M0-базу.

Предыдущий 46-файловый архив fix1 является только review-delta поверх:

```text
53e2644 feat(simulation): add distributed compute contracts
```

Он не является самостоятельной поставкой от M0 и не должен использоваться для чистой установки checkpoint.

## Причина fix1

Первый S1 candidate проверял самосогласованность job/result, но authority принимала job обратно от вызывающей стороны. Worker мог изменить `to_tick` или расширить write set, пересчитать публичные hashes и получить authoritative commit.

Также network contract не доказывал точную эквивалентность `projected_state` объявленному read set и не связывал write-set identity с authoritative aggregate.

## Исправлено

- добавлен локальный authority-issued job registry;
- `SimulationJobFactory` обязательно регистрирует canonical job в authority;
- `accept_result()` принимает только result и извлекает issued job по `job_id/job_attempt`;
- proposal/result содержат `job_checksum`;
- добавлены `COMPUTE_JOB_NOT_ISSUED`, `COMPUTE_JOB_CHECKSUM_MISMATCH`, `COMPUTE_JOB_CONFLICT`;
- fingerprint связывает job type, capability, read-set hash и write-set hash;
- exact projection validation отклоняет лишние и отсутствующие projected fields;
- input references обязаны точно соответствовать read-set entries;
- write-set kind/schema сверяются с input и текущим authoritative snapshot;
- S1 protocol v1 отклоняет CREATE/DELETE и разрешает только UPDATE;
- финальная строка network runner исправлена с M0 на S1.

## Новые негативные gates

- result для невыданного job;
- повторная выдача того же job attempt с другим checksum;
- forged job с изменённым `to_tick`;
- forged job с расширенным write set;
- дополнительное projected field;
- отсутствующее declared projected field;
- дополнительный input reference;
- write-set kind/schema mismatch;
- CREATE/DELETE в protocol v1;
- exact result replay после потерянного ACK.

При отказе forged result не изменяются:

- M0 generation;
- authoritative state checksum;
- aggregate snapshot checksums;
- state revision;
- server tick;
- outbox count.


## Результаты проверки

Использован `Godot 4.7.1.stable.double.custom_build.a13da4feb`, Linux x86_64, double precision.

```text
S1 contracts:                 64/64 PASS
S1 integration:             147/147 PASS
S1 total:                   211 assertions
Network foundation profile:  37/37 suites PASS
Network assertions:        3060/3060 PASS
World manifest:               80/80 tests PASS
World runner equivalent:      83/83 steps PASS
Main scene:                     6 PASS, 0 FAIL
```

Тяжёлые runtime-сценарии:

```text
Unified runtime boot:            PASS, exit 0
World switch during generation: PASS, exit 0
World boot matrix:              PASS, exit 0
```

Runtime-роли `offline`, `listen-host` и `simulation-server` завершили по 6/6 тестов с exit 0. Для `simulation-server` подтверждено `active_presentation_nodes: 0`.

PowerShell отсутствовал в Linux-среде проверки. Выполнены эквивалентные шаги runners: editor import, все объявленные Godot scripts, manifest coverage и main-scene CLI.


Статическая проверка:

```text
git diff --check:          PASS
JSON files:                37, errors 0
GDScript / UID:           364 / 364
Missing or duplicate UID:   0
Changed res:// references: 320, missing 0
Markdown links:              7, broken 0
Roadmap phases:             23, cycles 0
World tests:             80 / 80
Trailing whitespace:         0
CRLF in overlay:             0
Broker SDK dependencies:     0
```

## Следующий этап

После независимого принятия fix1 можно переходить к `B1 — NATS Core Service Adapter`. B1 должен использовать только B0 semantic ports и не переносить broker identity в S1/M0/domain contracts.
