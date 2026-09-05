# PROJECT-FOCUS-2026-09-05-R1 — ограниченная control-работа

Статус: подготовленный кандидат; не acceptance проекта, P7, ECO или FABRIC.
Ветка: `control/project-focus-harness-reconciliation-r1`.
База: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.

## Work Order и полномочия

Основание — запрос владельца привести проект в порядок, выделить визуальное сетевое MVP, согласовать исследовательские ветки и усилить harness. Работа ограничена control-кандидатом поверх указанной main-базы. Этот документ сохраняет её scope; он не является runtime dispatch и не создаёт фиктивный execution ledger.

Разрешены: `scripts/harness/**`, связанные `tests/harness/**`, `config/control/**`,
`validation/harness/**`, control-документы, новый план развития, AGENTS и wrapper,
workflow Project Control. Запрещены: runtime, scenes, simulation owners, переписывание
исторических execution evidence и acceptance, выдача нового runtime lease, merge без
предусмотренного проектом решения человека.

Risk: HIGH — расширяется публичный интерфейс controller и маршрут восстановления
управления. Нужны независимые Reviewer/Verifier и проверка перед принятием. В этой
сессии пользователь запретил запуски и тесты: инструкции AGENTS о Drive/Close и
проверочных запусках не исполнялись, поскольку противоречат этому ограничению.
Непройденные gates не отмечаются PASS и не обходятся.

## Design brief

Проблема: несколько оперативных копий состояния расходятся; research simulation,
visual и bake развиваются с разными точками отсчёта; старый execution может скрыть
саму задачу сверки из-за stale epoch.

Выбранное решение: расширить существующий registry метаданными семейств, хранить
цели в существующих goals, читать их отдельным проектором до execution selection.
Дорожная карта описывает результаты и порядок, CURRENT_PROJECT_FRONTIERS остаётся
указателем. Создание второго scheduler или автоматическое закрытие по branch status
отклонены: они создали бы новые источники полномочий.

Границы: main объявляет состояние; candidate явно обозначен; branch reports не
становятся acceptance. Сохранённые track pins проверяются в соответствующих Git
деревьях. Research findings сохраняют локальный scope. Canonical P7 ACCEPTED имеет
приоритет над историческим долгом сверки, но не принимает следующий MVP checkpoint.

Риски: совместимость новых output_kind с потребителями CLI; смешение Git snapshots;
устаревшие current-state ожидания в regression suites; рост registry generation при
неизменных старых epochs. Меры: явные envelope-ветки в schema и документации,
закреплённый main SHA для чтения acceptance, обновление оперативных ожиданий,
сохранение historical fixtures и запрет runtime во время closure reconciliation.

## Реализованный объём

- MVP-first goals, контрольный срез веток с точными commits и evidence paths.
- Разделение ECO workbench/simulation/VIS/integration/repair и FABRIC core/bake/observatory/history.
- Объявленный, но не dispatched MVP composition checkpoint перед P8.
- Overview и CheckConsistency без требования активного execution.
- Canonical reconciliation route перед stale epoch; P7 acceptance закрывает P7, не MVP.
- Стоп повторного runtime dispatch текущего P7 при hold.
- Обновлённые текущие policy-поля, карта развития и указатели для агентов.

## Evidence и ограничения проверки

Источники анализа — Git main и точные деревья веток, перечисленные в registry.
Историческое P7 rotation evidence сохранено без изменений; расхождение с сообщением
чата записано в `config/control/harness/project-focus-reconciliation.v1.json`.

Независимое pre-build design review выделило семь ограничений: источник полномочий,
независимость от execution, отсутствие второго scheduler, различение состояния refs,
merge/acceptance, согласованность mirrors и изоляция research findings.

Первое статическое implementation review вернуло FIX_REQUIRED: закрытие принятой
P7 зависело от MVP activation; acceptance могла читаться с подвижного ref; локальные
research errors влияли на общий gate; checker пропускал противоречия в mirrors.
Исправления внесены. Следующее чтение выявило недостающий false в registry P7.7
и старые ожидания policy в существующих tests; они также исправлены. Эти результаты
не являются runtime verification.

Добавлены regression-сценарии границ полномочий: candidate не делает dispatch;
обзор не требует execution; research findings не блокируют MVP; завершение P7 не
принимает MVP; acceptance читается с закреплённого main commit; старый dispatch не
обходит hold. Существующие immutable activation/epoch/acceptance fixtures сохранены.

Godot, Python harness, unittest, PC0, Drive/Close и CI в рамках этой сессии не
запускались. Выполнены чтение кода/данных и статический просмотр diff. Работоспособность
новых команд исполнением не подтверждена. Перед merge остаются предусмотренные
проектом проверка control-кандидата, независимая verification и human merge gate.

Статический разбор 9 изменённых Python-исходников через AST и чтение 10 JSON
документов без дублирующихся ключей завершились без ошибок; исходники не исполнялись.
`git diff --check` не обнаружил ошибок оформления diff. Независимое статическое
review для commit `2a502c28269ebc3e07d4570d4497af8bf2d7b628` сохранено в
`PROJECT_FOCUS_STATIC_REVIEW_RU.md` с ограничением NOT_RUNTIME_VERIFIED.

Публикация ветки через `git push` отклонена автоматической проверкой разрешений:
внешняя отправка содержимого в `rootfabric/distributed-world-simulator` требует
явного согласия пользователя на публикацию и адрес назначения. Через другие
интерфейсы публикация не повторялась. Локальные commits и архив изменённых файлов
подготовлены для просмотра; main и remote acceptance этим не изменены.

## Следующая разрешённая работа после принятия control-кандидата

Director сверяет уже существующие post-merge P7 доказательства и оформляет итоговое
состояние через действующую процедуру. Отсутствие найденной записи не является
основанием автоматически повторять все runtime-прогоны. После P7 acceptance —
отдельная активация визуального MVP с точной принятой базой, planner и Work Order.
