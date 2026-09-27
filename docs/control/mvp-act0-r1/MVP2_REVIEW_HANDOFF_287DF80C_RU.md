# MVP2 — exact handoff после восстановления сессии

## Зафиксированный предмет

- Runtime HEAD: `287df80c69840fea7ae9ac0ea69a07581f192d34`.
- Runtime TREE: `e591dc6c5346139bc1b4659915c54bf80603713e`.
- Freeze ref: `freeze/v0-mvp2-287df80c-r1`. Это закреплённая ссылка; branch-protection не изменялась. При каждой проверке снова сверять точный SHA.
- Review diff base: `6fd80b8dbc0cfc422c2ef9a05d2e60a4e7342b57`.
- Canonical main при проверке: `127c732a56cc5c25d5712f24a7627ed4bb877374`.
- Parent `V0-MVP-R1-WO-001` остаётся `IN_PROGRESS`; события 1–7 не меняются. MVP1 закрыт, MVP2 пока не VERIFIED.

Предыдущий ответ чата об отсутствии реализации/записей был неверен. Источником истины являются достижимые commits, event 7 и exact run ниже. Эта запись не переписывает историю.

## Реальное machine evidence

`MVP2 Exact Two Client Shared World`, run `34605253942`, artifact `10266940288`.

```text
ZIP SHA256      850c2422884493c4bd8aeccc2e5dad286c7550610bf43397fe3722f05c746f1f
manifest SHA256 885a15a7552918a67ada595796bb1e4cfe25fb77c68de5c896dac5cdaea4300f
```

317 Harness tests OK, 19 evidence tests OK, MVP1 focused 16 assertions, MVP2 focused 27 assertions. Три отдельных процесса server/A/B, два настоящих X11 graphical client viewport. По сырым witnesses: A переместился на 2,3 м, B на 2,2 м; снимки игроков (кроме верхнеуровневого clock и его checksum) и полный Item Graph совпадают у сервера и обоих клиентов. Все 35 members перехешированы; расхождений нет. PC0 standard/directional YELLOW, blocking RED 0, overlaps пусты. Separate Project Control run `34605258160` SUCCESS на том же HEAD.

Это exact машинная проверка, не independent verdict. Полная world/core-регрессия для этого leaf не запускалась. Windows MVP1 PASS не переносится на MVP2 как новый Windows run. Immutable bootstrap-проекция не является сетевым копанием или доказательством произвольной terrain collision.

## Долговечность и native consumer

Индекс: `config/control/harness/executions/E2026-09-09-V0-MVP-R1/evidence/MVP2-VALIDATION-INDEX-287DF80C-R1.v1.json`.

Индекс не подменяет исходный canonical manifest. Сейчас raw files находятся в digest-bound GitHub artifact (expiry `2026-12-10T13:36:15Z`), а не в этом carrier. Нельзя объявлять native REUSED consumer PASS до публикации всех исходных bytes.

Агент, располагающий локальным Git, должен работать в отдельной evidence/review ветке, происходящей от frozen runtime (или от этого carrier), не в runtime ветке. Скачать оригинальный ZIP artifact `10266940288` через авторизованный GitHub connector/API. Anonymous 401 — ограничение скачивания, не FAIL кандидата; не подставлять иной архив.

Утилита публикационной подготовки:

```text
python docs/control/mvp-act0-r1/materialize_mvp2_evidence.py <original-artifact.zip> --repo <evidence-worktree>
```

Она проверяет ZIP digest, original manifest digest, HEAD/TREE/epoch/order/run, все 35 artifact digest и отсутствие лишних members; извлекает 36 byte-identical files в original intended sink. Не изменяет runtime, не делает git commit/push, не выдаёт PASS роли и отказывается перезаписывать существующий sink. Локально проверены исходный архив (36/36 byte identity), повреждённый архив (отказ) и существующий sink (отказ).

Затем агент проверяет diff, коммитит только новый native evidence sink на своей ветке и запускает неизменённый `validate_review_machine_evidence` / `validate_review_record` для настоящего exact-head review record. Worktree runtime остаётся clean. Не редактировать manifest, не менять старые events, не переписывать старые FAIL. Истечение artifact требует fresh rerun/нового evidence, а не подделки старых bytes.

## Fresh independent review

Отдельный read-only review запрошен в PR #597, comment `5642087579`, точно на `287df80c…`. Обзор старого `991c6f9…` не является final exact review. Реакция бота означает только получение запроса, не PASS.

Проверить source diff, единственного M3/NX authority, replica/remote-presentation, isolated sessions/user data, neutral acknowledgement/velocity boundaries, atomic report publication и сохранение именно проверенного witness, negative controls, bounded R15/R16 changes и честность evidence. Требуются `PASS/FAIL/INSUFFICIENT_EVIDENCE`, exact HEAD/TREE, `required_fixes`, `evidence_gaps`, `rank_up_moves`, `risk_assessment`. Generic completion/emoji не заменяет formal verdict.

После независимых Reviewer/Verifier PASS — отдельный append-only non-terminal `PREDICATE_VERIFIED` для MVP2; parent остаётся IN_PROGRESS. Этот carrier не создаёт такое событие и не разрешает runtime merge, acceptance всего MVP, MVP3 или P8.
