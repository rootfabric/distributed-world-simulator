# WORLD PACKS — Parallel Agent Protocol R1

Статус: **branch-local orchestration / noncanonical control helper**.  
Контроллер: `control/world-packs-parallel-r1`.  
База исполнения: `feature/world-packs1-surface-library-contract-r1 @ 2bb97961a21bd8e56b07430a48b51f20cebabb5a`.

Этот слой не заменяет `PROJECT_CONTROL.md`, Harness, main-owned registry или архитектурных owners. Он решает более узкую задачу: безопасно вести несколько независимых WORLD PACKS workstreams параллельно, сохранять прогресс в Git и в любой момент получать машинно вычисленный следующий шаг.

## 1. Главный invariant

```text
CHAT IS NOT WORKSTREAM STATE
GIT IS WORKSTREAM STATE
```

Агент не имеет права закончить существенный этап сообщением в чате без durable Git record.

Каждый workstream имеет:

```text
fixed branch
bounded allowed paths
milestone list
branch-local state JSON
focused validation
Git commits
normal non-force pushes
independent integration/review gate
```

Контроллер читает удалённые refs и state-файлы непосредственно из Git. Поэтому новый агент после потери предыдущей сессии может восстановить прогресс без истории чата.

## 2. Перед любой работой

Обязательно:

```bash
git fetch --all --prune
git status --short
git branch --show-current
git rev-parse HEAD
```

Если checkout грязный и изменения не принадлежат текущему workstream — ничего не удалять, не reset/clean. Использовать чистый worktree/checkout.

Далее прочитать:

```text
AGENTS.md
PROJECT_CONTROL.md
HARNESS_CONTROL.md
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
config/world_packs/parallel/controller.v1.json
этот документ
```

И получить machine-derived instruction:

```bash
python tools/world_packs/parallel_controller.py instructions <TRACK>
```

`<TRACK>` заменяется реальным ID выбранного потока; список фиксирован в controller manifest и приведён в `PARALLEL_WORKSTREAMS_RU.md`.

## 3. Запрещённое поведение

В worker-ветках запрещено:

```text
force-push
rebase/history rewrite активной worker history
amend уже опубликованных durable commits
reset --hard чужой работы
clean -fd без доказанной необходимости
прямой push/merge в main
самостоятельный merge child PR
изменение canonical simulation/Matter/network/control paths
silent scope widening
chat-only progress/blocker
```

Если основная WORLD PACKS база или `main` ушли вперёд, worker не переписывает историю. Контроллер покажет drift; final integration выполняется через свежую composition/revalidation, а не через скрытый force-rebase.

## 4. Durable checkpoint — обязательная двухфазная фиксация

Для каждого законченного milestone:

### Phase A — implementation commit

```text
implement one bounded milestone
        ↓
focused tests
        ↓
git diff review
        ↓
scoped stage
        ↓
Conventional Commit
        ↓
normal push
```

Пример формата commit:

```text
feat(world-packs): add bounded raw asset cache
```

После commit получить точный SHA:

```bash
git rev-parse HEAD
```

И повторно подтвердить необходимые tests на этом implementation head.

### Phase B — state/evidence commit

Обновить только свой файл:

```text
config/world_packs/parallel/workstreams/<TRACK>.v1.json
```

Записать:

```text
status
completed_milestones
blockers
next_action
last_checkpoint_head
tested_head
validation[]
updated_at_utc
notes
```

`tested_head` должен быть точным implementation commit, который реально проверялся.

После этого:

```bash
git add config/world_packs/parallel/workstreams/<TRACK>.v1.json docs/world_packs/evidence/...
git diff --cached
git commit -m "chore(world-packs): record <track> checkpoint evidence"
git push origin HEAD
```

State/evidence-only commit после `tested_head` допустим. Любое изменение implementation-файла после `tested_head` делает validation stale и контроллер обязан это показать.

## 5. Если агент заблокирован

До остановки:

```text
status = BLOCKED
blockers = [конкретная причина]
next_action = конкретный способ разблокировки или необходимое решение
```

State commit + push обязателен.

Недопустимо:

```text
"не успел"
"что-то не работает"
"нужно посмотреть позже"
```

