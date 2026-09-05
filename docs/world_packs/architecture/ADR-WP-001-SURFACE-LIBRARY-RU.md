# ADR-WP-001 — Surface library, immutable assets and presentation recipes

Дата: 2026-09-05. Статус: **PROPOSED / BRANCH CONTRACT CANDIDATE**.
Область: WORLD PACKS, docs + metadata tooling; independent review pending.
Не меняет main-owned harness, canonical Matter, WORLDGEN activation или runtime.

## 1. Design brief

**Проблема.** WP0 правильно запрещает вторую физическую истину, но фактическая
единица повторного использования — Godot profile для плоской gallery pad. Это
недостаточно для объёмных изменяемых миров, произвольных frames и внешней библиотеки.
JSON V1 требует props/decals/POI даже для голого астероида; физические material ID,
поколения assets, неизменяемые locks и storage abstraction в нём не выражены.

**Желаемый результат.** Data library, из которой один WORLDGEN/presentation pipeline
собирает разные поверхности. Новые миры в основном добавляют данные, а не уникальный
renderer или копию тяжёлых файлов. Богатая библиотека не становится вторым world owner.

**Альтернативы.** (A) Продолжать WP0.11 новыми биомами — отклонено как основной путь:
не закрывает asset identity и реальные поверхности. (B) Переписать WP0 — отклонено:
теряется validated content без необходимости. (C) Отдельный слой ниже gallery,
неразрушающий legacy V1 — выбран. (D) Сразу строить CDN/asset server — отложено:
Git descriptors + locations + будущий локальный cache пока достаточны.

**Риск.** MEDIUM для нового data contract, LOW для воздействия на runtime: никаких
production callers, загрузки сети, распаковки или изменения Godot-кода в этом патче.
Главная опасность — принять metadata fixture за завершённую систему; статусы и gates
явно отделены. Большой renderer/worldgen rewrite исключён.

## 2. Основание в живом DWS

Проверенные источники зафиксированы по commit, а не по старым названиям веток:

| Источник | Что действительно задаёт |
|---|---|
| `main@5b4152958624be4e9cc40f2369ce32c4964f65c3`, `docs/plans/WORLDGEN1_PROCEDURAL_MATTER_TERRAIN_ROADMAP_RU.md` | WORLDGEN = procedural revision-0 Matter; mesh производный; WG1 design-only до activation gate |
| Тот же main, `scripts/simulation/matter/generation/moon_geology_sampler.gd` | SDF `length(body_fixed_position)-radius`; feature catalog пока не влияет на эту функцию; реальные физические слои |
| Тот же main, `scripts/simulation/matter/catalog/matter_material_catalog.gd` | `matter-catalog/core-v1@1.0.0`, физические свойства, материал и catalog hash |
| Тот же main, `docs/plans/V0_P7_MATTER_PRODUCTION_CONVERGENCE_RU.md` | MW4–MW10, RL2/RL3, Item Graph и единственные владельцы изменений |
| Тот же main, `docs/architecture/DYNAMIC_MATTER_FABRIC_RU.md` | body-fixed frames, sparse bricks, малые тела и планеты; legacy radial terrain не универсальное вещество |
| `ECO VIS5@a73cccb8064fdfb4df266338d3d20e24ac9f082b`, `scripts/labs/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter.gd` | radial gravity basis отдельно от terrain normal; адаптер всё ещё ограничен наружной радиальной поверхностью |
| `WORLD FILL@002fde20b04e4f8379cdd053ba9b609dfe3b38ef`, `docs/world_fill/README.md` | removable consumer-only dressing; не новый canonical owner |

Нынешние Matter ID: `matter/regolith-loose`, `matter/regolith-compacted`,
`matter/basalt`, `matter/fractured-basalt`, `matter/water-ice`,
`matter/iron-nickel-ore`, `matter/silicate-waste`. Пример `dws.material.basalt`
не является ID текущего каталога и не вводится вместо него.

