# Windows local workspace / test layout

## Status

Это стандартная локальная Windows-схема для разработки и ручного/runtime тестирования Distributed World Simulator.

Новые инструкции, runner-скрипты и отчёты не должны предполагать старые checkout-пути вроде `C:\distributed-world-simulator-v0-*` или `C:\Godot\lunar-world-*`.

## Каноническая локальная структура

```text
C:\distributed-world-simulator\
  distributed-world-simulator\        # центральный checkout репозитория
  worktrees\                           # все task/feature worktree
    <worktree-name>\
  artifacts\                           # необязательные внешние артефакты/архивы
```

Центральный checkout:

```text
C:\distributed-world-simulator\distributed-world-simulator\
```

Все новые worktree должны располагаться внутри:

```text
C:\distributed-world-simulator\worktrees\
```

Пример:

```powershell
cd C:\distributed-world-simulator\distributed-world-simulator

git fetch origin

git worktree add `
  C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab `
  origin/feature/sm0-two-authority-seamless-handoff-lab
```

Не создавать новые рабочие checkout рядом с корнем диска (`C:\distributed-world-simulator-v0-*`).

## Канонический Godot 4.7.1 double build

Каталог:

```text
C:\Godot\godot\bin\
```

Console executable для headless/tests/log capture:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
```

Graphical executable:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe
```

Windows test runners должны по умолчанию использовать именно console executable и разрешать явный `-GodotExe` override только для диагностики/CI.

Graphical runner должен использовать graphical executable и не подменять его single-precision build.

## Правила runner-скриптов

Новые PowerShell runners должны:

1. определять project root относительно собственного расположения, поэтому одинаково работать в central checkout и worktree;
2. иметь default `GodotExe = C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`;
3. не зависеть от current working directory;
4. создавать runtime logs под `%LOCALAPPDATA%\DistributedWorldSimulator\...` либо под явно переданный artifact directory;
5. печатать exact project root, git HEAD и log directory;
6. не мутировать центральный checkout при запуске тестов;
7. не выполнять `git reset --hard`, `git clean -fdx` или очистку чужих worktree;
8. после теста позволять проверить `git status --short` и ожидать чистое дерево.

## Центральный checkout и worktree

`C:\distributed-world-simulator\distributed-world-simulator\` — точка управления репозиторием: fetch, создание worktree, просмотр product frontier.

Feature-разработка предпочтительно выполняется в отдельном worktree внутри `C:\distributed-world-simulator\worktrees\`.

Если пользователь сознательно переключает центральный checkout на feature branch для локальной проверки, runner обязан работать и там, но инструкции агента не должны требовать этого как единственного способа.

## SM0

Для seamless lab рекомендуемый worktree:

```text
C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab\
```

Запуск тестов выполняется из этого каталога или по полному пути к runner; Godot остаётся в `C:\Godot\godot\bin\`.
