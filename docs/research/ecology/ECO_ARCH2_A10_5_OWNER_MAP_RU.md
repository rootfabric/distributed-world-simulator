# ECO ARCH2 A10.5 / ECO-POLYGON-1 — Owner Map (P0)

Статус: OWNER MAP, построен по ФАКТИЧЕСКИМ файлам на диске (base `e200a61`). Дата: 2026-09-20.

Все пути — реальные файлы из `scripts/research/ecology/v2/` (линия A1–A9) и связанных каталогов A10 (matter/construction/region/network). Полигон вызывает эти API; он не создаёт параллельных реализаций.

## 1. Таблица canonical операций

| # | Операция | Source file (реальный) | Public API (точная сигнатура) | Owner | Read/Write role | Polygon usage / adapter |
|---|---|---|---|---|---|---|
| 1 | Genome validation | `scripts/research/ecology/v2/organism_genome_v2.gd` | `static func validate(g: Variant) -> String`; также `create(program: Dictionary, label: String = "organism") -> Dictionary`, `biological_hash(g: Dictionary) -> String`, `serialize/deserialize` | A1 | polygon: read+create (варианты генома); canonical schema — write только через create | Genome editor вызывает `validate` перед запуском, `biological_hash` для provenance/сравнения вариантов |
| 2 | DevelopmentProgram validation | `scripts/research/ecology/v2/development_program_v1.gd` | `static func validate(p: Variant) -> String`; `validate_action(a: Variant) -> String`; `normalized(p: Dictionary) -> Dictionary`; билдеры `action(op, role, delta, radius, area, reach, target)`, `rule(id, actions, next, channel, low, high)` | A1/A2 | polygon: read+create через билдеры | Rule editor правит только разрешённые значения через `action()/rule()` + `validate` до применения |
| 3 | Development / growth | `scripts/research/ecology/v2/development_interpreter_v1.gd` | `static func begin_tick(source: Dictionary, genome: Dictionary, environment: Dictionary, grant: Dictionary = B.stock(), sequence: int = -1) -> Dictionary`; `static func advance(source: Dictionary, genome: Dictionary, operation_budget: int = 4096) -> Dictionary`; `resize_capacity(source, genome, modules, tips) -> Dictionary` | A2 | write (переходы state) выполняет lifecycle runtime; polygon только читает результаты | Polygon НЕ вызывает интерпретатор напрямую; рост идёт через `resource_lifecycle_runtime_v1.step_population` (см. строку 6) |
| 4 | Mutation | `scripts/research/ecology/v2/genome_mutation_v1.gd` | `static func mutate(parent: Dictionary, seed: int, operator: String = "small") -> Dictionary`; `crossover(parent: Dictionary, donor: Dictionary, seed: int = 0) -> Dictionary`; `delete_rule(parent, id, seed) -> Dictionary`; `draw(seed, key, count) -> int`; OPERATORS: small/medium/regulatory/duplicate/activate/delete/rewire/insert/module_parameter/development_parameter/none | A3 | write нового genome-варианта (parent immutable) | Genome editor «создать вариант» = `mutate(parent, seed, operator)`; toggle operators — только фильтр разрешённых, не новая семантика |
| 5 | Environment | `scripts/research/ecology/v2/local_environment_field_v1.gd` + `environment_field_contract_v1.gd` | Field: `create(owner_token, owner_epoch, origin_mm, cell_size_mm, width, depth, initial_stock, capacities, signals)`; `sample(state, request, supports) -> Dictionary`; `allocate_demands(source, demands, owner_token, owner_epoch, revision) -> Dictionary`; `apply_effects(...)`; `set_cell_signals(...)`; `advance_tick(...)`; sampling-адаптер: `field_environment_adapter_v1.gd: sample_for_development(field, organism_id, position_mm, extent_mm, supports)`; контракт: `environment_field_contract_v1.gd: validate_state/validate_sample/serialize/deserialize` | A4 | write field state — только через owner_token/epoch/revision API; polygon: read snapshots + явные редактируемые входы (stocks/signals) через тот же API | Environment editor меняет stocks/signals ТОЛЬКО через `set_cell_signals`/пересоздание с явным provenance; sampling для development — через `field_environment_adapter_v1` |
| 6 | Resource-funded lifecycle (рост/выживание/размножение за ресурсы) | `scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd` | `static func step_population(field: Dictionary, population: Array, owner_token: String, owner_epoch: int, revision: int) -> Dictionary`; `individual(blueprint, individual_id, position_mm, endowment, origin_kind) -> Dictionary`; `materialize_propagule(propagule, blueprint, paid_parent_state) -> Dictionary`; `validate_propagule(v, blueprint, paid_parent_state) -> String` | A5 | write (population advance, propagules); вход: field + blueprints; polygon — orchestration only | ExperimentController вызывает `step_population` один раз на tick (один canonical mutation step на session); propagules → `materialize_propagule` тем же runtime |
| 7 | Death / decomposition / feedback | `scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd` | `static func advance(source: Dictionary, owner_token: String, owner_epoch: int, revision: int) -> Dictionary`; `create(session_id, field, population, policy) -> Dictionary`; `default_policy() -> Dictionary`; `validate_policy(v) -> String`; `serialize/deserialize`; `balance(state) -> Dictionary` | A6 | write (frames, corpses, mineralization); balances — read | ExperimentController: после `step_population` вызывает `feedback.advance(...)`; observability читает `balance()` |
| 8 | Observability | `scripts/research/ecology/v2/phenotype_snapshot_v1.gd` + `observatory_session_v1.gd` + `diversity_metrics_v1.gd` | `phenotype_snapshot_v1.gd: static func compile(state: Dictionary, genome: Dictionary) -> Dictionary`; `observatory_session_v1.gd: func start(t: Dictionary) -> bool`, `func advance() -> bool`, `func observe() -> Dictionary`, `func export_report() -> String`, `func source_hashes() -> Dictionary`; `diversity_metrics_v1.gd: static func compare(a, b, pa, pb) -> Dictionary` | A1/A7 | read-only projection | UI-слой полигона читает ТОЛЬКО completed immutable snapshots (`observe()`, `compile`); metrics/comparison — `diversity_metrics_v1.compare` + `observatory_session.export_report` |
| 9 | Snapshot / restart | `scripts/research/ecology/v2/snapshot_seam_v1.gd` + `observatory_session_v1.gd` | `snapshot_seam_v1.gd: func start(treatment, entity_id, region_id, owner_id, owner_epoch) -> bool`, `func apply(command: Dictionary, expected_snapshot_hash: String, received_payload: String = "") -> Dictionary`, `func load_text(text, expected_snapshot_hash, expected_origin_hash) -> bool`, `func snapshot_text()/snapshot_hash()/origin_hash()/cursor()/observe()`; `observatory_session_v1.gd: func save_text() -> String`, `func load_text(text, expected_experiment, expected_step) -> bool`; SCHEMA `dws.ecology.snapshot-seam.v1` | A8 | write через seam (commands, bounded MAX_COMMANDS=96); polygon — только через эти API, без второго save format | Save/restore/fork полигона = `observatory_session.save_text/load_text` + `snapshot_seam_v1` для world-compatible mode; checkpoint hash связывает ветки |
| 10 | Fidelity / representation (LOD отделён от ecological truth) | `scripts/research/ecology/plant_multiscale_representation_v1.gd` + `plant_far_representation_materializer_v1.gd` | `plant_multiscale_representation_v1.gd: static func select_tier(projected_height_px: float) -> String`, `select_tier_hysteretic(projected_height_px, previous_tier, margin_ratio) -> String`, `build(description: Dictionary, tier: String) -> Dictionary`, `compute_hash(representation) -> String`; `plant_far_representation_materializer_v1.gd: static func build(representation: Dictionary) -> Dictionary`, `compute_hash(materialization) -> String` | A9 | read-only derived view (tier select + representation build) | Presentation-слой: phenotype → description → tier → representation; **нужен reusable adapter** от canonical `phenotype_snapshot_v1.compile` к `description` input (сейчас description-формат plant-lineage-specific — см. расхождения) |
| 11 | Matter / world / site | `scripts/simulation/matter/contracts/matter_material_batch.gd` (`create/validate/normalize`), каталог `scripts/simulation/matter/contracts/` (matter_body_definition, matter_composition, matter_mass_ledger и др.), analysis `scripts/simulation/matter/analysis/matter_body_mass_integrator.gd`; ecology-side mapping — A10 adapter `v2/matter_resource_mapping_v1.gd` (см. §2) | `matter_material_batch.gd: static func create(data: Dictionary) -> Dictionary`, `validate(value) -> Dictionary`, `normalize(value) -> Dictionary` | A10 / MW-line | polygon: read-only (WORLD-COMPAT); Matter batch — external trusted anchor, polygon не создаёт Matter semantics | WorldAdapter (P11) читает Matter contracts; любые ecology↔Matter соответствия — только через explicit-only mapping A10-адаптера; guessed Matter meaning запрещён |
| 12 | Region / handoff | `scripts/ecology/production/ecology_region_ownership_v1.gd` + `ecology_region_state_v1.gd` + `scripts/network/contracts/handoff_ticket.gd` | `ecology_region_ownership_v1.gd: prepare_handoff(state, target_owner_server_id) -> Dictionary`, `accept_handoff(current_state, package, accepting_server_id) -> Dictionary`, `authorize(...) -> bool`, `commit_snapshot(...) -> Dictionary`; `ecology_region_state_v1.gd: create_region_state(region_id, last_simulated_world_time, p3_state) -> Dictionary`, `validate_region_state(state) -> Dictionary`, `compute_region_state_hash(state) -> String`; `handoff_ticket.gd: create(...)`, `validate(value)`, `ticket_hash(value)`, `is_terminal(value) -> bool` | A10 / production region line | polygon: read-only (WORLD-COMPAT); не владеет Region/ownership | WorldAdapter читает region state/ownership через перечисленные API; handoff — только наблюдение WARM-prep/post-commit ACTIVE через snapshot seam, без собственного handoff-механизма |
| 13 | Construction / body damage | `scripts/construction/damage/construction_damage_record.gd` | `static func create(damage_id: String, request_checksum: String, damage_plan_checksum: String, repair_plan: Dictionary, component_checksums: Array, applied_generation: int) -> Dictionary`; `mark_repaired(value, generation) -> Dictionary`; `validate(value) -> Dictionary`; `compute_checksum(value) -> String`; SCHEMA `planet_simulator.construction_damage_record.v1` | A10 / construction line | polygon: read-only (WORLD-COMPAT); DamageRecord — external trusted anchor | WorldAdapter отображает damage/effective function из DamageRecord; ecology-side bridge `v2/body_construction_binding_v1.gd` (см. §2) |

