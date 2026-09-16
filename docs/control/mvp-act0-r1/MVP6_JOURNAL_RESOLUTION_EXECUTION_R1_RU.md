# MVP6 journal resolution: exact исполнение после «разрешаю»

Разрешение пользователя зафиксировано в `68433ec7`; runtime repair `789c3af3`.
Frozen feature subject `73b8818184c93986e3313f35f9f4548c608e47e6`, tree
`a1bbe30fd68af5db3a9535bee942683ebe761bc1`. Exact worktree clean.
Единственный новый runtime blob journal `abdf0c0a335f4e2c968933156fb17f94a7b45bd1`.
Четыре строки совпадают с approved proposed patch; canonical snapshot/owners
и remaining pending semantics сохранены. Assertions предшественников не менялись.

## Проверки implementer

- RED 77 assertions / 10 failures → GREEN 77/77 на одном final test.
- Exact Windows feature: native408 + security48 + MVP3 232 + MVP5 270 PASS,
  дополнительно journal77. MVP4 45+57, NX6 940, bridge66, P4 ordering64 PASS.
- NX serial Windows: baseline с явным approved journal repair1077 и candidate
  с тем же repair плюс точный V0 M4 blob1077 PASS. Parser-only debt явно указан.
  `dependency_revalidated=false`, `repair_composition_revalidated=true`:
  текущий canonical main не назван исправленным.
- Main integration branch `repair/v0-mvp6-journal-resolution-r1`, PR #646:
  subject `3b82145ae946bb51aebf67f048a28420368b40be`, tree
  `6b1b8c9ead5c16d15dc8565813d3abb1bf94d880`. Journal и test byte-identical feature.
  Обязательный Windows launcher: import +77/940/66 PASS.
- Linux run35097654348 SUCCESS, validation branch commit804d306e запускает
  отдельно frozen main3b82145a и frozen feature73b88181. Main77/940/66 PASS;
  NX обе композиции1077 PASS. Artifact10446937610, ZIP скачан и проверен:
  `afd5aeac91fd73e893fb569cc11a46a49c15673244c79c0a1dcd2e661160c1cd`.

Raw logs/commands/summaries/hashes: `journal-resolution-exact-r1/machine-manifest.json`.
В пакете сохранены оба отклонённых прогона: native на789c был инвалидирован
изменением tracked probe при исполнении, NX initial import имел MCP port9080
collision при одновременном editor import. Ни один не засчитан PASS. Fresh
неизменяемый native subject и последовательные NX imports дали чистые результаты.

## Отдельный незакрытый Construction gate

Неизменённая canonical construction команда дала183 assertions /1 failure:
`CONSTRUCTION_MATERIAL_INSUFFICIENT` на stage1. Causal A/B с исходным journal
blobed23f0d2 воспроизвёл те же183/1. Это прежний product gap, не journal regression.
В failed extended report EXPECTED_HEAD/TREE не заданы; точный invocation/root
связан внешним runner/manifest. Modified-journal causal result явно не exact-clean.
Ни один failed Construction report не принят как product evidence.

Allocator намеренно не тратит hotbar ore без inventory slot; native fixture
переносит также hotbar state. Следующий Construction шаг должен использовать
существующий canonical item flow, не второй material owner и не weakened assertions.
Root-cause hypothesis требует отдельного подтверждения после control gate.

## Recovery и границы

Full world/core запущен на main3b82145a стандартным RUN_WORLD_REGRESSION_TESTS.ps1,
327 discovered tests, ещё выполняется; итог будет отдельным append-only пакетом.
Fresh Reviewer проверяет оба frozen subject; Verifier следует после его PASS.
PR646 — узкая альтернатива generic PR643, не второй patch поверх него.
Нельзя merge оба и переносить review/clearance более широкого6b147 на этот subject.

Canonical main6982a563 не изменён. Raw PC0 standardYELLOW / directionalRED.
PR646 Project Control35097399200 red на existing live directional assertion,
как PR643: gate не ослаблен. Main merge остаётся HUMAN. Прежний scope HA resolved;
новый merge HA не заявляется готовым до автоматической проверки кандидата.
MVP6 IN_PROGRESS; construction/five-process/whole-MVP не accepted.
