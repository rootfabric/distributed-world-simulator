# SM0 P2.2 — bounded recovery performance runtime evidence

Статус этого документа: branch-local experimental evidence для `feature/sm0-two-authority-seamless-handoff-lab`.

Это НЕ production/global/canonical acceptance. Cross-server authority остается CRITICAL-risk экспериментом, а `SERVER_HANDOFF` по-прежнему находится за `stop_before` V0-S1.

## Exact tested candidate

- branch: `feature/sm0-two-authority-seamless-handoff-lab`
- exact tested HEAD: `57672d2846072a4c70a4a77bf841eebb900ab290`
- exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Project Control: run #637, run id `31920576479`, conclusion `success`

## Что проверял P2.2

P2.1 уже ограничивал replay history движения и число recovery snapshot файлов. P2.2 дополнительно ограничивает накопление:

- SM0 service-operation replay history;
- OwnershipService replay history;
- historical `_prepared_transfers`;
- historical `_committed_transfers`.

Цель — не допустить постепенного роста стоимости каждого durable MOVE/recovery snapshot и, как следствие, постепенного уменьшения effective movement rate после многих handoff/recovery циклов.

## Headless Windows acceptance

Команда:

```powershell
.\RUN_V0_SM0_RECOVERY_PERFORMANCE_V2_ACCEPTANCE.ps1
```

Результаты на exact candidate:

- established P2.1 recovery performance: `PASS (188 assertions, 40 durable moves)`;
- active-owner recovery regression: `PASS (41 assertions)`;
- P2.2 bounded service/ownership/transfer replay regression: `PASS (30 assertions)`;
- final gate: `SM0-P2.2 bounded handoff replay performance: PASS`.

Сильный synthetic pre-compaction case подтвердил фактическое ограничение накопленной истории:

- service operations: `18 -> 3`, removed `15`;
- ownership operations: `17 -> 2`, removed `15`;
- prepared transfers: `5 -> 0`;
- committed transfers: `5 -> 0`;
- persisted snapshot: примерно `9860` bytes.

После restore/rebind bounded state остался корректным:

- service operations: `4 -> 4`;
- ownership operations: `3 -> 3`;
- prepared/committed transfer history: `0/0`;
- persisted snapshot: примерно `13250` bytes;
- canonical player identity/state recovered successfully.

## Interactive graphical evidence

Команда:

```powershell
.\RUN_V0_SM0_GRAPHICAL_RECOVERY_PERFORMANCE_V2_LAB.ps1 -Restart -RequireRecoveries 1
```

Log root:

```text
C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0GraphicalRecoveryLab\logs\20260816-115957
```

Один и тот же graphical client process `PID=25780` пережил по меньшей мере семь последовательных alternating A<->B crossings в одной сессии. Для каждого показанного crossing canonical velocity после handoff осталась неизменной по модулю: `0.25`.

Наблюдавшиеся transfers:

1. `handoff/sm0/a/2/1`, A -> B, input sequence 43, velocity `+0.25`;
2. `handoff/sm0/b/3/1`, B -> A, input sequence 99, velocity `-0.25`;
3. `handoff/sm0/a/4/2`, A -> B, input sequence 155, velocity `+0.25`;
4. `handoff/sm0/b/5/2`, B -> A, input sequence 225, velocity `-0.25`;
5. `handoff/sm0/a/6/3`, A -> B, input sequence 275, velocity `+0.25`;
6. `handoff/sm0/b/7/3`, B -> A, input sequence 333, velocity `-0.25`;
7. `handoff/sm0/a/8/4`, A -> B, input sequence 404, velocity `+0.25`.

Главный interactive result от локальной проверки: после переходов **скорость больше не теряется**. Это закрывает наблюдавшуюся на P2.1 постепенную деградацию effective movement rate для данного экспериментального graphical recovery сценария.

Окончательный close-window PASS banner для graphical runner в приложенном выводе не зафиксирован, поэтому эта часть evidence намеренно формулируется как interactive observation на >=7 successful crossings, а не как полный graphical acceptance gate.

## Важное различие latency и recovery-chaos

Наблюдаемые примерно 3.6-3.9 s между route switching и crossing completion в этом runner не являются нормальной стоимостью здорового handoff. `SM0GraphicalRecoveryLab` специально делает три полных total A+B outage/restart/recovery фазы на каждый crossing: PREPARED, COMMITTED и ACTIVE_OWNER.

Следующий отдельный performance checkpoint должен измерять normal healthy A<->B handoff без fault profile, process kills и artificial recovery holds.

## Verdict

P2.2 дает положительное branch-local experimental evidence против накопительного падения movement throughput: bounded replay/transfer history прошла headless gates, exact candidate прошел Project Control, а interactive graphical session сохранила скорость на множественных последовательных переходах.

Это не меняет глобальный риск-класс SM0 и не авторизует перенос cross-server handoff в V0-S1 runtime.
