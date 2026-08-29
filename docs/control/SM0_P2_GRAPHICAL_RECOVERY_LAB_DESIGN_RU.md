# SM0-P2 — Graphical Recovery Lab

Статус: **DESIGN / BRANCH-LOCAL EXPERIMENTAL PRESENTATION SURFACE**.

P2 не является новым authority protocol, production recovery implementation или global acceptance. `SERVER_HANDOFF` остаётся CRITICAL-risk и вне V0-S1 runtime frontier.

## База

H4.3 exact runtime-tested candidate:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

H4.3 runtime evidence:

`docs/control/SM0_H4_3_RECOVERY_OF_RECOVERY_RUNTIME_EVIDENCE_RU.md`

P1 graphical handoff lab уже показывает ручной healthy crossing и client-observed authority/epoch/identity. P2 должен добавить визуальное наблюдение именно durable recovery dynamics, не меняя canonical truth.

## Цель

Пользователь вручную ведёт того же graphical client через boundary `x=0`. На первом fresh handoff runner использует уже проверенный H4.3 test-only fault profile:

`h4-recovery-of-recovery-same-transfer-v1`

и визуально проводит один exact transfer через:

`TARGET_PREPARED -> total A+B outage -> restore -> TARGET_COMMITTED -> total A+B outage -> restore -> ACTIVE_OWNER -> total A+B outage -> restore -> exactly-one crossing`.

После завершения можно идти обратно; следующая chain должна работать симметрично B -> A. Lab может повторять chains до закрытия graphical window.

## Архитектурная граница

Canonical gameplay state, directory epoch, ownership epoch, player identity и recovery snapshots остаются исключительно существующими SM0 authority/recovery nodes.

Graphical client по-прежнему использует `sm0_manual_client_node.gd` и показывает derived authoritative player projection.

P2 supervisor PowerShell:

- запускает два authority process с существующим H4.3 fault profile и одним recovery root;
- наблюдает exact H4.3 crash markers в server logs;
- завершает оба authority process на каждой из трёх durable boundaries;
- выдерживает короткую визуальную zero-authority паузу;
- восстанавливает target/source из тех же durable recovery files;
- пишет presentation-only JSON status file.

Godot graphical recovery scene читает только этот presentation-only status JSON и показывает:

- online/down/recovering state A и B;
- current durable phase и generation каждой стороны;
- source / target;
- exact transfer id;
- chain number и outage number;
- заметный `TOTAL OUTAGE` banner во время zero-authority interval;
- базовый client HUD из P1: authority, zone, client state, epochs, player id, position, handoff count.

Status JSON не читается authority nodes и не участвует в protocol decisions. Потеря/повреждение presentation status не должна менять canonical runtime.

## Visual sequence

Начальное состояние:

- A online / owner WEST;
- B online / standby EAST;
- instruction: `Hold D and cross x=0`.

PREPARED:

- source A durable `SOURCE_RETIRED`;
- target B durable `TARGET_PREPARED`;
- exact T виден в HUD;
- затем A+B становятся DOWN.

COMMITTED recovery:

- B восстанавливается как target и продвигает тот же T до `TARGET_COMMITTED`;
- A остаётся exact `SOURCE_RETIRED`;
- второй total outage.

ACTIVE recovery:

- B восстанавливается и тот же T достигает `ACTIVE_OWNER`;
- A остаётся `SOURCE_RETIRED`;
- третий total outage.

Terminal restore:

- клиент не перезапускается;
- crossing завершается ровно один раз;
- base HUD показывает Authority B / EAST, epoch +1, тот же player identity;
- P2 status возвращается `READY`, предлагая пройти обратно.

## Fail-closed expectations

Supervisor обязан остановить lab с ошибкой, если после начала chain:

- authority process неожиданно завершается до ожидаемого marker;
- PREPARED / COMMITTED / ACTIVE marker не относится к текущему exact T;
- target/source recovery не поднимаются;
- client завершается во время outage;
- recovery не приводит к ожидаемому crossing completion;
- stale process остаётся жив после total-outage kill.

До первого пользовательского crossing graphical window может быть закрыто без protocol failure.

## Local checkpoint

P2 считается реализованным для локальной проверки, когда существуют:

- `scripts/runtime/seamless/sm0/sm0_graphical_recovery_lab.gd`;
- `scenes/testing/sm0_graphical_recovery_lab.tscn`;
- `RUN_V0_SM0_GRAPHICAL_RECOVERY_LAB.ps1`;
- compile/smoke checks exact double Godot;
- clean-worktree protection;
- `-Stop` / `-Restart` lifecycle;
- presentation-only status projection;
- manual repeated recovery-chain loop.

Runtime acceptance P2 оформляется отдельно после реального Windows graphical run. До этого P2 остаётся implementation candidate.
