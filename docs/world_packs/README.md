# WORLD PACKS — reusable world-generation content library

**Назначение:** библиотека воспроизводимых, версионируемых assets, surface families,
профилей представления среды и композируемых рецептов, из которых потребители DWS
собирают отображение канонических миров без отдельного кода для каждой планеты.

WORLD PACKS не владеет геометрией, физическими материалами, экологией, погодой,
Construction, gameplay, replication или persistence. Тяжёлые исходники хранятся
вне Git. Runtime использует заранее подготовленные локальные ресурсы.

## Два поколения, без разрушения совместимости

**WP0 — сохранённая gallery/content foundation.** Шесть работающих exemplars:
Moon Industrial, Mars Dust, Frozen World, Volcanic World, Temperate, Alien Wetland.
Их `dws.world_pack.v1`, GDScript profiles, registry, POI library и сцены остаются
неизменными. Это полезные примеры и regression fixtures, не универсальная модель
генерации планет. Alpine Settlement и другие предложенные названия не являются
фактическими шестью пакетами в проверенном HEAD `8da220d5`.

**WP1.0 — отдельный DRAFT_CONTRACT_FIXTURE.** Добавлен metadata-only прототип
`dws.world_library.v1`: точные ссылки `id@version`, SHA-256, provenance, независимые
source locations, surface bindings и композиция рецептов с отказом при конфликте.
Он НЕ является уже подключённым WORLDGEN resolver, downloader, importer или renderer.
Единственный payload — оригинальный диагностический текст, не PBR-материал.

## Где читать

- [Решение и границы систем](architecture/ADR-WP-001-SURFACE-LIBRARY-RU.md).
- [Дорожная карта и измеримые конечные состояния](WORLD_PACKS_ROADMAP.md).
- [Параллельный agent protocol](PARALLEL_AGENT_PROTOCOL_RU.md).
- [Пять параллельных workstreams](PARALLEL_WORKSTREAMS_RU.md).
- [Внешний research, лицензии и кандидаты ресурсов](RESEARCH_AND_SOURCES_RU.md).
- [Evidence текущего аудита](evidence/WP1_0_ARCHITECTURE_AUDIT_2026-09-05.md).
- [Историческое WP0.10 evidence](evidence/WP0_10_GALLERY_HARNESS_2026-09-04.md).

WP0.10 evidence сообщает о MCP graphical captures 2026-09-04; реальные draw-call
замеры всё ещё pending. Исторические PASS не являются новым runtime-прогоном аудита.

## Parallel controller

Для параллельной разработки используется branch-local helper, который не заменяет
main-owned Project Control/Harness:

```text
control/world-packs-parallel-r1
```

Он отслеживает пять независимых child branches:

```text
WP-ASSET1
WP-CONTENT1
WP-SURFACE1
WP-VIS1
WP-TOOLS1
```

Быстрый dashboard:

```powershell
.\RUN_WORLD_PACKS_PARALLEL_CONTROL.ps1 -Action status
.\RUN_WORLD_PACKS_PARALLEL_CONTROL.ps1 -Action next
.\RUN_WORLD_PACKS_PARALLEL_CONTROL.ps1 -Action instructions -Track WP-ASSET1
```

Linux:

```bash
./RUN_WORLD_PACKS_PARALLEL_CONTROL.sh status
./RUN_WORLD_PACKS_PARALLEL_CONTROL.sh next
./RUN_WORLD_PACKS_PARALLEL_CONTROL.sh instructions WP-ASSET1
```

Source of truth для allocation/milestones/allowed paths:
`config/world_packs/parallel/controller.v1.json`.
Каждый worker фиксирует progress/blocker/tests в собственном
`config/world_packs/parallel/workstreams/<TRACK>.v1.json` и публикует обычные
non-force Git commits. Chat не считается durable progress.

## Проверка нового metadata-контракта

Из корня репозитория, Python 3.11+:

```bash
python -m pip install -r tools/world_packs/requirements-library.txt
python tools/world_packs/library_contract.py --verify-fixtures
python -m pytest -q tests/world_packs/test_library_contract.py
```

Для тестов нужен pytest; аудит использовал pytest 9.0.2, Python 3.13.5,
jsonschema 4.26.0. Установка зависимостей — подготовительный шаг, не runtime.
Вывод `presentation_lock_hash` относится только к представлению. Это не checksum
Matter, не world identity и не доказательство одинаковых пикселей на разных GPU.

## Сохранённые WP0 entry points

```powershell
.\RUN_WORLD_PACKS_WP0_1_TESTS.ps1
.\RUN_WORLD_PACKS_WP0_2_TESTS.ps1
.\RUN_WORLD_PACKS_PROFILE_TESTS.ps1
.\RUN_WORLD_PACKS_WP0_9_TESTS.ps1
.\RUN_WORLD_PACKS_WP0_10_HARNESS.ps1
```

Gallery: `res://scenes/labs/world_packs/world_packs_gallery.tscn`.
Использовать проектную double-сборку Godot и правила `AGENTS.md`, не произвольный
редактор из системы. Последний прочитанный WP0.10 build:
`4.7.1.stable.double.custom_build.a13da4feb`, GL Compatibility.

## Как добавить поверхность

Подобрать источник и проверить права → зафиксировать реальные bytes/hash/version →
зарегистрировать asset → определить visual family и ссылки на существующие Matter ID →
составить presentation recipe → проверить данные → подготовить локальный cache →
передать recipe через согласованный WORLDGEN/RL adapter.

Сегодня исполняются только проверки metadata/fixture. Fetch/import и реальный
WORLDGEN adapter имеют отдельные gates в roadmap. Не выдавать их за выполненные.
Удаление WORLD PACKS не должно ломать canonical simulation или блокировать P7/V0.
