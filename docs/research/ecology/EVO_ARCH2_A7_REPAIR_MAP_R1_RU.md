# A7 Repair Map R1 — publication byte pin

Work Order: EVO-ARCH2-A7-20260912-R1. Exact failed source: baf97c89c8c84d6b3341d5e57865f25b75ab6c85. Run34696740552, job103561401420: failure BEFORE runtime tests.

Источник: source-blobs fence обнаружил `scripts/labs/ecology/arch2_a7_observatory.gd` actual8cf89d035999b0cd9a73769ebd459134fec0cc66 против prepublicationac97e6d57c292387958df0266a43ecc6947ec636. Все первые шесть проверенных файлов совпали; дальнейшие pins должны быть проверены новым run.

Root cause: локальная трёхстрочная summary-надпись содержала literal newline внутри GDScript string. Публикация записала два перевода строк как `\n`. Локальная замена ровно этих двух последовательностей воспроизвела Git blob8cf89d035999b0cd9a73769ebd459134fec0cc66; другие строки UI не менялись. Это совпадающая текстовая семантика, но не byte-identical файл, и старый pin был неверен.

Repair: исправлен published source pin, не код и не assert gate. Runtime source, tests и verifier неизменны. Предыдущий run остаётся FAIL, full tests не выполнялись; отсутствие artifact после preflight failure не выдаётся за потерянный PASS. Новый frozen HEAD требует полного exact-run и свежего review. Pin сам по себе не доказывает поведение: настоящий UI gate и capture выполняются после него.

Sibling coverage: manifest проверяет все16 файлов, fail-closed mismatch не отключается. Local prepublication evidence остаётся помеченным как prepublication; конечный source/runtime должен проверяться на опубликованном exact HEAD/TREE.
