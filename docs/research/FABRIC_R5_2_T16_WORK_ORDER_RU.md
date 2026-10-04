# FABRIC R5.2 / T16 — Work Order R1

Статус: IN_PROGRESS. Роль: IMPLEMENTER. Риск: HIGH (physical fallback / state preservation).

Разрешение: явный запрос пользователя реализовать T16 после merge T14 #719 и T15 #732.

## Exact inputs

- canonical main observation: `894f7033b16cefcf78e40d660bdbaf0c9b061afe`;
- research base: T15 merge `d53352bca414f806a1096633ea683ba21b955083`;
- base tree: `ce5c0faa0e67e847cb1a4557059790eb22024754`;
- branch: `research/fabric-r5-2-t16-no-safe-bake-r1`;
- roadmap: `FABRIC_CURRENT_ROADMAP_R4_1_R4_2_R5_RU.md`, раздел T16.

## Scope

Новая additive research negotiation/fallback surface и исполняемый falsification campaign. Проверить hidden mode, observability/event contract, reconstruction, conservative step/error envelope, stale/corrupt provenance и numerical refusal. Использовать существующие T4 physical executors и T1 singular reducer, не вводить device-specific physics kernels. Declined candidate не исполняется и не публикуется. Canonical source/state остаются caller-owned. FULL не обходит authority и не выдумывает недостающее состояние. Не допускается два physical executor на один attempt.

Разрешены только новые T16 runtime/test/runner/collector/docs/evidence файлы и отдельный control-only Windows carrier. T1–T15, physical core, main registry, LIVE, ECO и SHIP-LAB не изменять. T16 не заявляет production integration или R5.3 recursive execution.

## Validation and handoff

Canonical Linux double SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`; fresh import; three separate T16 processes; deterministic physical trace evidence; unchanged T15/T14/T13.5/T13/T12 regressions; strict Python evidence checks. Затем exact Windows на опубликованном HEAD/TREE, durable implementer evidence, fresh independent Reviewer/Verifier. Implementer не присваивает себе independent PASS или ACCEPTED. Merge только после отдельного human gate.

## Repair R2 — F1/F2/F3 (review 5405947680)

Разрешение: отдельный явный запрос пользователя закрыть ровно три замечания. START/Repair Map опубликован в PR #734, comment 5979853850. Input HEAD `a34ab6409c35974b2499badd0bb3e3e1e5da04ff`, tree `f6aef32e753dba6cc214ca33e318ab0185688d63`. Роль остаётся IMPLEMENTER.

- F1: владелец — temporal policy T16 adapter; prepare_candidate и execute_full использовали разные схемы интеграции. Выбрано консервативное решение: единая функция выбора FULL substeps, COMPACT допускается только при одном FULL substep. Оценка ошибки и tolerance не расширяются. Альтернатива — новый многошаговый compact executor — отклонена как лишняя для узкого repair. Проверка: 22 парных actual COMPACT/FULL сценария около rate*dt=0.5, на 0.75 и до прежнего 0.9 предела; независимые source-cell события.
- F2: владелец — T16 _source_gate до candidate/COMPACT/FULL. Оба request/live envelopes валидируются, привязываются к graph/material и сравниваются по canonical frontier, authority и dependencies. Проверяются live-only смены owner/epoch/revision, missing fields и graph/material/dependency mismatch. Свежий source со старой только capsule сохраняет FULL-путь. Новая система authority не вводится.
- F3: владелец — FULL-adapter до native Full.execute. Точная схема и numeric domain проверяются явно; неизвестное состояние отказывается, не усекается и не копируется как якобы решённая физика. Наблюдаемые native solver call/state-update counters должны оставаться нулевыми при таком отказе.

Разрешённый diff относительно R1 — существующие T16 gate/backend/acceptance/collector/Python tests и две T16 documentation surfaces. Тесты ядра, T1–T15, runners, основной whitelist и main control не менять. Отдельный control-only Windows carrier допустим. Требуются чистая exact-tree проверка, 3 Linux + 3 Windows процесса, исходные регрессии и новое независимое ревью; implementer PASS не закрывает независимые gates.
