# ECO VIS2.1 — Windows exact-engine + graphical validation

Дата: 2026-08-16

Статус: **WINDOWS_RUNTIME_VALIDATED_CANDIDATE**

Это не merge и не глобальный acceptance. Независимый review всё ещё обязателен.

## Exact candidate

Branch:

`feature/eco-vis2-1-control-vs-treatment`

Validated simulation/test HEAD:

`a1295c0157c6b82e993dc165d92715b324633efd`

Graphical launcher-only repair HEAD:

`39336f31501f15166cd4eb9766b02c98f5bcaf12`

Launcher repair изменяет только `RUN_ECO_VIS2_1_LAB.ps1`; simulation/runtime/test scripts относительно `a1295c...` не менялись.

## Exact Godot

Windows build:

`4.7.1.stable.double.custom_build.a13da4feb`

## Automated isolated gate

Полный Windows запуск `RUN_ECO_VIS2_1_TESTS.ps1` завершился PASS:

- CONTROL runner: PASS (82 assertions)
- TREATMENT R1 runner: PASS (96 assertions)
- Comparator R1: PASS (82 assertions)
- VIS1.8B regression: PASS (51 assertions)
- VIS1.9 regression: PASS (29 assertions)
- VIS2.0 regression: PASS (33 assertions)
- VIS2.1 integrated: PASS (57 assertions)
- long smoke G20..G220 with rolling eviction: PASS
- isolated gate: PASS (7 scripts + parser preflight)

Hardened runner также проверяет non-zero exit code, timeout, missing PASS marker и `SCRIPT ERROR` / `ERROR` / `Parse Error` даже при zero exit code.

## Подтверждённые VIS2.1 invariants

Windows long-smoke подтвердил:

- common fork сохраняется immutable;
- CONTROL и TREATMENT имеют один common CRN root;
- Treatment forcing начинается только с fork+1;
- CONTROL остаётся BASELINE;
- Treatment rebranch не переписывает CONTROL future;
- generation caches CONTROL/TREATMENT ограничены 64;
- raw runner trace caches ограничены 64;
- canonical comparison input ограничен 64;
- fork point постоянно остаётся в comparison input;
- comparison rebuild имеет O(64) shape;
- rolling eviction действительно происходит;
- restart после eviction детерминирован;
- CONTROL остаётся data-only;
- visible population field ровно один;
- whole-field PH5 turnover rebuild == 0;
- spectator mouse routing работает через comparison panel;
- TreatmentRunner lifecycle привязан к lab scene.

## Graphical Windows confirmation

Ручной graphical run подтверждён пользователем.

Наблюдаемый пример:

- fork: G70
- paired generation: G145
- treatment: FLOOD 100%
- CONTROL: reps=57, mean fitness≈0.934, unique genomes=57
- TREATMENT: reps=52, mean fitness≈0.689, unique genomes=52
- delta population=-5
- delta mean fitness≈-0.245
- delta unique genomes=-5
- delta deaths=+3

CONTROL/TREATMENT comparison charts обновляются, visible Treatment population продолжает рождаться/умирать, spectator controls сохраняются.

Поведение соответствует causal design: на fork обе ветви идентичны; после fork common RNG сохраняется, а divergence возникает через Treatment environment -> fitness -> survival/reproduction.

## Presentation note

После fork VIS2.1 намеренно использует realtime proxy tier для видимой Treatment population. Birth/death animation сохраняется, но progressive PH5 и rich near/mid/far presentation из pre-fork VIS chain в paired mode отключены.

Это не считается defect VIS2.1 causal candidate. Возврат дешёвого distance-based realtime LOD вынесен в следующий presentation stage без изменения simulation truth.

## Graphical launcher repair

Первый graphical launch через full repository `project.godot` выдал:

`Resource file not found: res://`

`Failed to instantiate an autoload, can't load from path: .`

Причина: repository debug autoload `BreakpointRuntimeBridge` через UID не разрешался в свежем detached worktree. Ecology lab от autoload не зависит и продолжал работать.

Commit `39336f31501f15166cd4eb9766b02c98f5bcaf12` перевёл `RUN_ECO_VIS2_1_LAB.ps1` на isolated temporary project без repository autoloads/editor plugins, не меняя VIS2.1 simulation code.

Повторный graphical launch после repair подтверждён как рабочий.

## Итог

VIS2.1 имеет статус:

**WINDOWS_RUNTIME_VALIDATED_CANDIDATE**

Следующий этап: `VIS2.1-V — Treatment Realtime LOD`, отдельная branch от этого validated checkpoint. Его scope — только presentation: вернуть distance-based near/mid/far detail для единственного rendered Treatment world без second simulation renderer и без whole-field PH5 rebuild.
