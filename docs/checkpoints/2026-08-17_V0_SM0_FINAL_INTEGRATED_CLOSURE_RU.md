# V0-SM0 FINAL — integrated closure / canonical acceptance

**Статус:** WINDOWS RUNTIME VALIDATED / READY FOR INDEPENDENT CLOSURE REVIEW  
**Ветка:** `feature/sm0-two-authority-seamless-handoff-lab`  
**Implementation boundary:** `f97f2fc03ead45f0e70006bc1921e0872c84567f`  
**P11 Windows-validated predecessor:** `b901ee779a0f8d2efce52bde4e421b720420302d`  
**Exact Windows-runtime-validated FINAL carrier:** `b5966ef113b73e3156488805057ce9b464362d89`

## Цель

SM0 FINAL не добавляет ещё одну модель authority. Это closure-gate, который связывает уже доказанные SM0 слои в один канонический воспроизводимый прогон и не позволяет закрыть lab по набору разрозненных локальных PASS.

Каноническая команда по плану сохраняется:

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Final -Restart
```

Теперь `-Final` маршрутизируется в `RUN_V0_SM0_FINAL_ACCEPTANCE.ps1`. Внутренний fixed 20-handoff carrier вызывается напрямую через `RUN_V0_SM0_ACCEPTANCE_R2.ps1`, поэтому рекурсии нет.

## Что обязан доказать один FINAL run

1. Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.
2. Clean worktree и неизменный HEAD до/после теста.
3. P8.1 reference-frame focused gate — `33 assertions`.
4. P8.1.1 stationary-passenger focused gate — `14 assertions`.
5. Канонический SM0 A<->B acceptance — ровно `20 / 20` authority handoffs.
6. В canonical `summary.json`:
   - `result=PASS`;
   - `player_identity_changes=0`;
   - `invariant_violation_count=0`;
   - `unexpected_error_count=0`;
   - epoch `1 -> 21`.
7. Полный P11 gate с минимум `120` process-soak iterations.
8. P11 обязан повторно протащить inherited P10 -> P9 -> P8 gate.
9. P11 deterministic matrix — `68 assertions`.
10. Simultaneous crossing / process isolation остается доказанным тремя отдельными authority Godot processes.

## Evidence

FINAL пишет собственный evidence root:

```text
artifacts/runtime/sm0-final-<run-id>/
  p8-1-reference-frame.log
  p8-1-1-stationary-passenger.log
  canonical-20-handoff.log
  canonical-summary.json
  p11-integrated.log
  summary.json
```

`summary.json` имеет schema:

```text
distributed_world_simulator.sm0_final_acceptance_summary.v1
```

Он фиксирует exact HEAD, Godot version, 20 canonical handoffs, epoch range, identity/invariant/error counters, P8.1/P8.1.1 assertion counts, P11 matrix и soak iteration count.

## Windows verification

Канонический workspace:

```text
C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab
```

Команда:

```powershell
$Project = "C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab"
Set-Location $Project

git fetch origin feature/sm0-two-authority-seamless-handoff-lab
git merge --ff-only origin/feature/sm0-two-authority-seamless-handoff-lab

git rev-parse HEAD
git status --short

.\RUN_V0_SM0_ACCEPTANCE.ps1 `
    -Final `
    -Restart `
    -ProjectRoot $Project
```

Финальный machine marker:

```text
SM0 FINAL integrated closure / canonical acceptance: PASS
```

## Windows runtime evidence — 2026-08-17

Реальный Windows runtime прогон завершён на exact carrier:

```text
b5966ef113b73e3156488805057ce9b464362d89
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Проверенный integrated result:

```text
SM0 P11 deterministic fault matrix: PASS (68 assertions)
SM0 P11 process-isolated simultaneous crossings + soak: PASS (120 iterations / 2052 assertions)
SM0-P11 deterministic fault matrix + simultaneous-crossing soak: PASS

SM0 FINAL integrated closure / canonical acceptance: PASS
  canonical   : 20 / 20 A<->B handoffs; stable player identity; epoch 1 -> 21
  reference   : P8.1 33 + P8.1.1 14 assertions
  world/item  : inherited P9 full foreign-item boundary gate PASS
  view/LOD    : inherited P10 multi-authority composition gate PASS
  fault       : P11 deterministic 68 assertions
  soak        : 3 authority processes / 120 simultaneous-crossing iterations
  invariant   : zero split-brain / zero identity changes / zero unexpected errors
```

P11 process isolation в этом прогоне подтверждена тремя отдельными authority Godot processes. Simultaneous crossings `A->B + B->A` и `A->B + B->C` прошли под deterministic fault matrix; retirement proof, epoch/operation fencing, stale-owner rejection, projection delay/reorder rejection и one-source dropout isolation остались green.

Windows evidence paths:

```text
C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab\artifacts\runtime\sm0-p11-20260817-233310995-d6b0d8f5
C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab\artifacts\runtime\sm0-final-20260817-233239363-f6845c11\summary.json
C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab\artifacts\runtime\sm0-final-20260817-233239363-f6845c11
```

Project Control для exact runtime-validated carrier `b5966ef113b73e3156488805057ce9b464362d89`: **SUCCESS**, run `#855`.

## Closure rule

Windows runtime gate теперь выполнен на exact FINAL carrier. SM0 FINAL может быть передан на независимый closure review. PR #102 остаётся draft/open до отдельного независимого решения; этот checkpoint не разрешает merge сам по себе и не делает claims о production World Directory, NATS/JetStream, dynamic balancing или глобальном seamless production acceptance.