Moon sampler имеет default границы 2 / 8 / 28 m, а не гипотетические 20 cm / 1 m.
Эти числа принадлежат physical generation profile и НЕ копируются в pack.
Численные свойства текущего Matter каталога не объявляются измеренной геологической истиной.

Legacy `procedural_moon_terrain.gd` сохраняет дальние radial representations;
его camera-local microrelief нельзя превращать в persistent canonical geology.
P7 использует bounded Matter bubble, не полную высокодетальную вокселизацию планеты.
Старые README/checkpoint заголовки не заменяют актуальный main program registry.

## 3. Матрица владельцев

| Concern | Owner | WORLD PACKS может |
|---|---|---|
| Body shape, SDF/topology, caves, strata, revision 0 | WORLDGEN → Matter sampler/materializer | ссылаться на согласованные semantics, не писать плотность/глубину слоя |
| Material identity/composition, mass, strength, mining yield | Matter material catalog + canonical simulation | выбирать presentation для существующего `matter/...` |
| Digging, cross-region mutation, revisions | MW4 / MW10 | читать результат и новые surface descriptors |
| Persistence / replication / handoff | MW5–MW9, существующие DWS owners | использовать immutable recipe reference через будущий adapter; не новый store/wire owner |
| Meshing, invalidation, near/far representation | RL2 / RL3 и presentation consumers | поставлять material bindings и варианты assets |
| Ecology, organisms, growth/morphology | ECO | предоставлять optional визуальные ресурсы, не создавать/удалять canonical life |
| Local scatter, props, scars, POI, feedback | WORLD FILL | выбирать catalogs и параметры уже существующих механизмов |
| Buildings/ships/physical props | Construction / Item Graph / FABRIC | reference к принятому blueprint/presentation; не скрыто создавать collider или inventory |
| Weather/atmosphere/gameplay environment | соответствующая canonical подсистема | cosmetic rendering hints, не физический климат |
| GPU materials, LOD, mip/streaming | renderer / asset preparation | declarative recipes, capability alternatives и budgets |

Итак, pack хранит рецепты, IDs, версии, provenance и presentation parameters;
выбирает ссылки на surface/asset/environment; параметризует отображение и dressing;
не владеет генератором, плотностью, глубиной strata, коллизией или живой экологией.

## 4. Сущности и поток данных

**Asset** — логический ресурс конкретной версии с неизменяемыми bytes/hash и
доказуемым происхождением. Это может быть отдельная карта или архив texture set;
версия source upstream не равна версии DWS asset. Идентичный blob переиспользуется.

**Surface family** — семантическое семейство отображения, например basalt или regolith.
Это не второй Matter material: связь many-to-many явно перечислена через canonical IDs.
Fractured basalt может использовать родственную визуальную семью, не теряя своего
отдельного физического материала. Похожий тёмный грунт не доказывает carbonaceous geology.

**Environment profile** — набор presentation hints/ссылок, применимый к уже известной
среде. `airless` не удаляет атмосферу из simulation. Наличие wetland не включает ECO
и не создаёт воду. Пустые atmosphere/audio/fill варианты допустимы.

**Presentation recipe** — композиция точных surface bindings, environment и optional
ECO/FILL consumer recipes. **Pack** — именованная поставка recipes и их dependency closure,
а не гигантская сцена. Для сегодняшнего прототипа дополнительный pack-wrapper не нужен.

**World generation recipe** принадлежит WORLDGEN: generator ID/version/seed, physical
profiles, feature/material catalogs. Удобное внешнее задание `generate world` в будущем
пинит generation recipe и presentation recipe отдельно. Подмена texture pack никогда
не меняет generation identity. WORLD PACKS не присваивает себе весь orchestration.

```text
WORLDGEN-owned identity + profiles        canonical Matter + persisted mutations
                    \                    /
                     semantic surface adapter (read-only)
                      | material composition + revision
                      | body-fixed point/frame + normal + exposure
                      v
Git recipe/family catalog --> WORLD PACK resolver --> presentation bindings
                                  |                 /       |        \
                                  |            renderer   ECO view  WORLD FILL
                                  v
                     exact asset closure / prepare plan
                                  |
           relocatable sources --> verified raw cache --> pinned import
                                                        --> local runtime bundle
```

