# EVO ARCH2 A7 — Main Integration Repair R2

Дата: 2026-09-13. Work Order: `EVO-ARCH2-A7-MAIN-INTEGRATION-20260913-R1`.

## Finding

Static preflight R2 `34732821534` снова подтвердил current-main ancestry, addition-only diff и exact accepted transfer pins. `res://` closure scan затем нашёл три пути:

```text
res://artifacts/a7/observatory.png
res://scripts/labs/ecology/evo_morphology_lab_v2_model.gd
res://scripts/labs/ecology/evo_morphology_lab_v2_renderer.gd
```

Первый путь — намеренно генерируемый graphical evidence output из `arch2_a7_ui.gd`; он не должен существовать до выполнения capture и не является source dependency.

Два остальных пути — реальные зависимости `arch2_a03_exact_acceptance.gd`. Current main их не содержит.

## Repair

Добавляются ровно два accepted blobs:

```text
scripts/labs/ecology/evo_morphology_lab_v2_model.gd
blob = a303fdf97003f985edeadd5bc340a84af77fc330

scripts/labs/ecology/evo_morphology_lab_v2_renderer.gd
blob = 12579d1d668d3c4b4c86b7814b71155ced033d47
```

Оба взяты byte-exact из accepted A7 `8eccf630...`; model preload-ит только уже перенесённые `scripts/research/ecology/v2/*`, renderer не имеет дополнительных `res://` dependencies.

Closure validator теперь обязан:

1. проверять source/test/scene dependencies;
2. разрешать отсутствие только явных generated output paths под `res://artifacts/`;
3. не использовать это исключение для `scripts/`, `tests/`, `scenes/` или config dependencies;
4. повторно проверять exact blob identity и факт отсутствия этих paths на base main.

После Repair R2 все старые static/exact/review результаты предыдущего integration HEAD считаются stale. Нужен новый frozen HEAD/TREE и fresh static + exact + independent review.

Production/network/simulation/control/architecture ownership и `project.godot` не меняются. Merge остаётся human gate.
