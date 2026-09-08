extends SceneTree
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
var passed := 0
var failed := 0

func _init() -> void:
	_regulation_freezes_prepaid_a2()
	_unpaid_maintenance_blocks_reproduction()
	_propagule_endowment_bound()
	_bounded_demand_ids()
	_deferred_reproduction_schedule()
	_offspring_counter_range()
	_propagule_sequence_continuity()
	_propagule_parent_binding()
	_cumulative_ledger_capacity()
	print("EVO_ARCH2_A5_REPAIRS assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(v: bool, name: String) -> void:
	if v: passed += 1
	else: failed += 1; push_error("FAIL:" + name)

func _field(owner: String, stock: int, light: int) -> Dictionary:
	return Field.create(owner, 1, [0,0,0], 1000, 1, 1, F.stock(stock), F.stock(1000000), F.signals(light, 500, 0, 0))

func _policy() -> Dictionary:
	var p := LH.create_default()
	p.uptake.basal_water_mg = 5000; p.uptake.basal_nutrient_mg = 5000; p.uptake.basal_organic_mg = 5000
	p.uptake.water_per_absorber_unit_mg = 0; p.uptake.nutrient_per_absorber_unit_mg = 0; p.uptake.organic_per_absorber_unit_mg = 0
	p.metabolism.maintenance_energy_per_module_mj = 2; p.metabolism.maintenance_water_per_module_mg = 1
	p.metabolism.photosynthesis_area_divisor_mm2 = 4; p.metabolism.photosynthesis_water_saturation_mg = 500
	p.growth.transfer_permille = 500; p.growth.max_transfer = B.stock(20000)
	return p

func _zero_cost_reproduction_policy() -> Dictionary:
	var p := _policy()
	p.reproduction.maturity_ticks = 1
	p.reproduction.interval_ticks = 1
	p.reproduction.endowment = B.stock()
	p.reproduction.fee_energy_mj = 0
	return p

func _reproductive_genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0,20,0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0,10,0], 1), P.action("branch", "support", [0,0,0], 0,0,0, "leaf")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "A5 reviewer repair witness")

func _step(field: Dictionary, population: Array) -> Dictionary:
	return R.step_population(field, population, field.owner_token, field.owner_epoch, field.revision)

func _emitted_propagule(parent_id: String = "repair.propagule.parent") -> Dictionary:
	var blueprint := BP.create(_reproductive_genome(), _zero_cost_reproduction_policy())
	var parent := R.individual(blueprint, parent_id, [500,0,500], B.stock(30000))
	if parent.is_empty(): return {}
	var reproduced := _step(_field("repair.propagule.rich", 900000, 900), [parent])
	if not reproduced.success or reproduced.propagules.is_empty(): return {}
	return {"blueprint": blueprint, "parent": parent, "result": reproduced, "propagule": reproduced.propagules[0]}

func _regulation_freezes_prepaid_a2() -> void:
	var blueprint := BP.create(Fixtures.make(5), _policy())
	var entry := R.individual(blueprint, "repair.regulation", [500,0,500], B.stock(30000))
	var rich := _step(_field("repair.reg.rich", 800000, 900), [entry])
	_check(rich.success and rich.population[0].state.development.reserves.material_mg > 0, "prepaid_a2_residual_exists")
	var before := C.digest(rich.population[0].state.development)
	var dark := _step(_field("repair.reg.dark", 800000, 0), rich.population)
	_check(dark.success, "dark_step_success")
	_check(C.digest(dark.population[0].state.development) == before, "dark_gate_freezes_a2_advancement")

func _unpaid_maintenance_blocks_reproduction() -> void:
	var p := _policy()
	p.metabolism.maintenance_water_per_module_mg = 2500
	p.survival.starvation_limit_ticks = 3
	p.reproduction.maturity_ticks = 2; p.reproduction.interval_ticks = 1
	p.reproduction.endowment = B.stock(); p.reproduction.fee_energy_mj = 0
	var blueprint := BP.create(_reproductive_genome(), p)
	var parent := R.individual(blueprint, "repair.maintenance", [500,0,500], B.stock(1000))
	var prepared := _step(_field("repair.maintenance.rich", 900000, 900), [parent])
	_check(prepared.success and int(H.compile(prepared.population[0].state.development, blueprint.genome).module_roles.get("reproductive", 0)) >= 1, "reproductive_parent_prepared")
	var starved := _step(_field("repair.maintenance.starve", 0, 900), prepared.population)
	_check(starved.success and starved.population[0].state.alive and starved.population[0].state.starvation_ticks == 1, "maintenance_unpaid_but_parent_alive")
	_check(starved.propagules.is_empty() and starved.population[0].state.reproduction_count == 0, "unpaid_maintenance_no_reproduction")