Вспомогательные canonical API, которые использует полигон (не отдельные операции):

- `canonical_value_v1.gd` — `integer/keys/identifier/vector/encode/digest/decode` (валидация и хэширование всех словарей).
- `body_graph_v1.gd` — `validate(modules) -> String`, `topology_signature(modules) -> String`, `cost(module) -> Dictionary`, `root() -> Dictionary` (A1/A2: BodyGraph truth; polygon — read-only + display).
- `organism_blueprint_v1.gd` — `create(genome, life_history) -> Dictionary`, `validate/biological_hash/serialize/deserialize` (A1: blueprint = genome + life history program).
- `life_history_program_v1.gd` — `create_default() -> Dictionary`, `validate(v) -> String`, `biological_hash(v) -> String` (A5 вход).
- `organism_life_state_v1.gd` — `create(blueprint, individual_id, position_mm, endowment, origin_kind)`, `create_parent_transfer(blueprint, propagule, paid_parent_state)`, `validate`, `state_hash`, OUTCOMES (MAINTENANCE_PAID…DEAD_INERT) — жизненный цикл особи.
- `organism_state_v1.gd` — `create(g, individual_id, reserves)`, `validate(s, g)`, `biological_hash` — developmental state организма.
- `organism_environment_ports_v1.gd` — `sample_request/demand/effect(...)`, `validate_sample_request/validate_demand/validate_effect`, `sampling_extent_mm(phenotype)` (A4: порты организма).
- `environment_fixture_v1.gd` — `create(water, light, with_host)`, `validate(env)`, `can_attach(env, id, position, reach)` (LAB fixtures).
- `observatory_protocol_v1.gd` — `manifest()`, `treatment(seed, common_garden, effects_enabled, mutations_enabled)`, `valid_treatment`, `ancestor()`, `founding_genome(t, protocol)`, `site_genesis(site_id, t, protocol)`; SITES = wet/dry/dark (A7: протокол эксперимента — прямой предшественник ExperimentManifest).
- `body_program_fixtures_v1.gd` — `make(index) -> Dictionary` (LAB founder-фикстуры).
- `legacy_genome_adapter_v1.gd` — `preserve/restore/valid` (совместимость с plant_genome_v1).

