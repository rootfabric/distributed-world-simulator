# ECO EVO3 — План выполнения оставшихся пунктов ветки

Статус: `RESEARCH_EXECUTION_PLAN / RESEARCH_ONLY / NO_PRODUCTION_AUTHORITY`.
Ревизия трекера: `ECO-R78-2026-08-22`. Базовый HEAD: `5fc9895`.
Живой источник состояния: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Карта остатка маршрута

```text
Этап 0  E3.8  Cross-Planet Generalization Matrix      IN_PROGRESS (PR #188)
Этап 1  ECO-R78 поправки: review → внедрение          READY (этот коммит)
Этап 2  E3.FINAL Planetary Ecology Compiler Challenge BLOCKED (после E3.8)
Этап 3  E3.6-R Multi-Snapshot Temporal Envelopes      CONDITIONAL (owner evidence)
Этап 4  XFER1 readiness                                PARALLEL_RESEARCH_ONLY
Этап 5  После EVO3: runtime convergence / EVO4         OUT_OF_BRANCH_SCOPE
```

Последовательность обязательна (`no_stage_skip`): этапы 2+ не активируются до принятия E3.8; этап 4 выполняется параллельно, но не создаёт полномочий.

---

## Этап 0 — E3.8 Cross-Planet Generalization Matrix (завершить)

**Состояние.** Ветка `feature/eco-evo3-e3-8-cross-planet-generalization-matrix` @ `7a6bb752`, PR #188 открыт; independent Reviewer отчёт: PASS (27 adversarial-проверок, claims #1–#8 подтверждены); closure run #2 и Project Control #1127 на exact HEAD успешны.

**Осталось сделать (по порядку):**

1. Проверить свежесть machine evidence на момент merge: если HEAD ветки сдвинулся после run #2/#1127 — перезапустить Closure + PC на новом exact HEAD.
2. Verifier PASS по fresh Reviewer PASS (Verifier до Reviewer заблокирован).
3. Director acceptance decision в PR (durable comment).
4. Merge с expected-head protection (merge-ref прогнан Project Control до merge; tree merge == проверенному).
5. Control-коммит: трекер → `E3.8 ACCEPTED`, `current_checkpoint = ECO.EVO3/E3.FINAL`, revision R78; баннеры prose-доков обновить тем же коммитом (правило A8).
6. Обновить `accepted_evidence` финальными run id (линт A5 должен проходить).

**Критерий выхода:** `ECO.EVO3/E3.8 = ACCEPTED`, все 6 семейств сохранены вместе с null/reversal/no-colonization исходами, retuning отсутствует (diff защищённых модулей пуст).

## Этап 1 — Поправки ECO-R78 (этот коммит → внедрение)

**Уже сделано:** трекер R77 (гейты A1–A3, политики A4/A5/A6/A7/A8), документ поправок, агрегирующий раннер + workflow (dispatch-only), линт привязки run id, XFER1 pre-design, фикс загрузки тестов архитектурного раннера.

**Осталось:**

1. Fresh independent Reviewer по этому docs/tools-коммиту (риск LOW/MEDIUM; science-поверхности не затронуты — diff не содержит принятых модулей и артефактов).
2. После Reviewer PASS: первый ручной запуск `e3-regression-closure` в CI (workflow_dispatch), затем решение Director о включении `pull_request`-триггера с paths-фильтром принятых поверхностей.
3. Привязать линт A5 в гейт: шаг во всех stage-closure workflow ИЛИ обязательный локальный прогон перед checkpoint proposal.
4. Начиная со следующего acceptance-коммита: баннеры prose-документов обновляются всегда (A8).

**Критерий выхода:** регрессия 8/8 в CI, линт зелёный, триггеры включены осознанным control-решением.

## Этап 2 — E3.FINAL Planetary Ecology Compiler Challenge

**Входные условия:** E3.8 ACCEPTED; отдельный dispatch от exact accepted control head.

**Precommit-пакет (до реализации, публикуется одним коммитом):**

