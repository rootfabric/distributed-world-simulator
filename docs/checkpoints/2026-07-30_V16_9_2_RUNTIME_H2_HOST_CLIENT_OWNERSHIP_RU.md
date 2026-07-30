# Checkpoint v16.9.2 — H2 host/client ownership

Статус поставки: candidate.

База: `v16.9.1-runtime-h1-playable-listen-host`.

Добавлено:

- authoritative `PlayerOwnershipRegistry`;
- replicated `PlayerOwnershipReplicaStore`;
- replay-safe join/leave;
- stable player identity across reconnect;
- ownership epoch fencing;
- отдельные ENet host/client process probes;
- негативные проверки spoofed/stale session, parallel owner, operation replay conflict, checksum tampering и revision rollback.

Acceptance gate:

```text
host player join
remote client join
ownership snapshot replicated
remote leave
remote rejoin on new transport session
same player entity ID
ownership epoch 1 -> 2
no duplicate player aggregate
host remains connected
```
