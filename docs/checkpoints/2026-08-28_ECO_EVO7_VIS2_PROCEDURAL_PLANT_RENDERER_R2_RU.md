# ECO EVO7 / ECO-VIS2 — Procedural Plant Renderer R2

## Причина R2

R1 candidate `1a9a9ab474f4e26bf91db88ba3382eab0176bc10` технически прошёл focused tests и Project Control, но ручная Windows-проверка выявила два visual/runtime-launch defects:

1. запуск VIS2 через positional scene argument мог уйти в проектный `run/main_scene=res://main.tscn` и открыть Moon gameplay/debug scene;
2. даже в корректно открытом VIS2 generation-0 founder markers были слишком мелкими, inherited top title оставался VIS1, а переход founder → phenotype был недостаточно очевиден.

R1 остаётся immutable evidence и не принимается.

## R2 repair

- launcher Windows/Linux использует explicit Godot `--scene res://scenes/labs/ecology/eco_evo7_vis2_procedural_plant_viewer.tscn`;
- runtime выставляет заголовок окна `ECO EVO7 — VIS2 Procedural Plant Viewer`;
- runtime печатает deterministic marker:
  `ECO.EVO7 VIS2 READY scene=EcoEvo7VIS2ProceduralPlantViewer revision=ECO.EVO7-VIS2.R2`;
- inherited VIS1 title заменяется на VIS2;
- generation 0 показывает явную подсказку: founder sprouts only, press +1;
- founder sprouts имеют читаемый minimum silhouette на 1x;
- phenotype stem/crown minimum sizes усилены без изменения biology;
- root debug увеличен и сделан контрастнее;
- acceptance проверяет runtime identity, title/help, minimum founder readability и explicit --scene в обоих launchers.

## Authority boundary

R2 не меняет LS3 biology и не вычисляет phenotype заново. Изменяется только presentation mapping и способ запуска сцены. Источник morphology остаётся accepted LS3.4 competition evidence через LS3.6 Workbench.

## Windows launch

```powershell
.\OPEN_ECO_EVO7_VIS2_PROCEDURAL_PLANT_VIEWER.ps1 -GodotBin 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
```

Эквивалентная явная команда:

```powershell
& 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe' \
  --path 'C:\distributed-world-simulator\worktrees\vis2-r2' \
  --resolution 1600x900 \
  --scene 'res://scenes/labs/ecology/eco_evo7_vis2_procedural_plant_viewer.tscn'
```

Правильный runtime должен показать VIS2 title и вывести `ECO.EVO7 VIS2 READY ... R2`. Если открывается Moon gameplay scene, visual acceptance запрещена.
