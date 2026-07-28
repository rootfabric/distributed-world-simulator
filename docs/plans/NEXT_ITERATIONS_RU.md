# Ближайшие итерации после v16.7.0-repository-r3.1-authoritative-recovery

## Текущий gate — R3.1 authoritative recovery

R3.1 сохраняет authoritative snapshot, revision/epoch/tick, Item Graph, operation ledger, command dedup и reconnect replay records в атомарном versioned checkpoint. Crash после commit возвращает cached result без второй мутации; orphan pending checkpoint не активируется.

## Следующий этап — N3 World Directory

```text
branch: feature/n3-world-directory
checkpoint: v16.8.0-network-n3-world-directory
```

N3 должен реализовать:

- регистрацию simulation nodes;
- heartbeat и health;
- authority region descriptors;
- lease issuance/renewal/expiration;
- route lookup;
- node draining;
- fencing старого authority owner по epoch.

Acceptance: два simulation-server регистрируются в Directory, один регион имеет ровно одного writer, клиент получает правильный endpoint, а expired/stale lease больше не разрешает mutation.

После N3:

```text
N4 cross-process authority handoff
→ N5 ghost replicas / interest management
```
