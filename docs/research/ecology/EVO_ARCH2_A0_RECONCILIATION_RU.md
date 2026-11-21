# EVO ARCH2 — A0: сохранённые выводы аудита и план коррекции

Статус: RESEARCH CANDIDATE. Дата фиксации: 2026-09-06.
Ветка: `feature/eco-evo-arch2-a0-a3-r1`.
Источник: `feature/eco-evo7-vis5-terrain-ecosystem-composition-r1` @ `a73cccb8064fdfb4df266338d3d20e24ac9f082b`.
Прочитанная canonical main: `fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91`.
Работа разрешена пользователем как изолированная research-коррекция A0–A3; это не main-owned production activation и не перенос foundation ownership.

## 1. Главный вывод, который нельзя потерять

Цель ветки — EVOLVABLE LIVING WORLD, а не процедурный декор. Цикл: genome → наследуемая программа развития → тело → функция и изображение → взаимодействие со средой → survival/reproduction → новые поколения. Организмы должны не только читать среду, но и изменять её; изменение среды создаёт последующий отбор.

Вердикт исходного аудита: D, требуется частичное перепроектирование. Не переписывать всё: сохранить детерминизм, source-bound representations, research/production split и presentation-only LOD. Заменить ограниченное developmental ядро successor-контрактом, не редактируя старые accepted kernels на месте.

Текущий parameter genome не является наследуемой программой развития. Существуют 9 PlantGenome + 8 DevelopmentTraits + 5 extension traits = 22 числовые оси, из них 13 мутируют штатно. Internode length, branch probability, branch angle, branch length ratio и branching depth не входят в текущую mutation policy. Branching depth в skeleton задаёт длину боковой цепочки, а не рекурсивное ветвление. Поэтому больше поколений или красивее renderer не открывают недоступные body plans.

## 2. Зафиксированные результаты исходного аудита

Executable baseline: `fb1a7ac21037e02033eae6d7e778ed8757514e19`, tree `89551693f0cbac555a5026424d36b50cd35b8804`. Три последующих VIS5 commit меняют документацию/конфигурацию, не runtime. Historical source tar SHA-256: `59ec27aa62b159ebeffc3897230406faa62c5d6204019f783318d7d64c91b021`.
Godot: `4.7.1.stable.double.custom_build.a13da4feb`, binary SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Это результаты предыдущего аудита, не новые independent acceptance A0–A3:

- EXP-A: 1000 realizations, 1000 geometry signatures, 492 rooted topology signatures, но одно структурное семейство; нет ветвления вне главной оси, нисходящих сегментов или нескольких graph roots.
- EXP-B: 100 малых мутаций при общей development seed были valid/similar, topology changes 0. Обычная смена индивидуальной seed меняла топологию даже без численного изменения генов. Не путать reseeding и наследуемую структурную эволюцию.
- EXP-C: один genotype давал разную высоту в wet/normal/dry/dark; root extent оставался тем же. Пластичность существует, её правила фиксированы.
- EXP-E: canopy light, water allocation и soil legacy способны менять subsequent selection в paired experiments. Это минимальное research niche construction, не полный persistent world loop.
- EXP-F: leaf-area proxy 0.187592→0.396027, root spread 1.6→16 m, root depth 0.85→1.36 m, litter proxy 5487→16573 при одинаковом render description. Функциональный phenotype видит extension traits, визуальный — не все.
- VIS5.0–VIS5.5: 87/70/57/101/92/114 PASS. Эти gates доказывают composition/lifecycle, а не evolvable topology.
- P4.2/P4.3/P4.4/P4.5: 66/67/52/60 PASS. Persistence существует, но payload p3_state не содержит всего современного development/body/field state.

Исходные поставленные материалы идентифицируются без зависимости от имени скачанного файла:

| Материал | SHA-256 |
|---|---|
| Полный отчёт R1 | `4eb5664907ca5a55e5934b861794d77c673550a3e6d6657eb40a13bd431506e3` |
| Архив 41 файла | `1486893550c40ffc31ee81318d3c78fc75ebf13ab290f6cb7a319153e22d0155` |
| Manifest R1 | `23879207615d40158e2974f8bd8c31a4dfbfb92537488b8c2ef730ba521e7358` |

## 3. Четыре независимые шкалы зрелости

| Ось | Подтверждённый смысл | Не означает |
|---|---|---|
| RESEARCH | PH/FFF/LS morphology, selection, feedback и population experiments | Production authority |
| PRODUCTION | P4 clock, catch-up, region state, persistence и ownership для прежнего payload | Полное сохранение EVO7 тела и эффектов |
| PRESENTATION | VIS4/5, PH5, terrain composition, source-bound LOD/streaming | Наследуемое развитие широкого класса организмов |
| INTEGRATION | Transfer contracts, отдельные PERF/VIS composition joins | Canonical living world activation |

