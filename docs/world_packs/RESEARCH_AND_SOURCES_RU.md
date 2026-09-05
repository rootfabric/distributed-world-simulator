# WORLD PACKS — external research and source candidates

Проверено: 2026-09-05. Ни один тяжёлый asset не скачан и не добавлен в Git.
Ни один внешний кандидат ниже не объявлен immutable/approved: byte SHA-256 и точный
размер должны вычисляться при onboarding выбранного файла. Rounded MB на сайте не lock.

## 1. Применимые архитектурные паттерны

| Подход / первичный источник | Полезная идея | Применение и ограничение DWS |
|---|---|---|
| [UE Material Layers](https://dev.epicgames.com/documentation/unreal-engine/using-material-layers-in-unreal-engine) | переиспользуемые слои и parameterized instances | surface families/variants; не второй physical material catalog |
| [UE PCG overview](https://dev.epicgames.com/documentation/unreal-engine/procedural-content-generation-overview) | spatial inputs, фильтрация, population graphs | recipe выбирает контент, WORLD FILL выполняет dressing; не перенос UE authority model |
| [UE Virtual Texturing](https://dev.epicgames.com/documentation/unreal-engine/virtual-texturing-in-unreal-engine) | SVT для disk-backed tiles, RVT для производного shading cache | будущая renderer оптимизация; не canonical state и не решение всех 3D cave seams |
| [Unity Terrain Layers](https://docs.unity3d.com/6000.0/Documentation/Manual/class-TerrainLayer.html) | один material layer переиспользуется на terrain tiles | полезная композиция; heightfield не выражает объёмную геологию DWS |
| [Unity Addressables remote content](https://docs.unity3d.com/Packages/com.unity.addressables@2.7/manual/RemoteContentDistribution.html) | catalog, content versions, cache и pre-download | подготовка отделена от gameplay; auto-update сохранённого мира не переносится |
| [Houdini terrain texture layers](https://www.sidefx.com/docs/houdini/heightfields/texturelayers.html) | masks erosion/flow/debris управляют слоями | WORLDGEN-derived masks, не texture-driven physics; 2D heightfield не универсальный Matter |
| [Substance exposed parameters](https://helpx.adobe.com/my_ms/substance-3d-designer/using/exposing-parameters.html) | параметризуемый reusable material graph | import/bake recipe, не обязательная proprietary runtime зависимость |
| [Godot StandardMaterial3D](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html) | triplanar/local/world coordinates и detail maps | удобный consumer; body-fixed mapping/floating-origin стабильность надо доказать отдельно |
| [Godot large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html) | double CPU и GPU precision различаются | cell-local/high-low coordinate strategy; double build не гарантирует стабильность любой shader texture |
| [No Man's Sky: Continuous World Generation, GDC 2017](https://www.gdcvault.com/play/1024265/Continuous_World_Generation_in__No_Man_s_Sky_) | отдельные stages voxel generation/polygonization/texturing/population | аналог разделённых owners; изучено описание доклада, не заявляется просмотр закрытого полного видео |
| [Star Citizen Alpha 3.11 postmortem](https://robertsspaceindustries.com/en/comm-link/transmission/17887-Alpha-311-Postmortem) | planet tools, объединение ground/object presets, стоимость streaming | reusable recipes + bounded budgets; не копирование engine/network semantics |
| [Star Citizen environment-art AMA](https://robertsspaceindustries.com/en/comm-link/transmission/17735-Environment-Art-AMA-Recap) | nondestructive procedural biome authoring | параметры и reusable presets вместо ручной копии каждой планеты |
| [Space Engineers features](https://www.spaceengineersgame.com/features/) | destructible persistent volumetric worlds | обязательность cave/exposure proof, но не источник готового distributed protocol DWS |
| [Space Engineers 2 voxel/flora technical discussion](https://2.spaceengineersgame.com/space-engineers-2-voxel-density-vs2-flora/) | совместное обсуждение voxel terrain и vegetation | подтверждает важность integration budget; physical hardness остаётся у Matter |

Вывод: общий переносимый паттерн — semantic world data → reusable material/content
recipes → prepared assets → bounded renderer. Не переносим плоский Landscape как
каноническую геологию, онлайн-загрузку во время gameplay или vendor-specific asset ID
как identity сохранённого мира. Planet rendering не сводится к размеру texture.

## 2. Лицензии, сервисные условия и долговечность

[Poly Haven license](https://polyhaven.com/license): assets CC0, включая commercial
use и redistribution, без обязательной asset attribution. Но сайт отдельно защищает
example renders, logos и прочий website content: thumbnail нельзя автоматически
считать CC0 только потому, что сам texture CC0.

[Poly Haven API](https://polyhaven.com/our-api): объявление 18 July 2026 снимает старое
предположение о платном commercial API. Сейчас API бесплатен и для commercial use,
но live integration требует понятной атрибуции Poly Haven и уникального User-Agent.
Это условия сервиса, не изменение CC0 самих assets. Проверять также
[API ToS](https://github.com/Poly-Haven/Public-API/blob/master/ToS.md).
API выдаёт links/sizes/hashes, но DWS всё равно фиксирует собственный SHA-256 bytes;
upstream files_hash/MD5 не переименовывается в SHA-256. API не обещает неизменность URL.

[ambientCG license](https://docs.ambientcg.com/license/): CC0 распространяется на
скачиваемые assets и material preview renders; commercial use/redistribution разрешены,
attribution необязательна. [API documentation](https://docs.ambientcg.com/api/) явно
предупреждает, что небольшой сервис не гарантирует enterprise-level стабильность.
Поэтому mirror/cache необходимы, даже когда исходная лицензия очень удобна.

[Fab Standard License summary](https://www.fab.com/eula): коммерческое использование
в проекте допускается, но standalone redistribution исходного asset запрещено;
Reference-Only — отдельный режим доступа. Это не источник безусловно раздаваемых
raw assets для DWS CDN. Для каждого приобретения проверять полный binding license,
entitlement и допустимость передачи соавторам/пользователям; summary не юридическое
заключение. Quixel/Fab label сам по себе не определяет права конкретного файла.

Базовая библиотека — reviewed redistributable assets. Download-by-user/reference-only
источники могут позже иметь отдельную policy/entitlement lane, не обход baseline gate.
Unknown provenance → reject, а не warning. Tiny previews — тоже лицензируемые данные.

## 3. Реальные кандидаты, без вымышленных hashes

| Кандидат | Наблюдаемые свойства | Coverage / ограничения | Onboarding |
|---|---|---|---|
| [Poly Haven Gravelly Sand](https://polyhaven.com/a/gravelly_sand) | 1K–16K; diffuse, AO, normal GL/DX, roughness, displacement, ARM; Dario Barresi; 2.5 m width | sand/gravel/soil; возможный artistic regolith analogue, не lunar sample | выбрать 1K/2K, зафиксировать maps/colorspace/scale/реальные bytes/hash |
| [Poly Haven Rock Face](https://polyhaven.com/a/rock_face) | 1K–16K; полный перечисленный PBR set; Dario Barresi / Greg Zaal; 2.4 m width | cliffs/rock; reddish weathered surface, не подтверждённый basalt | проверить tiling/seams и derived color variants, без заявления measured basalt |
| [Poly Haven Rock Face 03](https://polyhaven.com/a/rock_face_03) | до 16K, rock/cliff PBR candidate | дополнительная rock variation, не свидетельство mineral composition | сверить выбранный release/file list при onboarding |
| [ambientCG Ground037](https://ambientcg.com/view?id=Ground037) | 1K–8K JPG/PNG PBR archives; surface photogrammetry, около 2.1×2.1 m | влажный forest ground/moss; terrestrial soil, не airless regolith | список каналов/normal convention проверять в выбранном archive; сайт сообщает reprocessed color map 2021-01-24 |
| [ambientCG Ice001](https://ambientcg.com/view?id=Ice001) | procedural PBR archives 1K–4K, JPG/PNG | water-ice look; не доказанная оптика planetary ice | проверить maps и transmission/opacity отдельно; не менять `matter/water-ice` |
| [ambientCG Snow001](https://ambientcg.com/view?id=Snow001) | procedural PBR archives 1K–8K, JPG/PNG | snow surface layer/look; не pack-owned snowfall/physical depth | только chosen small variant; точные channels/hash после подготовки |

Для Poly Haven кандидатов действуют CC0 asset rights и отдельные API/preview условия;
для ambientCG — CC0 assets/previews. Отдельный source descriptor должен хранить author
из выбранной authoritative записи: при отсутствии имени нельзя придумывать автора.

**Basalt / metal-rich / organic-rich asteroid material gap:** просмотренные generic
rock assets не доказывают mineral composition или measured planetary reflectance.
Допустимы честно названные artistic alternatives, либо отдельный research/onboarding
эталонных samples. Не зарегистрированы фиктивные basalt/ore measured assets.
Ice/Snow PBR completeness здесь означает заявленный PBR archive, а не уже распакованный
и проверенный полный набор всех shader inputs. Asset quality ещё требует визуального review.

Все эти ссылки — discovery/provenance candidates, НЕ runtime locators и не разрешённый
автодownload список. Срок доступности не гарантирован ни для одного upstream.
