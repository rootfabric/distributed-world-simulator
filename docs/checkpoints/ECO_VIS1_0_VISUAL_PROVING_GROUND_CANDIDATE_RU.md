# ECO.VIS1.0 — Visual Proving Ground Candidate

Статус: `IMPLEMENTED_CANDIDATE / WINDOWS AUTOMATED + GRAPHICAL CHECK PENDING / NOT ACCEPTED`.

## Что реализовано

VIS1.0 создаёт отдельный лабораторный полигон без подключения production persistence/authority и без изменения ecology truth.

Состав:

- детерминированная поверхность `500 x 500 m`;
- `64 x 64` terrain cells;
- выраженный лабораторный relief с низиной, возвышенностью, общим уклоном и волнистой частью;
- свободная операторская камера;
- ограничение камеры границами полигона и минимальной высотой над землёй;
- пять reference markers: четыре угла + центр;
- HUD с координатами камеры, высотой terrain и clearance;
- isolated headless automated smoke;
- isolated graphical launcher без gameplay/MCP autoloads.

Текущий VIS1.0 не содержит растений и не пытается моделировать биомы. Это сознательная граница: `EcoEnvironmentProvider` начинается только в VIS1.1.

## Exact candidate

```text
branch = feature/eco-vis1-visual-proving-ground
source frozen P4 = f0e16195f1331f238bbacab2768e5d72ec01d1a3
VIS1.0 implementation head = 246b55d4c7c6fb1547d16de1ab872e3799e81286
movement smoke hardening = fcff82aab6c8b0fc3fcbb6957bb05efcc4870b18
```

Ключевые blobs:

```text
controller = a507ebbc25d3ff6d23bc4f2a95c3ec1ab79cfe74
scene      = e8e00a7c8ad6531ef9829289edb7958479f5295c
smoke      = c71a7672477e84257e5f9a8f4d514fa5c743b15a
runner     = a7306e4c5374d9904e81c24fb8d9bc4dbf9c9ad7
```

Validation:

`validation/ecology/eco-vis1-0-visual-proving-ground-validation.json`.

## Supplementary exact-engine result

На приложенной Linux double-сборке того же Godot commit:

```text
Godot = 4.7.1.stable.double.custom_build.a13da4feb
parser preflight = PASS
ECO.VIS1.0 headless scene smoke: PASS (24 assertions)
```

Smoke дополнительно проверяет реальный `W` key input через `Input.parse_input_event`, движение камеры, clamping по границам полигона и минимальную высоту над terrain.

Это дополнительное доказательство parser/runtime корректности, но не Windows graphical acceptance.

## Управление

```text
WASD   движение
Q / E  вниз / вверх
Shift  ускорение
мышь   обзор
Esc    отпустить/захватить мышь
Home   вернуть камеру в начальную точку
```

## Windows automated check

Из exact checkout/worktree этой ветки:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_VIS1_0_TESTS.ps1 -GodotPath $Godot
```

Ожидаемый финал:

```text
ECO.VIS1.0 exact Godot identity: PASS
ECO.VIS1.0 isolated project without gameplay/MCP autoloads: PASS
ECO.VIS1.0 parser preflight: PASS
ECO.VIS1.0 headless scene smoke: PASS (24 assertions)
ECO.VIS1.0 automated gate: PASS
```

## Windows graphical check

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_VIS1_0_LAB.ps1 -GodotPath $Godot
```

Launcher создаёт временный минимальный Godot project, копирует туда только VIS1.0 scene/controller и ждёт закрытия окна. Общие gameplay/MCP autoloads проекта не участвуют.

Нужно визуально проверить:

1. поверхность действительно видна и имеет читаемый рельеф;
2. камера стартует над полигоном;
3. WASD/QE/mouse/Shift работают удобно;
4. камера не уходит за границы и под поверхность;
5. HUD обновляет координаты и ground height;
6. четыре угловых и центральный markers различимы;
7. в консоли нет parser/runtime ошибок.

## Acceptance boundary

VIS1.0 нельзя объявлять accepted только по implementer smoke.

После Windows automated PASS + human graphical confirmation можно заморозить VIS1.0 и перейти к:

`VIS1.1 EcoEnvironmentProvider + LabEnvironmentProvider`.
