# Procedural World Realism Roadmap — RL7

**Ветка:** `feature/rl7-procedural-world-realism`.
**Архитектура:** `docs/architecture/PROCEDURAL_WORLD_REALISM_FABRIC_RU.md`.
**Статус:** документационный roadmap; реализация не начата.

## 1. Место в общей последовательности

```text
RL0  unified representation contracts — ACCEPTED
RL1  Matter summary pyramid — ACCEPTED
RL2  multiresolution Matter meshing — ACCEPTED
RL3  network artifact streaming — CURRENT CANDIDATE
RL4  Construction HLOD backend
RL5  shared cache and background builders
RL6  visual/network/scale acceptance
RL7  procedural world realism
MI0–MI4 Moon/planet integration
```

RL7 опирается на RL0–RL6, но не должен изменять их текущие acceptance-контракты. Его задача — определить, какие канонические причинные поля и производные представления нужны для правдоподобной планеты.

## 2. Цель

Получить процедурную генерацию, в которой лес, пустыня, тундра, каменистая поверхность и другие биомы воспринимаются как результат природных процессов, а не как случайная расстановка моделей.

Ключевой критерий:

```text
мир должен оставаться правдоподобным в graybox-режиме,
без production-текстур и дорогих ассетов
```

## 3. Этапы

### RL7.0 — Contracts and Reference Fixtures

Результат:

- `ProceduralRealismProfile`;
- иерархия глобального, планетарного, регионального и локального seed;
- versioned dependency contracts для климата, геологии, гидрологии, почвы и биомов;
- четыре фиксированных эталонных биома;
- graybox-сцены;
- offline metrics runner;
- deterministic replay manifest.

Acceptance:

- одинаковый seed даёт byte-stable descriptors;
- порядок загрузки регионов не меняет результат;
- границы соседних регионов совпадают;
- fixture можно оценить без SceneTree и камеры.

### RL7.1 — Planet and Biome Macrostructure

Результат:

- крупномасштабные климатические поля;
- геологически связанные формы рельефа;
- гидрологические зависимости;
- карты почвы;
- биомные пятна и переходные зоны;
- поля возраста и нарушений;
- macro landmarks;
- summaries для дальнего LOD.

Acceptance:

- отсутствует очевидный тайлинг;
- биомы соответствуют климату, высоте и воде;
- дальний LOD сохраняет крупные поляны, границы и нарушения;
- orbit-to-region сохраняет идентичность местности.

### RL7.2 — Ecological Community Generation

Результат:

- выбор видов;
- возрастные распределения;
- кластерная пространственная модель;
- конкуренция;
- вертикальные ярусы;
- подлесок;
- сухостой, пни и мёртвая древесина;
- естественное возобновление.

Acceptance:

- nearest-neighbor и многомасштабная кластеризация находятся в заданных диапазонах;
- присутствуют поляны и зоны разной плотности;
- нет массовых одинаковых силуэтов;
- структура связана с влагой, уклоном, светом и почвой.

### RL7.3 — Surface Contact and Environmental Presentation

Результат:

- terrain-aware placement;
- контактные маски;
- локальная вариация субстрата;
- подавление конфликтующей травы;
- пространственное поле ветра;
- biome audio descriptors;
- согласование цвета, освещения и атмосферы;
- явные профили gameplay bias.

Acceptance:

- крупные объекты не выглядят установленными поверх terrain;
- нет массовых пересечений;
- движение растений не синхронно;
- плотность и звук меняются между поляной и плотным массивом;
- NATURALISTIC, BALANCED и GAMEPLAY_READABLE дают воспроизводимые различия.

### RL7.4 — Representation and Distributed Generation

Результат:

- representation summaries биомов;
- content-addressed community artifacts;
- cross-region boundary continuity;
- server/offline builder equivalence;
- cache invalidation после изменения Matter, климата или disturbance state;
- progressive network streaming через RL3;
- background build через RL5.

Acceptance:

- клиент не получает все отдельные растения на дальней дистанции;
- дальний proxy сохраняет плотность, границы и силуэт массива;
- изменение одного локального участка не перестраивает весь биом;
- потеря cache не изменяет каноническую среду;
- handoff региона не меняет результат генерации.

### RL7.5 — Planet Realism Acceptance

Сценарии:

- орбита → атмосфера → регион → лес → контакт с поверхностью;
- хвойный лес;
- смешанный лес;
- тундра;
- каменистая пустыня;
- разные seeds;
- разные времена суток и погода;
- локальное изменение Matter;
- пересечение серверной границы;
- быстрое движение наблюдателя;
- потеря и восстановление artifact cache.

Acceptance:

- graybox сохраняет читаемость биома;
- нет заметного тайлинга;
- LOD не меняет воспринимаемый масштаб;
- duplicate silhouette rate ограничен;
- generation, memory, draw-call и network budgets ограничены;
- соседние регионы непрерывны;
- canonical result не зависит от клиента и камеры.

## 4. Обязательные метрики

```text
nearest_neighbor_ratio
ripley_k_multiscale
cluster_size_distribution
clearing_size_distribution
canopy_closure_distribution
visibility_depth_distribution
age_spatial_autocorrelation
duplicate_silhouette_rate
contact_error_rate
intersection_rate
lod_silhouette_error_px
biome_boundary_continuity_error
seed_replay_mismatch_count
region_order_dependency_count
```

Метрики дополняют, а не заменяют перцептивную оценку.

## 5. Базовые fixtures

### Хвойный лес

Проверяет:

- крупные вертикальные силуэты;
- неоднородную плотность;
- молодняк на просветах;
- бедный подлесок под плотными кронами;
- сухостой;
- дальнюю читаемость лесного массива.

### Смешанный лес

Проверяет:

- сочетание видов;
- разные формы крон;
- сезонную вариативность;
- несколько вертикальных ярусов;
- более сложные переходные зоны.

### Тундра

Проверяет:

- зависимость от ветра, влаги и экспозиции;
- низкую растительность;
- крупные открытые пространства;
- отсутствие необходимости скрывать слабую структуру деревьями.

### Каменистая пустыня

Проверяет:

- геологическую причинность камней;
- осыпи и обнажения;
- эрозию;
- редкие биологические кластеры;
- масштаб без растительной маскировки.

## 6. Integration gates

Перед RL7.4:

```text
RL3 PASS
RL5 scheduler/cache contract available
MW regional revisions stable
```

Перед MI production planet integration:

```text
RL7.0 PASS
RL7.1 PASS
RL7.2 PASS
RL7.3 PASS
RL7.4 PASS
RL7.5 PASS
```

## 7. Неизменяемые правила

- отдельные foliage meshes не являются world state;
- camera position не влияет на canonical generation;
- gameplay readability задаётся явным профилем;
- одна и та же причина должна давать один и тот же результат;
- локальная мутация имеет ограниченный rebuild fan-out;
- дальнее представление сохраняет структуру, а не только средний цвет;
- production-ассеты подключаются только после graybox gate;
- генерация идёт сверху вниз: планета → регион → сообщество → объект → контакт.
