# EVO ARCH2 A6 — приёмка исследовательского исходника R1

Дата: 2026-09-12. Решение: **A6 = RESEARCH ACCEPTED** в пределах Work Order `EVO-ARCH2-A6-20260912-R1`.

Это отдельное решение о bounded research-source после независимого review и фактически завершившейся self-hosted проверки. Оно не объявляет каноническую main-owned mission завершённой и не разрешает production promotion.

## Принятый исходник

| Поле | Значение |
|---|---|
| Repository / PR | `rootfabric/distributed-world-simulator`, #606 |
| Acceptance ref | `acceptance/eco-evo-arch2-a6-r1` |
| HEAD | `993271eb46880b77f0e7584f931131d4bd0a5125` |
| TREE | `adce0899b348d6e8b359d732972af0ca5579c742` |
| Принятая база A5 | `ce98434481c90f7661f787ceb89b07104a586a2f` |
| Implementation branch | `feature/eco-evo-arch2-a6-persistent-feedback-r1` |

Acceptance ref указывает непосредственно на проверенный исходник. Документы приёмки публикуются отдельно в `control/eco-evo-arch2-a6-acceptance-r1`, созданной от main `127c732a56cc5c25d5712f24a7627ed4bb877374`; они не меняют принятый TREE. Ref сохраняется по контракту, без заявления о настроенной branch protection.

## Основания решения

1. Независимый Codex review всего A6: [результат #5642821827](https://github.com/rootfabric/distributed-world-simulator/pull/606#issuecomment-5642821827), reviewed commit `993271eb46`, результат «Didn't find any major issues». При контрольном чтении новых inline findings нет, implementation HEAD не изменился.
2. [Self-hosted run 34667080254](https://github.com/rootfabric/distributed-world-simulator/actions/runs/34667080254), attempt 1, job `103481058351`, runner `dws-linux-outenemy` — **SUCCESS**. Прочитаны job log и ZIP-артефакт, а не только зелёный статус workflow.
3. Повторно вычислен SHA-256 полученного ZIP, проверены все 67 хешей логов из original summary, точные assertion markers, отсутствие fatal/error markers и 29 пар побайтово одинаковых повторных логов.

Workflow HEAD `2579fbd50641de0996569fd11e34d84172e24080` — это оркестрация проверки, **не** принятый runtime HEAD. Checkout, source-blob fence и финальная clean-tree проверка относятся к `993271eb... / adce0899...`.

Godot: `4.7.1.stable.double.custom_build.a13da4feb`; SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

| Gate | Результат |
|---|---|
| A6 core / adversarial / lineage | 77 / 76 / 11 assertions PASS, каждый набор ×2 |
| Cross-process restart write/read | PASS ×2 |
| A5 exact / reviewer repairs | 69 / 29 assertions PASS ×2 |
| Существующие RM11–23, RM25–30, RM32–34 | Все PASS ×2 |
| A4 / A0–A3 | 32 / 86 assertions PASS |
| VIS5.0–VIS5.5 | 521 assertions PASS |
| Cold import / source fence / final exact clean seal | PASS |

Итого: **67 process checks, 1741 assertion executions**, включая повторы. Это не 1741 уникальный тест.

Артефакт: `a6-exact-993271eb`, ID `10290359286`, 49748 bytes; SHA-256 `ad80f01255db65715d465ab077c4498b6639f3ad9c44b9593d52c66602de344d`. Original summary SHA-256: `4bd112048f5bbfede1aa494d38b6c525b89ceaca25c71f587eb1491fa5cd93d0`. Плановое истечение Actions-артефакта: `2026-10-12T04:13:37Z`; наличие digest не является обещанием бессрочного хранения исходных логов в Actions.

Машинное решение: `config/ecology/evo-arch2-a6-research-acceptance.v1.json`. Полный перечень групп логов с individual SHA-256: `validation/ecology/evo_arch2_a6/SELF_HOSTED_34667080254_VERIFIED_R1.json`.

## Контроль проекта и граница приёмки

В remote-артефакте оба аудита выполнены от main `127c732a...`, registry generation 82: standard **YELLOW**, directional **YELLOW**. Историческая ветка `feature/eco-evolutionary-ecology` содержит собственные RED/advisory findings; приёмка A6 их не закрывает и не превращает общий проект в GREEN.

На том же exact main повторены production entrypoints `harness.cli drive`, `close-role`, `close-mission` для `ECO_ARCH2_A6_PERSISTENT_ENVIRONMENTAL_FEEDBACK`: exit 5, `ACTIVE_EXECUTION_NOT_FOUND`. Это честно сохраняется как отсутствие main-owned execution, а не PASS или `MISSION_COMPLETE`. Каталог, registry, scheduler и полномочия main не изменены. Принимается только явно разрешённый пользователем изолированный research-source с отдельным Work Order.

Предмет приёмки: возврат ресурсов трупа через A4 typed effects, capacity-aware остаток, независимая минерализация после вымирания, атомарный candidate step, bounded paid outbox, anchored replay persistence и проверенная причинная связь donor → field → recipient. Принятые A0–A5 и production/simulation/network исходники не изменены.

Сохраняются границы: 32 начальных организма, 64 ячейки, 64 шага, `steps × max(1, initial population) <= 512`, 128 pending propagules, snapshot ≤ 2 MiB. Нет автоматической materialization потомков, mutation/crossover, бесконечного эксперимента, distributed ownership/seam, production storage journal или физико-химической калибровки. Trusted manifest и выбор последнего durable snapshot принадлежат вызывающей стороне.

## Следующий маршрут

**A7 — Observatory**, отдельные Design Brief / Work Order / feature branch от точного принятого A6. Здесь A7 не реализуется и не dispatch-ится. PR #606 остаётся OPEN + DRAFT; runtime merge, перенос в main и production promotion не выполнялись.
