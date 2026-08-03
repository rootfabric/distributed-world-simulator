# MW9 fix3 — стабилизация concurrent expired-lease claim

```text
checkpoint: v17.11.0-simulation-mw9-durable-handoff-recovery
build_id:   mw9-durable-distributed-handoff-recovery
delivery:   fix3
branch:     feature/mw9-durable-handoff-recovery
base:       MW9 fix2
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Причина исправления

Независимая проверка RL2 обнаружила флак существующего MW9 multi-process gate. Первый concurrent expired-lease claim завершился несколькими ошибками, а повторный запуск прошёл.

Причиной оказалось не CAS-сравнение authority lease и не checkpoint progression. Старый repository release выполнял две отдельные файловые операции:

```text
remove owner.json
remove .matter-handoff-state.lock
```

Между ними существовало ownerless-окно. Contender, который в этот момент не смог установить свой candidate lock, видел каталог без owner metadata и мог удалить его как stale. Durable checkpoint победителя уже был записан, но `_release_lock()` возвращал ошибку. В результате оба процесса сообщали `claim_success=false`, хотя canonical checkpoint содержал единственного победителя.

## Исправление

### Атомарный release

Lock больше не разбирается на месте. Владелец проверяет PID и token, затем одной namespace-операцией переименовывает весь каталог:

```text
.matter-handoff-state.lock
        ↓ atomic rename
.matter-handoff-state.lock.<token>.released
        ↓ cleanup
removed
```

Canonical lock path исчезает атомарно. Новый contender может захватить его только после завершения rename и никогда не наблюдает промежуточный каталог без `owner.json`.

### Grace fence для ownerless lock

Повреждённый или оставленный старой версией ownerless-каталог больше не удаляется немедленно. Для него используется mtime каталога и стандартный 30-секундный stale threshold. Это дополнительно закрывает race со старыми release-реализациями.

### Безопасная stale quarantine

Stale lock сначала переименовывается в уникальный quarantine path и только затем удаляется. Перед удалением повторно проверяется PID/token наблюдавшегося owner. Если identity изменилась, lock восстанавливается вместо удаления более нового владельца.

### Cross-platform liveness

После stale threshold проверяется живость owner process:

- Linux: `/proc/<pid>`;
- Windows: `tasklist /FI "PID eq ..." /FO CSV /NH`;
- macOS/BSD: `kill -0`;
- при неизвестном результате применяется консервативный threshold 120 секунд.

### Диагностика

Lock timeout теперь возвращает:

- число попыток;
- число stale reclamations;
- фактическое время ожидания;
- последний observed owner.

Claim race reports дополнены PID, ожидаемым checksum lease, исходной generation/revision, длительностью claim и error details.

## Усиление тестов

Обычный multi-process профиль теперь выполняет восемь независимых claim-race раундов вместо одного. Каждый раунд проверяет:

- ровно одного успешного contender;
- наличие CAS/progression отказа у проигравшего;
- `authority_epoch: 4 → 5`;
- `checkpoint generation: 1 → 2`;
- совпадение report winner и восстановленного durable checkpoint;
- отсутствие pending files;
- отсутствие canonical lock, candidate, released и stale residue.

Contract/runtime профиль дополнительно проверяет:

- атомарный release marker;
- отсутствие deferred cleanup;
- невозможность немедленно удалить свежий ownerless lock;
- восстановление действительно старого lock.

Добавлены отдельные batched stress runners:

```text
RUN_MW9_RACE_STRESS_TESTS.ps1
RUN_MW9_RACE_STRESS_TESTS.sh
```

По умолчанию они выполняют 100 раундов пакетами по 8. Перезапуск родительского Godot между пакетами не позволяет самому harness накапливать process handles и делает soak одинаково применимым на Windows и Linux.

## Авторская проверка

```text
MW9 contracts/runtime: 203/203 PASS ×3
MW9 multi-process:      225/225 PASS ×3
MW9 combined:           428/428 PASS ×3
MW9 claim race stress:  100/100 rounds PASS
Race assertions:        2500/2500 PASS
MW10 regression:        235/235 PASS
RL2 regression:         197/197 PASS
```

PowerShell stress runner требует фактического независимого запуска на Windows. В authoring-среде PowerShell отсутствовал; оба Godot suite и bash stress runner выполнены на Godot 4.7.1 double.