Server не загружает 4K textures и не запускает importer. Серверу достаточно принятых
semantic IDs/recipe references; rendering fidelity и codec/platform variants локальны
клиенту. Одинаковость simulation не зависит от наличия GPU или пакета декораций.

## 5. Mutable surfaces: не рисовать собственную геологию

WORLDGEN генерирует revision 0 напрямую, а не миллионы фиктивных dig operations.
MW4/MW10 изменяет те же bricks, выдаёт canonical material yield, создаёт revisions.
RL invalidation обновляет представление. После раскопки resolver получает фактический
material composition/state новой грани: top/subsurface/deep — это роли относительно
канонической геологии, а не pack-owned depth thresholds.

Surface descriptor должен позволять default/fresh/weathered/fracture presentations.
Если причинная система не даёт exposure age, pack не должен выдумывать canonical age:
используется обозначенный presentation fallback. Material blends используют реальные
composition weights; cliff/cave exposure не закрашивается всегда top-surface texture.

Будущий cache key включает source revision/representation identity и presentation lock,
чтобы после mutation не оставалась старая текстура на новой стенке. Pack не внедряет
собственный mutation journal. Decorative displacement ограничен visual envelope:
он не создаёт tunnel, collision, добываемую массу или blocking rock.

## 6. Координаты и пространственные масштабы

| Масштаб | Данные recipe / consumer |
|---|---|
| Orbital / planetary | крупные color/albedo provinces и macro masks, far representation |
| Regional | геологические/macro variation masks, coherent surface transitions |
| Terrain | tileable layered PBR, material weights, triplanar/tangent mapping |
| Local | exposed strata, rocks/scatter/decals, bounded detail |
| Micro | detail normal, roughness, bounded height/parallax/displacement |

Одна 4K texture не является planetary material solution. Все полосы имеют отдельные
physical scale, coverage и budget; точные единицы/UV channel/normal convention/color space
и displacement envelope фиксируются в WP1.2 import contract и WP2 renderer adapter.
В WP1.0 перечисляются scale roles, но shader/mip/VT реализация НЕ заявляется.

Mapping привязан к body-fixed coordinates либо стабильному локальному surface frame,
а не к Godot floating origin. GPU может потребовать cell origin + local offset или
high/low split: double CPU не превращает shader float в double. Normal и gravity direction
раздельны; для пещеры normal может смотреть против radial-up, при zero-g gravity отсутствует.

ECO VIS5.1 полезен как пример разделения basis, но его `normal.dot(radial_up)>0` и
`slope<=90` непригодны как универсальный контракт для overhang/interior. Нельзя заменить
один global Y-up другим неявным допущением о единственной поверхности на радиусе.

RVT/virtual texture/clipmap идеи могут быть кешем renderer, но не canonical Matter.
LOD/mip смена не переставляет semantic features, не меняет физику и не стирает mutation.
Детерминизм selection/lock отдельно от GPU byte/pixel equivalence.

## 7. Композиция вместо неявного inheritance

WP0 class inheritance полезно для gallery utilities, но это не data inheritance.
WP1.0 использует точные `recipe/...@1.0.0` includes как DAG множеств.
Порядок файлов, includes, JSON keys и catalog entries не определяет результат.
Одинаковое binding через diamond дедуплицируется. Два разных surface bindings для
одного canonical material, два разных environment profiles либо цикл — ошибка.
Не вводятся last-wins, неявные overrides или mutable aliases.

Последовательное blending слоёв в будущем требует отдельного явно ordered operation
contract. Нельзя сортировать произвольный shader graph алгоритмом set-json-v1.
Overrides можно добавить только как отдельные проверяемые operations с явной целью;
текущий прототип намеренно fail-closed вместо угадывания приоритета.

