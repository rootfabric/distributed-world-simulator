# FABRIC COMPLEX2-D — Independent Structural Failure

**Статус:** ✅ PHYSICAL EXACT VERIFIED  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**Exact subject:** `3ac206b02c77002fe62bc937105ee67e1ef46260`  
**TREE:** `64be92fbcb535c973b9eb22935510a016d1cf18d`  
**Evidence:** `validation/FABRIC_COMPLEX2_D_INDEPENDENT_STRUCTURAL_FAILURE_EXACT_EVIDENCE.md`

## Зачем нужен D

Предыдущие события COMPLEX2 уже умели отделять detachable module и ломать support, несущий functional path. Для более сложной машины этого недостаточно: нужен отказ, который является **чисто структурным** и заставляет конструкцию перераспределить нагрузку, не разрывая весь объект и не выключая функциональную сеть.

D использует независимый brace:

```text
brace/complex2-12-16
```

Он не совпадает с:

```text
support/complex2-23-24  # detach #24
support/complex2-10-11  # functional path B
```

## Structural subnetwork

```text
module12 -- module13 -- module14 -- module15 -- module16
   |                                             |
   +-------------- redundant brace -------------+
```

На module16 прикладывается 100 N, module12 является anchor. До отказа часть нагрузки идёт через brace; после отказа нагрузка обязана перейти в длинную chain path.

Exact значения:

```text
brace before   61.608243 N
tip before      0.123216486 m
tip after       0.320945163 m
chain ratio      2.604726
residual       ~2.84e-14 N
```

После отказа все 25 модулей остаются в одном connected component. Это не detachment.

## Canonical / derived ordering

Structural failure является canonical topology event. Его source projection затрагивает два execution partitions:

```text
FULL
CONTACT_BAKE
```

Поэтому правильный lifecycle:

```text
canonical brace failure
        ↓
FULL + CONTACT stale
        ↓
mixed execution blocked
        ↓
partial single-region rebuild rejected
        ↓
atomic FULL+CONTACT rebuild
        ↓
zero handoff error
        ↓
mixed == FULL reference
```

COMPLEX2-B compliant HYBRID backend и COMPLEX2-C coupled DYNAMIC backend не перестраиваются и сохраняют identity.

## Отсутствие скрытого functional event

Brace `12-16` не является support relation для functional links. Поэтому D требует:

```text
functional subject before == functional subject after
functional solve before   == functional solve after
```

То есть structural damage сам по себе не должен автоматически порождать электрический/functional damage, если causal support relation не существует.

## Fail-closed boundaries

```text
COMPLEX2D_EVENT_ALREADY_APPLIED
COMPLEX2D_REFINEMENT_REQUIRED_LOAD
COMPLEX2D_REFINEMENT_REQUIRED_DEFLECTION
BRIDGE2_MIXED_STEP_BLOCKED
BRIDGE2_REBUILD_REGISTRY_FAILED
```

## Visual lab

```text
res://scenes/labs/fabric/complex2d_structural_failure_lab.tscn
```

`Space` переключает baseline / failed state. Observer показывает исчезновение brace, рост tip displacement и перераспределение chain force. Visual layer read-only.

## Exact result

```text
FABRIC COMPLEX2-D Independent Structural Failure Acceptance:
PASS (50 assertions)

hash:
5dcc2f802c5aaf444eeca2c910aab9973205ab7ab2d4c3b2caada3257b27b580
```

Два независимых запуска exact source bundle дали один hash.

## Control-plane status

Project Control на D-head остаётся RED из-за repository-wide ownership/passport drift в G/ECO/V0/MATTER/P7 dependencies. Эти файлы не входят в D implementation diff. Поэтому D отмечается как `PHYSICAL EXACT VERIFIED`, но Project Control не подменяется зелёным результатом.

D открывает следующий lifecycle falsifier: `COMPLEX2-E Settle → Rebake → Re-impact`.