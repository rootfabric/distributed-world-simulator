# Windows local workspace / test layout

## Status

Это стандартная локальная Windows-схема для разработки и ручного/runtime тестирования Distributed World Simulator.

Новые инструкции, runner-скрипты и отчёты не должны предполагать старые checkout-пути вроде `C:\distributed-world-simulator-v0-*` или `C:\Godot\lunar-world-*`.

## Каноническая локальная структура (flat worktree layout)

Действующая ворктри-политика: единый bare-репозиторий в корне рабочей зоны, а все worktree — сиблинги первого уровня рядом с ним. Подкаталог `worktrees\` и выделенный центральный checkout `distributed-world-simulator\distributed-world-simulator\` больше не являются каноническими; существующие пути такого вида — legacy, новые инструкции и runner-скрипты их не вводят.

```text
C:\distributed-world-simulator\
  .git-store\repo.git                  # bare-репозиторий (общий git storage)
  main\                                # control worktree (ветка main)
  <worktree-name>\                     # все task/feature worktree — сиблинги main
  godot-userdata\                      # изолированные Godot user data
  archive\                             # необязательные внешние артефакты/архивы
```

Центральный control worktree:

```text
C:\distributed-world-simulator\main\
```

Все новые worktree создаются сиблингом первого уровня:

```text
C:\distributed-world-simulator\<worktree-name>\
```

Пример:

```powershell
cd C:\distributed-world-simulator\main

git fetch origin

git worktree add `
  C:\distributed-world-simulator\sm0-two-authority-seamless-handoff-lab `
  origin/feature/sm0-two-authority-seamless-handoff-lab
```

Не создавать новые рабочие checkout рядом с корнем диска (`C:\distributed-world-simulator-v0-*`) и не возвращать старый вложенный layout (`worktrees\`, `distributed-world-simulator\distributed-world-simulator\`).

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
6. не мутировать control worktree `main\` (и любые чужие worktree-сиблинги) при запуске тестов;
7. не выполнять `git reset --hard`, `git clean -fdx` или очистку чужих worktree;
8. после теста позволять проверить `git status --short` и ожидать чистое дерево.

## Центральный control worktree и worktree

`C:\distributed-world-simulator\main\` — точка управления репозиторием: fetch, создание worktree, просмотр product frontier. Git-хранилище общее: `.git-store\repo.git`, поэтому `git worktree list` доступен из любого worktree зоны.

Feature-разработка предпочтительно выполняется в отдельном worktree-сиблинге `C:\distributed-world-simulator\<worktree-name>\`.

Если пользователь сознательно переключает worktree `main` на feature branch для локальной проверки, runner обязан работать и там, но инструкции агента не должны требовать этого как единственного способа.

## Запуск из правильного worktree

Перед запуском runner/Godot убедись, что команда выполняется из того worktree, над которым идёт работа:

```powershell
cd C:\distributed-world-simulator\<worktree-name>
git branch --show-current
git status --short
```

Runner-скрипты определяют project root относительно собственного файла, поэтому путь запуска (`.\RUN_*.ps1` из worktree или полный путь `C:\distributed-world-simulator\<worktree-name>\RUN_*.ps1`) задаёт Godot `--path` именно этого worktree. Нельзя запускать runner из `C:\distributed-world-simulator\` (корня зоны) — там нет `project.godot`.

## SM0

Для seamless lab рекомендуемый worktree:

```text
C:\distributed-world-simulator\sm0-two-authority-seamless-handoff-lab\
```

Запуск тестов выполняется из этого каталога или по полному пути к runner; Godot остаётся в `C:\Godot\godot\bin\`.
