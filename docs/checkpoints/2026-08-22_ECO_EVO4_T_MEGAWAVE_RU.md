# ECO.EVO4 — Мега-волна E4.T: закрытие T0–T4

Статус: `RESEARCH_ONLY / COMPLETE_T0_T4 / NO_ACCEPTANCE_CLAIM`. Дата: 2026-08-22.
План исполнения: `docs/plans/ECO_EVO4T_MEGAWAVE_PLAN_RU.md`; предизайн: `docs/plans/ECO_EVO4T_MULTITROPHIC_PREDESIGN_RU.md`.
База: T0 PASS 4/4 (`6f1b3cb0`), tip ветки перед волной `7e8ed8bb`.

Инварианты соблюдены: новых генов нет (только прокси v0 от metabolic-полей), population truth не вводилась, принятые ядра E3.x/PH/CAL1 и замороженные артефакты не тронуты (регрессия T0 после волны: PASS 4/4, digest `fe6dfcb27877031a…` — байт-идентичен). Presentation-слой не влияет на хеши цепи.

## E4.T1 — Herbivore agent contract: PASS (гейты 3/3, тесты 6/6)

- Агент `{appetite, mobility, preference_vector(v0: nutrient_value↑, toxicity↓)}` — `scripts/research/ecology/evo4_t1_herbivore_agent_v1.py`.
- Агрегатное давление на патч поверх манифеста B6 (11 патчей × 90 экземпляров). Честная находка состава: **все патчи B6 композиционно идентичны** (по 10 экземпляров каждого из 9 видов), поэтому предпочтение выражается внутри патча — сплит давления по видам ∝ сдвинутых preference-score; визиты по патчам — смесь «концентрация на лучшем ↔ пропорционально привлекательности» по mobility. Сток давления = 1.0, давление линейно по appetite.
- Прокси v0: defense — точная формула T0 (на общих геномах воспроизводит sealed-значения 0.5641 / 0.3755 бит-в-бит); nutrient/toxicity — декларированные деривации от vigor/shade/dormancy + hash-unit.
- Гейты: G1 внутренняя детерминированность пересчёта; G2 монотонность давления по appetite (перпатч non-decreasing + строгий рост суммарного); G3 выравнивание предпочтения (давление смещено к более питательным видам). Все TRUE.
- Тесты: `python tests/research/ecology/test_evo4_t1_herbivore_agent.py` → OK (6/6), включая fresh-process детерминизм артефакта (двойной прогон, sha256 байт-в-байт).
- Артефакт: `validation/ecology/evo4_t1_agent_pressure.v1.json`.
- Коммит: `07a16639`.

## E4.T2 — Коэволюционный цикл: PASS (недоминируемость + рестарт-детерминизм + 3 сида)

- `scripts/research/ecology/evo4_t2_coevolution_loop_v1.py`: 40 поколений «распределение защиты растений ↔ предпочтение агентов» на 9 видах моста B6.
- Payoff наследует запечатанную структуру T0 (константы DEFENSE_COST=0.35, HERBIVORY_GAIN=0.85; в концах x∈{0,1} формулы совпадают с T0) с декларированной v0-квадратичной сатурацией между концами — даёт внутренние best-response решения и честную частотозависимость.
- Динамика не вырождена: mean_defense 0.117 → 0.222 за цикл; равновесие полиморфно (NONE/LIGHT смесь: 3+6 видов); intake агентов падает 0.452 → 0.338 по мере роста защиты.
- Гейты:
  - G1 недоминируемость чистых стратегий (аналог PH3C): чистое сообщество «без защиты» инвазируемо мутантом с defense>0 (лучший случай e3f-ext-05: payoff 0.078 → 0.190 при defense=0.45); чистое «полная защита» инвазируемо мутантом с дешёвой защитой (e22-alpha-late: 0.100 → 0.376 при defense=0.20). Оба направления TRUE.
  - G2 restart-determinism байт-в-байт: два независимых прогона пайплайна in-process → одинаковый canonical sha256; внешние двойные прогоны скрипта → артефакты байт-идентичны (тест).
  - G3 robustness: сиды {20260822, 20260823, 20260824} — оба invasion-checks TRUE на каждом.
- Тесты: `python tests/research/ecology/test_evo4_t2_coevolution_loop.py` → OK (6/6).
- Артефакты: `validation/ecology/evo4_t2_coevolution_trajectory.v1.json`, `validation/ecology/evo4_t2_coevolution_result.v1.json`.
- Коммит: `58e7c150`.

## E4.T3 — Визуализация трофики: PASS (пиксельный гейт)

