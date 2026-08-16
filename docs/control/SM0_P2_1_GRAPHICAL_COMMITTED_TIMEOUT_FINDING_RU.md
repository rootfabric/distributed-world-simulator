# SM0-P2.1 — graphical COMMITTED timeout finding

Статус: BRANCH-LOCAL EXPERIMENTAL FINDING / REPAIR IMPLEMENTED / WINDOWS GRAPHICAL RE-VERIFICATION PENDING.

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`.

Никакой production/global/V0-S1 acceptance этим документом не объявляется. Cross-server authority остаётся CRITICAL; `SERVER_HANDOFF` остаётся за `stop_before` V0-S1.

## Проверенный failing candidate

Windows graphical run выполнялся на exact HEAD:

`e30a8b7027d0702b95b83a6a7220640f6e0ac300`

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Команда:

`RUN_V0_SM0_GRAPHICAL_RECOVERY_PERFORMANCE_LAB.ps1 -Restart -RequireRecoveries 1`

Run directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0GraphicalRecoveryLab\logs\20260816-113815`

Observed transfer:

`handoff/sm0/a/2/1`

Перед первым outage source A имел durable `SOURCE_RETIRED` generation 22, target B имел durable `TARGET_PREPARED` generation 1. После restart target B и source A graphical client вошёл в `ACTIVATING`, но supervisor не увидел H4.3 `COMMITTED` crash point и завершился:

`SM0-P2 FAIL: Timeout waiting for H4.3 stage COMMITTED ... server-b-segment01.log`

## Причина

Это не failure P2.1 bounded movement compaction и не потеря durable handoff state. На HUD оба durable состояния были восстановлены корректно: A=`SOURCE_RETIRED`, B=`TARGET_PREPARED`.

Причина находится в test-only H4.3 recovery-chain fault orchestration.

`recovery_resume.setup()` немедленно replays COMMIT/redirect для restored `SOURCE_RETIRED` transfer. H4.3 fault node разрешал этот exact replay пройти только пока выполнялся `super.setup()`. Если первый UDP COMMIT отправлялся до того, как только что запущенный target успевал bind/listen, datagram мог быть потерян. После setup нормальный 200 ms source retry для того же restored transfer ошибочно переставал считаться recovery replay и снова попадал под PREPARED suppression. В результате exact durable pair оставался живым, но transaction не мог продвинуться до TARGET_COMMITTED.

P2.1 изменил timing достаточно, чтобы этот латентный race стал воспроизводим в graphical run.

## Repair

Repair commit:

`d287ed6b174a23cc95919613c5c86b8323ebe133`

Message:

`fix(sm0): keep restored source replay retryable`

Изменён только branch-local test/fault node:

`scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_chain_fault.gd`

Новая семантика H4.3:

- exact `SOURCE_RETIRED` transfer, восстановленный при boot, считается recovery replay не только внутри setup, но и для последующих retries того же exact transfer id;
- immediate replay и normal retry COMMIT/redirect проходят без повторного PREPARED fault;
- новый/fresh transfer в том же recovered process имеет другой transfer id и по-прежнему создаёт H4.3 PREPARED crash point;
- canonical recovery algorithm и P2.1 movement compaction не менялись.

## Следующий обязательный gate

Повторить Windows graphical P2.1 на head, содержащем repair. Первый переход должен пройти PREPARED -> COMMITTED -> ACTIVE -> crossing exactly once. После этого выполнить несколько round-trip crossings и проверить отсутствие прогрессирующего movement slowdown.
