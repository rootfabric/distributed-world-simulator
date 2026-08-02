# Robot Construction Grid — будущая функция PlanetSimulator

**Статус:** `FUTURE FEATURE / ARCHITECTURE FROZEN FOR LATER IMPLEMENTATION`
**Дата фиксации:** 3 августа 2026 года
**Серия будущих этапов:** `RCG0–RCG8`
**Рекомендуемая первая ветка:** `feature/rcg0-robot-construction-grid-contracts`

## Назначение каталога

Этот каталог фиксирует модель локальных гридов роботов, машин, роверов, кораблей и других составных подвижных конструкций.

Robot Construction Grid не заменяет:

- мировой `SimulationCell`;
- `Item Graph`;
- `ConstructAggregate`;
- structural bonds и damage/split;
- utility networks;
- Representation LOD Fabric.

Он добавляет недостающий слой локального дискретного размещения частей внутри одного item-backed construct.

```text
мировой spatial grid
└── Robot / Machine ConstructAggregate
    ├── один или несколько rigid grid segments
    │   └── локальные grid cells и установленные parts
    ├── structural graph
    ├── joint graph
    ├── power/data/fluid/mechanical graphs
    └── derived mesh, collision и LOD representations
```

## Документы

- `ROBOT_CONSTRUCTION_GRID_ARCHITECTURE_RU.md` — каноническая архитектура, границы ответственности и инварианты.
- `ROBOT_CONSTRUCTION_GRID_IMPLEMENTATION_GUIDE_RU.md` — точка старта, зависимости, этапы `RCG0–RCG8`, структура файлов и тестовые gates.

## Краткое решение по сроку

Pure-domain этап `RCG0` разрешено начинать после создания одного воспроизводимого integration checkpoint, в котором одновременно присутствуют:

1. принятый строительный срез `C23 Production Hardening fix1`;
2. принятые общие representation contracts `RL0`, доступные в составе текущего `RL1`;
3. согласованные `Item Graph`, aggregate transaction и authority boundaries;
4. зелёные construction, network и world regression профили после объединения.

Не требуется ждать `MW9`, `MW10`, `RL2–RL6`, Moon integration или полноценного agent runtime.

До integration checkpoint разрешена только документация и отдельный throwaway prototype, который не становится частью production domain.
