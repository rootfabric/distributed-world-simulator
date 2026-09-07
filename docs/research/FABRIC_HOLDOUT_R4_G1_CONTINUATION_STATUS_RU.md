# HOLDOUT-R4 G1 — сохранённые результаты и продолжение

Статус: **IMPLEMENTED / G1_FAIL_REPORTED / FINAL_EVIDENCE_RECONCILIATION_REQUIRED**.
Этот документ не объявляет independent acceptance, CLOSED, успешный CI или разрешение SCALE-R5.

## Неизменные идентификаторы

```text
WORK_ORDER = FABRIC-HOLDOUT-R4-WO-001
PR = 583
BRANCH = research/fabric-holdout-r4-frozen-generalization-r1
FROZEN_RUNTIME_HEAD = fd6e83b35301d7a15e92c55939654f1f95729730
FROZEN_RUNTIME_TREE = 314330d717db059cd9b9db32c5d6150097e1f2c3
PREREGISTRATION_HEAD = c73262adf568e2309fe5dd49a034812492566691
MEASUREMENT_HEAD = 9bb354c31d65600eccd6df713118e11a1f26f548
MEASUREMENT_TREE = 846af7694545a361f7b97e738687f244602cc752
CHALLENGE_COMMENT_ID = 3950896660
CHALLENGE_REVIEW_ID = 5133411089
CHALLENGE_AUTHOR = chatgpt-codex-connector[bot]
CHALLENGE_SHA256 = 7e2dd992e372129a7d006ca26fc2666473ca15f5aeeb45d769818cc0216a793f
CAPTURE_RUN = 34136924738
CAPTURE_ARTIFACT = 10024337632
CAPTURE_ARTIFACT_SHA256 = 501a7f8a529b98ac9c01ac498a0885e7d1af24b1a7cb92e260cf813bae562974
CONTROL_AUDIT_RUN = 34139444320
INDEPENDENT_HARNESS_REVIEW_REQUEST = 5572886663
LAST_OBSERVED_EXACT_CI_RUN = 34139101343
LAST_OBSERVED_EXACT_CI_STATE = pending
```

Идентификаторы описывают сохранённые предметы опыта, не утверждают свежесть mutable refs или состояния Actions после последнего чтения. Объектами проверки остаются точные commits, а не HEAD этого status-документа.

## Уже опубликованная реализация

Отдельный Work Order зафиксирован до независимого раскрытия. Затем опубликованы восемь исходных авторских случаев, raw GitHub response и provenance, преобразование в существующие canonical Construction/Matter records, независимые физические ориентиры, metamorphic проверки, ограниченный runner, холодное воспроизведение и диагностика сериализации. Существующие runtime/compiler/solver и R1/R2/R3 tests не изменяются.

Первый завершённый измерительный прогон зарегистрировал 61 исходное/metamorphic измерение: 22 успешных физических или отрицательных проверки и 39 отказов обобщения. Это НЕ 61 независимо созданное семейство. Независимых исходных семейств восемь. Итоговую таблицу нужно связать с фактическим report.json и manifest последнего полного exact-прогона; этот текст не заменяет raw evidence.

Поддерживаемые малый механизм и guard/FULL-поведение дали успешные физические измерения. Физически корректные ветвление, мост и несколько boundary ports отвергаются с R3_SERIES_PATH_REQUIRED; многомассовая и слабомодовая системы — с R3_ONE_SLIDER_REQUIRED. Проверки исходных R2 примитивов для этих пяти семейств проходят. Это capability FAIL R4, а не автоматически дефект относительно узкой грамматики R3 и не успешный отрицательный тест.

Проверка холодного replay также выявила отказы. Отдельный probe внутри Godot, без промежуточного Python-перекодирования, показывает: live checksum и warm replay проходят; JSON.stringify/parse меняет дробное genesis_sources/mechanical_matter/bulk_volume_m3, после чего R3_REPLAY_DOCUMENT_INVALID. Диагностика сохраняет исходные JSON-байты, их SHA256 и двоичное представление отличающихся чисел. Нельзя пересчитать checksum после чтения и выдать это за исправление.

В ходе предыдущего исполнения сообщён полный локальный exact FAIL G1 при успешных неизменных регрессиях R3/R2/R1. Для окончательного доказательного отчёта необходимы raw logs, exits, hashes и проверка именно MEASUREMENT_HEAD/TREE. Pending remote run не считается PASS или FAIL физики. Успешный control audit не является successful holdout.

## Что нельзя делать

Не изменять frozen runtime, исходные авторские кейсы, preregistered thresholds или требования семейств, чтобы сделать G1 зелёным. Не переписывать прошлые FAIL. Не объявлять no-findings review выполнением конкретных verifier-команд. Не вливать PR583 в frozen R3/main. Не активировать SCALE-R5 или INTEGRATION-R6.

## Следующее действие

1. Прочитать актуальные review/comments PR583 и проверить полные локальные/CI результаты для MEASUREMENT_HEAD. Ошибки измерителя отделять от физических/contract failures.
2. Сохранить на отдельной evidence-ветке итоговую таблицу всех восьми исходных семейств, expanded cases, cold replay, неизменных регрессий и freeze-before/after с хешами исходных логов. Отдельно указать actual independent verdict и его ограничения.
3. При исправлениях measurement-инструмента дать новый instrumentation HEAD и повторить исходный неизменный G1; прежние результаты сохранить как superseded instrumentation, а не стирать.
4. Итог G1 при подтверждении наблюдений — EXPERIMENT_COMPLETED_FAIL, не HOLDOUT-R4 CLOSED/PASS. Для будущего успешного R4 требуется отдельный ограниченный pre-freeze этап общей graph/port/multi-mass capability и надёжного persistence representation, после него G2 и новый независимый holdout. G1 после раскрытия является регрессией, не новым holdout.

Проверка возможностей R3 и выполнение экспериментальной процедуры — разные результаты. Работоспособный стенд не доказывает прохождение проверяемой системой HOLDOUT-R4.
