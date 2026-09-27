# Windows local workspace / test layout

## Статус

Это каноническая локальная Windows-схема для разработки и runtime-тестирования Distributed World Simulator.

Новые инструкции, runner-скрипты, worktree и отчёты должны использовать эту схему, если пользователь явно не задал другой путь.

## Каноническая структура

```text
C:\distributed-world-simulator\
  distributed-world-simulator\        # центральный checkout репозитория
  worktrees\                           # все task/feature worktree
    <worktree-name>\
  artifacts\                           # внешние артефакты/архивы при необходимости
```

Центральный checkout:

```text
C:\distributed-world-simulator\distributed-world-simulator\
```

Все новые worktree:

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

Не создавать новые checkout у корня диска в стиле:

```text
C:\distributed-world-simulator-v0-*
```

## Канонический Godot 4.7.1 double build

Каталог:

```text
C:\Godot\godot\bin\
```

Console executable для headless tests и log capture:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
```

Graphical executable:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe
```

Не использовать single-precision Godot для V0/network/spatial acceptance.

## Требования к Windows runner

PowerShell runner обязан:

1. определять project root относительно собственного файла;
2. работать одинаково из центрального checkout и feature worktree;
3. иметь default Godot console path `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`;
4. разрешать явный `-GodotExe` override для диагностики/CI;
5. не зависеть от current working directory;
6. печатать exact project root, Git HEAD и log/evidence directory;
7. хранить runtime logs под `%LOCALAPPDATA%\DistributedWorldSimulator\...` либо в явно заданном artifact directory;
8. не выполнять `git reset --hard`, `git clean -fdx` или очистку чужих worktree;
9. после теста оставлять tracked source tree неизменным; `git status --short` должен совпадать с состоянием до запуска;
10. при multi-process test сохранять PIDs/session state так, чтобы `-Stop`/`-Restart` были детерминированными.

## Роли central checkout и worktree

`C:\distributed-world-simulator\distributed-world-simulator\` — центральная точка управления: fetch, просмотр canonical/product refs, создание worktree.

Feature-разработка предпочтительно выполняется в отдельном worktree внутри:

```text
C:\distributed-world-simulator\worktrees\
```

Если пользователь сознательно переключает central checkout на feature branch для локальной проверки, runner обязан работать и там, но проектные инструкции не должны требовать этого как единственного способа.

## Старые пути

Исторические документы могут содержать старые пути. Новые Work Orders/runner/instructions должны считать этот документ источником истины по Windows layout и не копировать старые абсолютные пути в новую разработку.
