# ECO.EVO7 — G5 визуальное доказательство: C-режим лабы FFF6 со скриншотами (implementer-отчёт)

**Дата:** 2026-08-24
**Роль:** IMPLEMENTER (завершение прерванной G5 visual-evidence задачи; статусы остаются **CANDIDATE**)
**Worktree:** `/home/yurig/distributed-world-simulator/worktrees/eco-evo7-fff-r1`, ветка `feature/eco-evo7-fff-r1`
**Точный HEAD на момент работы:** `29c62c65` (pushed); в рабочем дереве — незакоммиченный блок C-режима + скриншота в `_autocap()` лабы, оставленный предыдущим агентом (сохранён и расширен).
**Godot:** `godot.linuxbsd.editor.double.x86_64` v4.7.1.stable.double.custom_build.a13da4feb, оконный прогон на живом рабочем столе (`DISPLAY=:0`, без `--headless`).

---

## 1. Что доказал прерванный прогон (факты, переиспользованы)

`artifacts/runtime/evo7-gui-cmode/run.log` (до изменений этого отчёта):

```text
ECO.EVO7-FFF6-VIS: READY zones=6 plants=150 result_hash=52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436
ECO.EVO7-FFF6-VIS: PASS rendered=150 zones_ok=true onoff=true geom_pairs=4 gap_delta=0.5657 stability_pin_max=0.080 replay=true result_hash=52995cf4bcd03578
ECO.EVO7-FFF6-VIS: SCREENSHOT size=1600x900 mean_luma=0.5754 err=0
```

`artifacts/evo7_fff6_lab_cmode.png` (1600x900, 189797 байт) был центрально проверен визуально: HUD полностью читаем (пер-зонная статистика, «G5 GEOMETRY READOUT (C-mode readable)», geometry-distinct pairs=4, HASH PANEL c `lab_result_hash=52995cf4bcd03578...`, REPLAY MATCH), **но 3D-вьюпорт пуст** — равномерный фон, ни растений, ни даже плит зон.

## 2. Что было недостаточно и почему

G5 требует, чтобы геометрия растений была **видна** нейтральным серым. Причина пустого вьюпорта: блок захвата ждал ровно один `process_frame` перед `RenderingServer.frame_post_draw` и чтением текстуры — на GL Compatibility-рендерере чтение кадра гонка́ло с фактическим рендером 3D-сцены (HUD рисуется каждый кадр, потому и был читаем). Прецедент `scripts/labs/ecology/eco_evo5_terrain_fly_lab.gd::_autocap()` (строки 366-378) перед захватом выдерживает сотни кадров — по той же причине.

## 3. Что изменено (только presentation, хэш-пути не тронуты)

Файл: `scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd`, блок в `_autocap()` после PASS-строки:

1. **C-режим** — как раньше, тем же путём, что обработчик KEY_C: `_neutral_materials = true` → `_apply_neutral_state()` → `_update_hud()`.
2. **Кадрирование из реальных координат зон** (не хардкод): границы по `_zone_origin(i)` всех 6 зон (сетка 3x2, центры x ∈ {-17, 0, +17}, z ∈ {-9.5, +9.5}); новый хелпер `_place_camera(position, target)` выводит `_yaw/_pitch` из пары позиция/цель и идёт через `_apply_look()` (состояние mouse-look остаётся консистентным).
3. **Широкий кадр** `artifacts/evo7_fff6_lab_cmode_wide.png`: камера `grid_center + (span.x*0.25, 40, -(span.z*0.5+42))` ≈ (8.5, 40, -51.5), цель (0, 3, 0) — возвышенный 3/4-вид всей сетки со стороны ряда FLOODED/RIPARIAN/MESIC_LOAM (у них нет canopy-кольца, поэтому 19.5-метровые стволы дальнего ряда остаются фоном, а не перекрывают сцену).
4. **Близкий кадр** `artifacts/evo7_fff6_lab_cmode_close.png`: центр пары соседних зон UNDER_CANOPY|CANOPY_GAP ((0,0,9.5)+(17,0,9.5))/2, камера ≈ (8.5, 4.5, 20.5) — ~11 м от пары, на высоте крон, цель (8.5, 3.4, 9.5).
5. **Ожидание рендера**: хелпер `_settle_frames(20)` (20 `process_frame`) перед каждым захватом + `RenderingServer.frame_post_draw` внутри нового хелпера `_autocap_capture(file_name)` (захват, декомпрессия, RGB8, save_png, строка `SCREENSHOT <имя> size=... mean_luma=... err=...`).
6. Оба вызова захвата — `await`-нутые: в ходе итераций найден и исправлен реальный дефект — вызов корутины без `await` позволял `_autocap()` сдвинуть камеру к близкой позе, пока широкий захват ещё ждал `frame_post_draw` (именно это портило широкий кадр на промежуточной итерации; диагностировано временной DBG-печатью позы камеры, после диагностики печать удалена из кода).

Экологическая симуляция, модуль `evo7_succession_simulation_v1`, панель хэшей и все входы `result_hash` не затронуты: изменения касаются только материала растений (C-режим), текста HUD и трансформации камеры.

## 4. Финальный прогон (команда и линии)

Команда — точно как в work order:

```bash
BREAKPOINT_RUNTIME_DISABLED=1 EVO7_FFF6_LAB_AUTOCAP=1 DISPLAY="${DISPLAY:-:0}" \
  "$GODOT_BIN" --path <worktree> --resolution 1600x900 \
  res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn \
  > artifacts/runtime/evo7-gui-cmode/run2.log 2>&1
```

