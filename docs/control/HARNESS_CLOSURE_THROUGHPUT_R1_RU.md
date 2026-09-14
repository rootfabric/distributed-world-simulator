# DWS Harness — ускоренное закрытие checkpoint без ослабления приёмки

**Revision:** `H0-CLOSURE-THROUGHPUT-2026-09-14-R1`  
**Scope:** post-freeze closure для MVP и других Harness-managed runtime checkpoint.  
**Не меняет:** canonical ownership, exact-head требования, обязательные product predicates, Reviewer/Verifier separation, human merge gates.

## 1. Зачем

Разработка небольшого leaf часто занимает минуты, а закрытие — существенно дольше из-за последовательных CI/review/verifier/control стадий. Цель этой поправки — уменьшить wall-clock latency, не превращая PASS в формальность.

Главное правило:

```text
DO NOT REMOVE GATES
REMOVE SERIAL WAITING AND FALSE NEGATIVES
```

## 2. Acceptance refinement усиливает каталог

`checkpoint-catalog` задаёт минимальный обязательный набор predicates. Work Order может добавлять более точные sub-gates, если они усиливают исходную приёмку.

Правильное отношение:

```text
catalog.required_predicates
        ⊆  (с сохранением порядка)
work_order.required_predicates
```

Запрещено:

- удалить catalog predicate;
- поменять его порядок так, чтобы изменить смысл control train;
- продублировать predicate;
- ослабить risk floor или required roles.

Разрешено:

- добавить уникальные leaf/sub-gates, которые делают acceptance строже;
- привязать generic top-level predicate к конкретному live gameplay proof.

Таким образом `pickup/drop/container/carry/build/recovery` могут уточнять `MVP_ITEM_CONSTRUCTION_PERSISTENCE_CONVERGENCE`, не ломая Harness только потому, что Work Order стал строже каталога.

## 3. Freeze → fan-out → barrier

После того как runtime implementation заморожен на exact `HEAD/TREE`, независимые read-only стадии не должны без причины идти цепочкой.

```text
IMPLEMENT
   ↓
FOCUSED PASS
   ↓
FREEZE exact HEAD/TREE
   ↓
   ├──────── full world/core
   ├──────── Project Control + PC0
   ├──────── fresh Reviewer
   └──────── fresh Verifier evidence consumption
             ↓
       CLOSURE BARRIER
             ↓
      PREDICATE_VERIFIED
```

Условия:

- runtime mutation writer остаётся ровно один;
- read-only review/verification/CI не потребляют mutation lease;
- финальный barrier всё равно требует все mandatory gates;
- runtime commit после freeze делает stale только те exact-head результаты, которые зависят от старого subject;
- evidence/control carrier не должен двигать frozen product HEAD.

## 4. Preferred Verifier недоступен — не ждать

Если конкретный внешний Verifier/Cloud environment не стартовал:

```text
PREFERRED_EXECUTOR_UNAVAILABLE
        ↓
record once
        ↓
DO NOT WAIT
DO NOT RETRY SAME ROUTE
        ↓
next allowed fresh isolated role context
        ↓
consume hash-bound exact-head machine evidence
        ↓
re-execute only when Work Order/risk/provenance requires it
```

Независимость роли сохраняется. Implementer может произвести механические логи, hashes и artifacts, но не может сам выдать independent verdict.

Отсутствие конкретного облачного окружения не является `NOT_VERIFIED`, если требуемые raw evidence доступны через другой разрешённый route. `NOT_VERIFIED` относится к отсутствию обязательного доказательства, а не к отсутствию любимого executor-а.

## 5. CI: product result и control diagnostics различаются

Один workflow может содержать несколько jobs. Их смысл надо классифицировать отдельно.

Пример:

```text
full-world-core = PASS
control-drive   = route/setup FAIL
```

Нельзя переименовывать это в `WORLD_CORE_FAIL`. Product gate остаётся PASS; control route failure сохраняется как отдельный repair item.

При этом настоящий test/evidence failure остаётся блокирующим.

Branch-sensitive команды `Status/Resume/Drive` должны выполняться на локальной ветке с объявленным именем, указывающей на тот же exact SHA. `actions/checkout` detached HEAD недостаточен для таких команд.

## 6. Review scope

Один parent product PR может оставаться долгоживущим. Fresh Reviewer/Verifier обязан читать текущий leaf как:

```text
predicate + exact HEAD/TREE + bounded diff + current evidence package
```

а не повторно расследовать весь многодневный PR thread.

Исторические findings повторно блокируют leaf только если:

- дефект воспроизводится на текущем exact subject; или
- текущий diff всё ещё затрагивает тот же контракт.

Создавать отдельный новый PR только ради каждого evidence-файла не требуется, если exact evidence/review carrier уже даёт чистую границу subject.

## 7. Что эта поправка намеренно НЕ делает

Она не разрешает:

- пропускать full world/core, когда он required;
- заменять Verifier на Implementer;
- принимать stale review после runtime change;
- ослаблять negative controls;
- удалять failed historical runs;
- запускать второго runtime writer;
- автоматически merge-ить main;
- принимать whole MVP без Human gate, если он объявлен.

## 8. Практический эффект для MVP5/MVP6+

Для frozen leaf целевое wall-clock closure ограничивается в основном самым длинным обязательным gate, а не суммой их длительностей.

```text
старое:
focused + world/core + review + verifier + control

новое:
focused + max(world/core, review, verifier, control) + closure barrier
```

Именно это является throughput-оптимизацией. Acceptance сила не уменьшается.