- `scripts/research/ecology/evo4_bridge_presentation_v1.gd`: опциональные presentation-only параметры `thorn_density` (шипы-конусы на боковых ветвях/twig'ах, ключуются individual_seed|segment|index, производятся от defense-прокси вызывающей стороной) и `browse_pressure` (детерминированная потеря листьев/цветов + побурение уцелевшей листвы). Значения по умолчанию 0.0 воспроизводят до-T3 сборки: токен thorn в presentation_hash добавляется только при thorns>0, цветовая ветка — только при browse>0. PH5 core не тронут, chain-hash воздействия нет.
- Регрессия совместимости: лаба B0.5 rich presentation после правки презентера → `ECO.EVO4/E4.B0.5 RICH PRESENTATION: PASS`.
- Лаба `scenes/labs/ecology/eco_evo4_t3_trophic_defense_lab.gd` (+tscn): 9 видов моста в две колонки «до / после» (thorns=defense-прокси слева; справа тот же сид при browse=0.65), подписи в кадре (вид, defense, −% листвы), заголовки колонок.
- Пиксельная проверка кадра: unique=379 цветов, column_delta яркости 0.0100, thorns=134, потеря листвы 66.7% → `ECO.EVO4/E4.T3 TROPHIC DEFENSE LAB: PASS`.
- Скриншот: `artifacts/evo4_t3_trophic_defense.png` (локальное evidence; каталог artifacts/ в .gitignore по конвенции репозитория).
- Коммит: `0c147b05`.

## E4.T4 — Планетарный трофический прогон: PASS (fps 165.3 ≥ 100, хеши цепи неизменны)

- `scripts/labs/ecology/eco_evo4_t4_planetary_trophic_lab.gd` (+tscn): равновесное распределение защиты из T2 (`equilibrium.final_defense`) применено к экземплярам региона B6 (polar-plateau-04/extended_r1, 990 экземпляров, 72 визуальных варианта) как классы защиты (NONE/LIGHT/…; фактические классы: NONE×4, LIGHT×5), шипы включены для всех экземпляров (6094 thorn-инстансов).
- Инвариантность цепи проверена в прогоне: для каждого вида graph_hash скелета напрямую == source_graph_hash сборки с шипами → true. Хеши программы/снапшота манифеста записаны в результат без изменений.
- Perf (тот же паттерн пробы, что B7: 30 кадров прогрева + окно 90 кадров, OpenGL): avg_fps=165.3, avg_ms=6.05, worst_ms=12.06, draw_calls=827 → гейт fps ≥ 100 выполнен с запасом.
- Результат: `validation/ecology/evo4_t4_planetary_probe_result.v1.json` (verdict PASS); финальный кадр `artifacts/evo4_t4_planetary_trophic.png` (локальное evidence).
- Коммит: `e4815f08`.

## Сводка гейтов

| Шаг | Вердикт | Ключевые гейты |
|---|---|---|
| E4.T1 | PASS | детерминизм fresh-process; монотонность по appetite; preference alignment; тесты 6/6 |
| E4.T2 | PASS | недоминируемость обоих направлений; restart sha256 byte-equal; robustness 3/3 сидов; тесты 6/6 |
| E4.T3 | PASS | Godot-прогон PASS; пиксельная проверка; регрессия B0.5 PASS |
| E4.T4 | PASS | graph_hash invariance true; avg_fps 165.3 ≥ 100 |

## Артефакты

- `validation/ecology/evo4_t1_agent_pressure.v1.json`
- `validation/ecology/evo4_t2_coevolution_trajectory.v1.json`
- `validation/ecology/evo4_t2_coevolution_result.v1.json`
- `validation/ecology/evo4_t4_planetary_probe_result.v1.json`
- `artifacts/evo4_t3_trophic_defense.png`, `artifacts/evo4_t4_planetary_trophic.png` (локальные, gitignored по конвенции)

## Ограничения и честность

- Defense/nutrient/toxicity — деривационные прокси v0 от уже принятых metabolic-полей; независимые трофические гены остаются за отдельной авторизацией (B1-v1-стиль).
- Композиционная однородность патчей B6 задокументирована в T1 и учтена двухуровневой моделью давления (патч × вид).
- Квадратичная сатурация payoff в T2 — декларированное v0-расширение между запечатанными концами T0.
- Скриншоты не коммитятся (gitignored `artifacts/*`) — путь фиксируется здесь и в машинах-результатах.

Трекер: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json` → `tracks.E4.T.status = COMPLETE_T0_T4`. Канонизация всего моста+E4.T остаётся за human gate (merge PR #196).
