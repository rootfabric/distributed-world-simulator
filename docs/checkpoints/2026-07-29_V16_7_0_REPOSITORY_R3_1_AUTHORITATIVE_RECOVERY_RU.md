# Checkpoint v16.7.0 — Repository R3.1 authoritative recovery

**Статус:** candidate для независимой Windows-проверки
**Build ID:** `r3.1-authoritative-persistence-crash-recovery`
**Ветка:** `feature/r3.1-authoritative-recovery`
**База:** `v16.6.0-network-n2-process-harness`

## Результат

R3.1 добавляет versioned authoritative checkpoint, атомарную repository commit-границу и восстановление command/replay state после restart.

Реализованы:

- строгий `AuthoritativeCheckpoint` с canonical checksum;
- active/previous/pending repository layout;
- progression fences generation/owner/epoch/revision/tick;
- persistence Item Graph, WORLD aggregate, ledger и gateway dedup;
- persistence bounded reconnect replay records без transport grants;
- transactional staged recovery;
- orphan pending diagnostics;
- corrupted active fail-closed;
- legacy world migration diagnostic;
- реальные process crash/restart tests.

## Acceptance-сценарии

```text
commit-crash
→ generation 2 recovered
→ same operation_id replayed
→ handler/mutation/ledger remain 1
```

```text
pending-crash
→ generation 1 recovered
→ pending generation 2 ignored
→ command executes exactly once
```

## Runner

```text
RUN_R3_AUTHORITATIVE_RECOVERY_TESTS.ps1
```

## Следующий этап

```text
N3 — World Directory and authority leases
branch: feature/n3-world-directory
```
