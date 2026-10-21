# FABRIC R5.6.1 R2 — COM recovery liveness narrow repair

Status: **R2 local repair candidate, independent verification pending**.

## New independent falsifier: recovery deadlock

На fixed research HEAD `91223acb7bf79c37e12fc11d44054ad3e2732455`
физически допустимые Construction Snapshot (2 × 1 kg) позволяли следующую последовательность:

1. `0 x = 1e12 m`, `x1 = x0 + 1m`: абсолютный COM корректно представлен;
2. owner-verified MOVE_PART задаёт `x1 = x0 + 0.0001220703125m`: checksum/revision источника и derived Fenwick индекс успешно продвигаются, COM query закономерно fail-closed с `R56_R2_RANGE_CENTER_PRECISION_UNSAFE`;
3. другой легитимный owner-verified MOVE_PART возвращает прежнее `x1 = x0 + 1m`: исходный R2 ошибочно **отказывает** ещё до update, поскольку для проверки полной массы вызывает `query_range(0, count)` на неподдерживаемом **старом** COM.

Исходный тест сохранил RED: 6 checks, 1 failure, `recovery_success=false`, `recovery_error=R56_R2_RANGE_CENTER_PRECISION_UNSAFE`.

## Repair

В `r5_6_1_r2_dynamic_aggregate_index_v1.gd`, `apply_owner_verified()` заменён запрос полной физической capsule на прямую проверку **только нулевого момента Fenwick — полной массы** за `O(log N)`.

- Проверяются finite и строго положительная исходная масса, ожидаемая масса после дельты и Matter ledger через прежний `_near`.
- Все доверенные source checksum, revision, идентичность деталей и stage-before-commit проверки остаются; нет байпаса авторитета Construction и нет второго мирового writer.
- `query_range()` продолжает независимо запрещать публикацию COM при ошибке представимости свыше 1 мкм. Никакого ослабления numeric precision и смены DTO.
- Recovery update теперь может вывести разрешённую, уже изменённую каноническую конструкцию из состояния без допустимого компактного COM descriptor. Это важно для будущего R5.6.2 multi-event/restart.
- Стоимость mass-only prefix = O(log N); полный Construction event/BRIDGE-4 остаётся O(N).

## Mandatory acceptance

`fabric_r5_6_1_r2_com_recovery_acceptance.gd` воспроизводит на **настоящих созданных Snapshot**:
- корректный safe COM первоначально;
- первый owner-verified sparse update и отказ `query_range()` после него;
- отказ на ложный Matter mass и stale source/revision с полной сохранностью index status;
- успешный второй sparse update обратно к поддерживаемому COM, правильную инерцию/COM по независимому оракулу и ровно два commit;
- запрет replay; ноль полных aggregate rescans.

Обязательный новый gate: `18/0` checks, `FABRIC_R56_R2_COM_RECOVERY`. Linux/Windows штатные runner'ы включают parse и execution; strict collector v4 связывает payload со всеми прежними R2 3×626/0, scale 255/0, numeric 54/0, COM 52/0, R1 203/0, narrow 26/0 и BRIDGE-4 49/0. Negative collector matrix расширена с 16 до 21 отказов.

Текущие pre-existing safety limits (точечные массы, numeric guard heuristic, no production writer) не меняются. R2 не является MERGE_READY до fresh exact на опубликованном HEAD, отдельного Reviewer/Verifier и human merge gate. 