## 2. A10 adapters — статус и публичные API

По заданию ожидается 5 адаптеров A10. Фактическое состояние на base `e200a61`:

| Adapter (ожидаемое имя) | Статус на диске | Публичный API | Frozen invariants |
|---|---|---|---|
| `scripts/research/ecology/v2/snapshot_seam_v1.gd` | **ЕСТЬ** | `start(treatment, entity_id, region_id, owner_id, owner_epoch) -> bool`; `apply(command, expected_snapshot_hash, received_payload) -> Dictionary`; `load_text(text, expected_snapshot_hash, expected_origin_hash) -> bool`; `snapshot_text()`, `snapshot_hash()`, `origin_hash()`, `ecology_text()`, `ticket_snapshot()`, `cursor()`, `observe()` | SCHEMA `dws.ecology.snapshot-seam.v1`; MAX_COMMANDS=96, MAX_TICKETS=8, MAX_COMMAND_BYTES=8192; команды валидируются (`COMMAND_FIELDS`); publish только целостного `_text`+`_hash`; integrates `handoff_ticket.gd` + `handoff_state_machine.gd` (ticket snapshot, ACTIVE ticket required для apply) |
| `scripts/research/ecology/v2/world_binding_v1.gd` | **ЕСТЬ** (введён A10-коммитами; напр. `a0df8f5 fix(eco): require ACTIVE region for A10 execution`) | `static func bind_matter_site(query: Dictionary, region: Dictionary, cursor: Dictionary) -> Dictionary`; `static func project_construction_damage(...)`; `static func admit_cursor(cursor: Dictionary, region: Dictionary) -> Dictionary` | Region execution = ACTIVE only; post-commit target = ACTIVE; cursor admission проверяет region state |
| `scripts/research/ecology/v2/matter_resource_mapping_v1.gd` | **ЕСТЬ** | `static func create(catalog: Dictionary, map_id: String, entries: Array = []) -> Dictionary`; `static func validate(value: Dictionary, catalog: Dictionary) -> String`; `static func admit_material_batch(batch, catalog, mapping, expected_batch_checksum) -> Dictionary` | Matter resource mapping = explicit only; no guessed nutrient/water meaning; Matter batch = external trusted anchor (checksum-verified) |
| `scripts/research/ecology/v2/world_seam_binding_v1.gd` | **ЕСТЬ** | `static func prepare_ticket(...)`; `static func admit_committed(...)` (использует `world_binding_v1` + `authority_region_descriptor` + `handoff_ticket`) | Handoff preparation target = WARM only; post-commit target = ACTIVE; ticket/seam идентичность проверяется |
| `scripts/research/ecology/v2/body_construction_binding_v1.gd` | **ЕСТЬ** | `static func create_binding(body_modules, source_snapshot, part_to_module) -> Dictionary`; `validate_binding(...)`; `create_overlay(...)`; `apply_damage(binding, overlay, body_modules, source_snapshot, event, expected_event_binding_hash) -> Dictionary`; `validate_overlay(...)`; `admit_overlay(...)`; `effective_function(...)` | DamageRecord/damage event = external trusted anchors; overlay не переписывает исторический BodyGraph; effective function вычисляется из binding+overlay |

