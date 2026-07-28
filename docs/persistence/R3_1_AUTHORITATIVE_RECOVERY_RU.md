# R3.1 — authoritative persistence и crash recovery

## Назначение

R3.1 делает authoritative item-command устойчивой к аварийному завершению процесса. После restart сервер восстанавливает канонический WORLD aggregate, Item Graph, operation ledger, gateway dedup state и reconnect replay records из одного versioned checkpoint.

Главный инвариант:

```text
committed operation после restart выполняется не более одного раза
```

## Состав checkpoint

Схема `planet_simulator.authoritative_checkpoint.v1` содержит:

- `generation` и `previous_generation`;
- authority owner/epoch;
- server tick и entity revision;
- logical session;
- последний committed operation ID/tick;
- полный authoritative domain state;
- completed command gateway records;
- bounded reconnect/replay state;
- canonical SHA-256 checksum.

Checkpoint не содержит Node, Resource, Callable, RID, presentation state или transport peer objects.

## Атомарная публикация

Repository использует staged commit:

```text
serialize + validate
→ write unique pending file
→ flush + close
→ read/validate pending file
→ validate progression against active checkpoint
→ preserve previous checkpoint
→ atomic rename to authoritative-checkpoint.json
→ read/validate committed file
```

Файлы:

```text
authoritative-checkpoint.json
authoritative-checkpoint.previous.json
.authoritative-checkpoint.<pid>.<ticks>.pending.json
```

Orphan pending-файл после аварии никогда не становится активным автоматически. Он перечисляется в диагностике и может быть удалён безопасной cleanup-операцией.

## Recovery

Восстановление выполняется fail-closed и транзакционно:

1. Проверяется outer checkpoint и checksum.
2. В отдельный staged-domain загружаются Item Registry, Container Registry, Attachment Registry, Operation Ledger и World Entity Store.
3. Повторно проверяются Item Graph и WORLD bindings.
4. В отдельный gateway загружается completed-operation state.
5. Из staged aggregate строится строгий `EntitySnapshotEnvelope`.
6. Snapshot checksum сравнивается с checkpoint.
7. Только после всех проверок staged state заменяет live state.

Ошибка на любой стадии не изменяет live aggregate, revision, tick или mutation count.

## Crash-сценарии

### Commit завершён, ответ потерян

```text
command mutation
→ ledger + replay record
→ generation 2 committed
→ process exits before response
→ restart
→ client repeats operation_id
→ cached terminal result returned
→ mutation count remains 1
```

### Crash до commit

```text
generation 1 committed
→ command prepares generation 2 pending file
→ process exits before atomic commit
→ restart loads generation 1
→ pending file ignored
→ command executes exactly once
→ new committed generation created
```

## Fences

Repository отклоняет:

- generation rollback или gap;
- authority epoch rollback;
- owner change без повышения epoch;
- state revision rollback;
- server tick rollback;
- same-revision domain mutation;
- повреждённый checksum;
- повреждённый active checkpoint;
- runtime objects;
- неизвестные поля;
- несовместимый legacy `world.json` без явной миграции.

Legacy state возвращает `LEGACY_WORLD_STATE_REQUIRES_MIGRATION`; автоматическая частичная загрузка запрещена.

## Тесты

```powershell
.\RUN_R3_AUTHORITATIVE_RECOVERY_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Process-test запускает отдельные Godot workers и требует ожидаемые crash exit codes, committed/pending recovery, отсутствие второй mutation и checksum equality.

## Ограничения

R3.1 не реализует:

- World Directory;
- lease renewal;
- cross-server handoff;
- distributed consensus;
- удалённое object storage;
- автоматическую миграцию старого `world.json`.

Следующий этап — N3 World Directory и authority leases.