VIS5 closure = CLOSED для presentation scope. Поздний PERF2.CONV R3 имеет отдельное closure `81a0b3fa60664684b02d8387e4693c5f328dbe28`. Старый current_checkpoint=PERF2.4 не должен скрывать позднее evidence. Новый PLAY1 join проверяется на собственном HEAD. PH, FFF, VIS, PERF, XFER, PLAY нельзя свести к одной линейной шкале готовности.

Состояние 20 архетипов: текущая модель частично выражает grass/shrub/tree silhouettes, но не полноценные creeping/reanchoring, multistem, climbing, cascading, radial-colony, planar-sheet и необычные recursive body plans. Root-heavy/canopy-heavy пока могут оставаться функциональными proxies. Случайная асимметрия не является наследуемой программой асимметрии. 492 topologies не равны 492 body plans.

## 4. Реестр ограничений, остающийся открытым до собственных gates

| ISSUE | Severity | Текущее ограничение → последствие → коррекция / момент блокировки |
|---|---|---|
| 01 | CRITICAL | Одно семейство тела → недостижимые body plans → typed modular program до расширения форм |
| 02 | HIGH | 13 mutable axes → manual presets не доказывают evolutionary reachability → mutation coverage и structural operators |
| 03 | HIGH | Потомок меняет individual seed → novelty ошибочно считается наследуемой → common-random controls до оценки evolvability |
| 04 | HIGH | cap64/main, cap512/total → 40 m при 2 cm internodes даёт 1.28 m ствол → явный budget/continuation вместо скрытой биологии |
| 05 | CRITICAL | Functional/visual split → важные traits не видны → один полный phenotype, blocker уже сейчас |
| 06 | CRITICAL | Instant PH2 rebuild → нет истории оплаченного развития → persistent growth points и steps |
| 07 | HIGH | Top-K scoring/gates → оптимизация proxies → resource-funded survival/reproduction до production selection |
| 08 | CRITICAL | Light target×source → O(N²) → locality/extent index до большого N |
| 09 | HIGH | Normalized proxies без units → неверный Matter balance → units/stocks/sources/sinks до canonical write-back |
| 10 | HIGH | Soil memory не единый state → feedback теряется при restart → versioned coupling state |
| 11 | HIGH | Empty effects могут означать empty field → abiotic evolution исчезает после extinction → independent field advance |
| 12 | HIGH | Разные cells/frames/owners → seam double truth → stable addresses, owner/revision/time/units |
| 13 | HIGH | P4 сохраняет p3_state → старый PASS не доказывает новый restart → consistent cut организм+fields |
| 14 | HIGH | PH4 eager/free seed batches → allocations и бесплатное потомство → paid cohorts; не утверждать, что LS использует этот путь |
| 15 | MEDIUM | Fixed plasticity profile → reaction norm не эволюционирует → typed regulatory genes |
| 16 | HIGH | Нет единого root/physical/damage binding → cut/dig не отражаются причинно → body modules и adapters к existing owners |
| 17 | MEDIUM | Species diagnostics без compatibility → lineage hash не biological species → ancestry отдельно от clustering/compatibility |
| 18 | HIGH | Visual LOD без ecological aggregation → нет million-organism guarantee → FULL/REDUCED/PATCH/AGGREGATE contracts |
| 19 | HIGH | Сильная divergence и roadmap drift → blind merge тащит старые foundations → selective current-main reconstruction |
| 20 | HIGH | GREEN/CLOSED смешаны между осями → новые этапы опираются на недоказанные claims → scope-specific gates |
| 21 | MEDIUM | Linux repeatability не cross-platform proof → возможен float drift → quantized arithmetic и target vectors |
| 22 | MEDIUM | Неиспользуемые/дублируемые genes → nominal dimensionality не effective → sensitivity map и единый semantics |

Monoculture, runaway height/leaf area, mutation collapse, bloat, chaotic extinction — проверяемые failure modes, а не все уже доказанные аварии. Защита — ресурсные ограничения, locality, heterogeneity, costs и честные measurements, не гарантированные species quotas.

## 5. Target architecture и invariants

`Genome → DevelopmentProgram → BodyGraph/DevelopmentState → PhenotypeSnapshot → {function, physics projection, presentation}`.
`Organism demands/effects ↔ owner-bound environmental fields → resource grants → growth/survival/reproduction → evolution`.

