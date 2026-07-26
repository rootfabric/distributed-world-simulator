# Проверка v15.5.1-fixed

## Зафиксированный состав

Версия завершает перенос координатной сетки из лунного слоя в общий simulation
partition layer. Старый `lunar_cube_address.gd` оставлен только как временный
совместимый фасад; production runtime на него больше не ссылается.

## Выполненная статическая проверка

На рабочей копии проверены:

```text
JSON-конфигурации:          16
res:// ссылки:             267
GDScript-файлы:            102
GDScript-функции:         1347
SceneTree entrypoints:      21
```

Результат:

```text
STATIC VALIDATION: PASS
```

Проверка включает:

- разбор всех JSON;
- существование всех найденных `res://` целей;
- баланс скобок и строк GDScript;
- присутствие всех 21 entrypoint в общем regression runner;
- отсутствие production-ссылок на старый `LunarCubeAddress`.

## Независимая численная проверка cube-sphere

Внешним от Godot расчётом повторены формулы `CubeSphereGrid`:

```text
Moon 48×48:  13 824 центра зон — roundtrip PASS
Earth 96×96: 55 296 центров зон — roundtrip PASS
Выборки центров чанков обеих сеток — PASS
Рёбра и углы всех шести граней — PASS
Ошибка геодезического смещения 10 км: 0.000000020 м
```

## Движковые тесты

Для окончательной проверки на целевой машине:

```powershell
.\RUN_COORDINATE_FOUNDATION_TESTS.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Runner требует double-precision Godot. При нестандартном пути:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

В среде сборки патча исполняемый double-precision Godot отсутствовал, поэтому
запуск реального Godot parser/runtime не заявляется как выполненный. Архив
проверен наложением на чистую v15.5, сравнением файлов и проверкой ZIP.
