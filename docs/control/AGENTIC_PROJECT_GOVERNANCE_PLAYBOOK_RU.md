# Portable Agentic Project Governance Playbook

## Инструкция по управлению очень сложными проектами с параллельно работающими агентами

Версия: `APG-1`

Статус: переносимая нормативная инструкция. Документ специально не привязан к конкретному движку, языку, продукту или структуре текущего репозитория и может быть перенесён в другой проект как основа управления параллельной разработкой агентами.

---

## 1. Назначение

Эта инструкция задаёт способ управления большим программным проектом, в котором много автономных агентов одновременно:

- проектируют архитектуру;
- реализуют независимые подсистемы;
- создают долгоживущие feature/fix/research ветки;
- меняют общие контракты;
- проводят тестирование и acceptance;
- передают работу другим агентам;
- интегрируют результаты в общую систему.

Главная задача управления — не мешать параллельной работе, но не позволять проекту постепенно превратиться в набор локально правильных и глобально несовместимых решений.

Основной принцип:

```text
BRANCHES REPORT FACTS
CENTRAL CONTROL DECLARES PROJECT STATE
AUDITOR CHECKS CONSISTENCY
ARCHITECTURE DEFINES WHAT IS ALLOWED
```

Иными словами:

1. Рабочая ветка сообщает, что она делает и что доказала.
2. Центральная ветка определяет официальную картину проекта.
3. Автоматический аудит сверяет заявления с реальным Git и validation evidence.
4. Глобальная архитектура ограничивает, какие решения вообще допустимы.

---

## 2. Два независимых контура: Architecture Plane и Project Control Plane

Нельзя хранить долговременные архитектурные правила и быстро меняющееся состояние разработки в одном документе.

Проект должен иметь два независимых контура.

### 2.1 Architecture Plane

Содержит медленно меняющиеся правила:

- архитектурные инварианты;
- фундаментальные сущности и их смысл;
- ownership подсистем;
- запрещённые зависимости;
- правила идентичности;
- authority boundaries;
- persistence/transaction/network contracts;
- глобальные dependency gates.

Architecture revision изменяется только при реальном изменении архитектуры.

Пример:

```text
ARCH-2026-R7
```

Обычный переход этапа `A4 -> A5` не должен создавать новую architecture revision.

### 2.2 Project Control Plane

Содержит быстро меняющееся состояние:

- какие программы существуют;
- какая ветка сейчас активна;
- какой stage выполняется;
- что было принято последним;
- что выполняется сейчас;
- следующий stage;
- blockers;
- health;
- branch/tested heads;
- dependency drift;
- cross-branch overlap.

Project Control revision и registry generation могут меняться часто и независимо от architecture revision.

---

## 3. Центральная ветка

В проекте должна существовать ровно одна каноническая управляющая ветка.

Обычно:

```text
main
```

или:

```text
trunk
```

Только центральная ветка имеет право объявлять:

- официальную architecture revision;
- список активных программ;
- active frontier каждой программы;
- глобальные ownership rules;
- cross-program dependencies;
- общие blockers;
- разрешение двигать frontier на следующий stage.

Рабочая ветка не может сама объявить себя новым официальным frontier всего проекта.

Она может только представить candidate state и evidence.

---

## 4. Рекомендуемая структура control plane

Минимальная переносимая структура:

```text
PROJECT_CONTROL.md

config/control/
    architecture.json
    ownership.json
    project-registry.json
    control-policy.json
    branches/
        BRANCH_PASSPORT_TEMPLATE.json

scripts/control/
    project_control.py

docs/control/
    PROJECT_GOVERNANCE.md
```

Названия могут быть другими. Важно разделение ответственности.

### `architecture.json`

Медленная архитектурная конституция.

### `ownership.json`

Кто владеет фундаментальными понятиями и какие программы могут только адаптировать их.

### `project-registry.json`

Официальная оперативная картина проекта.

### `control-policy.json`

Правила аудита и merge/acceptance gates.

### `branches/<passport>.json`

Локальный паспорт каждой активной ветки.

### `PROJECT_CONTROL.md`

Человекочитаемая центральная точка входа.

Она может быть статической инструкцией или generated dashboard, но не должна становиться единственным machine-readable source of truth.

---

## 5. Основная единица управления — Program

Большой проект нельзя контролировать как плоский список веток.

Работа группируется в программы.

Примеры абстрактных программ:

```text
CORE
NETWORK
STORAGE
SIMULATION
UI
TOOLS
SECURITY
MIGRATION
PERFORMANCE
```

Program — долгоживущая область развития с собственной последовательностью checkpoints.

Для каждой программы центральный registry должен хранить минимум:

