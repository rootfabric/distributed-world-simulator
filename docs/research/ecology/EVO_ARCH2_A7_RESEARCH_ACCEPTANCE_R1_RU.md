# ECO/EVO ARCH2 A7 — приёмка исследовательского исходника R1

Дата решения: 2026-09-13. Роль: USER_AUTHORIZED_DIRECTOR.
Пользователь явно поручил выполнить следующий шаг после готовности A7 к research acceptance. Это отдельное решение о принятии проверенного исследовательского исходника, не Implementer-only PASS и не принятие центрального production checkpoint.

## Решение

**A7 = RESEARCH_ACCEPTED** в ограниченной области Observatory.

- Репозиторий: `rootfabric/distributed-world-simulator`.
- Work Order: `EVO-ARCH2-A7-20260912-R1`.
- Runtime PR: #614; остаётся OPEN + DRAFT.
- Acceptance ref: `acceptance/eco-evo-arch2-a7-r1`.
- HEAD: `8eccf6304078bec3a3ccaa5860c5aab6ee311209`.
- TREE: `24e876b7377cb3e1e521f08ff9766331fe4e895a`.
- Принятый A6: `993271eb46880b77f0e7584f931131d4bd0a5125`.

Acceptance ref указывает непосредственно на проверенный commit. Документы этого решения находятся в отдельной control-ветке от main и не изменяют принятую source TREE. Исторические DISPATCHED/VERIFYING/READY документы в frozen source и completion receipt остаются неизменными.

## Проверенные основания

Независимый whole-A7 review `chatgpt-codex-connector[bot]`: request `5646688780`, result `5646711443`, reviewed `8eccf63040`, «Didn't find any major issues». При повторном чтении перед решением оба прежних threads закрыты; новых блокирующих threads нет. Это существующее независимое review, а не вымышленное новое заключение в этой сессии.

Self-hosted run **34701231448 = SUCCESS**, attempt 1, job `103573241829`, runner `dws-linux-outenemy`. Workflow commit `190ee0791e0b805ada2d42ce6ced0c4e0ca44d86` не подменяет source HEAD. Точный Godot double: `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Повторно сверены байты архива и все 79 логов: контрольные суммы, exit codes, ожидаемый полный набор тестов, markers и error scan; 34 пары побайтово одинаковы. Подтверждены 2361 GDScript assertion executions, включая повторы, и 2 отдельных Python guard tests. В обязательный полный PASS входит graphical32, а не только headless UI. Проверены холодный импорт, 18 source pins и final exact clean seal из доверенного run.

Артефакт `10300600678` / `a7-exact-8eccf630`: 204958 bytes, 94 файла.
ZIP SHA256: `3e0397f440abf5dc21203986dc8fed1bb3ce4c436610d3aa2d7f9dbf0e6dec64`.
Summary SHA256: `71194a042924a01824df1822d964cdb8fcb920ef81f9e5e7630c3a01f6309805`.
Срок хранения Actions: `2026-10-12T15:24:38Z`; это не обещание бессрочного хранения сырых логов.

Manifest всех логов закреплён в `a20fb9d65256fd2fe96b5e411df65d9d4fb8e663:validation/ecology/evo_arch2_a7/COMPLETION_8eccf630_R3_R1.json`. Новая запись сверки: `validation/ecology/evo_arch2_a7/ACCEPTANCE_RECHECK_20260913_R1.json`.

## Графический и научный результат

Повторно просмотрен фактический viewport 1440×960 и сопоставлен с capture-sources.json: tick16, seed20260912, одинаковый founder genotype; wet7 modules / 2 paid propagules, dry1 / 0, dark1 / 0. Изображение не обрезает тело; общий масштаб и подписи читаемы. Материал, вода и энергия сходятся по каждой локации. Снимок и отчёт привязаны контрольными суммами, а не приняты по внешнему виду.

PNG SHA256: `8c0b322e64fd71f7501e9b3c9eae425e6744f41cc954e45d26196937e9408d64`.
Source report SHA256: `09be584972fc30f8bf1ad166ee46af9929b933bc76a7fd4e5fd96b36c0d8ff09`.

## Control и запреты на расширение вывода

Live main при решении: `7dfc68ab5a1e90254a1b7039807f275b5da04eef`, тот же, что в выполненном A7 control audit; registry generation 82. Standard/directional reports = YELLOW. Сохранённые Drive/CloseRole/CloseMission дали exit5 `ACTIVE_EXECUTION_NOT_FOUND:ECO_ARCH2_A7_OBSERVATORY`. Это отсутствие центрального A7 execution; оно не переименовывается в MISSION_COMPLETE. Старые ECO findings не закрываются; global PC0 GREEN не заявляется.

Приёмка ограничена research source: 3 локации, 16 шагов, 2 initial organisms/site, save/report ≤2 MiB. Founder mutation controls не означают автоматическую многопоколенную эволюцию; propagules остаются в outbox. Это не A8 production journal/seam, не Windows runtime qualification и не интеграция в main. A0–A6, production, registry/catalog/scheduler не изменены. Runtime-тесты на этом шаге повторно не запускались: повторно проверена применимость и целостность уже выполненного exact run на неизменном исходнике.

## Следующий маршрут

Следующий исследовательский этап — **A8: snapshot/seam**. Он требует отдельного bounded Work Order, чтения актуальных main-owned contracts и соблюдения ownership/human gates. Эта приёмка **не запускает A8** и не разрешает runtime/main merge. Перенос control-записи в main также остаётся отдельным решением.