Базовые module roles: attachment, support, transport, collector, absorber, storage, reproductive, sensor, defense. Растение — специализация, не global enum. Genome graph не равен body graph. Нет произвольного исполняемого кода в genotype.

KEEP: deterministic ordering, source seals, mutation authority, frozen V1 oracles, research/production split, presentation-only LOD, typed effects, bounded generation, lineage history и P4 fences.
EXTEND: ports, morphology tools, lineage, source-bound adapters.
REFACTOR: genotype/development/phenotype boundaries, units, field coupling, roadmap.
REPLACE только в successor: fixed skeleton как universal ядро; global all-pairs shading; обязательный production fitness score.
DEPRECATE как evidence новой цели: hash count вместо diversity; render PASS вместо topology; old persistence PASS вместо full restart.

Правила мира читаются через snapshot, эффекты агрегируются данными. Не вводить Plant↔Soil↔Water callback сеть. Не делать new ENV/Authority/Material/Region owner. Не подключать ecology напрямую к произвольному physics research HEAD. Один организм у seam имеет одного owner; resources имеют field owners. Handoff переносит idempotency/commit cursors, не mesh cache. Эти production bindings не входят в A0–A3.

## 6. Коррекционный train

| Этап | Результат / зависимости / acceptance |
|---|---|
| A0 | Scope/evidence/owner reconciliation; read-only main; historical GREEN не переименовываются |
| A1 | Versioned genome/program/body/state/phenotype; strict validation, units, hashes, migration envelope; A0 |
| A2 | Persistent points; extend/branch/differentiate/attach/allocate/retire; bounded paid operations; slicing/restart invariance; A1 |
| A3 | Parameter/regulatory/structural mutation, explicit rejections, Lab V2 с editor реальных rules; multi-parent locality/diversity; A2 |
| A4 | Local field index, conservative exchange, owner-bound field interface; A1–A3 |
| A5 | Regulated survival, maintenance, paid reproduction; no required global fitness; A2–A4 |
| A6 | Persistent niche construction, abiotic update после extinction; A4–A5 |
| A7 | Three-location Observatory, wet/dry/dark, common-garden, effects-off/mutation-off controls, seeds fixed заранее; A3/A5/A6 |
| A8 | Full organism+field consistent snapshot, restart и seam ownership; current main contracts и human gate |
| A9 | Ecological fidelity отдельно от render LOD; exact historical individuals не восстанавливаются из lossy aggregate без достаточного state |
| A10 | Selective integration from current main, terrain/Matter/construction/damage/network bindings; no blind merge |
| A11 | Visible persistent evolving habitat acceptance |

A0–A3 budgets: 256 modules, 32 active growth points, 64 rules, 8 actions/rule, до 4096 операций в slice. Достижение capacity должно быть явно BUDGET_BLOCKED, не mature phenotype. Compute slicing не меняет ecological tick. Synthetic environment/grants допустимы и подписаны; conservative world fields и полноценная reproduction ecology остаются A4+.

## 7. Новые gates

Строгие schema/unknown opcode/dangling reference/nonfinite/overflow rejects; canonical import/export; biological hash не зависит от labels/individual ID. Six body fixtures: axial recursive, basal multi-axis, spreading/reanchoring, radial colony, supported climbing, planar collectors. Они должны исполняться одним interpreter без renderer preset switch.

Stop/resume и save/load на промежуточной операции; large slice == many small slices. Modules и branches оплачены; budgets явно блокируют без повреждения state. Один phenotype содержит геометрию, функции и physical proxies; изменение collector area/absorber reach должно менять видимое representation descriptor.

Mutation campaign: не менее 1000 parents; zero mutation neutrality; common-random controls; per-operator valid/rejected/broken counts и reasons; median/p95 distances; нет silent repair. Предварительный small parameter validity gate ≥99%. Structural locality не обещается: её распределение измеряется.

Fresh independent Reviewer/Verifier, exact head/tree/evidence и PC0 нужны для accepted status. Implementer не self-accept. Runtime merge, main push и ownership promotion не выполняются. Current work reports execution facts; main сохраняет право объявлять состояние проекта.

## 8. Transport / recovery

Normal Git attempt завершился `Could not resolve host: github.com`. Read/write выполняются доступным GitHub connector, non-force refs. Не создавать/изменять Actions и не использовать CI для реконструкции или публикации commits. Приложенный source archive — historical runtime baseline; он не выдаётся за fresh fetch.

Следующий агент читает этот файл, `config/ecology/evo-arch2-a03-work-order.v1.json`, capability manifest и validation evidence. Продолжение не требует истории чата.
