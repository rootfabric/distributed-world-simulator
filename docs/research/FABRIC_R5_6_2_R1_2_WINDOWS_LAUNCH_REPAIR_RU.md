# FABRIC R5.6.2 R1.2 — Windows launcher: argv loss / timeout evidence

Статус: bounded implementer repair; Windows Godot exact и отдельная независимая
приёмка обязательны. Предыдущие Windows FAIL не переименовывать в PASS.
Risk: HIGH inherited from lifecycle; изменение только test infrastructure.
Замороженный RED parent: `d3e3d3b29c9ef068937048ef14aa6c7114700904`,
TREE `c69a84ea47b339c83f982568d95563db6d9fe373`.
Control main observed: `aac301b9a9a89e027f6d99864437eb750a4202ca` (не изменять).

## Repair Map и коррекция диагноза

Windows report: PR #800 comment 6319033193. Import-recovery завис на 30 минут,
игровой мир стримился, наблюдались inventory class-cache errors.
Логи доказывают игровой запуск, но название стадии не доказывает доставку CLI.
В `RunGodot([string]$Name, [string[]]$Args)` использовано имя автоматической
переменной PowerShell `$args` (регистр значения не имеет). Аргумент этапа
терялся ещё до `Process.Start`: выполнялось только `--headless --path <project>`.
Это затрагивало и `--script`/`--check-only`, не только импорт.

Диагностика вынесена в отдельную ветку
`verify/fabric-r562-r12-launcher-diagnostic-r1` @ `af6a3898205bbcca341d0c2ac29cad1bbefcf965`.
[CI 39681246805](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39681246805)
на Windows и Ubuntu с **PowerShell 7.6.7** извлекает настоящий `RunGodot` из
frozen parent, останавливает его непосредственно перед созданием процесса и
читает `ProcessStartInfo.ArgumentList`. Никакой игровой процесс не запускается.

```text
OLD: --headless --path "C:/probe path/with spaces"
RENAME $Args -> $GateArgs:
     --headless --path "C:/probe path/with spaces" --editor --import --recovery-mode
```

Windows artifact 12383837332 и Ubuntu artifact 12383419081:
`legacy_red=true`, `rename_green=true`, `godot_launched=false`.
Предыдущее предположение «сам Godot обязательно запускает игру при корректно
переданных --editor --import» не установлено этим раннером. Упомянутый в отчёте
прямой CLI repro требует отдельной проверки с записанным argv и тем же binary.
Если он воспроизводится после доставки флагов, это отдельный сохраняющийся дефект;
его нельзя закрыть результатом unit-теста. Issue #808 пока не закрывать.

## Изменения / границы

- `RUN_FABRIC_R5_6_2_R1_TESTS.ps1`: именованный обязательный `$GateArgs`, точная
  allowlist argv каждой из десяти стадий до `Start`, JSON фактического argv;
  stdout/stderr и итог процесса сохраняются до исключения, включая timeout.
  Запуск main.tscn из-за пустых/чужих флагов запрещён до создания процесса.
- Жёсткий timeout остаётся 1800 s; тест процесса использует 1 s только в
  изолированном falsifier. Убивается только принадлежащий тесту процесс/его дети.
- Маркеры gameplay на import дополнены `terrain_streaming_summary` и
  `spectator_predictive_stream`; любой такой результат — FAIL.
- Collector v2 на Windows требует 10 точных argv/process receipts, exit=0,
  started=true, timeout=false, отсутствие gameplay, совпадение обоих raw streams
  с общим логом. Linux не получает вымышленных Windows receipts.
- Тест PowerShell извлекает настоящий launch-function; только executable
  boundary адаптирован к Python child, который печатает полученный native argv.
  Binding, argv-builder, timeout/log/fatal path остаются из product runner.
- CI проверяет launch-contract на hosted Windows с pinned PowerShell 7.6.7 и
  Ubuntu; Windows unit PASS НЕ называется Windows Godot Exact PASS.
- Source carrier теперь содержит Git bundle: локальная exact-проверка может
  действительно использовать frozen commit, а не синтетическую identity tar.

Разрешённый repair scope: два названных runner/collector файла, этот документ,
`test_r5_6_2_r1_windows_launcher.ps1`, `test_r5_6_2_r1_launch_evidence.py`,
`.github/workflows/fabric-r5-6-2-r1-unified-lifecycle.yml`.
Не менять физический runtime, GDScript acceptance, Construction/Matter,
BRIDGE-4, inventory, project.godot, engine pins, PR #784, main.

## Validation plan / факты implementer

Локальный PowerShell 7.6.7: **75/0**, включая original RED, все 10 native argv,
пути с пробелами/кириллицей, 7 отказов до создания процесса, nonzero exit,
fatal stderr при exit=0, gameplay marker, timeout с сохранением обоих потоков.
Python collector tamper suite: **19/19** (1 положительный + 18 отрицательных).
Это implementer tests, не отдельные Reviewer/Verifier.

Нормативный следующий шаг: published exact HEAD/TREE, чистый detached Windows
worktree, прежний канонический Godot double 4.7.1 и неизменённый strict runner.
Проверить `import-recovery.argv.json` до доверия имени этапа; теперь там обязаны
присутствовать все три флага. Оба cold-import этапа, lifecycle 3x616/0, регрессии,
42 sandbox receipts, collector v2, identity before/after, SHA256SUMS обязательны.
При новом FAIL опубликовать argv, process receipt, stdout/stderr, GUI+console
binary hashes и отдельный прямой CLI repro; не прогревать cache как нормативный fix.

PR #800 остаётся draft. Merge #784/#800, main promotion, R5.6.2 R2 и runtime
расширение не входят в этот repair. Fresh независимые роли и human merge gate
сохраняются.
