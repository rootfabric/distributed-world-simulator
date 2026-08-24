# ECO.EVO6-WATER R1 — сильное влияние воды на эволюцию растений

## Цель

Связать уже существующие водные наблюдения мира (`in_water`, `water_dist_m`, `soil_moisture_ppm`) с уже существующими генами растений (`water_preference`, `water_tolerance_width`, `root_depth_m`) так, чтобы вода была сильным фактором естественного отбора.

## Реализация

1. В DSL добавлен `soil_moisture_ppm` и полноценные числовые операторы `<`, `<=`, `>`, `>=`, `==`.
2. Добавлен сильный water rule pack: затопление почти уничтожает terrestrial, амфибии получают крупный бонус, насыщенная почва давит terrestrial, засуха особенно давит amphibious и одновременно стрессует все растения.
3. `evo6_water_fitness_v1` вычисляет непрерывную водную пригодность из реальных наблюдений воды и генома. Глубокие корни дают преимущество только в сухих условиях.
4. `evo6_water_evolution_bridge_v1` не создаёт второй mutation kernel: размножение делегируется существующему `plant_mutation_lineage_kernel_v1.gd`.
5. Causality gate использует одинаковый generation-one mutation candidate pool во всех режимах и требует разных финальных популяций.

## Режимы acceptance-теста

- flooded: `in_water=true`, moisture `1.0`;
- riparian: `water_dist_m=1.5`, moisture `0.65`;
- mesic: `water_dist_m=8`, moisture `0.40`;
- dry: `water_dist_m=20`, moisture `0.18`.

На локальном Godot `4.7.1.stable.double.custom_build.a13da4feb`, 36 поколений, population=18, offspring=4:

- flooded: mean `water_preference 0.58 -> 1.00`;
- dry: mean `water_preference 0.58 -> 0.343`;
- dry: mean `root_depth_m 0.85 -> 2.164`;
- generation-one candidate pool одинаков для всех режимов;
- финальные выбранные популяции различаются;
- deterministic replay совпадает по result hash.

## Запуск

Полный прогон с регрессиями предыдущего EVO6:

```powershell
.\RUN_ECO_EVO6_WATER_SELECTION.ps1 -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Быстрый только новый water-layer:

```powershell
.\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```
