# FABRIC R5.6.1 R1 — independent semantic review (16 октября 2026)

## Вердикт: `REVIEWER_FAIL_WITH_FALSIFIERS` / `REPAIR_REQUIRED`

**Точный субъект**: PR #774, HEAD `ee1fa655981bba4c7adadd3e7d1d64b3635dfae1`, TREE `52b2c8c94ad69faeff824e9208b5849fcc68268b`, BASE R5.5 merge `e74c20725a760e56cac01ffd9eaf39a5e9ad5a90`. Сам продукт не изменялся, `main` не затронута, merge не выполнен.

**Платформа независимого воспроизведения**: канонический Godot Linux `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`. Собственный отдельный detached Git checkout из точной истории. Тест из Reviewer не входит в продуктовый PR; создан независимо от авторского acceptance. Для нового теста `--check-only = 0`, реальное исполнение `EXIT=1 (expected RED)`.

## Что прошло (SOUND)

- Код аддитивен, 9 файлов R5.6.1; closed R5.1–R5.5, Construction/Matter schemas и `main` не изменены.
- Обычные источники/снимки проверяются существующими `ConstructSnapshot`, `ConstructionConstructMutation` и `BRIDGE-4`.
- Имеется separation of concern: `Session.prepare` лишь формирует предложение, без собственного вызова `Store.apply_mutation`.
- При честном жизненном цикле опубликованная каноническая ревизия делает старый binding stale; внешний альтернативный successor без изменения private pending отвергается штатным сценарием.
- Полный независимый Linux exact пройден (см. `FABRIC_R5_6_1_R1_FRESH_VERIFIER_RU.md`): 3×203/0, BRIDGE-4 49/0, collector PASS. Эти зелёные результаты подтверждают покрытый acceptance, а **не** отсутствие выявленных ниже дефектов.

## BLOCKER F1: имитация canonical Store через duck typing

`r5_6_1_canonical_delta_session_v1.gd:22` проверяет `store.has_method("get_snapshot")`, **но не принадлежность переданного объекта** проверенному `ConstructionConstructStore` и не наличие доверенного источника. Новая GDScript-заглушка `SpoofStore extends RefCounted` с единственным `get_snapshot()` проходит `start`, может предоставить корректный ConstructSnapshot, после чего `prepare` и `observe_external_commit` проходят полностью. Реальной операции `ConstructionConstructStore.apply_mutation` нет, но сессия объявляет внешнее изменение наблюдённым и публикует новый derived graph.

Исходный контрпример: **`duck_store_start_accepted=true`, `fake_proposal_prepared=true`, `fake_commit_observed=true`**. Falsifier ожидает отказ недоверенному объекту; реальный исход — успех (RED). Это нарушение формулировки Work Order «derived consumer настоящего внешнего ConstructionConstructStore» и подрывает доверенную границу, хотя не доказывает компрометацию существующего production-сервера.

**Repair map**: вводить проверяемый тип/подтверждённую владельцем ссылку на настоящий Store (не просто наличие метода), отделить авторизованный owner/receipt от произвольного GDScript-поставщика DTO. Запрещено считать произвольный `get_snapshot` доказательством внешнего canonical commit. Тестировать фальшивый store и обычный настоящий Store одновременно.

## BLOCKER F2: post-prepare rewrite внутреннего pending-предложения

В `r5_6_1_canonical_delta_session_v1.gd:47` `_pending` получает mutable `Dictionary`. `observe_external_commit()` на строках 50–75 доверяет **текущему** `_pending` и заново вычисляет ожидаемый successor на основании его полей. При этом не сохраняется независимый неизменяемый binding к **первоначально** подготовленному предложению.

Falsifier запускает настоящий `ConstructionConstructStore`: `Session.prepare(BREAK_BOND, link-01, event_id)` проходит; внешний владелец вместо него применяет другую, корректную `SET_BOND_STRENGTH(link-03,123.0)` с тем же event ID. Контрольный исход без вмешательства в `_pending` — `R56_AUTHORITATIVE_SUCCESSOR_MISMATCH`. После согласованной подмены `session._pending = alternative.details.duplicate(true)` вызов `observe_external_commit` **успешен**, а `read_binding()` возвращает опубликованный graph. Исходная предложенная операция не выполнялась.

Payload: **`original_prepared_action="BREAK_BOND"`, `external_actual_action="SET_BOND_STRENGTH"`, `forged_pending_observed=true`**. Новый strict assertion ожидает отказ, фактически получает success (RED). Это требует возможности изменять GDScript-поля runtime-объекта (отдельная модель угроз; не обычное изменение возвращённого detached DTO), но именно такой класс mutable provenance-блокеров выявлялся в R5.5. Полагаться только на `_pending`, допускающий согласованную подмену всех полей, для high-risk source admission опасно.

**Repair map**: надёжно связать original prepare с ожидаемой authoritative mutation/receipt до публикации, не используя только второй изменяемый runtime-хеш как независимый эталон. Сохранить invariant: внешняя легитимная мутация, отличная от подготовленного предложения, не становится принятой только из-за подмены derived памяти. Нужны RED→GREEN и rollback/ретрай.

## Дополнительные оговорки / scope findings

- Срок жизни `events` ограничен derived session; `ConstructionConstructStore` не хранит event ID, cold restart exactly-once отложен в R5.6.2. Не объявлять R1 production exactly-once across sessions.
- `MatterBatch` и authority подаются из trusted caller и сравниваются при observe, но в R1 нет live Matter authority service. Не утверждать, что сессия обнаруживает все out-of-band matter/authority изменения в любой момент.
- O(N) recompilation/хеширование допустимо по Work Order R1; динамические агрегаты и физический tick — R5.6.1 R2 / R5.6.3. Обязательные performance утверждения не были расширены.

## Evidence / next action

Файл `review_r56_1_owner_and_proposal_falsifier.gd` и оригинальный stderr/stdout находятся в ZIP. Точное содержимое теста помещено в отдельную review-ветку, не в PR #774.

**Текущий итог**: точный Linux runtime `PASS`, semantic Reviewer `FAIL`, общий gate **`REPAIR_REQUIRED`, `MERGE_READY=false`**. Требуется bounded repair в PR #774, новый HEAD/TREE, свежие Linux/Windows exact и новый независимый reviewer/verifier. Не менять закрытые R5 kernels / `main`. Не делать merge.