WP0 сохраняет свои исторические IDs/R1. Миграция идёт через явный adapter mapping:
legacy exemplar → environment/presentation recipe. Не интерпретировать автоматически
`basalt_slab` как `matter/basalt`; manufactured plate и природная порода различны.

## 8. Immutable identity, storage и сохранённые миры

Разделены schema version, logical entity version, upstream source version,
import recipe/toolchain version и client prepared-bundle version.
Ссылка для сохранённого recipe — exact `id@semver`, не URL и не `latest`.
Asset descriptor содержит SHA-256 и expected byte count. Sources — отдельный документ,
привязанный к exact asset/hash. Замена mirror/CDN/object storage не меняет descriptor
hash и presentation lock. Исчезновение источника не разрешает скачать другие bytes.

WP1.0 lock хеширует transitive descriptor closure, включая версии, права, import refs
и все объявленные fidelity variants. Locator URLs исключены. Lock не имеет timestamp,
absolute local path, HTTP ordering или server process ID. Resolver identity pinned.
`wp-set-json-v1`: JSON keys lexicographic, ASCII JSON escaping, compact separators,
целые числа в portable range, schema arrays имеют set semantics и сортируются по
canonical bytes. Duplicate keys/NaN/Infinity запрещены. Это собственный узкий формат,
не заявление о реализации RFC 8785 и не произвольная JSON canonicalization.

Физическое сохранение продолжает пинить generator/profile/feature/material hashes и
canonical mutations. Связанный presentation lock сохраняется отдельным metadata
контрактом через существующего persistence owner после review WP2; этот патч не
добавляет wire fields. Старый мир не принимает новую библиотеку автоматически.
Обновление presentation требует explicit migration с записью old/new locks и oracle
неизменности physical hash. Replays могут запросить старое отображение; исчезнувшие
bytes дают диагностируемую недоступность или заранее разрешённый exact fallback.

Content hash не доказывает лицензию, безопасность или доступность. Git/release manifest
является доверенным корнем; будущие registry attestations могут расширить его.
Отзыв/уточнение прав блокирует новые поставки, но не подменяет молча сохранённую физику.

## 9. Fidelity без форка мира

Одна surface family содержит casual / standard / high_fidelity variants.
Требования к capability и ordered fallback policy будут закреплены renderer consumer
contract; WP1.0 только валидирует labels и asset refs, не выбирает GPU variant.
Semantic material/family, seeded variation и canonical objects не меняются.

Высокая texture resolution сама по себе не означает measured appearance. Нужны
reference provenance, масштаб, lighting/albedo calibration, units, normal convention,
known limitations. Неизмеренный basalt-like artistic материал не переименовывается
в physically measured basalt. Cheap clients могут уменьшать detail, но не менять
collision, yield, authoritative plants или скрывать нужные gameplay objects.

Variation использует domain-separated hash от seed + body + стабильного spatial key +
surface reference + channel. Fidelity, camera origin, region owner и filesystem order
в этот ключ не входят. Сам алгоритм seed/RNG WORLDGEN остаётся его ответственностью.

## 10. Внешние assets и воспроизводимая подготовка

Целевой pipeline (fetch/import ещё НЕ реализованы):

```text
resolve immutable recipe --> license/entitlement gate --> fetch bounded bytes
--> verify size + SHA-256 --> publish immutable raw cache atomically
--> safe extraction --> allowlisted, versioned import recipe
--> engine/platform-specific prepared bundle --> runtime without network
```

Raw cache content-addressed, например `sha256/52/529c...`, вне Git. Offline reuse
перепроверяет provenance/lock/hash; corrupt/partial files не становятся cache hit.
Concurrent prepare использует locks/atomic rename, disk quotas и eviction, сохраняющую
pinned releases. Ошибки missing asset/source/license/hash/size/importer раздельны.

Prepared cache key: raw hashes + import recipe/settings + exact Godot binary hash,
precision + importer/plugin versions + target platform/renderer + compression settings.
Godot `.godot/imported` — временный cache, не первичный asset store. Готовый export/PCK
или локальный resource bundle готовится из доверенного staging project; не абсолютные
пути из машины автора. Same toolchain/target должен давать одинаковый prepared artifact;
между GPU/платформами проверяется контрактная visual equivalence, не ложный byte oracle.

