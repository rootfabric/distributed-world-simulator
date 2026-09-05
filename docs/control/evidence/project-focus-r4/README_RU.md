# PROJECT-FOCUS R4 — executable evidence и внешний blocker

Дата: 2026-09-05. Основной draft PR: #547.

Проверенный control subject: `cc89d80599eb24ab4efd55b38332ead4b16468bf`,
TREE `1f51c4a7c0d2e4892d635d6ce830c053f0799ef4`.
Canonical main: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.
Этот evidence-only carrier не заменяет subject и не меняет runtime/main.

Полная машинная карта: `validation-record.v1.json` в этой директории.

## Исполнено

Независимые R1/R2 review findings воспроизведены и устранены в control scope.
Exact event CI 33960324883 завершился success: JSON Schema, duplicate keys,
generation, новые overview/control tests, V0 policies и complete Harness discovery.
Сырые standard/directional PC0 имеют overall YELLOW. Локальные RED G/ECO
сохранены; они не блокируют V0 по main-owned policy. Это не заявление «RED нет».

Свежий независимый code review comment 5551158623 после exact-head request
5551129707 сообщил отсутствие крупных проблем. Формального Harness verdict
этот ответ не содержит; он не заменяет Verifier. Пять inline threads remediated,
исходные comments/reviews не редактировались. Точные ID и исправление clerical
ссылок в Repair Map R4 записаны в JSON и PR comment 5551196939.

Exact PowerShell launcher 33960456571 проверил SHA/TREE, реальные fetch/ref
команды и чистый tracked checkout до/после. Overview/CheckConsistency candidate
завершились exit 0, runtime authority false. Canonical main ещё без control
merge: CheckConsistency exit 3, Drive/CloseMission exit 3 с
EPOCH_REGISTRY_GENERATION_MISMATCH. Эти ожидаемые запреты не являются
разрешением закрыть миссию. Дополнительный локальный Python CLI recheck после
результатов ролей повторил те же ошибки на чистом cc89d805.

## Реальный внешний blocker

Отдельный Verifier dispatch на cc89d805 не исполнился. Ответ Codex в comment
5551132126: «To use Codex here, create an environment for this repo.»

Классификация: EXTERNAL_VERIFIER_ENVIRONMENT_REQUIRED. Repair-author CI и
launcher не являются independent verification. Поэтому нет запроса MERGE,
нет P7 acceptance и нет MVP activation. Нужна среда Codex, привязанная к
rootfabric/distributed-world-simulator, затем отдельная verification этого
замороженного SHA и durable formal role evidence.

## Сырые источники и ограничения хранения

- Project Control run 33960324883, artifact 9967725574: полные JSON/Markdown
  standard и directional reports.
- Launcher run 33960456571, artifact 9967760004: полные stdout/stderr, exit codes,
  JSON outputs, preflight/postflight и SHA256SUMS всех файлов.
- Source export run 33959514945, artifact 9967470666: точный вход fb0d7f6 с Git
  metadata и pinned dependency. Не путать с результатом cc89d805.

SHA256 архивов и ключевых raw records закреплены в JSON. Все downloaded
launcher SHA256SUMS перепроверены. Полные локальные копии доступны в архиве
сессии. GitHub Actions artifacts имеют ограниченное retention; до удаления
артефактов последующий Verifier должен сохранить требуемые raw logs в своём
Git evidence sink. Эта запись не утверждает, что весь stdout уже включён в Git.

Helper #548/#549 не предназначены для merge. Собственный Project Control
helper HEAD 744eeca3/run 33960456590 завершился failure; это не exact candidate
cc89d805/run 33960324883. Причина ancillary helper failure здесь не объявляется
установленной. Сам launcher отдельно checkout-ит cc89d805 и завершился success.

## Что не изменялось и что не проверялось

Runtime, scenes, old P7 execution events/reviews/evidence, acceptance records
не изменены. P7 post-merge full gate, приложенный Godot и визуальный MVP не
проверялись в этой control-фазе. Main всё ещё хранит старый P7 mutation lease
с generation 80; candidate предлагает generation 81, capacity 1, closure-only
hold. До human merge это не каноническая смена lease.

Canonical P7 acceptance path, MVP activation commit, fresh MVP epoch/WO и
Director runtime dispatch отсутствуют. Миссия остаётся незавершённой по
зафиксированному внешнему prerequisite, а не потому, что commit или review
сами по себе являются допустимым концом миссии.
