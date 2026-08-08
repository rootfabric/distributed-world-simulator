# M7 FIX8 — prediction clock alignment и bounded visual correction

## Откуда взялся FIX8

FIX7 подтвердил, что основной server-side stall устранён: в ручном двухклиентном `LOCAL` прогоне сервер не имел scheduler backlog, `slow_process_frames = 0`, а READY report build упал до единиц миллисекунд. При этом визуально сохранилась небольшая дёрганость локального и иногда удалённого персонажа.

Итоговые client reports дали характерную картину:

- максимальная prediction error у обоих клиентов около `0.300 m`;
- скорость ходьбы `6 m/s`, fixed tick `60 Hz` => `0.1 m/tick`;
- movement snapshot публикуется примерно раз в 3 authority tick => ровно `0.3 m` между соседними сетевыми состояниями;
- hard corrections отсутствуют;
- visual offset успевал вырасти примерно до `0.8–1.1 m`, то есть заметно больше любой одиночной prediction error;
- remote presenter периодически попадал в `HOLD_EXTRAPOLATION_LIMIT`, но старый отчёт не позволял отделить hold во время движения от hold после остановки клиента.

FIX8 поэтому не увеличивает snapshot rate и не меняет server authority. Он исправляет фазу prediction clock и compositor визуальной коррекции, а для remote interpolation добавляет недостающую диагностику перед любым изменением playout delay/extrapolation policy.

## Неподвижные инварианты

FIX8 сохраняет:

- authoritative simulation: `60 Hz` на сервере;
- существующий movement snapshot cadence;
- NX3 input buffering/backpressure;
- NX4 authoritative reconciliation и history replay для обычного прошлого snapshot;
- разные input sequence как реальное потенциальное расхождение, которое нельзя маскировать clock alignment;
- hard correction для настоящего большого расхождения свыше существующего порога;
- FIX7 render-rate sub-tick presentation;
- FIX5 Item Graph/world-item authority semantics.

## Слой A — monotonic prediction clock alignment

`FixedTickScheduler` получает узкий API:

`MONOTONIC_FORWARD_PRESERVE_SUBTICK_PHASE_V1`.

Он умеет только переместить clock вперёд к заданному tick. Rewind запрещён. Накопленный sub-tick accumulator не сбрасывается, поэтому FIX7 render presentation не теряет фазу после очередного authoritative snapshot.

## Слой B — sequence-matched future pre-alignment

Политика:

`SEQUENCE_MATCHED_FUTURE_TICK_PREALIGN_V1`.

Если authoritative snapshot имеет tick впереди текущего prediction clock, FIX8 сначала проверяет:

1. snapshot не старее последнего authoritative tick;
2. player state валиден;
3. `authoritative last_input_sequence == current local input sequence`;
4. разрыв не больше 8 tick.

Далее есть два случая.

### Настоящий clock-only snapshot

Если position/velocity/yaw уже совпадают с текущим predicted state, gameplay state не симулируется заново. Вперёд двигается только clock с сохранением sub-tick phase. Это сохраняет ранее принятый NX4 clock-only contract.

### Snapshot той же input sequence, но на несколько simulation tick впереди

Клиент детерминированно просчитывает недостающие tick тем же shared movement kernel до authoritative tick, затем уже сравнивает состояния на одной временной координате.

Пример ожидаемого эффекта:

```text
до FIX8:
client T100 vs server T103 -> 0.3 m "prediction error"

FIX8:
client locally reconstructs T103
predicted T103 vs authoritative T103 -> ~0 m
```

Если input sequence различается, FIX8 ничего не угадывает и оставляет snapshot старому authoritative reconciliation path.

## Слой C — bounded/rate-limited visual correction

Политика:

`BOUNDED_CONTINUITY_OFFSET_RATE_LIMITED_DECAY_V1`.

Сохраняется continuity offset, но вводятся два предохранителя:

- максимальный применяемый visual offset: `0.50 m`;
- максимальная скорость погашения visual correction: `2.50 m/s`.

Decay duration теперь определяется не только одиночной prediction error, но и фактической величиной накопленного presentation offset. Поэтому метр визуального долга больше не может быть протолкнут через короткое окно, рассчитанное по одной коррекции порядка 0.3 m.

Hard correction остаётся прежним для настоящих больших ошибок.

## Слой D — remote interpolation telemetry

Поведение remote interpolation в FIX8 сознательно пока не меняется: текущий лог не доказывает, что `HOLD_EXTRAPOLATION_LIMIT` происходил именно во время движения.

`RemotePlayerPresenter` теперь сообщает:

- `fix8_snapshot_gap_samples`;
- `fix8_mean_snapshot_gap_ticks`;
- `fix8_max_snapshot_gap_ticks`;
- `fix8_moving_extrapolation_samples`;
- `fix8_moving_hold_samples`;
- `fix8_moving_buffer_underruns`;
- `fix8_max_moving_hold_streak`.

`moving_buffer_underrun` считается только когда скорость удалённого игрока выше малого epsilon и presenter впервые входит в `HOLD_EXTRAPOLATION_LIMIT`. Это позволит следующий tuning remote playout делать по измерениям, а не увеличивать delay вслепую.

## Focused regression

Новый тест `tests/network/test_m7_prediction_clock_fix8.gd` проверяет:

- 3-tick future phase при той же input sequence перестаёт быть 0.3 m prediction error;
- canonical predicted state сходится к authority на том же tick;
- sub-tick accumulator переживает clock alignment;
- настоящий clock-only path не симулирует лишнее движение;
- sequence mismatch не pre-align'ится;
- repeated continuity correction ограничивается 0.5 m и получает rate-limited decay;
- remote snapshot gap telemetry считает интервалы правильно;
- source contracts FIX8 присутствуют.

Runner:

```powershell
.\VALIDATE_M7_PREDICTION_CLOCK_FIX8.ps1 -GodotPath $Godot -IncludeTwoClientProcess
```

Он включает focused FIX8, FIX7 regression, NX4 regression и далее весь предыдущий FIX7/FIX6/FIX5 accepted baseline.

## Ручная приёмка

Повторить тот же двухклиентный `LOCAL` сценарий: длительное движение обоих клиентов, повороты, периодические item actions.

Ожидается:

- server-side показатели не ухудшаются относительно FIX7;
- `hard_corrections = 0`;
- обычная трёхтиковая фаза отражается в `clock_alignment_events/ticks`, а не в повторяющейся `~0.300 m` correction;
- `max_bounded_visual_offset_m <= 0.50`;
- visual offset не растёт до прежних `0.8–1.1 m`;
- субъективное локальное back-pull/micro-jerk уменьшается;
- remote `moving_buffer_underruns` показывает, действительно ли остаточная дёрганость другого персонажа связана с underrun snapshot buffer.

Если после FIX8 локальный игрок станет плавным, а remote `moving_buffer_underruns > 0` совпадёт с оставшейся дёрганостью, следующий отдельный tuning сможет адаптивно менять remote playout delay/extrapolation horizon без вмешательства в local prediction или server tick rate.

## Статус

FIX8 является кандидатом до прохождения точного Windows gate и повторного ручного двухклиентного теста. PR должен оставаться draft и не должен merge'иться до явной приёмки.