Проверено: `git ls-tree origin/main scripts/research/ecology/v2/` — все 5 адаптеров присутствуют в canonical main (base `e200a61`, merge "integrate selective world bindings (#670)"). Ранняя проверка через `git ls-files` в рабочем дереве дала ложно-отрицательный результат и была исправлена прямой проверкой tree-объектов origin/main.

## 3. Расхождения и пробелы (важно для P1+)

1. ~~4 из 5 A10-адаптеров отсутствуют~~ — **опровергнуто**: все адаптеры присутствуют в origin/main (см. §2). WORLD-COMPAT (P12) не заблокирован отсутствием API.
2. **A9 representation-контракты plant-lineage-specific**: вход `plant_multiscale_representation_v1.build(description, tier)` ожидает `description` plant-render формата (`plant_render_description_v1.gd`), а не universal phenotype. Для полигона нужен **reusable adapter** `phenotype_snapshot → render description` (не копия формул). Помечено в строке 10.
3. **Observatory protocol ограничен** тремя сайтами (wet/dry/dark) и фиксированным `treatment(...)`; ExperimentManifest P1 должен расширить входы (custom zones, произвольные founders), не ломая `valid_treatment`-контракт.
4. `ecology_region_*` (P4.1/P4.5) — production-line API с собственными schema `distributed_world_simulator.ecology.*`; polygon должен читать их как trusted contracts, не подменяя ownership-модель. Ecology-side мост к Matter — через `matter_resource_mapping_v1` (explicit-only), НЕ через прямое чтение Matter catalog.

