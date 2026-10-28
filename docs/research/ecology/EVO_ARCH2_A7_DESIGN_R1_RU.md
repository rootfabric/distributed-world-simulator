# EVO ARCH2 A7 — Three-location Observatory / Design Brief R1

Дата: 2026-09-12. Work Order: `EVO-ARCH2-A7-20260912-R1`. Risk: HIGH.

## Основание

A0 reconciliation определяет A7: three-location Observatory, wet/dry/dark, common-garden, effects-off/mutation-off, seeds fixed заранее. База — принятый A6 `993271eb46880b77f0e7584f931131d4bd0a5125`, tree `adce0899b348d6e8b359d732972af0ca5579c742`. Main прочитан на `7dfc68ab5a1e90254a1b7039807f275b5da04eef`; registry generation 82. Прочитаны root router, PROJECT_CONTROL/HARNESS_CONTROL, development/review/autonomy/channel-recovery contracts, goals/catalog, ECO passport и A0/A6 design. Это явно разрешённый пользователем research Work Order, не центральная production-активация.

## Решение и граница биологии

A7 — наблюдатель и controller трёх настоящих A6 experiments, не новый ecological kernel. Каждая локация использует неизменённые A4 field и A5 life states внутри A6; UI получает только производные phenotype/ledger snapshots. Шаг трёх локаций атомарен на уровне candidate: если одна не прошла, ни одна не продвигается.

До измерений фиксируется protocol и seeds `[20260912, 104729, 130363]`. Основатели во всех трёх локациях имеют одинаковые генотипы, возраст, endowment и общие random keys. Wet/dry отличаются только исходной водой, wet/dark — светом. Common-garden выращивает те же основательские генотипы заново в одинаковой wet-среде; это новый явно помеченный эксперимент, не бесплатный перенос body/resources между мирами. Effects-off отключает decomposition/mineralization в A6 genesis, не подкручивает output metrics.

Mutation-on применяет настоящий A3 `module_parameter` к исходному genome ДО создания founder, сохраняя parent/child hashes, operator и seed. Mutation-off использует A3 `none`. Не заявляется мутация оплаченных детей: A5/A6 outbox по-прежнему не материализуется автоматически. A7 не выдаёт смену seed за новое поколение, не называет genotype hash видом и не вводит fitness/top-K.

В каждой локации study-растение и явно обозначенный litter donor с ресурсно вызванной смертью. Donor нужен для наблюдаемого resource-feedback; его баланс не рисуется вручную. Графика показывает реальный BodyGraph всех осей и функциональные размеры collector/absorber, в одном масштабе трёх локаций. Мёртвое тело отображается как исторический provenance, не второй расходуемый inventory.

## Управление и сохранение

Одна запускаемая Godot scene: пауза/продолжение, один ecological tick, скорость, reset, предобъявленный seed, common-garden/effects/mutation toggles, выбор локации/организма, inspector с genotype/program/phenotype/ledger, экспорт отчёта и сохранение/загрузка. Treatment меняется только через явный reset, не мутирует live session. Wall-clock speed и UI selection не участвуют в биологических hashes.

Save envelope содержит канонические A6 payloads строками, чтобы не углублять ancestry. Restore требует внешние ожидаемые experiment hash и revision. Дополнительно genesis каждого сайта сверяется с заново полученным из закреплённого protocol/treatment. Хеш, лежащий внутри произвольного файла, не является аутентификацией. Все 3 сайта имеют одинаковый step; частичный restore запрещён. Метрики/экспорт source-bound и ограничены по размеру; отчёт не является импортируемым симуляционным состоянием.

## Bounds / non-goals

Ограниченный research horizon, два initial organisms на site; A6 limits не расширяются. Budget exhaustion — явный STOP/BUDGET, не смерть/отбор. Нет production authority, A8 seam/storage journal, physics binding, бесконечной эволюции, новых химических законов, изменения accepted A0–A6 или main merge. Старые ECO advisory findings и global PC0 не переименовываются в GREEN.

## Альтернативы и проверка

Отдельный UI simulator отклонён как duplicate truth. Предрассчитанные декоративные silhouettes отклонены: изображение обязано следовать тому же phenotype, что функциональные метрики. Live genome editing/offspring mutation отложены, чтобы не обходить A5 paid-parent provenance.

Проверки: все заранее заданные seeds, wet/dry/dark causal differences, common-garden equality при одинаковом genome, mutation-off neutrality и реальный A3 event, effects-off paired control, отсутствие UI mutation, синхронный transactional rollback, malformed/stale/rehash envelope rejects, bounds, process restart, GUI interaction и viewport capture. Exact Godot double с SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`, A7 x2 и preserved A0–A6/VIS5 regressions; затем fresh independent review. Implementer не self-accept.
