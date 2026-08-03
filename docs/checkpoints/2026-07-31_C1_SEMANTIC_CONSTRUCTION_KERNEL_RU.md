# C1 Semantic Construction Kernel

```text
base_commit: 2879fdb7134032f645ffc5c98c0535aecfc09caf
recommended_branch: feature/c1-semantic-construction-kernel
status: ISOLATED_CANDIDATE
integration: deferred until multiplayer foundation completion
```

## Что реализовано

- архитектурная парадигма стройки нового уровня;
- отдельная дорожная карта C0–C13;
- строгие part/bond/snapshot contracts;
- item-backed ConstructAggregate;
- revision и operation replay fencing;
- deterministic snapshot и SHA-256 checksum;
- capability compiler;
- стол как первый vertical slice;
- повреждение связи и пересчёт rigid islands/capabilities.

## Граница

Этот этап намеренно не изменяет текущий multiplayer runtime, canonical M4 Item Graph service, UI, network DTO или persistence. Он является изолированным доменным кандидатом для дальнейшего review.

## Проверка

```text
Godot: 4.7.1.stable.double.custom_build.a13da4feb
editor parse: PASS
C1 construction contracts: PASS (26 assertions)
C1 construct aggregate: PASS (40 assertions)
focused total: 2/2 tests, 66 assertions
```

Полный regression актуального repository tree не запускался: GitHub checkout недоступен из рабочего контейнера. Проверка выполнена в минимальном проекте с оригинальным `network_contract_utils.gd` и целевыми новыми файлами. Перед merge требуется прогнать focused profile и полный repository regression на локальном checkout пользователя.