func _propagule_endowment_bound() -> void:
	var emitted := _emitted_propagule()
	_check(not emitted.is_empty() and R.validate_propagule(emitted.propagule, emitted.blueprint).is_empty(), "correct_endowment_valid")
	var tampered: Dictionary = emitted.propagule.duplicate(true)
	tampered.endowment.material_mg += 1
	_check(R.validate_propagule(tampered, emitted.blueprint) == "PROPAGULE_ENDOWMENT" and R.materialize_propagule(tampered, emitted.blueprint).is_empty(), "tampered_endowment_rejected")

func _bounded_demand_ids() -> void:
	var blueprint := BP.create(Fixtures.make(5), _policy())
	var id_a := "a".repeat(128)
	var id_b := "a".repeat(127) + "b"
	var entry_a := R.individual(blueprint, id_a, [500,0,500], B.stock(30000))
	var entry_b := R.individual(blueprint, id_b, [500,0,500], B.stock(30000))
	_check(not entry_a.is_empty() and not entry_b.is_empty(), "max_length_individual_ids_valid")
	var phenotype_a := H.compile(entry_a.state.development, blueprint.genome)
	var phenotype_b := H.compile(entry_b.state.development, blueprint.genome)
	var demands_a := R._demands(entry_a.state, blueprint, phenotype_a)
	var demands_b := R._demands(entry_b.state, blueprint, phenotype_b)
	var valid := not demands_a.is_empty() and not demands_b.is_empty()
	var ids_a := {}
	var ids_b := {}
	for demand in demands_a:
		valid = valid and demand.request_id.length() <= 128 and Ports.validate_demand(demand).is_empty()
		ids_a[demand.request_id] = true
	for demand in demands_b:
		valid = valid and demand.request_id.length() <= 128 and Ports.validate_demand(demand).is_empty()
		ids_b[demand.request_id] = true
	_check(valid, "max_length_generated_demand_ids_bounded_and_valid")
	var overlap := false
	for request_id in ids_a:
		if ids_b.has(request_id): overlap = true
	_check(not overlap, "distinct_max_length_organisms_have_distinct_demand_ids")
	var result := _step(_field("repair.longids", 900000, 900), [entry_b, entry_a])
	_check(result.success and result.population.size() == 2, "max_length_ids_shared_population_step_success")

func _deferred_reproduction_schedule() -> void:
	var p := _policy()
	p.reproduction.maturity_ticks = 1
	p.reproduction.interval_ticks = 1000000
	p.reproduction.endowment = B.stock()
	p.reproduction.fee_energy_mj = 0
	var blueprint := BP.create(_reproductive_genome(), p)
	var entry := R.individual(blueprint, "repair.schedule", [500,0,500], B.stock(30000))
	_check(not entry.is_empty(), "max_interval_schedule_parent_valid")
	var reproduced := _step(_field("repair.schedule.rich", 900000, 900), [entry])
	_check(reproduced.success and reproduced.population[0].state.next_reproduction_tick == 1000001, "max_interval_absolute_schedule_preserved")
	_check(reproduced.success and LS.validate(reproduced.population[0].state, blueprint).is_empty(), "deferred_schedule_state_valid")