```text
program_id
program_name
active_branch
role
short_description
purpose
expected_outcome
current_stage
stage_status
progress_note
last_accepted_checkpoint
next_stage
blockers
health
```

Это позволяет в любой момент ответить:

- что это за направление;
- зачем оно существует;
- что должно получить в результате;
- где оно сейчас;
- что уже принято;
- что будет следующим;
- почему оно заблокировано.

---

## 6. Один primary frontier на программу

По умолчанию:

```text
ONE PROGRAM = ONE PRIMARY ACTIVE FRONTIER
```

Это не означает, что разрешена только одна ветка.

Допускаются явно зарегистрированные parallel tracks:

```text
PRIMARY
FIX
RESEARCH
SCALE_PROBE
MIGRATION
EXPERIMENT
```

Но каждая такая ветка должна быть зарегистрирована и иметь роль.

Не допускается состояние, когда существует несколько долгоживущих веток одной программы и никто не знает, какая из них является продолжением канонической линии.

---

## 7. Каждая активная ветка обязана иметь паспорт

До начала существенной реализации агент создаёт branch passport.

Минимальный контракт:

```text
branch
program
role
parent_branch
base_commit
parent_checkpoint
architecture_revision
control_plane_revision

short_description
purpose
expected_outcome

current_stage
stage_status
progress_note
last_accepted_checkpoint
next_stage

owned_paths
watched_paths
critical_watched_paths
runtime_paths

dependencies
new_contracts
ownership_claims
forbidden_foundation_ownership

tested_heads
validation_paths
blockers
```

### Обязательная семантика описания ветки

Каждая ветка обязана коротко ответить на четыре вопроса.

#### Что это?

`short_description`

Одно-два предложения о функции ветки.

#### Зачем она нужна?

`purpose`

Какую проблему проекта она закрывает.

#### Что она обязана получить?

`expected_outcome`

Наблюдаемый результат, после которого stage имеет смысл принимать.

#### Где она находится сейчас?

`current_stage + stage_status + progress_note`

Не roadmap вообще, а текущий фактический прогресс.

Это обязательные поля dashboard.

---

## 8. Агент не начинает с кода

Перед началом задачи агент обязан выполнить START PROTOCOL.

### START PROTOCOL

1. Получить свежую центральную control state.
2. Определить program и active frontier.
3. Найти accepted parent checkpoint.
4. Прочитать architecture revision.
5. Прочитать ownership boundaries.
6. Прочитать branch passport или создать его.
7. Определить `owned_paths`.
8. Определить `watched_paths`.
9. Определить forbidden ownership.
10. Определить acceptance evidence до реализации.

Агент должен уметь сформулировать до написания кода:

```text
Что я меняю?
Почему это моя ответственность?
От чего я завишу?
Какие общие foundations я не имею права создавать?
Как будет доказано завершение?
```

Если на эти вопросы нет ответа, реализация ещё не готова начинаться.

---

## 9. Ownership — главный механизм защиты сложного проекта

Главная причина архитектурного расползания при параллельной агентной разработке — повторное изобретение общих foundations внутри локальных веток.

Центральная ownership matrix должна перечислять фундаментальные понятия.

Абстрактный пример:

```text
IDENTITY              owner: CORE
TRANSACTION_MODEL     owner: CORE
AUTHORITY             owner: CORE
PERSISTENCE           owner: STORAGE
TRANSPORT             owner: NETWORK
MATERIAL/TYPE_SYSTEM  owner: CORE
PRESENTATION          owner: UI / domain adapters
SCHEDULING            owner: RUNTIME
```

Локальная программа может создавать adapter к foundation, но не второй foundation.

Пример:

```text
PaymentNetworkAdapter        OK
PaymentGlobalTransactionManager inside UI branch    NOT OK
```

---

## 10. Правило нового фундаментального понятия

Если агент собирается ввести новый объект с архитектурным смыслом, он обязан объявить его до реализации.

Особое внимание именам и ролям вроде:

```text
*Manager
*Registry
*Coordinator
*Authority
*Transaction
*Identity
*Region
*Scheduler
*Store
*Persistence
*Protocol
*Global
```

Это не запрет на такие классы.

Это сигнал, что необходимо проверить ownership.

Агент обязан классифицировать новый контракт как одно из:

```text
LOCAL_IMPLEMENTATION_DETAIL
DOMAIN_CONTRACT
DOMAIN_ADAPTER
SHARED_CONTRACT
GLOBAL_FOUNDATION
```

Если это `GLOBAL_FOUNDATION`, локальная ветка должна остановиться и запросить central architecture decision.

---

## 11. STOP AND ESCALATE rule

