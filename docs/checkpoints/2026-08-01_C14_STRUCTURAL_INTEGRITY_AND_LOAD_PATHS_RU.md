# C14 — Structural Integrity and Load Paths

**Статус:** IMPLEMENTED CANDIDATE
**Рекомендуемая ветка:** `feature/c14-structural-integrity-load-paths`
**База:** принятый C13 поверх C12 `1152c94`.

## Цель

Добавить детерминированный инженерный слой между массой item-backed частей и C9 damage lifecycle без превращения mesh/physics в источник истины.

```text
ConstructSnapshot
+ part mass / structural metadata
+ bond strengths
+ gravity / external loads / supports
        ↓
deterministic load graph
        ↓
part and bond utilization
        ↓
progressive cascade proposal
        ↓
C9 DamageRequest
        ↓
retained aggregate / split aggregate / salvage / repair
```

## Принятые решения

1. Load case pin-ит construct checksum, supports, gravity, external loads, safety factor и cascade limits.
2. Активный граф строится только из неуничтоженных частей и небroken bonds.
3. Для каждой нагрузки выбираются детерминированные кратчайшие пути к ближайшим опорам; при нескольких равноудалённых опорах нагрузка делится поровну.
4. Part capacity берётся из `metadata.structural.capacity_n`; optional `buckling_capacity_n` ограничивает её сверху.
5. Bond capacity выводится из `strength_n`, safety factor и degraded factor.
6. Profile является JSON-safe derived cache и содержит реакции опор, load paths, utilisation и critical IDs.
7. Progressive collapse ломает по одному наиболее перегруженному элементу, каждый раз полностью пересчитывая граф.
8. Результат каскада не меняет конструкцию напрямую: он создаёт строгий C9 `DamageRequest` с заранее назначенными split identities.
9. Retry/replay использует terminal operation ledger; конфликтный load case с тем же operation ID отклоняется.
10. Compact structural summary сохраняет состояние, максимальную utilization и counts для far/dormant режима.

## Контрольный vertical slice

Конструкция имеет основной короткий путь нагрузки и более длинную резервную brace-ветвь.

```text
foundation — column — payload — tool
                 └ brace ──────┘
```

При дополнительной нагрузке:

1. перегружается primary bond;
2. после его разрушения нагрузка переходит на secondary brace path;
3. secondary bond также перегружается;
4. `payload + tool` становятся неподдерживаемой связной компонентой;
5. C9 атомарно создаёт child aggregate и перепривязывает те же ItemInstance;
6. C9 repair удаляет временный root и восстанавливает исходные пять parts и bonds.

## Проверки

```text
C14 contracts:    PASS — 90 assertions
C14 integration:  PASS — 78 assertions
C14 total:        PASS — 168 assertions
Editor parse:     PASS
```

Локально повторно пройдены C1–C8 и C10–C13. C9 focused требует отсутствующие в patch-only workspace production M0-файлы, но C14 integration выполняет реальный C9 in-memory damage/split/repair path.

Ожидаемый внешний профиль:

```text
C1–C13:            PASS
C9:                PASS — 204 assertions
C2B:               PASS — 258 assertions
C14:               PASS — 168 assertions
Network N0–M4:     PASS
World regression:  PASS — 129/129 tests, 132 steps
Main-scene CLI:    PASS — 6/6
```

## Граница этапа

C14 не является FEM и не моделирует деформации, контактные напряжения, вибрации или нелинейный материал. Это массово масштабируемая графовая модель статической нагрузки. Более точные solver-профили могут быть добавлены позднее, не меняя C9 authority boundary.
