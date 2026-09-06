# PROJECT-FOCUS — Repair Map R4: canonical gates и event-aware CI

Дата: 2026-09-05. Parent: PROJECT-FOCUS-CONTROL-VALIDATION-R1 / PR #547.
Risk: HIGH. Замороженный вход: `fb0d7f67991e3d840243a49da0dd36938a1e3dfd`,
TREE `963f47285fb62589d76657cb8b21ef32189bcb44`.
Canonical main: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.

## Основание и воспроизведение

Независимый Reviewer R2: `chatgpt-codex-connector[bot]`, review 5120775578,
2026-09-05T09:56:40Z. Required findings: 3940214680, 3940214686, 3940214692.
Это новые конкретные дефекты; замечания R1 и их исторические результаты сохранены.

На неизменённом входе в изолированном локальном Git fixture воспроизведены четыре
неправильных exit 0: Drive без jsonschema; Drive при несовпадении registry/lease
generation; изменённый registry без увеличения generation; новый JSON с повторным
ключом после push в main. Fixture refs не изменяли remote/main или source checkout.
Полный reproduction log сохраняется отдельным append-only evidence после exact-run.

## Карта исправления

| Finding | Владелец / вход | Причина | Ограниченное исправление |
| --- | --- | --- | --- |
| 3940214680 | ContractBundle / canonical_reconciliation_route / CLI | Early route читает scheduler и acceptance, обходя dependency/contract и consistency gates | Проверять bundle, schemas и product consistency на одном закреплённом main snapshot, без загрузки старого execution epoch |
| 3940214686 | Project Control candidate validation | Константа generation >= 81 не сравнивает изменение с исходным canonical control | Сравнивать generation и изменённые registry/scheduler с exact comparison base; отклонять rollback, повторное использование и несовпадение lease |
| 3940214692 | Project Control workflow JSON selection | origin/main...HEAD пуст после push в main | Для push использовать event.before..HEAD; при отсутствии предыдущего дерева проверять все текущие control JSON; PR и прочие события сравнивать с закреплённым canonical main |

Callers: публичные Status/Plan/Resume/Drive/CloseMission, CloseRole, Project Control
CI. Siblings: read-only Overview, CheckConsistency, explicit execution, candidate
preview, scheduled/manual/post-merge CI, historical epoch tests.

Work Order scope не расширяется: scripts/harness, tests/harness, Project Control
workflow и этот документ. Нового scheduler, authority или runtime lease нет.
Общий CI validator извлекается из существующего inline-кода для воспроизводимых
тестов; это не второй владелец политики. ContractBundle остаётся владельцем
контрактов и поддерживает чтение из одного pinned Git snapshot.

## Границы и required validation

Acceptance lookup выполняется только после control gates. Research-local findings
не блокируют MVP; product/observability errors блокируют route и close. Epoch
generation не переписывается: старые execution остаются непригодны для нового
runtime dispatch. Canonical P7 acceptance не принимает MVP.

Нужны отрицательные и положительные tests для всех трёх дефектов, existing overview,
role/mission, generation-80, complete Harness discovery, exact event CI, pinned
PowerShell wrapper, standard/directional PC0 и fresh independent Reviewer/Verifier
на одном новом subject. Локальный implementer validation не заменяет независимость.

## Внешний blocker независимого Verifier

Codex дважды ответил на отдельный verifier dispatch PR #547:
`To use Codex here, create an environment for this repo.`
Комментарии: 5550862331 (09:31:41Z) и 5550883833 (09:50:35Z).
Это external execution-environment prerequisite, не human merge approval и не
runtime defect. Нельзя создавать VERIFIED или принимать результат автором repairs.
Автоматизируемые repairs и executable evidence продолжаются независимо от blocker.

P7 acceptance, MVP activation/epoch/WO, runtime, scenes и historical evidence этим
изменением не создаются и не переписываются. Merge остаётся human gate после всех
доказательств. Миссия не объявляется завершённой этим Repair Map.

## Связанные regression fixtures

Первый полный локальный discovery выявил два старых положительных fixture,
содержавших только scheduler без обязательных canonical contracts. Они теперь
получают реальные неизменённые policy/schema/product-evidence файлы, но не execution
epoch. Отдельный отрицательный test закрепляет запрет scheduler-only route. Новые
проверки production не ослаблены; historical events/reviews/evidence не изменены.

Bounded critique: извлечён один общий CI validator вместо дублирования inline-кода;
canonical route использует существующий ContractBundle и read-only consistency,
не новый owner. Независимые роли и human gates сохранены.

Prepublication diagnostics: focused 35 tests / 0 failures; после исправления
неполных fixtures полный discovery 196 tests / 0 failures / 0 errors / 2 skips
(live GitHub metadata tests без DNS). Schema/duplicate-key и candidate consistency
exit 0. Это diagnostics изменённого checkout, не exact published verification.
После публикации обязателен новый exact CI без этих skips и fresh review.
