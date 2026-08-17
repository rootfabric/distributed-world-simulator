# V0-SM0 FINAL — integrated closure / canonical acceptance

**Статус:** IMPLEMENTED / WINDOWS RUNTIME VERIFICATION REQUIRED  
**Ветка:** `feature/sm0-two-authority-seamless-handoff-lab`  
**Implementation boundary:** `f97f2fc03ead45f0e70006bc1921e0872c84567f`  
**P11 Windows-validated predecessor:** `b901ee779a0f8d2efce52bde4e421b720420302d`

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

## Closure rule

До реального Windows PASS на exact current carrier SM0 FINAL остаётся `WINDOWS RUNTIME VERIFICATION REQUIRED` и PR #102 остаётся draft/open. После green runtime evidence результат фиксируется в PR и только затем SM0 может быть передан на независимый closure review. Этот checkpoint сам по себе не разрешает merge и не делает claims о production World Directory, NATS/JetStream, dynamic balancing или глобальном seamless production acceptance.
