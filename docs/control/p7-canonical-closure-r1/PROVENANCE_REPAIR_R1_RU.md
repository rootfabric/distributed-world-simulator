# P7 closure — исправление provenance R1

Исходные замечания: Reviewer #577/3944182567 и независимый Verifier
#578/3944190688 на package 97c9c146bac70c7db317d23d01c8712173751ab7.
Это новые доказательства и ограниченная коррекция аудитора, не acceptance.

## Исправление

Сохранены точные Git blobs исходного runtime workflow и обоих P7 gate-runner.
Manifest связывает source commit/path, blob SHA и SHA256; аудитор проверяет
все три снимка до успешного результата, даже без fetched workflow-ветки.
Снимки только читаются, не исполняются вместо канонического source.

Отдельный actions-snapshot.v1.json содержит проверенную проекцию GitHub API:
run/job/step identities и success states, artifact IDs/digests/sizes и SHA256
каждого файла из фактически скачанных исходных ZIP. Это явно обозначенная
проекция, НЕ подписанная GitHub attestation и НЕ выдаваемый за полный API ответ.
Её собственный SHA256 закреплён в аудиторe. Все 38 runtime members и оба PC0 JSON
сверяются с оригинальными member-hashes. Runtime/job/PC0 IDs, ZIP digests,
engine hash, exit code и clean flags из основного manifest также проверяются.
Engine/exit/clean основаны на exact workflow с set -euo pipefail и успешных
соответствующих шагах provider job, а не только на строке в отчёте.

`--github` повторно проверяет пять оригинальных run/job/artifact API объектов.
CI выполняет его с read-only token. Offline-аудит явно возвращает 0 live checks;
он подтверждает сохранённый capture, а не объявляет свежий запрос провайдера.
Независимый Verifier обязан оценить достаточность доверия к capture и evidence.

Негативные тесты проверяют подмену workflow failure logic, отсутствие nested
runner, wrong workflow/source commit, duplicate snapshots, mutation matrix
run/job/engine/exit/clean, artifact identity/digest и изменённые log bytes.
Локально выполнено 20 tests / 0 failures / 0 errors. Это mechanical self-test,
не результат независимого Reviewer/Verifier. Fresh exact CI и роли обязательны.

## Неудачные world/core попытки сохранены

34037672871: Windows-oriented PowerShell summary writer не увидел скрытый
Unix temp-файл; product assertions ещё не выполнялись.
34037903545: после read-only Get-Item:Force default 37 шагов прошли, M2 test
остановился на отсутствии /usr/bin/Xvfb. Test не пропущен и не ослаблен.
34038189645: dependency installation остановилась на `sudo: a password is required`.
Это внешний недостаток прав runner; повтор того же sudo не выполняется.

ec946f6e1eb140363bcd84184beda087af62523f переключает полный gate на изолированный
GitHub Ubuntu runner. Self-hosted предоставляет только SHA256-проверенный
предсобранный Godot binary dependency; НЕ source, checkout или .git. Репозиторий
получается обычным actions/checkout на exact c14. GODOT SHA проверяется повторно.
Прежний 2032 train не запускается повторно и остаётся неизменным.

FULL_WORLD_CORE_REGRESSION_PASS пока не объявлен. Ни registry, ни scheduler,
ни acceptance, ни runtime lease, ни MVP activation этим repair не изменяются.
