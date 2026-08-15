# SM0-P1 — operator graphical evidence — 2026-08-15

Статус: `OPERATOR_EVIDENCE / BOUNDED_LAB_PASS`

Это запись фактов ручного запуска, а не global/main acceptance и не замена independent review.

## Exact runtime

- branch: `feature/sm0-two-authority-seamless-handoff-lab`
- exact HEAD: `b9a4667c536287af3b182a589835eb57bd703556`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- launcher: `RUN_V0_SM0_GRAPHICAL_LAB.ps1 -Restart -RequireHandoffs 2`

## Process topology observed by operator

Одновременно были запущены три разных процесса:

- authority A server: PID `9384`;
- authority B server: PID `5100`;
- graphical/manual client: PID `15288`.

Это подтверждает process-level two-authority topology: два server process одновременно работают на разных SM0 endpoints, а graphical client является отдельным процессом. При этом directory сохраняет single-owner semantics: player writer authority переключается A -> B -> A, а не становится двойным writer.

## Observed crossing sequence

Initial:

- authority A / WEST;
- directory authority epoch `1`;
- `player_entity_id = player/a`;
- position `x=-5.0`.

Four completed handoffs were observed in client events:

1. `handoff/sm0/a/2/1`: A -> B, directory epoch `2`, handoff index `1`;
2. `handoff/sm0/b/3/1`: B -> A, directory epoch `3`, handoff index `2`;
3. `handoff/sm0/a/4/2`: A -> B, directory epoch `4`, handoff index `3`;
4. `handoff/sm0/b/5/2`: B -> A, directory epoch `5`, handoff index `4`.

Across all shown events:

- `player_entity_id` remained exactly `player/a`;
- directory epochs advanced monotonically `1 -> 2 -> 3 -> 4 -> 5`;
- client route alternated WEST/EAST consistently with authority A/B;
- no `SM0_INVARIANT_VIOLATION` or remote error was shown in the supplied log excerpt;
- no handoff remained stuck in `WAIT_HANDOFF` or `ACTIVATING`;
- final graphical HUD showed `Authority: A`, `State: ACTIVE`, authority epoch `5`, ownership epoch `3`, handoffs `4`, player `player/a`, position about `x=-2.75`.

## Interpretation

The supplied runtime evidence supports the bounded P1 claim that manual movement drives the same existing SM0 handoff protocol and that graphical presentation follows the authoritative player state through repeated A/B crossings.

It does not prove crash-after-commit recovery; that remains H2.2 scope.
