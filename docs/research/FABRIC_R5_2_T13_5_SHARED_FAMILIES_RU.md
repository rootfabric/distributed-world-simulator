# FABRIC R5.2 / T13.5 — Shared Families & Parametric Variants

Статус: **IMPLEMENTED / EXACT GATE PENDING**.

База: закрытый T13 merge `b41b07a988726e6c7a18a39819183e2a9ce6aefe`.

## Цель

T13 доказал один immutable CompiledModel → 100 независимых instance state.

T13.5 проверяет следующий реальный случай: мир состоит не только из полностью
одинаковых объектов. Несколько structural family должны переиспользовать уже
скомпилированные неизменённые поддеревья, а число экземпляров не должно
увеличивать compile work.

Acceptance строит 4 family:

- **A / 40 instances** — LFP battery + WATER cooling + GAAS emitter;
- **B / 30 instances** — family A, но cooling unit03 заменён на GLYCOL;
- **C / 20 instances** — family A, но battery заменена на NMC;
- **D / 10 instances** — family A, но emitter unit03 заменён на GAN.

Итого 100 instances.

## Selective compile accounting

Instrumented fixture считает только реальные вызовы compiler/compose.

Полная базовая T12 Ship Matryoshka:

```text
battery                     1
3 × turret subtree         27
bank                        1
ship                        1
------------------------------
base                       30 compile events
```

Variant delta:

```text
battery NMC:
  battery + ship            = 2

cooling GLYCOL:
  cooling + cannon
  + turret + bank + ship    = 5

emitter GAN:
  emitter + cannon
  + turret + bank + ship    = 5
```

Итого selective compile work:

```text
4 full family × 30              = 120
selective family compile        = 42
cross-family avoided            = 78
```

Это именно инкрементальный результат T13.5 относительно уже закрытого T13.

Для справки, совместный эффект T13 + T13.5 относительно полностью наивного
подхода «компилировать каждый из 100 экземпляров целиком»:

```text
no-cache 100 × full Ship        = 3000
selective family compile        = 42
combined avoided                = 2958
```

После регистрации family создание и исполнение 100 instance добавляет **0 compile events**.

## Compiled subtree pool

Registry вычисляет exact binary SHA-256 каждого compiled subtree и интернирует
его один раз.

Для четырёх family:

```text
subtree occurrences       = 120
unique subtree identities = 42
reuse hits                = 78
shared identities         = 29
max family reuse          = 4
```

Проверяются конкретные relations:

- unit01 и unit02 целиком общие для A/B/C/D;
- battery общая для A/B/D, NMC в C отлична;
- полный bank общий для A/C;
- unit03 servo/drive общие для всех;
- cannon power общий для всех;
- GAAS emitter общий для A/B/C, GAN в D отличен;
- WATER cooling общий для A/C/D, GLYCOL в B отличен.

## Execution model

Каждая **уникальная full family** получает один prepared T13 SharedModel.
Точный duplicate family id маршрутизируется на уже существующий owner и не
создаёт новый prepare.

100 instance получают независимые T13 binding/state.

T13.5 **не заявляет**, что prepared child-runtime object уже физически pointer-shared
между разными full-family runtime. На этом шаге переиспользуется compiled subtree
identity/representation и selective upstream compilation. Recursive shared
execution / mixed-resolution child runtime остаётся задачей R5.3.

## Damage isolation

Один instance из family B получает local disable damage. Acceptance запускает
healthy control и candidate для всех 100 объектов.

Требуется:

```text
damaged instance diverges       = true
other 99 exact-equivalent       = 99
family prepares after instances = 0 additional
compile events after instances  = 0 additional
all family models intact        = true
```

## Критерий T13.5

Главный инвариант:

```text
T13.5 incremental:
4 full families = 120
selective structural compile = 42
cross-family reuse avoids = 78

combined T13 + T13.5 no-cache comparison:
100 full instance compiles = 3000
selective family compile = 42
```

Таким образом T13.5 отдельно доказывает **reuse между family**, а T13 уже
отдельно доказал отсутствие compile-work на каждый instance.

T13.5 является мостом:

```text
T13  identical instances
  ↓
T13.5 structural families + subtree reuse
  ↓
T14 selective observation-driven refinement
```
