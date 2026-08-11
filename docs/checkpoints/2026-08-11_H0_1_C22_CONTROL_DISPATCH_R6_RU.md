# H0.1 / C22 — CONTROL DISPATCH R6

Статус: **PRE-DISPATCH CONTROL CANDIDATE**.

- Epoch: `E2026-08-11-H0-1-R6`
- Canonical base: `1112d1f7cfad1df18fb3621a537e191e674848c6`
- Registry generation: `75`
- Work Order: `H0-1-R6-C22-WO-001`
- Risk: `HIGH`
- Runtime worker limit: `1`
- Runtime merge: **FORBIDDEN** до `H0_1_PASS + C22 SOURCE_ACCEPTED_MERGE_READY` и отдельного human gate.

## Назначение

Первый H0.1 closed-loop runtime pilot должен перенести SOURCE_ACCEPTED C22 incremental local rebuild в свежую ветку от текущего `main`, не импортируя историю старой C22 ветки. Старый `feature/c22-incremental-local-rebuild` является только источником доказательств и принятых файлов.

## До Director dispatch

Разрешены только control/harness изменения. C22 production/runtime файлы не меняются.

## После Director dispatch

Разрешено создать ровно одну runtime-ветку `feature/h0-1-c22-current-main-r1` и выполнить bounded capability transfer только по путям Work Order. Далее обязательны production diff equivalence, C22 focused, C24 contracts, graphical, full world/core regression, Evidence Map, Reviewer/Verifier, standard/directional PC0 и recovery drill.

## Стоп

Этап обязан остановиться на предложении `H0_1_PASS + C22 SOURCE_ACCEPTED_MERGE_READY`. Runtime merge не входит в этот Work Order.
