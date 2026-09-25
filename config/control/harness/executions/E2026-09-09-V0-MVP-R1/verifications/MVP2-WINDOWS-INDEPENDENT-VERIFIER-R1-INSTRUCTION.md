# MVP2 — FRESH INDEPENDENT WINDOWS VERIFIER R1

Ты работаешь как **FRESH INDEPENDENT VERIFIER**, не Implementer и не Reviewer, для проекта `rootfabric/distributed-world-simulator`.

## Цель

Независимо решить только один bounded predicate: `MVP_TWO_CLIENT_SHARED_WORLD`.

Не принимать на веру предыдущий Implementer/Reviewer/coordinator PASS. Все SHA, refs, digests и Git topology перепроверить live. Не делать MVP3, не делать whole-MVP acceptance, не merge в `main`, не менять frozen runtime, не переписывать события 1–7.

## Точки, которые нужно перепроверить live

Canonical main, ожидаемый: `7dfc68ab5a1e90254a1b7039807f275b5da04eef`.

Frozen MVP2 runtime:
- HEAD `287df80c69840fea7ae9ac0ea69a07581f192d34`
- TREE `e591dc6c5346139bc1b4659915c54bf80603713e`
- freeze ref `freeze/v0-mvp2-287df80c-r1`

Reviewer/evidence carrier: `666a6ff703c82de05307b2f55562000df7709101`.

Current-main composition: `8812e229e22a711338f9243f50350cca87cec3cf`, expected parents:
- `7dfc68ab5a1e90254a1b7039807f275b5da04eef`
- `666a6ff703c82de05307b2f55562000df7709101`

Verification carrier machine-pass parent:
- HEAD `8e0782450a2c46e58c463e5a73e23bd656ba6273`
- TREE `3018de2a955080835ba31523e2c1bf843a0554e6`

Machine PASS:
- Project Control run `34691381495`
- job `103547126527`
- full Harness `333/333`, 0 failure, 0 error
- PC0 standard YELLOW, HARNESS GREEN
- directional PC0 YELLOW, blocking RED = 0
- artifact `10296269475`, bytes `27586`
- artifact SHA256 `80d77e0ab45bc5979157e220112a5e809e3040e193048627de66e35f5cb165bc`

Original exact MVP2 evidence:
- run `34605253942`
- artifact `10266940288`
- ZIP SHA256 `850c2422884493c4bd8aeccc2e5dad286c7550610bf43397fe3722f05c746f1f`
- native manifest SHA256 `885a15a7552918a67ada595796bb1e4cfe25fb77c68de5c896dac5cdaea4300f`
- 35 indexed members, expected digest mismatch = 0

Formal Reviewer record:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/reviews/MVP2-INDEPENDENT-REVIEW-287DF80C-R1.v1.json`

REUSED evidence manifest:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/evidence/MVP2-REVIEW-PROJECTION-287df80c6984-34605253942/manifest.v1.json`
expected SHA256 `06638b1b4a111c0eef4cb2028c592ee3e0cfce18f2d9eb3a5922d52b4ec78c17`.

Machine carrier record:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/evidence/MVP2-CURRENT-MAIN-CARRIER-MACHINE-PASS-8E078245-R1.v1.json`.

## Исходная ветка Verifier

Начинай только от `control/v0-mvp2-verifier-handoff-r1`.

После fetch создай свою ветку: `verify/v0-mvp2-287df80c-current-main-r1`.

Не продолжай, если handoff HEAD отличается от того exact SHA, который указан в machine record внутри ветки, пока не разберёшься с append-only изменениями.

## Обязательная независимая проверка

1. Прочитать `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/control/DEVELOPMENT_HARNESS_RU.md`, `docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md`, `docs/control/HARNESS_CHANNEL_RECOVERY_RU.md`.

2. Git identity/topology:
   - `git fetch origin --prune`;
   - проверить live `origin/main`;
   - проверить HEAD/TREE frozen runtime;
   - freeze ref должен указывать на frozen runtime;
   - `git merge-base --is-ancestor 7dfc68ab5a1e90254a1b7039807f275b5da04eef <handoff>` должен PASS;
   - проверить parents `8812e229e22a711338f9243f50350cca87cec3cf`;
   - доказать, что repair после composition менял только test-fixture scope, а production runtime/Harness policy не менялся.

3. Проверить Reviewer как входной факт, но не принимать его выводы:
   - schema/review type/subject HEAD/TREE;
   - `verdict=PASS`, `required_fixes=[]`;
   - machine manifest path/digest/run binding;
   - выполнить production consumer для review record через `scripts/harness/evidence_provenance.py`.

PowerShell: `$env:PYTHONPATH="scripts"`. Затем Python должен загрузить current `config/control/harness/harness-policy.v1.json`, epoch `config/control/harness/executions/E2026-09-09-V0-MVP-R1/project-epoch.v1.json`, review JSON и вызвать `harness.evidence_provenance.validate_review_record(root, policy, epoch, review, relative)`. Требуемый итог: без exception.

4. Independently проверить raw evidence:
   - пересчитать SHA256 committed projection manifest;
   - пересчитать SHA256 всех `artifact_paths` из manifest;
   - проверить exact subject/run/work-order/epoch/runner bindings;
   - прочитать `result.json`, а не только summary;
   - `passed=true`, `errors=[]`, `runtime_workload_pass=true`;
   - все ожидаемые child processes exit 0;
   - negative controls должны быть true;
   - result не должен сам объявлять `independent_verdict=true` или `predicate_verified=true`.

5. Source review независимо от Reviewer:
   - diff `6fd80b8dbc0cfc422c2ef9a05d2e60a4e7342b57..287df80c69840fea7ae9ac0ea69a07581f192d34`;
   - убедиться, что нет нового canonical network/Item/Matter/persistence owner;
   - composition root должен переиспользовать existing M3 server/client + RemotePlayerPresenter;
   - bootstrap surface не должен сохранять mutable Matter authority;
   - проверить validator/fixture на process isolation, user-data isolation, session identity, both-direction movement, shared snapshots, full Item Graph equality, neutral acknowledged boundary, remote visibility и negative falsifiers.

6. Windows machine corroboration. Используй установленный exact Godot 4.7.1 double. Ожидаемый SHA256 Windows binary: `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`. Сначала вычисли hash фактического binary. Если exact binary отсутствует — это evidence gap, но не подменяй его другим Godot.

На verifier handoff/current carrier допустимо выполнить:
- `python -m unittest discover -s tests/harness -p "test_*.py" -v`
- `python -m unittest discover -s tests/integration -p "test_v0_mvp_two_client_evidence.py" -v`
- `python scripts/control/project_control.py --no-fetch --no-fail-on-red`
- `python scripts/control/project_control_directional_watch.py --no-fail-on-red`
- exact Godot import
- `res://tests/runtime/test_v0_mvp_two_client_shared_world.gd`