Fetcher обязан ограничивать protocols, public DNS/IP и каждый redirect, credentials,
timeouts, response size, retries и destinations; один syntax check URL не защита от SSRF.
Archive extractor обязан отвергать `..`, absolute/drive/UNC paths, backslashes,
symlinks/hardlinks/devices, case collisions, zip bombs и превышение count/unpacked-size.
Нельзя запускать script из import manifest, `@tool`, autoload или исполняемый asset.
Nested glTF/image URIs тоже проверяются. Эти security tests обязательны в WP1.1/1.2,
но не выдаются за выполненные: WP1.0 ничего не скачивает и не распаковывает.

## 11. Provenance, Git и масштаб библиотеки

Git: descriptors, schemas, recipes, hash locks, license records, provenance URLs,
upstream version, expected bytes, import recipes, небольшие разрешённые previews и
ограниченные fixtures. НЕ Git: 4K/8K оригиналы, scans, audio archives, imported caches.
До допуска asset нужны license expression/text or reviewed reference, author,
attribution obligations, rights to redistribute raw data, commercial compatibility,
source record и реальный checksum. `unknown` и запрещённые права fail-closed.

Commercial-compatible не означает redistributable. Reference-only/download-by-user
каталоги отделены от базовой redistributable library; WP1.0 их намеренно не разрешает
в lockable baseline. Поддержка будущей entitlement policy не требует менять logical ID.
CC0 asset и условия доступа к API/preview — отдельные вещи; подробности в research.

Структура роста: `assets/<namespace>/<family>/<id>/<version>.json`,
`surfaces/<family>/<version>.json`, `environments/...`, `recipes/...`, отдельные
`locations/` и immutable `locks/`. Сейчас небольшой catalog bundle использует те же IDs;
будущая sharding/index сборка должна дать тот же lock независимо от расположения файла.
Поиск по tags/taxonomy — не identity resolution. Global duplicate-ID gate обязателен.
Deprecation не удаляет сохранённые версии; aliases только для discovery.

10,000 assets — будущий проверяемый scale gate, не обещание текущего прототипа.
Текущий draft ограничивает recipes до 128, не содержит БД, server или CDN.
DWS Asset Store позже возвращает locations по `id/version/hash`; recipes не меняются.

## 12. Как сделать новую поверхность Марса

1. Выбрать/создать surface assets; отделить artistic look от подтверждённой геологии.
2. Проверить лицензию и provenance; вычислить bytes/hash на реальном файле.
3. Зарегистрировать exact asset и independently replaceable locations.
4. Собрать surface families/variants; сослаться на существующие canonical materials.
5. Составить presentation recipe из общих компонентов; проверить conflicts и locks.
6. Выполнить prepare/cache/import с pinned recipe, затем offline sample.
7. Передать WORLDGEN-owned world identity и WP presentation recipe через adapter.
8. Проверить разные масштабы, mutation/exposure, fallback и invariants.

Новый physical материал или генераторный оператор требует изменения у соответствующего
owner, а не обхода через pack. Поверхность Марса не требует Mars-specific renderer;
уникальная геология может потребовать новый общий WORLDGEN operator, что честно отделено
от content-only задачи. Никакая библиотека не заменяет ещё не реализованную геометрию.

## 13. Граница этого коммита и следующий gate

Добавлены draft schema, один diagnostic asset, две surface families, environment,
base + composed recipe, source sidecar, metadata resolver/validator и тесты.
Нет production Matter consumer, реального asset fetch/import/cache, GPU material,
вариантного renderer selection или E2E A–E. Сохранены все WP0 runtime files.

Перед merge в WORLD PACKS — independent review diff/test evidence. Перед WORLDGEN
исполнением — повторная live проверка P7/WG activation и scheduler. Перед main promotion —
канонический harness и human merge gate. Этот ADR не самопровозглашает FOUNDATION DONE.
