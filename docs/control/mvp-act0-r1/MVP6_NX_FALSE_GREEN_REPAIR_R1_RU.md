# MVP6 → NX: восстановление достоверности dependency evidence

Parent: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`.
Замороженный исходный subject: `3a969296cadfe2f750d5c51cabc9c0792a66f6ee`,
tree `98ad696851db57d6bb53db9d2d3a02f1936729e4`.
Main `6982a563dd0c88c81449566131852c601ae89868`; NX
`1a56fe0e845c941f14ce7b9296ee939e9d0ca8bc`.

## Найденный дефект и независимая оценка

Run `35090924573`, artifact `10444336824`, ZIP SHA256
`ce84c862c8a20b52f837b8b595bc3558297a39b74bae4bf9f120922127bedd83`
содержит ложный `dependency_revalidated=true`. Исходная evidence сохранена без
изменений в соседнем каталоге `nx-false-green-r1/`. Двенадцать log hashes совпадают
с исходным summary. В обеих композициях movement печатает PASS (20 assertions),
rollback — PASS (0 assertions), несмотря на семь ERROR/SCRIPT ERROR в каждом
из этих четырёх логов. Остальные три теста исполняют 31, 25 и 940 assertions.

Fresh read-only Reviewer `/root/nx_evidence_review` независимо проверил этот
subject и все логи: **FAIL** для исторического positive claim;
**INSUFFICIENT_EVIDENCE** для реальной совместимости. Регрессия V0 не установлена.
Это отменяет пригодность старого summary для clearance, но не переписывает его.

## Repair Map

Owner проверки — `mvp6_nx_dependency_probe.py`; callers — именованный diagnostic
workflow и `mvp6_nx_dependency_probe_exact_runner.py`. Root cause: probe принимал
exit 0, а GDScript тесты после runtime exceptions могли доходить до `_finish()`
с пустым failures. NX leaf `networked_gameplay_service_owner_movement.gd:63`
содержит динамическое `var validation := _movement.apply_authoritative_state(`.
Parser error лишал часть тестов исполняемого OwnerService. Это дефект проверки
evidence и отдельно compiler debt старого NX composition.

Bounded repair: fatal-log scan import/tests, ровно один PASS, точные динамические
counts 44/31/37/25/940, одинаковые counts A/B. Sibling wrapper больше не повторяет
уже выполненную tick normalization. Windows/Linux engine hashes фиксированы.
Временная NX runtime normalization меняет только один `:=` на `=` одинаково в
A/B, с точным precondition и before/after hashes. NX branch не меняется;
assertions, payloads, вызовы и алгоритм не меняются. Это расширение только
диагностической композиции, не разрешение runtime repair NX.

Новый результат — **PARSER_NORMALIZED_NX_COMPOSITION**: допускается проверка
узкой совместимости одного V0 M4 blob, но запрещены raw NX runtime PASS,
NX source acceptance, MVP6 acceptance и foundation mutation acceptance.

## Следующая проверка и recovery

Отклонить четыре исходных false-green logs, включая ненулевой movement count;
проверить отсутствующий/нулевой/неполный PASS и fatal при exit 0. Заморозить repair
HEAD/TREE, выполнить полный baseline/candidate на canonical Godot, записать
hash manifest и получить fresh Reviewer/Verifier для нового exact subject.
Raw current-main PC0 остаётся standard YELLOW / directional RED.
Main-owned clearance готовится только после достаточного evidence; merge остаётся
HUMAN gate. Native/MVP3–MVP5 historical результаты не переоткрываются этим
diagnostic repair; gameplay runtime не меняется.