Агент обязан прекратить самостоятельное расширение scope и эскалировать решение в central control, если обнаружено хотя бы одно из условий:

- нужен новый global identity;
- нужен новый cross-domain transaction model;
- нужен новый authority model;
- нужен новый persistence model;
- нужен новый shared protocol;
- два active programs претендуют на один foundation;
- текущий architecture invariant мешает корректной реализации;
- обнаружено, что parent checkpoint имеет фундаментальный дефект;
- реализация требует изменения семантики другой программы;
- branch scope начинает захватывать несколько независимых domain owners.

Правильное действие:

```text
DISCOVER GLOBAL ISSUE
        ↓
RECORD BLOCKER
        ↓
CENTRAL DECISION
        ↓
architecture revision / shared contract update if needed
        ↓
SYNC AFFECTED FRONTIERS
        ↓
RESUME LOCAL WORK
```

Неправильное действие:

```text
локально придумать обход
+
спрятать новый foundation внутри feature branch
```

---

## 12. owned_paths и watched_paths

Каждая ветка должна разделять пути на две категории.

### `owned_paths`

Область, которую ветка имеет право менять как часть своего scope.

### `watched_paths`

Область, от которой ветка зависит, но которой не владеет.

Например:

```text
owned_paths:
    src/payments/**

watched_paths:
    src/core/identity/**
    src/network/contracts/**
```

Аудитор проверяет изменения в `main` после branch merge-base.

Если main изменил watched dependency:

```text
normal dependency change   -> YELLOW
critical contract change   -> RED
```

Это превращает абстрактное `branch is 150 commits behind` в полезный вопрос:

> изменилось ли то, от чего реально зависит эта ветка?

---

## 13. Critical watched paths

Для особо опасных зависимостей задаётся:

```text
critical_watched_paths
```

Например:

```text
protocol schemas
identity contracts
transaction semantics
persistence formats
authority APIs
```

Изменение critical dependency автоматически требует revalidation или explicit convergence review.

---

## 14. Три уровня health

Проект обязан использовать ограниченный и однозначный health vocabulary.

### GREEN

Работа может продолжаться.

Типичные условия:

- architecture revision соответствует;
- parent принят;
- validation актуален;
- dependency drift отсутствует;
- ownership conflict отсутствует;
- blockers отсутствуют.

### YELLOW

Работа может продолжаться, но требуется review/convergence до следующего крупного checkpoint.

Примеры:

- docs/config drift;
- branch далеко разошлась с main;
- watched dependency изменилась;
- новый shared contract требует review;
- validation не полный, но stage ещё candidate;
- есть неопасное пересечение веток.

### RED

Нельзя официально продвигать frontier дальше.

Примеры:

- unaccepted parent;
- stale runtime validation;
- critical dependency drift;
- duplicate foundation ownership;
- conflicting runtime changes двух active branches;
- unresolved inherited blocker;
- architecture mismatch;
- acceptance evidence не соответствует текущему runtime head.

RED не обязательно означает, что агент должен прекратить абсолютно всю работу.

RED означает:

```text
NO FRONTIER ADVANCEMENT UNTIL RESOLVED
```

---

## 15. Жизненный цикл stage

Рекомендуемая state machine:

```text
PLANNED
   ↓
ACTIVE
   ↓
IMPLEMENTED_CANDIDATE
   ↓
VALIDATION_PENDING
   ↓
ACCEPTED
   ↓
SUPERSEDED / FROZEN
```

Дополнительные состояния:

```text
FIX_REQUIRED
BLOCKED
REJECTED
```

Исторический acceptance не переписывается задним числом.

Если позже найден дефект:

```text
A5 ACCEPTED
    ↓
A5 FIX1 REQUIRED
    ↓
A6 BLOCKED_BY A5_FIX1
```

а не:

```text
переписать историю и сделать вид, что A5 никогда не принимался
```

---

## 16. Acceptance имеет несколько измерений

Слово `DONE` слишком слабое для сложного проекта.

Минимум следует различать:

```text
SOURCE_ACCEPTED
MAIN_INTEGRATED
COMPOSITION_VERIFIED
PRODUCTION_READY
```

Или эквивалентные понятия конкретного проекта.

Пример:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

Это позволяет понимать реальное состояние без ложного бинарного `готово/не готово`.

---

## 17. Tested head является частью доказательства

Validation без привязки к commit бесполезен.

Каждый acceptance record обязан хранить:

```text
candidate_head
focused_tested_head
full_regression_tested_head
```

или эквивалент.

Главный guard:

```text
CURRENT_RUNTIME_STATE
must be covered by
TESTED_RUNTIME_HEAD
```

Если после теста изменился runtime code:

```text
VALIDATION_STALE = RED
```