`artifacts/runtime/evo7-gui-cmode/run2.log`, exit code 0:

```text
ECO.EVO7-FFF6-VIS: READY zones=6 plants=150 result_hash=52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436
ECO.EVO7-FFF6-VIS: PASS rendered=150 zones_ok=true onoff=true geom_pairs=4 gap_delta=0.5657 stability_pin_max=0.080 replay=true result_hash=52995cf4bcd03578
ECO.EVO7-FFF6-VIS: SCREENSHOT evo7_fff6_lab_cmode_wide.png size=1600x900 mean_luma=0.5702 err=0
ECO.EVO7-FFF6-VIS: SCREENSHOT evo7_fff6_lab_cmode_close.png size=1600x900 mean_luma=0.5269 err=0
```

**Инвариантность хэша подтверждена**: `result_hash` в READY-строке идентичен прерванному прогону и всем итерациям этого отчёта (run2/run3/run4/final) — `52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436`; PASS-строка байт-в-байт та же. Кадрирование камеры/второй захват хэш не изменили.

## 5. Кросс-доказательство «HASH PANEL на PNG vs stdout»

На обоих PNG читаем HASH PANEL: `lab_result_hash=52995cf4bcd03578...` — префикс совпадает с `result_hash` из stdout (READY/PASS) того же прогона; `REPLAY vs previous R: MATCH`. Т.е. кадр с серыми растениями и кадр хэшей — один и тот же детерминированный прогон.

## 6. Файлы-доказательства и визуальная верификация (самим имплементатором)

| Файл | Размер | mean_luma | Что видно (личная проверка read_image) |
|---|---|---|---|
| `artifacts/evo7_fff6_lab_cmode_wide.png` | 1600x900, 213867 байт, sha256 `539d37ec...` | 0.5702 | Все 6 плит зон 3x2-сеткой (в ближнем ряду MESIC_LOAM/RIPARIAN/FLOODED-вода, в дальнем CANOPY_GAP/UNDER_CANOPY/DRY_SAND), оба canopy-кольца (8 стволов с тёмно-зелёными кронами — они сознательно НЕ нейтрализуются C-режимом) над своими зонами; на плитах различимы мелкие серые силуэты растений + белые корневые стержни. HUD читаем полностью. |
| `artifacts/evo7_fff6_lab_cmode_close.png` | 1600x900, 369312 байт, sha256 `40d7c441...` | 0.5269 | Пара UNDER_CANOPY (зелёная плита, слева) и CANOPY_GAP (оливково-жёлтая, справа) с ~11 м: отдельные серые силуэты растений различимы поодиночке — стволики, кронки, белые корневые стержни под плитами; на CANOPY_GAP заметны ветвящиеся силуэты; на заднем плане полосы FLOODED/DRY_SAND с их растениями. HUD читаем полностью. |

Оба PNG воспроизведены байт-в-байт в двух независимых прогонах (run4 и финальный) — детерминизм кадрирования подтверждён.

## 7. История итераций кадрирования (честно, 3 попытки)

1. **Попытка 1** (фронтальный возвышенный вид, высота 44 / отступ 49.5): сцена впервые видна, но 19.5-метровые стволы canopy-колец двух ближних зон перекрывают кадр, растения — мелкие светлые точки.
2. **Попытка 2** (вид со стороны ряда без canopy, высота 40 / отступ -51.5; близкая камера 4.5/11): близкий кадр хороший, широкий испорчен — захвачен уже сдвинутой камерой. Причина найдена: вызов корутины `_autocap_capture` без `await` (гонка поз камеры). Диагностика — временной DBG-принт позы камеры в момент захвата (удалён).
3. **Попытка 3** (= финальный код: тот же кадр + `await`): оба кадра корректны, растения видны — итерации прекращены.

## 8. Ограничения (честно)

- В широком кадре растения различимы как серые силуэты, но мелки (~20-40 px); оценка «различимость размер/форма между зонами» на широком кадре ограничена, основная различимость — на близком кадре.
- Близкая пара UNDER_CANOPY|CANOPY_GAP выбрана по work order как **пространственные соседи**; по readout'у она НЕ входит в 4 geometry-distinct пары (те: RIPAR|DRY_S, RIPAR|UNDER, MESIC|DRY_S, MESIC|UNDER — средние h/cr этих зон близки: h=3.24 vs 3.10, cr=0.63 vs 0.64). Сравнение геометрически различных зон — широкий кадр + числа HUD/G5-readout.
- Canopy-кольца не нейтрализуются C-режимом (по построению лабы: это статическая презентация из замороженных констант) — коричневые стволы в кадрах это ожидалось.
- Прогон оконный на живом рабочем столе пользователя (кратко появлялось окно 1600x900) — по требованию work order; GL Compatibility-рендерер.
- Скриншоты/логи лежат в `artifacts/` (git-игнор), в коммит не входят; коммитятся только код лабы и этот документ.

## 9. Граница роли

Формальная переклассификация строки G5 в line-audit (`docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md`, строка G5: PARTIAL) из PARTIAL в PROVEN — компетенция **свежей независимой line-auditor роли**, а не имплементатора. Настоящий документ — только implementer-отчёт о выполненной визуальной половине G5-доказательства; все статусы остаются **CANDIDATE** до такой независимой верификации.
