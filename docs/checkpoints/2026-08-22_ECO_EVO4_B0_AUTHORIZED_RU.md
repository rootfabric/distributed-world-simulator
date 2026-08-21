# ECO.EVO4/E4.B0 — AUTHORIZED (Director dispatch)

Статус: `RESEARCH_ONLY / E4_B0_AUTHORIZED`.
Основание: Director merge-авторизация PR #190 (merge commit `5b44068d`) + явный dispatch в сессии. Шаги E4.B1–E4.B7 остаются PROPOSED.

## Авторизованный объём E4.B0 (и только его)

Демо-труба моста на ОДНОЙ записи принятого persisted SpeciesCatalog (`genome/e22-beta`, каталог `evo2_full_persisted_species_catalog.e3_4.v1.json`):

1. Детерминированная деривация developmental-параметров v0 из metabolic-полей генома (правило честности B1-v0: новая поверхности отбора не создаётся).
2. Построение GrowthGraph skeleton (PH1-паттерн: deterministic, без классов TREE/BUSH/GRASS).
3. Рендер принятой PH5-машинерией (`plant_render_description_v1.gd` → `plant_renderer_profile_v1.gd` → `plant_3d_materializer_v1.gd`), профиль `BRANCH_TUBES`/`BRANCH_LEAF_INSTANCED`.
4. Скриншот-evidence по контракту `docs/MCP_GODOT.md`.

## Гейты шага

- Детерминизм: тот же вход → тот же graph hash (fresh-process).
- PH1 morph-tests применимы к деривации (sweep параметров → плавные переходы формы без классов растений).
- Никаких изменений принятых поверхностей E3.x/PH; новые файлы только в research-слое моста.
- Результат — derived presentation; ноль притязаний на population truth.

## Вне объёма

B1–B7, сезонные состояния (BLOCKED_WAIT_E36_R), product promotion, планетарная индивидуальная истина.
