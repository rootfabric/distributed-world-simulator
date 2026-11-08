# FABRIC R5.6.3 P0 — CI repair R1

Дата: 2026-10-27. Роль: Implementer. Risk: MEDIUM (достоверность CI evidence).
Статус: IMPLEMENTED_CANDIDATE; independent acceptance pending; MERGE_READY=false.

## Предмет и границы

Замороженный родитель: PR #865, HEAD `5e9ed0d0146f9c82ec249e50f43bf30913808849`,
TREE `e148a88f0c38f70dee21e6d68a9cb2dd0cb457d1`.
Repair branch: `repair/fabric-r563-p0-ci-evidence-r1`.
Main при проверке: `aac301b9a9a89e027f6d99864437eb750a4202ca`.
Ровно пять изменённых путей: три workflow ниже, тест `tests/ci/test_fabric_r563_p0_ci_repair.py`
и этот документ. Новый commit является потомком #865, не заменяет его frozen HEAD.

Запрещены изменения физики, Construction/Matter, source authority, исторических
receipts, main, engine pins и порогов acceptance. Не выполняется merge.
Сохраняются исходные blob SHA физики `cd36048523a7f86928d8891e9f6a0fc8362b1f23`
и теста `5f27f60092a05bccfb928adcabdff37648238c66`.

## Repair Map / причины

1. **P0 evidence:** Codex P2 в PR #865, discussion `4374912756`. Bash fail-fast
   завершал шаг до копирования `$EVIDENCE` в upload directory. `if: always()`
   у uploader не восстанавливает не скопированные файлы.
   Исправление: писать непосредственно в upload directory, фиксировать exit code
   каждого процесса и всего шага, независимо хешировать имеющиеся файлы в
   отдельном `always()` шаге. Ошибка процесса сохраняет исходный ненулевой exit;
   ошибка валидации не создаёт успешный canonical-result. Даже отказ поиска
   движка оставляет identity и код завершения. Не заявляется сохранение логов
   при физической потере хоста или принудительном завершении самого runner.
2. **Windows B0.4-C:** run `40286118636` остановился до импорта: Desktop PowerShell
   не разрешил `Get-FileHash`. Точная причина поломки module autoload на хосте
   не установлена. Ограниченный repair устраняет зависимость: явный `pwsh` с
   проверкой Core >=7, SHA256 через .NET stream с Dispose. Версия и SHA движка
   проверяются строго; вывод `--version` собирается полностью до чтения первой
   строки, ненулевой native exit отвергается. Изолированные APPDATA/LOCALAPPDATA
   и двухфазный импорт не затрагивают профиль пользователя. stdout/stderr
   импорта и тестов сразу пишутся через Tee-Object в публикуемые логи.
3. **T14:** в concurrency.group и artifact.name было три `${{{` вместо `${{`.
   Исправлены только лишние скобки; trigger остаётся на исходной T14-ветке.
   Пустой список jobs в старом run согласуется с отказом разбора workflow.

## Валидация

Regression test исполняет фактические shell bodies из YAML, а не их переписанную
копию. Тестовый fake Godot проверяет только CI-проводку; его результаты никогда
не считаются физическими испытаниями.

- Linux: положительный сценарий; ненулевой exit в каждом из четырёх Godot stages;
  нулевой exit с parse error; неверный счётчик, drift >1%, несовпадение повторов;
  отсутствующий executable и неверный SHA. Проверяется публикация частичных
  логов, сохранение отказа, отсутствие ложного canonical-result и все SHA256SUMS.
- Windows/PowerShell: корректный fixture executable при намеренно недоступном
  Get-FileHash; неверный SHA; другая версия; ненулевой exit `--version`.
  Подмена digest допускается исключительно во временном тестовом скрипте для
  fixture executable, не является параметром рабочего workflow.
- Контракты: исходные physics blob pins, 438 checks / 12 negatives / failures=[],
  drift <0.01 и идентичность двух результатов сохранены; T14 expression syntax;
  `always()` finalizer/upload; Core shell, изоляция профиля, strict import errors.
- Hosted CI matrix: Ubuntu + Windows; отсутствие pwsh запрещено, не даёт
  молчаливо зачесть пропущенные PowerShell проверки. Локально без pwsh эти
  четыре проверки честно показываются как skipped.
- Canonical Godot Linux: повторить P0 2x438/0 в полном checkout на новом exact
  commit/tree. Старый PASS `40286024340` остаётся историческим PASS на #865.

Локально воспроизведён RED: frozen parent + сбой import-recovery, exit=23,
файл ошибки отсутствует в upload directory. После repair Linux fault matrix
проходит. При первой локальной проверке: 13 unittest methods, 9 PASS и 4 skipped
(нет pwsh). Полный Windows/Godot и hosted matrix verdict публикуются отдельно,
только после реального исполнения на опубликованном HEAD.

## Приёмка и nonclaims

Post-build critique: NO_MATERIAL_REFACTOR_REQUIRED; нет нового источника истины,
нет изменений физических данных. Исправление расположено в точках запуска и
публикации evidence. Тест не ослабляет действующие acceptance guards.

Fresh Reviewer проверяет failure-path evidence, Windows native exit handling,
.NET hash disposal и отсутствие расширения физического scope. Separate Verifier
проверяет опубликованный HEAD/TREE, raw CI artifacts и исходные physics blobs.
Implementer не выдаёт себе независимые role verdicts. PR #865, #818 и #855,
чужие runner processes и main не меняются. R5.6.2 R2 / #867 и игровая интеграция
не закрываются этим ремонтом. MERGE_READY=false до независимой приёмки и human gate.
