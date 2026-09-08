# Post-build critique — P7 post-acceptance repair

Subject: `62ae64d3651af81d726134b1f2c5b8661000998c` / `b3653e480d42b71a2a2d61fac44086b05a9d73d0`.

Результат Implementer: **NO_MATERIAL_REFACTOR_REQUIRED**. Это не независимый вердикт и не приёмка.

Существующие владельцы MW9/MW10 сохранены. Исправление не создаёт нового Registry/Authority/Transaction или checkpoint truth: меняется только адресация файлов lock. Два sibling repository имеют одинаковые правила, без нового общего persistence owner. Контракты записи checkpoint, CAS progression, pending files и сеть защищены точными source pins и сравнением неизменяемых функций.

Добавочная коррекция MW9-теста не удаляет старые проверки: из нового файла удаляются только три фиксированных добавления и получается прежний Git blob побайтно. Unknown nonempty metadata и empty released residue проверяются раздельно. Ожидаемая ошибка JSON предыдущей попытки не стала исключением в scanner: исправлены данные теста, а ERROR остаётся запретом.

Новый native-тест находится в tests/matter/transactions и автоматически включается существующим world runner через discovery. Он не остаётся только диагностическим скриптом в docs. Повторные случайные прогоны до первого PASS не используются: fixed campaigns и точные negative controls заранее зафиксированы. Все неудачные попытки сохранены.

Оставшиеся обязательства при публикации: полный exact world, отдельный независимый Verifier, разрешённый merge с проверкой дерева, свежие post-merge Harness/PC0 и append-only addendum. Старый accepted record не доказывает принятие этого исправления.

Эксплуатационная граница: private local filesystem одного хоста и единое PID namespace. Перед обновлением остановить всех MW9/MW10 writers; смешанный старый/новый протокол не поддерживается. Invalid nonempty owner metadata остаётся fail-closed. Это осознанное ограничение автоматического recovery, не право удалять неизвестного живого владельца.