Если изменились только docs/control metadata, runtime evidence может остаться действительным согласно policy.

---

## 18. Тесты должны проверять не только happy path

Агентные реализации особенно склонны закрывать локальную задачу happy-path тестом.

Для stateful и distributed systems acceptance должен включать, где применимо:

- replay;
- duplicate operation;
- stale revision;
- conflict;
- partial failure;
- restart/reconnect;
- rejection with zero side effects;
- fault injection между prepare и commit;
- out-of-order delivery;
- dependency unavailable;
- recovery after failure.

Правило:

```text
A SUCCESS TEST PROVES THE FEATURE CAN WORK.
A FAILURE TEST PROVES THE ARCHITECTURE CAN SURVIVE.
```

---

## 19. Cross-branch overlap audit

Central auditor обязан сравнивать активные ветки не только с main, но и друг с другом.

Минимальная матрица:

```text
A ↔ B
A ↔ C
B ↔ C
...
```

Если две ветки меняют один runtime/shared-contract file:

```text
RED
```

Если пересечение только в централизованно синхронизируемой документации:

```text
YELLOW or ignored by explicit policy
```

Важно: ignored patterns должны быть явно перечислены. Нельзя просто игнорировать все конфликты `docs/**` или `config/**`.

---

## 20. Convergence audit

Не требуется постоянно rebase/merge всех активных веток с main.

Но требуется регулярно проверять совместимость.

Рекомендуемое правило:

```text
MAJOR CHECKPOINT ACCEPTED
        ↓
PROJECT CONTROL AUDIT
        ↓
CONVERGENCE REQUIRED?
```

Также:

> Нельзя проходить несколько крупных checkpoints подряд без control-plane convergence review.

Число может быть задано policy проекта, например максимум два checkpoint между обязательными convergence audits.

---

## 21. Frontier advancement — отдельное решение

Acceptance текущего stage не всегда означает автоматическое разрешение следующего.

Пример:

```text
A5 SOURCE_ACCEPTED = true

BUT

A6 advancement_gate requires:
    A5_FIX1_ACCEPTED
```

Поэтому central registry должен уметь хранить:

```text
accepted_checkpoint
active_fix
blocked_next_stage
```

Это особенно важно, когда дефект обнаружен после первоначального acceptance.

---

## 22. Agent handoff contract

Каждый агент перед окончанием работы обязан оставить состояние так, чтобы другой агент мог продолжить без восстановления истории по чату.

Минимальный HANDOFF:

```text
WHAT WAS CHANGED
WHY
CURRENT BRANCH
CURRENT HEAD
PARENT CHECKPOINT
CURRENT STAGE
STATUS
TESTS RUN
TESTED HEADS
KNOWN RISKS
BLOCKERS
NEXT EXACT ACTION
```

Handoff должен быть записан в репозиторий или machine-readable validation/checkpoint, а не существовать только в сообщении агента.

Правило:

```text
CHAT IS NOT PROJECT MEMORY.
REPOSITORY STATE IS PROJECT MEMORY.
```

---

## 23. Агент обязан обновлять паспорт по мере движения

Branch passport — не документ создания ветки, который после первого commit забывается.

Обновляются как минимум:

```text
current_stage
stage_status
progress_note
tested_heads
validation_paths
blockers
next_stage
```

Dashboard должен отражать фактическое состояние текущего HEAD.

---

## 24. Central registry не должен автоматически доверять ветке

Branch passport — заявление ветки.

Central registry — официальное состояние.

Auditor обязан сравнивать их.

Если ветка пишет:

```text
stage = A7 ACCEPTED
```

а main registry считает:

```text
stage = A6
```

это не автоматически означает, что main устарел или ветка права.

Результат:

```text
CENTRAL_PASSPORT_DRIFT = YELLOW/RED
```

и требуется control decision.

---

## 25. Central state нельзя получать из имени ветки

Нельзя выводить stage из строк вроде:

```text
feature/a7-new-runtime
```

Имя ветки — удобная метка, но не source of truth.

Source of truth:

```text
main registry
+
branch passport
+
validation evidence
+
actual git refs
```

---

## 26. Machine-readable first

Критические факты проекта должны храниться machine-readable.

Правильно:

```text
JSON/YAML/TOML registry
        ↓
generated Markdown dashboard
```

Неправильно:

```text
огромный Markdown
        ↓
агент пытается угадать актуальное состояние по абзацам
```

Human-readable документы нужны для объяснения причин и архитектуры, но текущий state должен быть структурирован.

---

## 27. Central auditor

Проект должен иметь один стандартный audit command.

Например:

```text
./CONTROL_PROJECT
```

или:

```text
python scripts/control/project_control.py
```

Auditor выполняет минимум:

1. Fetch/prune refs.
2. Загружает registry из central branch.
3. Проверяет существование active branches.
4. Читает branch passports.
5. Проверяет architecture revision.
6. Проверяет required passport fields.
7. Сравнивает passport и central registry.
8. Проверяет branch divergence.
9. Проверяет watched dependency drift.
10. Проверяет tested-head freshness.
11. Проверяет ownership claims.
12. Проверяет blockers.
13. Проверяет pairwise active-branch overlap.
14. Генерирует machine-readable report.
15. Генерирует human-readable dashboard.

---

## 28. Dashboard

Dashboard должен позволять за минуту понять весь проект.

Минимальная таблица:

```text
PROGRAM
BRANCH
WHAT / WHY
CURRENT STAGE
CURRENT PROGRESS
LAST ACCEPTED
NEXT
BLOCKERS
HEALTH
```

После таблицы — подробные branch cards.

Каждая карточка должна показывать:

```text
Что это
Зачем
Ожидаемый результат
Текущая стадия
Текущий прогресс
Последний acceptance
Следующий stage
Blockers
HEAD
Tested HEAD
Main divergence
Dependency drift
Cross-branch conflicts
```

---

## 29. CI policy

Control audit должен запускаться автоматически:

```text
on pull request
on push to central branch
manual dispatch
optionally scheduled
```

Но важно разделять:

```text
AUDIT EXECUTION FAILURE
```

и:

```text
PROJECT HEALTH = RED
```

Сам auditor должен успешно выполнить проверку и опубликовать RED report.

CI может блокировать merge только там, где policy явно говорит, что данный RED относится к этому frontier/merge gate.

Иначе один известный RED в одной программе заблокирует вообще всю разработку проекта.

---

## 30. Merge gate

Перед интеграцией stage рекомендуется проверять:

```text
BRANCH_REGISTERED
PARENT_ACCEPTED
PASSPORT_PRESENT
ARCHITECTURE_REVISION_MATCH
OWNERSHIP_PASS
DEPENDENCY_DRIFT_REVIEWED
CROSS_BRANCH_OVERLAP_REVIEWED
RUNTIME_TESTED_HEAD_CURRENT
FOCUSED_VALIDATION_PASS
REQUIRED_REGRESSION_PASS
STATUS_DIMENSIONS_RECORDED
BLOCKERS_EMPTY_OR_EXPLICITLY_WAIVED
```

Waiver, если разрешён, обязан быть explicit и записан с причиной и владельцем решения.

---

## 31. Глобальная коррекция всегда делается через central branch

Если локальный агент обнаружил необходимость общего архитектурного изменения, он не должен исправлять весь проект из своей feature branch.

Правильная последовательность:

```text
LOCAL DISCOVERY
     ↓
GLOBAL_DECISION_REQUIRED
     ↓
CENTRAL ARCHITECTURE CHANGE
     ↓
NEW ARCHITECTURE REVISION if semantics changed
     ↓
SYNC AFFECTED FRONTIERS
     ↓
LOCAL IMPLEMENTATION CONTINUES
```

Это сохраняет причинность архитектуры.

---

## 32. Не повышать architecture revision из-за оперативных изменений

Следующие события обычно НЕ требуют новой архитектурной revision:

- новый accepted checkpoint;
- смена active branch;
- добавление fix branch;
- изменение progress note;
- новый test evidence;
- merge candidate;
- docs correction без изменения semantics.

Для них меняется registry generation.

Architecture revision меняется только если поменялось то, что другие программы должны считать новым глобальным правилом.

---

## 33. Immutable history policy

Accepted/frozen checkpoint не следует переписывать под последующие правила только ради внешнего единообразия.

История должна показывать, при каких условиях решение реально принималось.

Если позже появилась новая architecture revision:

```text
old checkpoint remains historical
active frontier aligns to new revision
```

Это делает историю аудируемой.

---

## 34. Documentation hierarchy

Рекомендуемая иерархия:

```text
GLOBAL ARCHITECTURE
        ↓
PROGRAM ROADMAP
        ↓
BRANCH PASSPORT
        ↓
CHECKPOINT / VALIDATION
```

Нижний уровень не может отменять верхний.

Если локальная документация противоречит global architecture, выигрывает global architecture и возникает blocker.

---

## 35. Dependency graph должен быть явным

Registry должен поддерживать связи:

```text
A depends_on B
A blocked_by C
A enables D
```

Это позволяет вычислять critical path проекта и видеть влияние задержки одной foundation на несколько программ.

Особенно полезно для агентов: агент видит не только свою задачу, но и кого она блокирует.

---