func _offspring_counter_range() -> void:
	var p := _policy()
	p.reproduction.maturity_ticks = 1
	p.reproduction.interval_ticks = 1
	p.reproduction.offspring_per_event = 4
	p.reproduction.endowment = B.stock()
	p.reproduction.fee_energy_mj = 0
	var blueprint := BP.create(_reproductive_genome(), p)
	var initial := R.individual(blueprint, "repair.counter", [500,0,500], B.stock(30000))
	var prepared := _step(_field("repair.counter.rich", 900000, 900), [initial])
	var entry: Dictionary = prepared.population[0] if prepared.success else {}
	if not entry.is_empty():
		entry.state.age_ticks = 250001
		entry.state.reproduction_count = 1000000
		entry.state.propagule_seq = 1000000
		entry.state.next_reproduction_tick = 250001
	_check(not entry.is_empty() and LS.validate(entry.state, blueprint).is_empty(), "million_offspring_boundary_state_valid")
	var reproduced := R._reproduce(entry.state, blueprint, blueprint.life_history) if not entry.is_empty() else {"success": false}
	_check(reproduced.success and reproduced.state.reproduction_count == 1000004 and reproduced.state.propagule_seq == 1000004, "four_offspring_cross_million_counter")
	_check(reproduced.success and LS.validate(reproduced.state, blueprint).is_empty(), "expanded_offspring_counter_state_valid")

func _propagule_sequence_continuity() -> void:
	var blueprint := BP.create(_reproductive_genome(), _policy())
	var entry := R.individual(blueprint, "repair.sequence", [500,0,500], B.stock())
	_check(not entry.is_empty(), "sequence_base_state_valid")
	var tampered: Dictionary = entry.state.duplicate(true)
	tampered.propagule_seq = 1
	_check(LS.validate(tampered, blueprint) == "LIFE_PROPAGULE_SEQUENCE", "sequence_divergence_rejected")
	var causal: Dictionary = entry.state.duplicate(true)
	causal.age_ticks = 1; causal.reproduction_count = 5; causal.propagule_seq = 5
	_check(LS.validate(causal, blueprint) == "LIFE_REPRODUCTION_CAUSALITY", "offspring_causality_bound")
	var emitted := _emitted_propagule("repair.sequence.parent")
	var expected_prefix := "seed/%s/" % String(emitted.propagule.parent_id).sha256_text()
	_check(not emitted.is_empty() and String(emitted.propagule.id).begins_with(expected_prefix) and String(emitted.propagule.id).length() <= 128, "full_digest_seed_identity_bounded")

func _propagule_parent_binding() -> void:
	var emitted := _emitted_propagule("repair.binding.parent")
	var p: Dictionary = emitted.propagule
	_check(not emitted.is_empty() and p.id == R._propagule_id(p.parent_id, p.sequence) and R.validate_propagule(p, emitted.blueprint).is_empty(), "propagule_parent_sequence_identity_valid")
	var wrong_parent: Dictionary = p.duplicate(true)
	wrong_parent.parent_id = "repair.binding.other"
	_check(R.validate_propagule(wrong_parent, emitted.blueprint) == "PROPAGULE_IDENTITY", "propagule_parent_tamper_rejected")
	var wrong_sequence: Dictionary = p.duplicate(true)
	wrong_sequence.sequence += 1
	_check(R.validate_propagule(wrong_sequence, emitted.blueprint) == "PROPAGULE_IDENTITY", "propagule_sequence_tamper_rejected")

func _cumulative_ledger_capacity() -> void:
	var cumulative := B.stock()
	cumulative.material_mg = B.MAX_STOCK
	var one := B.stock()
	one.material_mg = 1
	_check(R._add_cumulative_stock(cumulative, one) and cumulative.material_mg == B.MAX_STOCK + 1, "cumulative_stock_crosses_current_stock_bound")
	var reserve := B.stock()
	reserve.material_mg = B.MAX_STOCK
	_check(not R._add_reserve_stock(reserve, one) and reserve.material_mg == B.MAX_STOCK, "instantaneous_reserve_bound_preserved")
	var blueprint := BP.create(Fixtures.make(0), _policy())
	var entry := R.individual(blueprint, "repair.cumulative", [500,0,500], B.stock())
	var ledger: Dictionary = entry.state.resource_ledger.duplicate(true)
	ledger.assimilated.material_mg = B.MAX_STOCK + 1
	ledger.field_intake.nutrient_mg = B.MAX_STOCK + 1
	ledger.assimilated.energy_mj = B.MAX_STOCK + 1
	ledger.external_energy_mj = B.MAX_STOCK + 1
	_check(LS._valid_ledger(ledger), "cumulative_ledger_accepts_lifecycle_totals_above_current_stock")
	var too_high := B.stock()
	too_high.material_mg = C.MAX_INT + 1
	_check(not LS.valid_cumulative_stock(too_high), "cumulative_ledger_rejects_above_canonical_int")
