# P7 — каноническое закрытие R1

Это пакет контрольного продолжения, НЕ acceptance и НЕ MVP activation.
Work Order: `V0-P7-CANONICAL-CLOSURE-R1`. Канонический runtime subject:
`c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f`, TREE
`04679a6e67fc86ec156d4341140fd5b0225d6085`.

## Уже существующее точное исполнение

Runtime run `34034752294`, job `101490676888` на self-hosted Linux проверил
именно этот checkout. Workflow source `eb94c9f1a902e7a0acfd263f9d4df87c4986042e`
НЕ является tested runtime HEAD. Artifact `9990033093` (ZIP SHA256
`812375ea7fa73cac914f4e63b9ccbb290b81bd0f1b84ccfb8b01a4700db0bc82`) содержит
все 29 отдельных стадий: 887 direct + 1145 nested = 2032 assertions, failures 0.
Godot `4.7.1.stable.double.custom_build.a13da4feb`, binary SHA256
`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
GitHub job подтвердил tracked clean before/after и gate exit 0.

`runtime-evidence.tar.xz` сохраняет побайтно все 38 файлов исходного ZIP.
Исходный SHA256SUMS ошибочно включает сам себя: его self-entry не используется
как доказательство. Все остальные 37 записей совпадают; исходный файл сохранён.
Новый SHA256 всего tar.xz связывает также оригинальный checksum-файл.
Аудитор не распаковывает содержимое на диск и не исполняет файлы артефакта.

PC0 run `34034314222` на c14: artifact `9989671139`, ZIP SHA256
`6c69486f813e2814f3428fe87da156e4f50a7ec92a38ceb01bdb77357ffc1b04`.
`pc0-evidence.tar.xz` сохраняет оба полных JSON. Производные Markdown остаются
в исходном ZIP. Standard YELLOW; G/ECO RED advisory. Directional YELLOW:
CH→NX и NX→T имеют global_blocking=true, но уровень YELLOW, не critical RED.
Флаги не скрываются. Cross-branch overlaps отсутствуют.

## Что ещё обязательно

Каталог P7 отдельно требует `FULL_WORLD_CORE_REGRESSION_PASS`. 2032 не подменяют
его. Новый Actions job запускает НЕИЗМЕНЁННЫЙ `RUN_WORLD_REGRESSION_TESTS.ps1`
на c14 с exact Godot. Timeout/failure не считается PASS. Сохраняются полный лог,
exit code, инкрементальный summary и чистота tracked checkout.

После результата: fresh Independent Reviewer и Verifier для exact runtime
subject и frozen evidence package; их verdict не выдается Implementer-ом.
Только затем — отдельный canonical acceptance proposal и human MERGE/HOLD.
В данном пакете нет acceptance record, нового runtime lease, runtime dispatch,
MVP activation или реализации `MVP_SHARED_VISUAL_SCENE`.

## Воспроизведение аудита

```bash
python scripts/harness/verify_p7_closure_packet.py --git
python -m unittest discover -s tests/harness -p 'test_p7_closure_packet.py' -v
```

`--git` проверяет exact TREE, достижимость P7 merge lineage и существование
исторических evidence paths в canonical runtime tree. Все historical records
остаются неизменными. Аудит подтверждает machine evidence, не независимый verdict.

## Дальнейший маршрут

Полный world/core → исправление только подтверждённых обязательных findings
→ Reviewer → Verifier → human canonical P7 acceptance/merge
→ отдельная main-owned MVP activation/epoch/Work Order/lease
→ Director dispatch `MVP_SHARED_VISUAL_SCENE`.
ECO/FABRIC/WORLD FILL/WORLD PACKS не добавлены в продуктовые зависимости.