## 36. Research branch не получает права менять production semantics

Research/experiment ветки должны иметь отдельную роль.

По умолчанию они могут:

- собирать данные;
- проводить benchmark;
- строить prototype;
- доказывать feasibility.

Но они не становятся production authority автоматически.

Результат research сначала превращается в decision/contract, а затем внедряется через официальный frontier.

---

## 37. Fix branch наследует исходный scope

Fix ветка должна по умолчанию закрывать конкретный invariant gap и не расширять архитектуру.

Хороший fix:

```text
problem
invariant
minimal repair
fault reproduction
regression proof
```

Плохой fix:

```text
во время исправления локальной ошибки заодно создать новый global manager
```

Если fix требует foundation change — применяется STOP AND ESCALATE.

---

## 38. Параллельные агенты должны минимизировать shared-file ownership

При разбиении работы следует стремиться к тому, чтобы программы изменяли разные production paths.

Shared contracts должны быть:

- маленькими;
- стабильными;
- явно versioned;
- изменяемыми через отдельный coordination checkpoint.

Чем больше агентов одновременно меняют одни и те же shared files, тем ниже реальная параллельность проекта.

---

## 39. Не использовать центральную ветку как рабочую feature ветку

Central branch должна оставаться control/integration plane.

Крупная implementation work должна происходить в зарегистрированных ветках.

Исключения:

- central control metadata;
- architecture decisions;
- маленькие интеграционные исправления по установленной policy.

---

## 40. Агент обязан сообщать не только успех, но и остаточный риск

В конце stage нельзя писать только:

```text
PASS
```

Нужно фиксировать:

```text
WHAT WAS PROVEN
WHAT WAS NOT PROVEN
KNOWN LIMITATIONS
DEFERRED RISKS
NEXT REQUIRED GATE
```

Особенно важно различать:

```text
implemented
focused tested
full regression tested
integrated
production ready
```

---

## 41. Control audit не заменяет архитектурное мышление

Автоматический auditor хорошо обнаруживает:

- stale validation;
- ref drift;
- overlapping files;
- explicit ownership conflicts;
- missing passports;
- dependency path changes.

Но он не способен полностью понять семантический конфликт двух разных реализаций.

Поэтому periodic architecture review остаётся обязательным.

Рекомендуемый вопрос review:

> Если принять все активные ветки одновременно, получится ли одна система или несколько конкурирующих моделей одного и того же мира/данных/authority/state?

---

## 42. Правило локальной истины и derived representation

Для сложных систем полезно явно определить, какие данные являются canonical, а какие derived.

Общий принцип:

```text
CANONICAL STATE != PRESENTATION
CANONICAL STATE != TRANSPORT
CANONICAL STATE != CACHE
CANONICAL STATE != COMPUTE ASSIGNMENT
```

Конкретный проект формулирует свои инварианты сам.

Ценность правила для параллельных агентов: UI/network/cache/performance ветки не начинают незаметно владеть domain truth.

---

## 43. Transactional rule для state mutations

Если операция может менять несколько связанных состояний, агент должен заранее определить atomicity boundary.

Минимальный шаблон:

```text
VALIDATE
   ↓
PURE PREPARE
   ↓
TRANSITION PLAN
   ↓
AUTHORITATIVE COMMIT
   ↓
PUBLISH / DERIVED EFFECTS
```

Rejected/failed operation по возможности должна иметь:

```text
ZERO CANONICAL SIDE EFFECTS
```

Если атомарность невозможна, recovery semantics должны быть явной частью контракта и acceptance.

---

## 44. Агент не должен полагаться на скрытый контекст другого агента

Каждая задача должна быть воспроизводима из репозитория.

Нельзя требовать знания:

- старого чата;
- приватного reasoning;
- устной договорённости;
- незафиксированного локального состояния.

Если знание необходимо для продолжения разработки, оно должно быть записано в:

- architecture;
- program roadmap;
- branch passport;
- checkpoint;
- validation;
- issue/PR decision record.

---

## 45. Рекомендуемый operating loop агента

### Перед работой

```text
READ CENTRAL STATE
READ ARCHITECTURE
READ OWNERSHIP
READ PASSPORT
RUN CONTROL AUDIT
```

### Во время работы

```text
KEEP SCOPE LOCAL
UPDATE PROGRESS
DECLARE NEW CONTRACTS
WATCH DEPENDENCIES
DO NOT CREATE HIDDEN FOUNDATIONS
```

### Перед candidate

```text
SELF-REVIEW OWNERSHIP
RUN FOCUSED TESTS
RUN FAILURE TESTS
RECORD TESTED HEAD
UPDATE PASSPORT
```

### Перед acceptance

