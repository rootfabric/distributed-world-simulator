# P7: отдельная независимая проверка пакета приёмки

## Граница роли

Это evidence-only ветка: `verify/v0-p7-post-acceptance-r2`. Она не изменяет runtime, тесты или workflow кандидата. Проверяемый продукт: HEAD `62ae64d3651af81d726134b1f2c5b8661000998c`, TREE `b3653e480d42b71a2a2d61fac44086b05a9d73d0`, PR #585, canonical base `438b21d0f5f348d838c2fae0bfae3547ba56a875`.

Нужен свежий **VERIFIER**, независимый от Implementer и от завершённого Code Reviewer (комментарий 5579669682). Read-only. Не реализовывать исправления, не выполнять merge, не создавать ACCEPTED за Implementer. По `HARNESS_AUTONOMOUS_EXECUTION_RU.md` допустима проверка trusted CI evidence без повторения всей машинной регрессии, но недостаточная доступность логов требует INSUFFICIENT_EVIDENCE, а не догадки.

Обычный запрос Codex execution был отклонён ответом 5579683403 (нет environment). Это не результат Verifier. Отдельный review пакета через доступный канал Code Review допустим как попытка альтернативного независимого контекста; общий ответ о коде без проверки этого пакета не объявляется верификацией.

## Что проверить самостоятельно

1. В `packet.v1.json` world, P7 и control обязаны быть завершены на одном exact subject; хотя бы один PENDING означает INSUFFICIENT_EVIDENCE. Проверить реальные jobs и artifact IDs в run 34189730552, а также основной Project Control 34189732621. Название артефакта или success job сами по себе не являются content proof.
2. Сверить SHA256 ZIP с GitHub artifact digest. Пересчитать каждый индексированный member, проверить отсутствие дубликатов/лишних файлов, совпадение HEAD/TREE/run/attempt/engine и clean preflight/postflight. Сопоставить команды, exit codes и raw logs, не доверять пересказу Implementer.
3. Для world: 326 различных скриптов / 331 стадия, native regression обнаружена обычным runner, три P7.4 фазы идут подряд, все exit0 и `main_scene_cli_all` присутствует. Проверить исходные negative controls: ABA22/6, empty-writer14/4, dded MW9 fixture203/2, control8!=0; затем native82, MW9 recovery208, MW9/MW10 process siblings, пять EG1 и три EG4.
4. Для P7: пересчитать все 29 отдельных листьев и их дайджесты/терминальные строки, итог2032/0. Для control: все274 Harness tests, оба PC0 non-RED, zero overlap и zero globally-blocking directional findings. Явно advisory G/ECO RED должны остаться видимыми; false должен быть настоящим boolean, не 0/string/null/missing.
5. Проверить source guards: обратное удаление ровно трёх добавлений восстанавливает оригинальный MW9 blob90a9437e; production MW9/MW10 с dded не менялся; checkpoint/CAS/pending/network owners не менялись. Восстановленные исторические R2 относятся к dca12cec и не могут принять62ae.

## Результат

В отдельном durable комментарии или документе указать: роль и независимый контекст, exact subject, фактически прочитанные артефакты и дайджесты, выполненные команды/проверки, PASS/FAIL/INSUFFICIENT_EVIDENCE, required_fixes, evidence_gaps, risk_assessment. Не утверждать independent machine rerun, если проверялись только trusted CI logs. Generic acknowledgement, queued request и старый Reviewer PASS не закрывают этот gate.

До завершения world и независимой проверки этот пакет не является acceptance. Исторический P7 ACCEPTED сохраняется, MVP не активирован.
