# R2 clearance — post-build critique исполнителя

Subject: `6902a99081c1fbdf676c71dca5ea0d80fd633267`, TREE `f4ae35216de7ed915fcb0c46b03b0f35baeccd6b`; PR #649. Этот документ хранится на отдельном evidence carrier и не изменяет frozen subject. Это не независимый Reviewer/Verifier verdict.

## Проверенные свойства diff

GitHub compare с actual main `a6d5eb6b287130a638ba6cf397c34e29169948c1` показывает ровно семь scoped paths: clearance registry, resolver, исторический тест, новый focused test, brief, input evidence и exact driver. Runtime/network/construction/scene paths отсутствуют. У production auditor entrypoint/loader нет изменений. Старые clearance rows не удалены; исторические тесты сохранены, кроме точной адаптации проверки current-versus-historical rebind.

Новый prerequisite проверяет фактический PR646 merge и journal blob одновременно в baseline commit и текущем origin/main. Проверки identity/hit-set/blob в существующем resolver продолжаются после этого prerequisite. Альтернативный PR643 не нужен. Revert journal после merge не должен пройти по одному ancestry; для этого существует отдельный negative control.

## Evidence и риск ложной приёмки

Raw postmerge ZIP локально перепроверен: SHA-256 `c1bca166ae69ef754065192a5a50e86d51434ccdaa92efba14af691d29c644c1`, 28/28 файлов manifest без расхождений. Свежий CI повторяет проверку распакованных файлов по закреплённому manifest digest. Нельзя трактовать исторические producer verdict IDs как fresh verdict текущего control diff.

Тестовый simulated main создаётся как отдельный локальный bare remote и clone с доступом к исходным объектам Git; записи refs остаются внутри fixture. Raw canonical аудит должен остаться RED до merge clearance. Simulated NON_RED не разрешает запись epoch audit и не означает canonical acceptance. Driver сохраняет эти две категории отчётов раздельно и перепроверяет неизменность настоящих origin refs.

## Остаточные ограничения

Проверенная NX composition содержит симметричную parser-only нормализацию; это не приёмка неизменённого NX source. Clearance применим только к указанным blobs и consumer HEAD/passport. Будущее изменение зависимости требует новой revalidation. Долговременная пригодность других подсистем и MVP6 Construction/physics не доказаны control-only tests.

`status=ACCEPTED` в proposed registry действует лишь после отдельного human-approved merge: production loader не доверяет unmerged копии. Нельзя сливать старый PR644 или альтернативный PR643 по прежнему разрешению PR646.

## Дальнейшая независимая проверка

Fresh Reviewer request: PR649 comment5707014668, whole exact HEAD6902a990. Exact CI: run35170637095 на отдельном read-only validation carrier. Итоги этих запусков в момент написания данного critique ещё не объявлены; terminal results и их hashes должны быть сохранены отдельной append-only записью. После machine evidence требуется fresh Verifier. При findings — bounded repair с новым subject и повторной проверкой, не редактирование старого PASS.
