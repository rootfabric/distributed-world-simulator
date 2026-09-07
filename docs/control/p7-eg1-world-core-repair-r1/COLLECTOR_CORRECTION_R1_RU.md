# P7 repair — исправление индекса доказательств

Кандидат `0d8f0f948055432a8f3c4d697e405ec2c1e135a9` запущен в runtime CI
`34117353691`. Project Control `34117403017` завершился успешно; скачанный
artifact `10016833815` имеет SHA256
`e366f417fb8fe6908f7be65c333b2c91a70ab4dc168ed4962c176e79a95a7fa9`.
Полные JSON дают standard/directional overall_health=YELLOW, overlaps=[];
замечания отдельных замороженных веток и блокировка P7 acceptance не скрываются.
Это проверка canonical main c14, не самостоятельное принятие repair-кандидата.

Во время проверки самого сборщика обнаружен дефект: фильтр `p.name !=
"manifest.json"` не включал во внешний файловый индекс также вложенные recovery
manifest.json. Raw-файлы при этом копировались. Исправление исключает только
`out / "manifest.json"`. Production adapter, исходный EG1 и его новый probe
остаются побайтно неизменными относительно 0d8.

Добавлены семь executable unit tests для исключения self-hash, включения
вложенных manifests, fatal при exit0, nonzero exit, явно ожидаемого negative
control, timeout и реального digest raw-лога. На старом collector: 7 tests / 1
failure / exit1. После исправления: 7 tests / 0 failures / exit0. Полные журналы
и digest-map — `collector-evidence/`. Unit fixtures явно помечены как не-runtime
и не-provider evidence. Не засчитывать их как EG1 или full-world PASS.

Workflow выполняет эти тесты на новом точном candidate HEAD, а также сохраняет
read-only Overview, CheckConsistency, Drive, CloseRole, CloseMission. Exit7/8
разрешён только как явный отказ закрытия роли/миссии; он не превращается в
ACCEPTED. Изменения control authority, registry и execution ledger запрещены.
Первый CI и все его отрицательные результаты сохраняются. Для окончательного
кандидата повторяются exact world/core и P7 проверки; старый HEAD не подменяет
новый. Независимые Reviewer/Verifier и человеческое решение ещё обязательны.


Дополнительно первый P7 CI завершил неизменённый P7.7/P7.5 bash runner с exit0,
29 leaf PASS и без fatal, но новый collector отклонил MW6 из-за слишком узкого
регулярного выражения. Artifact `10017042227` / ZIP SHA256
`d9dbda084720a03f7669e9b373ca49c10601540a3230ade2bca65621ba5817ac`
содержит исходный failure.json, raw logs и clean HEAD/TREE; run не переписывается.
Поддержаны все три реально используемых канонических формата, строго связанные
с названием теста и точным числом assertions. PASS без явного failures count
принимается только в штатном terminal-формате соответствующего теста. Отдельно
отвергаются неверный субъект, неправильный count, nonzero failures, дубликат
summary, fatal и FAIL перед PASS. В `p7-leaf-summaries.v1.json` сохранены все
29 фактических terminal-строк из данного artifact как parser fixtures, а не
новый runtime PASS. Всего collector regression теперь содержит 11 unit tests.