Проверяй exit code и fatal markers, а не только PASS-строку.

**НЕ запускай `validate_mvp2.py` как current-main exact validation**: frozen producer намеренно hardcodes historical main `127c732a...`; такой запуск на current main ожидаемо даст MAIN_DRIFT и не является корректным новым доказательством. Не подменяй `origin/main` старым SHA ради PASS.

7. Если есть GitHub access, независимо перепроверь metadata original run/artifact. При возможности скачай artifact `10266940288` и пересчитай ZIP SHA256. Если download недоступен, committed digest-bound projection + production consumer остаются допустимыми, но явно запиши это как inherited/reused evidence, а не fresh runtime execution.

8. Проверить machine/current-main gate:
   - run `34691381495` действительно SUCCESS на `8e0782450a2c46e58c463e5a73e23bd656ba6273`;
   - exact checkout совпадает;
   - full Harness `333 tests ... OK`;
   - standard/directional PC0 не имеют blocking RED для этого bounded continuation;
   - artifact `10296269475` digest совпадает с machine record.

## Verdict

PASS/VERIFIED разрешён только если exact frozen runtime identity подтверждена; source review не нашёл required fix; Reviewer record и REUSED machine evidence проходят production consumer/digest verification; current-main topology/audit carrier валиден; нет blocking evidence gap именно для `MVP_TWO_CLIENT_SHARED_WORLD`.

Если найден дефект — `FIX_REQUIRED` с точным файлом/строкой/репродуктором. Tool/network failure — не product FAIL; используй durable refs и fallback, а затем честно укажи недоступный маршрут.

## Durable output

Если VERIFIED: создай ровно один verifier result (и только необходимые fresh verifier logs/manifest, если решишь их коммитить) в новой verifier branch.

Рекомендуемый путь:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP2-INDEPENDENT-VERIFICATION-287DF80C-R1.v1.json`

Используй schema `distributed_world_simulator.harness_verification.v1`.

Минимально зафиксируй:
- verification_id;
- work_order_id/project_epoch/program/checkpoint;
- verifier identity;
- `verifier_role_is_not_implementer_not_reviewer=true`;
- verdict `VERIFIED` или `FIX_REQUIRED`;
- verified_at_utc;
- `execution_performed` (только то, что реально запускал);
- `inherited_execution_evidence` (true для reused original Linux runtime evidence);
- frozen runtime HEAD/TREE/ref;
- current main;
- handoff/carrier HEAD/TREE;
- reviewer record path/digest/verdict;
- original run/artifact/digests;
- current-main Project Control run/job/artifact/digest;
- все выполненные команды, exits, assertion/test counts;
- Windows OS/Git/Python/Godot version+SHA;
- evidence gaps/nonblocking notes;
- tracked cleanliness before/after;
- `merge_performed=false`;
- `human_approval_created=false`;
- явно: whole-MVP acceptance=false, MVP3 not started.

Коммит: `verify(mvp2): independent Windows verification of frozen two-client predicate`.

Push only `verify/v0-mvp2-287df80c-current-main-r1`.

**Не создавай `PREDICATE_VERIFIED` event и не обновляй Work Order snapshot.** Это сделает coordinator после чтения твоего verifier result. Не merge ни один PR.

В финальном ответе верни:
- VERDICT
- verifier branch
- result commit + TREE
- result file path
- frozen runtime HEAD/TREE
- handoff HEAD/TREE
- Windows Godot SHA
- commands/results
- evidence gaps
- git status clean/dirty
- подтверждение `NO_MERGE / NO_EVENT / NO_MVP3`.
