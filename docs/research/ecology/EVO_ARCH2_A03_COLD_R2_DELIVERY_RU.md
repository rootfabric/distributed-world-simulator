# EVO ARCH2 A0–A3 — cold-checkout R2 и идентичность поставки

Дополнение к `EVO_ARCH2_A03_PUBLICATION_STATUS_RU.md`. Это metadata/evidence запись, **не публикация A2/A3 runtime и не ACCEPTED**.

## Что дополнительно найдено и исправлено локально

После успешного warm-cache R1 новый чистый checkout показал Parse Error: Expected '[' в трёх старых сценах. Каждая содержала начальный UTF-8 BOM EF BB BF; исходные байты совпали с immutable VIS5 baseline.

Bounded repair `EVO-ARCH2-A03-REPAIR-COLD-IMPORT-R2` удаляет только три начальных байта в:
- `scenes/labs/ecology/eco_evo5_probe2_tree_lab.tscn`
- `scenes/labs/ecology/eco_evo5_t51_creature_lab.tscn`
- `scenes/labs/ecology/eco_evo5_terrain_fly_lab.tscn`

Остальное содержимое сцен побайтно неизменно. Старые GDScript kernels не изменены. Проверка ERROR в runner не ослаблена; failed cold R1 сохранён отдельно. Эти три исправления, как и A2/A3, пока находятся только в локальной поставке.

## Окончательная проверка

Полный runner повторён в новом checkout с пустым `.godot`:
`run_20260905T235322Z` → PASS, RC=0.

Godot `4.7.1.stable.double.custom_build.a13da4feb`, binary SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

- 749 contracts/development assertions PASS; два fresh-process reports совпали.
- 31 graphical Lab assertion PASS, настоящий OpenGL/Xvfb/llvmpipe.
- 18 JSON Schema documents PASS.
- 1000 родителей, 2000 потомков, 1000 neutral controls; 0 corrupted states.
- Fresh-process replay первых 250 родителей совпал.
- Неизменённые VIS5 gates: 87/70/57/101/92/114 PASS = 521.
- Все четыре полных mutation reports и оба contract reports R1/R2 совпали побайтно.

Summary SHA-256: `9bcbe76f0e8f74f67cfa189cbe9e10a30f04e68c68f462771a46ac3592ec26d3`.

Local-only tested source HEAD `519b8adf926d56cd6313ecced0645a233f3ea37b`, TREE `4eed3333c522a12070a2d6600f5bad8da68ab90d`. Это локальная история материализации исходников, **не доступный remote commit**. Итоговый local documentation/evidence HEAD `6201d405e047005e7e0f96dac56160ee52f25679` не меняет проверенный runtime.

## Переданный patch

Имя: `EVO_ARCH2_A0_A3_R2_patch.zip`.
Размер: 2040176 bytes; файлов: 147.
SHA-256: `5c24dd09831fc15d86b3dd95d221cdf4ee802ceb6190b5a4901fdf6d2e469392`.

Архив передан пользователю как downloadable attachment в сессии работы; он **не загружен как GitHub artifact/release asset**. В нём только новые/изменённые scoped файлы, исходные пути, 24 проверенных source files, UIDs только новых scripts, raw evidence, screenshots, полный исходный отчёт аудита и README. Godot binary, `.git`, `.godot` и неизменённые kernels не включены.

Основная инструкция: `docs/research/ecology/EVO_ARCH2_A03_IMPLEMENTATION_RU.md`.
Source/evidence manifest: `validation/ecology/evo_arch2_a03/delivery_manifest.json`.
Final evidence: `validation/ecology/evo_arch2_a03/final_r2/summary.json`.

Patch рассчитан на published A0/A1 branch на `189397902eb2033bee8c43a9d5175da05461df7f` или его metadata-only продолжении. Дополнительная проверка lower-hex attachment hash в A1 также входит в patch, но не в remote A1.

## Чего результат не означает

Cold checkout выполнен тем же implementer, а не независимым verifier. Windows, global PC0 и full world/core acceptance не объявлены пройденными. Шесть форм — authored programs, не естественно возникшие виды. V2 ещё не подменяет LS3/PH5 production consumers. A4 environmental fields, A5 survival/paid reproduction и distributed binding остаются последующими этапами.

Внешний platform write block для A2/A3 не обойдён. Draft PR #563 по-прежнему частичный. Следующий gate: штатное разрешение блока публикации → полный source/evidence в ветке → независимые exact-head review/verifier → только затем принятие A0–A3 и переход к A4. Main/ownership не изменялись.
