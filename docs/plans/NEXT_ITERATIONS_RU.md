# Ближайшие итерации после v16.6.0-network-n2-process-harness

## Текущий gate — N2 process harness

Ветка: `feature/n2-process-harness`.

N2 объединяет N1.1–N1.3 process fixtures в один manifest-driven runner:

- динамические UDP-порты;
- отдельные server/client `user://`;
- readiness и per-scenario timeout;
- проверка terminal report и process exit code;
- гарантированная cleanup-ветка;
- success и expected-failure сценарии;
- stdout/stderr, JSON и JUnit.

Acceptance: все сценарии классифицированы точно, после каждого запуска нет живых дочерних процессов, полный сетевой профиль и world regression проходят.

## Следующий этап — R3.1

```text
branch: feature/r3.1-authoritative-recovery
target: v16.7.0-repository-r3.1-authoritative-recovery
```

R3.1 сохраняет authoritative snapshot, revision/epoch, operation ledger и replay/dedup records. Повторный `operation_id` после server restart должен вернуть прежний terminal result без второй мутации.

После R3.1:

```text
N3 World Directory и authority leases
→ N4 cross-server authority handoff
→ N5 ghost replicas и interest management
```