1. Unseen planet fields: предобъявленный набор планет вне фикстур E3.1–E3.8, byte-frozen (blob+sha256), без target-aware инъекций.
2. Каталожные варианты (A1): расширенный каталог 10+ видов; граничные распределения трейтов; моно-вид. Все — persisted EVO2-форматом, byte-frozen.
3. Sealed outcome envelopes (A2): по конверту класса исхода на каждую планету×каталог; вскрываются после заморозки программ.
4. Scale ceiling (A3): предобъявленные лимиты wall-time/памяти/размера артефакта.

**Реализация:** компиляция цепочкой E3.1→E3.7 без retuning; для каждой комбинации планета×каталог — полный `PlanetEcologyProgram`; no-colonization валиден; fail-closed сезонность сохраняется.

**Гейт-пакет:** fresh-process byte/hash determinism ×2; schema PASS; committed artifact identity; execution envelope таблица; вскрытие sealed envelopes и фиксация совпадений/расхождений как falsification evidence; post-build critique; Evidence Map; independent Reviewer; Verifier; PC0 + directional audit; Director acceptance; human gate на объявление EVO3 COMPLETE.

**Критерий выхода:** `ECO.EVO3/E3.FINAL = ACCEPTED` — plant-only planetary generalization proof завершён; E3.6-R и XFER1 остаются вне доказательства.

## Этап 3 — E3.6-R Multi-Snapshot Temporal Envelopes (условный)

Не блокируется и не блокирует этап 2. Активируется только owner-dispatch, который обязан:

1. Объявить критерии достаточности temporal evidence ДО поставки данных.
2. Поставить мульти-снапшотные поля как byte-exact снапшоты.
3. Сохранить инварианты: ECO не владеет TF/ENV, canonical history не переписывается.

До этого весь маршрут остаётся на `UNRESOLVED_SINGLE_SNAPSHOT` (fail-closed) — это принятое корректное состояние, а не дефект.

## Этап 4 — XFER1 readiness (параллельно, без полномочий)

Готово: `docs/plans/ECO_XFER1_READINESS_PREDESIGN_RU.md`.

При появлении канонических контрактов G/ENV/MAT/WQ/SD/TF — последовательность §5 pre-design: перепривязка адаптеров E3.1 без retuning science → полное регрессионное замыкание → Reviewer/Verifier/PC0 → human gate activation. До этого XFER1 остаётся `BLOCKED_WAIT_CANONICAL_*`; LIVE остаётся deferred.

## Этап 5 — После EVO3 (вне этой ветки)

Plant runtime convergence и EVO4 multi-trophic проектируются отдельно после ACCEPTED E3.FINAL. Животные/food-web не опережают plant planetary generalization proof. Production integration остаётся separate main-owned product train.

---

## Сквозные правила выполнения

```text
sequential, no_stage_skip            — этапы только в порядке карты
exact-head freshness                 — reviewed HEAD == evidence HEAD == tested HEAD
no-retuning                          — принятые модули/артефакты не изменяются после acceptance
implementer cannot self-accept       — Reviewer/Verifier/Director по risk routing
RED не переинтерпретируется          — статусы PC фиксируются как есть
git is durable memory                — каждое состояние коммитится; чат не память
human gates                          — merge в production-поезда, XFER1/LIVE activation, architecture promotion
```

## Известные риски и контрмеры

| Риск | Контрмера |
|---|---|
| Stale evidence к моменту merge E3.8 | Перезапуск Closure+PC на exact HEAD непосредственно перед merge |
| Локальные env-отличия ломают stage-раннеры | Пин `jsonschema==4.26.0` задокументирован; CI ставит его явно; агрегат делает различия видимыми |
| Каталожные варианты вскроют дефекты масштабирования цепочки | Это цель этапа 2; находки идут через Repair Doctrine, а не через retuning принятых этапов |
| Расхождение sealed predictions с результатами | Не проваливает этап; сохраняется как falsification evidence и анализируется в critique |
| Долгое ожидание canonical foundations (XFER1) | Этап 4 конвертирует ожидание в подготовку без нарушения границы |