## 4. REPAIR R1 (ECO-POLYGON-1) — single-trajectory runtime + mutation receipts

Статус: REPAIR R1 применён на ветке `repair/eco-arch2-a10-5-polygon-r1` (base `af192718`, tree `b29e770f`). Дата: 2026-09-21.

### 4.1 Новые canonical компоненты

| Компонент | Файл | Роль |
|---|---|---|
| EcologyRuntimeV1 | `scripts/research/ecology/v2/ecology_runtime_v1.gd` | ЕДИСТВЕННАЯ текущая ecology state trajectory (один field, одна population). Композиция тика: A5 `step_lifecycle` (ровно один раз) → `admit_propagules` (receipt-only) → A6 `step_feedback` на ТОМ ЖЕ field/population. Владеет accounting-якорем (conservation per step, fail-closed), integrity seal, outbox (paid-but-unmaterialized emissions, пуст на rest). Переиспользуем для A11+; workbench — consumer. |
| GenomeMutationReceiptV1 | `scripts/research/ecology/v2/genome_mutation_receipt_v1.gd` | Canonical contract мутационного события: `{schema, parent_genome_hash, child_genome_hash, operator, seed, event_hash, bias_hash}`; `issue` (из фактических объектов) + `validate` (seal) + `validate_admission` (binding parent/child/propagule + наследование life_history). |

### 4.2 Backward-compatible расширения canonical API

| Owner | Расширение | Совместимость |
|---|---|---|
| A5 | `resource_lifecycle_runtime_v1.gd: materialize_propagule(propagule, blueprint, paid_parent_state = {}, mutation_receipt = {}, parent_blueprint = {})` | Без receipt — прежний v1 witness (бит 1:1); с receipt — `validate_mutated_parent_transfer` (LS): receipt binding + полный v1 witness против реконструированного parent blueprint. Fail-closed, fallback отсутствует. |
| LS | `organism_life_state_v1.gd`: опциональный ключ `mutation_receipt` (schema `dws.ecology.parent-transfer-mutation.v1`, `{receipt, parent_genome}`) | Состояния без ключа сохраняют точный v1 key-set; каждая последующая валидация перепроверяет binding (durable provenance). Глубина canonical-энкодинга ограничивает цепочки подряд мутированных поколений (fail-closed при рождении — задокументировано в файле). |
| A6 | `persistent_environmental_feedback_v1.gd`: `advance_after_lifecycle(field, population, corpses, policy, step)` + shared statics `register_corpses`, `corpse_return_transition`, `mineralization_transition`, `balance_over`, `accounts_error`, `inventory`, `field_inventory` | Старый public `advance()` сохранён и исполняет ТЕ ЖЕ формулы через shared statics (zero behavior change; regression: arch2_a6_* suites PASS). Новый API не создаёт второго field/population truth. |
| A3 | Receipt contract ссылается на `Mutation.OPERATORS`/`biological_hash`; сама A3 без изменений | arch2_a03 suite PASS. |

