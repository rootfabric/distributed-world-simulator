# ECO.EVO4/E4.B0 — Bridge demo pipe: первый прогон

Статус: `RESEARCH_ONLY / DEMO_EVIDENCE / NO_ACCEPTANCE_CLAIM`.
Дата: 2026-08-22. Движок: `Godot 4.7.1.stable.double.custom_build.a13da4feb`, OpenGL, RTX 4060.

## Что выполнено

Авторизованная демо-труба «принятый вид каталога → developmental v0 → GrowthGraph → PH5-рендер»:

1. `scripts/research/ecology/evo4_bridge_derivation_v0.py` прочитал принятый каталог `evo2_full_persisted_species_catalog.e3_4.v1.json` (bake `eco-evo2-bake/ff406486cc83bb8217d66213`), вывел DevelopmentTraits v0 из metabolic-полей, чек-суммы совместимы бит-в-бит с `plant_development_traits_v1.compute_checksum`.
2. Артефакт входа: `validation/ecology/evo4_b0_bridge_input.v1.json`, sha256 `1a50be86a93f38b90e5152fe4ef94b05a39220776de49df17beab76e3a23ce38`.
3. Лаба `scenes/labs/ecology/eco_evo4_b0_bridge_demo_lab.tscn` собрала GrowthGraph через принятый PH1-продюсер, описания через принятый PH5-builder, материализовала профилем `BRANCH_LEAF_INSTANCED` принятым `plant_3d_materializer_v1.gd`.

## Результаты прогона

```
ECO.EVO4/E4.B0 BRIDGE DEMO: PASS (2 subjects)
genome/e22-beta       graph_hash=648538d347d688664340c2ee50167532b2ef530bbcd7b76549ec9d9b5e4e1769 geometry_hash=050d72400256b355de5c7501713e6ca3a7ae86dcbdeaf6a3e8beab50a6dad203 branches=13 foliage=11 h=3.20m r=0.53m
genome/e22-alpha-late graph_hash=c5ac719599475d46ed184218bcff60cdc26ac351ea3a50302d6606c3706cb281 geometry_hash=ac34dc402f0d9df056d293ebf8b052de27905019f2ce8f59312f58ac02482efa branches=16 foliage=15 h=6.00m r=0.94m
```

- Гейт детерминизма: каждый субъект строился дважды независимо в одном прогоне — hash совпал.
- Скриншот: `artifacts/evo4_b0_bridge_demo.png` (1280x719, 282369 байт; вне Git по правилу artifacts/). Программная верификация пикселей: цвета ветвей `(51,42,32)` соответствуют материалу albedo `(0.36,0.23,0.12)` при освещении сцены; листва и стволы присутствуют в двух ожидаемых позициях кадра.
- Один генератор, разные геномы: beta (низкий, раскидистый, apical 0.30) vs alpha-late (высокий, узкий, apical 0.60) — без классов TREE/BUSH/GRASS.

## Замечания

- Godot `JSON.parse_string` возвращает float для всех чисел; лаба коэрцирует `branching_depth` к int перед валидацией PH0 (требование TYPE_INT).
- MCP-хост в этой сессии недоступен; захват выполнен собственным механизмом сцены (viewport → artifacts/) через канонический double-Godot CLI запуск. Управляемый MCP-прогон остаётся доступным для последующих гейтов.
- Шаги E4.B1–B7 остаются PROPOSED; настоящая демо-труба не создаёт accepted-поверхностей и population truth.
