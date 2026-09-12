# A7 Observatory — запуск и смысл эксперимента

A7 — отдельная research scene поверх принятого A6. Это не production ecology и не новый симулятор.

## Запуск

Ветка `feature/eco-evo-arch2-a7-observatory-r1`, сцена `res://scenes/labs/ecology/arch2_a7_observatory.tscn`.
Не переключайте основной checkout: используйте отдельный worktree по `docs/GODOT_LOCAL_TESTING_RU.md`.

Ubuntu, из каталога выбранного worktree:

```bash
(
  godot="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
  "$godot" --headless --editor --path "$PWD" --import &&
  "$godot" --path "$PWD" res://scenes/labs/ecology/arch2_a7_observatory.tscn
)
```

Windows PowerShell, из каталога worktree:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& $Godot --headless --editor --path $PWD.Path --import
if ($LASTEXITCODE -eq 0) {
    & $Godot --path $PWD.Path res://scenes/labs/ecology/arch2_a7_observatory.tscn
}
```

Сборка: `4.7.1.stable.double.custom_build.a13da4feb`. Linux SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

## Управление

Пуск/пауза, `+1 tick`, скорость 1/2/4, выбор локации и study/litter-donor. Seed и три переключателя применяются только кнопкой RESET. Значения status относятся к активному эксперименту, а не к ещё не применённым настройкам. Возраст и tick не являются номером поколения.

Все поля, тела и балансы читает одна модель. Три сайта продвигаются вместе; ошибка одного не продвигает остальные. Пауза, выбор, повторное рисование и скорость не меняют genome/field hashes. Скорость задаёт частоту целых ecological ticks, а не величину шага или догоняющие пачки.

## Что сравнивается

Заранее заданы seeds 20260912 / 104729 / 130363; не происходит поиска удачной картинки. Wet/dry отличаются водой, wet/dark — светом. Во всех локациях одинаковы начальный genotype, study endowment и donor. На каждом сайте живёт study-организм и litter-donor: отсутствие воды в его reserves при ненулевом maintenance вызывает настоящую A5-смерть. A6 возвращает material донора в organic и минерализует его.

Common-garden — новый эксперимент, в котором те же founder genotypes заново выращиваются во всех трёх колонках при одинаковой wet-среде. Он проверяет пластичность/нейтральность при одинаковой среде; это НЕ бесплатная пересадка выращенного тела или evolutionary selection.

Effects-off — реальные A6 policy flags decomposition/mineralization=false. Initial field stocks не подменяются. Mutation-off — реальный A3 `none`, mutation-on — A3 `module_parameter` до создания founders; parent/child hash и detail видны в inspector/export. Мутации оплаченных детей и автоматическая materialization не добавлены. Разные hashes не объявляются разными видами, generation/fitness не выдумываются.

## Изображение

Изображается BodyGraph из того же PhenotypeSnapshot, что functional statistics: start/end по X/Y/Z, radius, collector area, absorber reach, reproductive role. Общее фиксированное поле зрения — 200×200 mm, сетка 10 mm; px/mm зависит только от общего размера панелей, не от выросшего тела. Это сохраняет сравнимость размеров и не обрезает верх на полном horizon. Круг collector — явная area proxy, не ботаническая форма листа. Root-only — реальный результат, не отсутствующий mesh. Мёртвое тело — неизменный provenance, расходуемый остаток только в corpse.remaining. Так графика не придумывает биомассу и не подменяет параметры окраской.

## Сохранения и экспорт

Сохранение: `artifacts/a7/observatory/<snapshot-sha256>.json` и отдельный caller-owned `manifest.json`. Для восстановления после запуска выберите те же treatment/seed и RESET, затем «Восстановить». Model restore сверяет ожидаемые experiment/revision, code-owned protocol/genesis и A6 replay каждого сайта. Не доверяет одному внутреннему хешу. Чужая локация, односторонний step, поддельный ledger или неполная запись отклоняются без изменения живой модели.

Manifest принадлежит оператору эксперимента; это не защита от злоумышленника, который владеет и manifest, и исходниками. Дисковые файлы исследовательские: production crash journal/atomic pointer recovery остаются A8. Неполный manifest безопасно отклоняется, старые content-addressed snapshots не удаляются.

Экспорт `artifacts/a7/observatory-report.json` содержит protocol/experiment/source hashes, treatment, A3 event, реальные fields, phenotypes, ledgers, corpses, balances и pending outbox. Отчёт не импортируется как симуляционное состояние. Строки A6 в save не углубляют ancestry payload.

## Ограничения

16 шагов на эксперимент, три сайта, два initial organisms на site, общий save/report ≤2 MiB. Существующие A6 bounds не меняются. STOP/BUDGET сохраняет состояние, не интерпретируется как смерть или selection. Проверочный JSON renderer — наблюдательный прототип, не production масштаб и не доказательство бесконечной/многопоколенной эволюции.

## Проверки

`validation/ecology/evo_arch2_a7/verify.py --godot <exact-bin> --head <HEAD> --tree <TREE>` запускает fail-closed A7 core/UI/restart x2 и A6/A5/all repairs/A0–A4/VIS5 regressions. Headless UI gate проверяет реальные Button handlers, а не фотографию. Отдельный graphical gate:

```text
Godot --rendering-method gl_compatibility --audio-driver Dummy --path <checkout> --script res://tests/research/ecology/v2/arch2_a7_ui.gd -- --capture
```

На Linux без физического дисплея допускается Xvfb. Он захватывает именно Godot viewport в `artifacts/a7/observatory.png`; source report лежит рядом в `capture-sources.json`. Read-only projection тестирует и изменение Z, чтобы наследуемая трёхмерная геометрия не скрывалась в XY-only картинке.
