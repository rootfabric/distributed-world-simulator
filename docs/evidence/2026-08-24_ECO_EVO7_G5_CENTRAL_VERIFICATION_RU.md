# Центральная верификация G5-захватов (Director-сессия, 2026-08-24)

Факты визуальной инспекции PNG центральной сессией через read_image (машина Ubuntu, worktrees/eco-evo7-fff-r1).

## Захват 1 (13:36, прерванная сессия первого G5-агента)
- Файл: artifacts/evo7_fff6_lab_cmode.png, 1600x900, 189797 байт, mean_luma=0.5754
- run.log: READY zones=6 plants=150 result_hash=52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436; PASS rendered=150 zones_ok=true onoff=true geom_pairs=4 gap_delta=0.5657 stability_pin_max=0.080 replay=true; SCREENSHOT err=0; exit 0
- Визуально: HUD полностью читаем — статистика 6 зон (h/cr/lai/root/pref/shade/transp/net/uniq=25/pin=0.00/clusters=25), «G5 GEOMETRY READOUT (C-mode readable)», «geometry-distinct pairs=4 (>=3 satisfies G5): RIPAR|DRY_S, MESIC|UNDER, DRY_S|UNDER, MESIC|UNDER», bound-pinning max 0.00 по зонам, HASH PANEL (seed=20260823, lab_result_hash=52995cf4bcd03578... — СОВПАДАЕТ с stdout), REPLAY vs previous R: MATCH
- НЕДОСТАТОЧНО для G5: 3D-вьюпорт без растений (равномерный фон) — камера не рамировала сцену

## Захваты 2 (14:26, run4, finisher a4e2bce1)
- artifacts/evo7_fff6_lab_cmode_wide.png, 1600x900, 367444 байт, mean_luma=0.5384 (run-лог), sha256 d63f50157c2a838922ec0b7dc50b4910e4ba51c38a78c583d16f1a8b895a6772
- artifacts/evo7_fff6_lab_cmode_close.png, 1600x900, 389914 байт, mean_luma=0.5333 (run-лог), sha256 dc1832ab768cce81ee3ca8ffb4f6b99120b3e3d998633af0e1e13210569d389c
- run4.log: те же READY/PASS строки, result_hash=52995cf4bcd03578... ИНВАРИАНТЕН; SCREENSHOT wide/close err=0; exit 0
- Визуально (wide): 6 платформ зон (цветные подложки-идентификаторы зон — презентационный слой лабы), серые силуэты растений на платформах, коричневые стержневые энкодеры корней, статичные тёмно-зелёные кроны (UNDER_CANOPY), HUD читаем, хеш-панель совпадает с stdout
- Визуально (close): крупный план соседних зон — серые силуэты растений различимы по форме/плотности, корневые стержни уходят под платформы, GeometryReadout и хеш-панель читаемы
- Вывод центральной сессии: пакет достаточен как machine-captured visual evidence для закрытия материала ограничения №1 FFF6; формальную переклассификацию строки G5 (PARTIAL→PROVEN) выполняет свежая независимая line-auditor роль, не реализатор

## ПРИМЕЧАНИЕ О ЦВЕТАХ
C-mode по определению лабы нейтрализует материалы МЕШЕЙ РАСТЕНИЙ (единый серый StandardMaterial3D); цветные подложки платформ и коричневые стержни — презентационные энкодеры лабы (EVO6-паттерн), не цветовое кодирование растений. Это соответствует формулировке гейта «различия видны геометрически при выключенном debug-color [растений]».

## ДОПОЛНЕНИЕ: верификация ФИНАЛЬНЫХ коммиченных артефактов (7e3c0ad7, run2 14:39)
- artifacts/evo7_fff6_lab_cmode_wide.png, 1600x900, 213867 байт, sha256 539d37ecff21f278856e6d25a9c49c79a3a6a497f2465c85b4ae4d24efcab51b, mean_luma=0.5702: вся сетка 3×2 в кадре — две canopy-зоны с зелёными кронами на высоких стволах (UNDER_CANOPY), серые силуэты растений на всех платформах, голубые FLOODED-платформы, оливковые MESIC/DRY_SAND; HUD читаем; HASH PANEL lab_result_hash=52995cf4bcd03578... совпадает с stdout; REPLAY MATCH
- artifacts/evo7_fff6_lab_cmode_close.png, 1600x900, 369312 байт, sha256 40d7c441148d92c1c25ff796b3c9581e1f2330c8ee1de2f9863ca36c09019097, mean_luma=0.5269: пара UNDER_CANOPY|CANOPY_GAP с высоты крон — серые силуэты растений с различимыми стеблями/кронами/ветвлением на обеих платформах, коричневые стволы статичной кроны, белые корневые стержни под платформами; HUD читаем; хеш-панель совпадает
- Вывод: финальный пакет (wide+close+run2.log) достаточен как machine-captured visual evidence; инвариантность result_hash подтверждена во всех прогонах (13:36, run2–run4)
