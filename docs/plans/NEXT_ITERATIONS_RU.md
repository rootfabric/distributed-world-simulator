# Ближайшие итерации после v16.5.2-foundation-network-n1

## Текущее состояние

```text
N1.0 transport boundary                   принято
N1.1 ENet handshake + initial snapshot   принято
N1.2 authoritative item command          принято
N1.3 reconnect + bounded replay          current candidate
```

## Текущий gate — принять N1.3

Ветка: `feature/n1-reconnect-replay`.

Acceptance:

- потеря первого результата после commit воспроизводится;
- два reconnect создают три уникальные transport sessions;
- logical session и `operation_id` сохраняются;
- domain handler, mutation и ledger вызываются ровно один раз;
- cached result/delta возвращаются дважды;
- клиент применяет delta один раз;
- bounded cache/TTL/conflict/resume-limit тесты проходят;
- полный network/world regression зелёный.

## Следующий этап — N2

Ветка после принятия N1.3:

```text
feature/n2-process-harness
```

Target checkpoint:

```text
v16.6.0-network-n2-process-harness
```

Результат N2 — один кроссплатформенный runner, который запускает реальные Godot server/client процессы на динамических портах, выдаёт им isolated `user://`, управляет readiness/timeouts/cleanup, выполняет fault scenarios и пишет JSON/JUnit.

После N2:

```text
R3.1 authoritative persistence/recovery
→ N3 World Directory
→ N4 cross-server handoff
→ N5 ghost replicas
```

UI-I3 и новые крупные gameplay API не должны менять authoritative command semantics до принятия N2.