без durable причины, точной команды/ошибки и следующего действия.

## 6. Если milestone прошёл

Агент добавляет его ID в `completed_milestones`. Процент не вводится вручную: контроллер вычисляет его как `completed / declared milestones`.

Поэтому progress нельзя улучшить редактированием красивого текста.

## 7. Перед каждым handoff

Запустить:

```bash
python tools/world_packs/parallel_controller.py verify <TRACK>
python tools/world_packs/parallel_controller.py status --no-fetch
git status --short
git log -n 10 --oneline --decorate
```

В отчёте указать:

```text
track
branch
HEAD
tested_head
completed milestones
реально выполненные tests
changed files
scope/controller flags
blockers
machine-generated NEXT
```

Не писать PASS для проверки, которая не запускалась.

## 8. READY_FOR_INTEGRATION

Worker может выставить `READY_FOR_INTEGRATION` только если:

```text
все declared milestones завершены
focused validation green
required predecessor regression green
validation не stale
scope violations = 0
hard forbidden paths = 0
blockers = []
evidence опубликован
```

После этого открывается/обновляется child PR:

```text
worker branch
    ↓
control/world-packs-parallel-r1
```

Worker не self-merge. Integrator/Reviewer проверяет точный HEAD.

Если base/controller/main drift появился после validation, integration приостанавливается до revalidation/composition. Завершённая worker history не переписывается.

## 9. Mini-controller commands

### Текущее состояние всех потоков

```bash
python tools/world_packs/parallel_controller.py status
```

Показывает:

```text
controller/base/main heads
execution-base drift
critical main drift
per-track ahead/behind
state
progress
scope violations
validation freshness
next milestone
cross-track file overlaps
```

### Что делать дальше

```bash
python tools/world_packs/parallel_controller.py next
```

Это основной ответ на вопрос:

> что сейчас поручить каждому агенту?

### Полная инструкция одному агенту

```bash
python tools/world_packs/parallel_controller.py instructions WP-ASSET1
```

или другой реальный track ID.

### Проверить конкретный workstream

```bash
python tools/world_packs/parallel_controller.py verify WP-ASSET1
```

Exit code `0` означает, что branch/state/scope/validation checks, доступные этому mini-controller, не обнаружили локальной ошибки. Это не означает canonical acceptance.

### JSON для внешнего dashboard

```bash
python tools/world_packs/parallel_controller.py status --json > artifacts/world_packs_parallel/status.json
```

`artifacts/` — generated cache, не durable source of truth.

## 10. Как контроллер обнаруживает разбегание

Для каждого worker:

```text
controller branch ... worker branch
        ↓
git rev-list --left-right --count
        ↓
ahead / behind
```

Также:

```text
controller ... worker
        ↓
changed files
        ↓
allowed_paths check
```

И pairwise:

```text
changed_files(track A)
        ∩
changed_files(track B)
        ↓
OVERLAP
```

State/evidence paths исключены из overlap noise, implementation overlap — сигнал integrator-у.

Дополнительно mini-controller сравнивает recorded `main_baseline_sha` с текущим `origin/main` по критическим Matter/WORLDGEN paths и recorded WP1.0 execution base с её текущим ref. Он не угадывает совместимость: drift блокирует final integration до review/revalidation.

## 11. Кто имеет право менять controller manifest

Только controller/integrator work. Worker не меняет:

```text
config/world_packs/parallel/controller.v1.json
parallel controller script/tests
parallel protocol docs
track allocation/allowed paths
external gate states
```

Если worker обнаружил, что scope недостаточен, он фиксирует `BLOCKED` и предлагает расширение. Он не расширяет allowed paths сам.

## 12. Recovery после обрыва сессии

Новый агент выполняет только:

```bash
git fetch --all --prune
python tools/world_packs/parallel_controller.py status
python tools/world_packs/parallel_controller.py instructions <TRACK>
```

Этого должно хватать для восстановления:

```text
где находится ветка
сколько она ушла от controller
что уже закрыто
что проверено
что stale
что блокирует
какой следующий milestone
какие пути разрешены
```

Если для этого требуется старый чат, workstream control считается неполным и должен быть исправлен.