```text
RUN REQUIRED REGRESSION
RUN PROJECT CONTROL
CHECK DEPENDENCY DRIFT
CHECK CROSS-BRANCH OVERLAP
CHECK BLOCKERS
WRITE VALIDATION RECORD
```

### Перед следующим stage

```text
CENTRAL FRONTIER HANDOFF
CONVERGENCE REVIEW IF REQUIRED
ONLY THEN CONTINUE
```

---

## 46. Central controller operating loop

Человек или управляющий агент верхнего уровня периодически выполняет:

```text
LOAD REGISTRY
        ↓
RESOLVE REAL REMOTE HEADS
        ↓
READ ACTIVE PASSPORTS
        ↓
CHECK ACTUAL PROGRESS
        ↓
CHECK TESTED HEADS
        ↓
CHECK DEPENDENCY DRIFT
        ↓
CHECK PAIRWISE OVERLAP
        ↓
CHECK OWNERSHIP
        ↓
CHECK BLOCKERS / CRITICAL PATH
        ↓
CORRECT CENTRAL STATE
        ↓
ISSUE GLOBAL DECISIONS IF NEEDED
```

Задача central controller — не писать весь код, а постоянно удерживать проект в единой архитектурной реальности.

---

## 47. Что central controller должен видеть за один просмотр

Dashboard должен отвечать на вопросы:

```text
Какие программы активны?
Что делает каждая ветка?
Зачем она нужна?
Что она должна получить?
На какой стадии она сейчас?
Какой последний checkpoint принят?
Что следующее?
Кто кого блокирует?
Какие программы RED/YELLOW?
Где stale validation?
Где dependency drift?
Где пересечение runtime/shared contracts?
Есть ли новые foundation claims?
Какие решения требуют global architecture correction?
```

Если для ответа требуется вручную читать двадцать PR, control plane недостаточно развит.

---

## 48. Минимальный branch passport template

```json
{
  "branch": "feature/example",
  "program": "EXAMPLE",
  "role": "PRIMARY",
  "parent_branch": "main",
  "base_commit": "<sha>",
  "parent_checkpoint": "EXAMPLE_1_ACCEPTED",
  "architecture_revision": "ARCH-R1",
  "control_plane_revision": "CONTROL-R1",

  "short_description": "Что делает эта ветка.",
  "purpose": "Зачем она нужна проекту.",
  "expected_outcome": "Какой наблюдаемый результат обязан быть получен.",

  "current_stage": "EXAMPLE.2",
  "stage_status": "ACTIVE",
  "progress_note": "Что уже реализовано и что остаётся.",
  "last_accepted_checkpoint": "EXAMPLE.1",
  "next_stage": "EXAMPLE.3",

  "dependencies": [],
  "owned_paths": [],
  "watched_paths": [],
  "critical_watched_paths": [],
  "runtime_paths": [],

  "new_contracts": [],
  "ownership_claims": [],
  "forbidden_foundation_ownership": [],

  "tested_heads": {
    "focused": "",
    "runtime": "",
    "full_regression": ""
  },

  "validation_paths": [],
  "blockers": []
}
```

---

## 49. Минимальный central registry entry

```json
{
  "program_name": "Example program",
  "branch": "feature/example",
  "role": "PRIMARY",
  "short_description": "Кратко что это.",
  "purpose": "Зачем программа нужна.",
  "expected_outcome": "Что она должна дать.",
  "current_stage": "EXAMPLE.2",
  "stage_status": "ACTIVE",
  "progress_note": "Фактическое состояние.",
  "last_accepted_checkpoint": "EXAMPLE.1",
  "next_stage": "EXAMPLE.3",
  "blockers": [],
  "health_declared": "GREEN"
}
```

---

## 50. Минимальный project-control report

Machine-readable report рекомендуется строить так:

```text
generated_at
architecture_revision
control_revision
overall_health

programs[]
    branch
    head
    merge_base
    current_stage
    health
    tested_head
    main_commits_since_merge_base
    branch_commits_since_merge_base
    dependency_drift[]
    runtime_changes_after_test[]
    findings[]

cross_branch_overlaps[]
architecture_findings[]
critical_path_blockers[]
```

---

## 51. Антипаттерны

### Огромный единый roadmap со всем состоянием

Проблема: architecture и operational state начинают постоянно конфликтовать.

Решение: разделить architecture и registry.

### Ветка без паспорта

Проблема: через неделю никто не знает её scope и место в проекте.

### Агент объявляет `DONE`

Проблема: неизвестно, что именно доказано.

### Validation без commit SHA

Проблема: невозможно понять, относится ли PASS к текущему коду.

### Каждый domain создаёт свой Manager/Registry/Transaction