### 4.3 Workbench (polygon) после ремонта

- `experiment_controller_v1.gd` — consumer runtime: единственное состояние `_runtime`; `_tick_once()` = `Runtime.step(...)`; WORLD_COMPAT gate сохранён до шага; `apply_field_patch`/`apply_world_stocks` → canonical owner-write API + `Runtime.adopt_field` (accounting re-anchor); checkpoint envelope несёт состояние runtime (старые pre-repair checkpoint-тексты отклоняются fail-closed — формат версионируется manifest_hash binding).
- `experiment_metrics_v1.gd` — emission `PARENT_TRANSFER_WITNESS_FALLBACK` удалён: мутация либо реально наследуется (applied, sealed receipt), либо canonical neutral (например оператор `none`).
- Тесты: `test_controller_equivalence.gd` переписан — oracle = явная композиция публичных примитивов EcologyRuntimeV1 (не копия orchestration); `test_runtime_single_state.gd` (новый) доказывает: A5 ровно один раз за tick; один field/одна population; mineralization меняет тот же field, который читает следующий A5; corpse return попадает в тот же canonical field; presentation/checkpoint видят то же состояние.


## 5. REPAIR R2 — closure of trust/persistence/world gaps

Ветка: `repair/eco-arch2-a10-5-polygon-r2`. Base: R1 retrain `8c42844e9`.

| Boundary | Canonical/shared owner | R2 composition |
|---|---|---|
| Single ecology truth | `ecology_runtime_v1.gd` | Polygon controller хранит только один `_runtime`; A5→receipt admission→A6 работают над тем же field/population |
| Heritable mutation | A3 + `genome_mutation_receipt_v1.gd` + A5 | Mutated child допускается только с sealed receipt; bias provenance входит как `bias_hash` |
| Development bias | `genome_mutation_v1.gd` | Versioned weights только над существующим `OPERATORS`; `organization_profile_v1.gd` лишь формирует canonical input |
| Runtime persistence | `ecology_runtime_checkpoint_v1.gd` | Shared checkpoint владеет `runtime_state + runtime_state_hash`; admission требует caller-owned text hash |
| Branch trust | `experiment_branch_v1.gd` | Внешний digest полного checkpoint record хранится отдельно; fully rehashed alternate checkpoint отвергается |
| WORLD-COMPAT persistence | `polygon_world_adapter_v1.gd` | Region/cursor/Matter mapping+batches/site/damage сохраняются как opaque canonical physical JSON envelope, привязанный hash'ами к shared checkpoint |
| Matter bridge | A10 `matter_resource_mapping_v1.gd` + A4 owner-write | Только new-batch delta; exact batch replay idempotent; multi-cell total без spatial allocation witness fail-closed |
| Damage trust | A10 `body_construction_binding_v1.gd` | `expected_event_binding_hash` хранится отдельно при trusted registration; apply не выводит expected anchor из event |
| Death E2E | A5 + A6 | Manifest `genesis.founder_endowment` задаёт явный experiment input; Polygon E2E наблюдает starvation death→corpse return→mineralization |
| Field bounds | A4 `FieldContract` | Controller использует `MAX_CELL_STOCK`, режет writes по `MAX_REQUEST` и коммитит genesis per-cell, не превышая `MAX_BATCH` |

### R2 trust chain

```text
caller-owned checkpoint anchor
        ↓
checkpoint state_text SHA-256
        ↓
shared EcologyRuntimeCheckpoint checksum
        ↓
Runtime.integrity_hash + Runtime.validate
        ↓
single field / population / feedback accounting

WORLD_COMPAT:
checkpoint.external_state_hash
        ↓
opaque world-state envelope digest
        ↓
physical canonical JSON state_hash/checksum
        ↓
Region + cursor + Matter admissions + damage trusted anchors
```

Это разделяет ownership: biological/runtime truth принадлежит shared ecology runtime; physical/world authority — существующим A10 contracts; workbench управляет экспериментом, но не создаёт параллельную biological/world truth.