Проблема: локально всё работает, глобальная модель распадается.

### Постоянный merge main во все ветки

Проблема: создаётся огромный интеграционный шум.

Решение: watched dependency audit + planned convergence.

### Никогда не синхронизировать длинные ветки

Проблема: интеграционный долг накапливается до взрывного уровня.

### Исправлять global architecture внутри локального fix

Проблема: остальные программы не знают, что архитектура фактически изменилась.

### Хранить project memory только в чате

Проблема: следующий агент начинает археологию вместо разработки.

---

## 52. Когда эта модель особенно полезна

Она особенно эффективна, если одновременно выполняются несколько условий:

- проект живёт месяцами или годами;
- существует много подсистем;
- несколько агентов работают параллельно;
- feature branches долгоживущие;
- есть distributed/stateful поведение;
- acceptance требует сложных test gates;
- архитектурные ошибки дороги;
- агенты могут сменяться между задачами;
- нужно уметь в любой момент провести глобальный аудит.

Для маленького проекта часть механики может быть избыточной.

---

## 53. Минимальная версия для нового проекта

Если переносить подход в новый репозиторий, достаточно начать с пяти вещей:

```text
1. GLOBAL ARCHITECTURE
2. CENTRAL PROGRAM REGISTRY
3. BRANCH PASSPORT TEMPLATE
4. OWNERSHIP MATRIX
5. PROJECT CONTROL AUDITOR
```

Затем добавить:

```text
6. tested-head freshness
7. watched dependency drift
8. cross-branch overlap
9. CI report
10. generated dashboard
```

Не нужно внедрять весь control plane в первый день.

---

## 54. Bootstrap нового agentic проекта

### Шаг 1

Определить центральную ветку.

```text
main
```

### Шаг 2

Записать 5–15 действительно важных architecture invariants.

### Шаг 3

Определить ownership главных foundations.

### Шаг 4

Разбить разработку на программы, а не на случайные ветки.

### Шаг 5

Завести central registry.

### Шаг 6

Создать branch passport template.

### Шаг 7

Требовать паспорт перед существенной реализацией.

### Шаг 8

Требовать tested-head evidence.

### Шаг 9

Автоматизировать project audit.

### Шаг 10

Проводить periodic central architecture review.

После этого количество агентов можно постепенно увеличивать.

---

## 55. Главная идея масштабирования агентной разработки

Количество агентов само по себе не делает разработку быстрее.

Реальная параллельность определяется тем, насколько хорошо разделены:

```text
OWNERSHIP
CONTRACTS
STATE
DEPENDENCIES
ACCEPTANCE
```

Если десять агентов могут независимо работать над десятью domain areas через стабильные контракты — проект масштабируется.

Если десять агентов одновременно меняют один shared manager — проект фактически однопоточный, несмотря на десять веток.

Поэтому цель control plane:

> не управлять агентами по шагам, а создать такую структуру проекта, в которой независимая работа остаётся безопасно компонуемой.

---

## 56. Итоговая модель

```text
                         CENTRAL BRANCH
                              │
              ┌───────────────┼───────────────┐
              │               │               │
       ARCHITECTURE       PROGRAM REGISTRY   OWNERSHIP
              │               │               │
              └───────────────┼───────────────┘
                              │
                           AUDITOR
                              │
        ┌─────────────┬───────┼───────┬─────────────┐
        ▼             ▼       ▼       ▼             ▼
     PROGRAM A     PROGRAM B PROGRAM C FIX TRACK  RESEARCH
        │             │       │       │             │
     passport       passport passport passport     passport
     validation     validation ...
     git refs
        └─────────────┴───────┼───────┴─────────────┘
                              │
                              ▼
                       PROJECT DASHBOARD
                              │
                              ▼
                  GLOBAL CORRECTIONS / HANDOFFS
```

Фундаментальные правила в краткой форме:

```text
1. Central branch owns official project state.
2. Architecture and operational state are separate.
3. Every active branch has a passport.
4. Every branch explains WHAT / WHY / EXPECTED / CURRENT.
5. Every foundation has one owner.
6. Agents declare dependencies and watched paths.
7. Validation is tied to exact tested commits.
8. Active branches are audited pairwise, not only against main.
9. Acceptance and frontier advancement are separate decisions.
10. Historical checkpoints are not rewritten.
11. Global architecture changes are escalated to central control.
12. Project memory lives in the repository, not in chat.
13. Failure/replay/recovery evidence matters as much as happy path.
14. Central dashboard must expose the complete project dynamics at a glance.
15. The system should maximize safe independence of agents, not merely the number of concurrent branches.
```

Это и есть базовый governance protocol для больших agentic software projects.