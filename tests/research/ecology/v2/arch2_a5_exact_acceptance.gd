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
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
var passed := 0
var failed := 0

func _init() -> void:
	_contracts_and_accounting()
	_regulatory_growth()
	_resource_funded_survival()
	_resource_funded_reproduction()
	_population_contention_determinism()
	_restart_replay()
	print("EVO_ARCH2_A5_EXACT assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _field(owner: String, stock: int, light: int = 800, competition: int = 0) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(stock), F.stock(1000000), F.signals(light, 500, competition, 0))

func _policy_fast() -> Dictionary:
	var p := LH.create_default()
	p.uptake.basal_water_mg = 5000
	p.uptake.basal_nutrient_mg = 5000
	p.uptake.basal_organic_mg = 5000
	p.uptake.water_per_absorber_unit_mg = 0
	p.uptake.nutrient_per_absorber_unit_mg = 0
	p.uptake.organic_per_absorber_unit_mg = 0
	p.metabolism.maintenance_energy_per_module_mj = 2
	p.metabolism.maintenance_water_per_module_mg = 1
	p.metabolism.photosynthesis_area_divisor_mm2 = 4
	p.metabolism.photosynthesis_water_saturation_mg = 500
	p.growth.transfer_permille = 500
	p.growth.max_transfer = B.stock(20000)
	p.reproduction.maturity_ticks = 2
	p.reproduction.interval_ticks = 20
	p.reproduction.endowment = {"material_mg": 1200, "water_mg": 800, "energy_mj": 600}
	p.reproduction.fee_energy_mj = 100
	return p

func _reproductive_genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0, 20, 0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [
		P.action("differentiate", "reproductive", [0, 10, 0], 1),
		P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf"),
	], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "A5 reproductive witness")

func _step(field: Dictionary, population: Array) -> Dictionary:
	return R.step_population(field, population, field.owner_token, field.owner_epoch, field.revision)

func _contracts_and_accounting() -> void:
	var policy := LH.create_default()
	_check(LH.validate(policy).is_empty(), "life_history_valid")
	var malformed := policy.duplicate(true); malformed.growth.transfer_permille = 1001
	_check(LH.validate(malformed) == "LIFE_HISTORY_GROWTH", "life_history_fail_closed")
	var blueprint := BP.create(Fixtures.make(0), policy)
	_check(BP.validate(blueprint).is_empty() and BP.biological_hash(blueprint).length() == 64, "blueprint_valid_hash")
	var bp_text := BP.serialize(blueprint); var bp_restored := BP.deserialize(bp_text)
	_check(not bp_restored.is_empty() and BP.biological_hash(bp_restored) == BP.biological_hash(blueprint), "blueprint_roundtrip")
	var endowment := {"material_mg": 20000, "water_mg": 12000, "energy_mj": 9000}
	var entry := R.individual(blueprint, "org.contract", [500, 0, 500], endowment)
	_check(not entry.is_empty() and LS.validate(entry.state, blueprint).is_empty(), "life_state_valid")
	_check(entry.state.development.received == B.stock() and entry.state.resource_ledger.initial == endowment, "no_free_a2_founder_resources")
	var text := LS.serialize(entry.state, blueprint); var restored := LS.deserialize(text)
	_check(not restored.is_empty() and LS.state_hash(restored.state, restored.blueprint) == LS.state_hash(entry.state, blueprint), "life_state_roundtrip")
	var field := _field("research.a5.contract", 500000)
	var result := _step(field, [entry])
	_check(result.success and result.field.ledger.outputs.water_mg > 0 and result.field.ledger.outputs.nutrient_mg > 0 and result.field.ledger.outputs.organic_mg > 0, "actual_a4_field_grants_consumed")
	var next: Dictionary = result.population[0].state
	_check(next.resource_ledger.assimilated.material_mg == result.field.ledger.outputs.nutrient_mg + result.field.ledger.outputs.organic_mg, "field_mass_maps_to_organism_material")
	_check(next.resource_ledger.assimilated.water_mg == result.field.ledger.outputs.water_mg, "field_water_maps_exactly")
	_check(next.resource_ledger.field_intake.water_mg == result.field.ledger.outputs.water_mg and next.resource_ledger.external_energy_mj == next.resource_ledger.assimilated.energy_mj, "field_and_external_energy_sources_explicit")
	_check(LS.validate(next, blueprint).is_empty(), "organism_resource_conservation")
	_check(next.resource_ledger.growth_transferred == next.development.received, "a2_growth_only_from_a5_transfer")
	var cross_tamper := next.duplicate(true)
	cross_tamper.resource_ledger.growth_transferred.material_mg += 1
	cross_tamper.metabolic_reserves.material_mg -= 1
	_check(LS.validate(cross_tamper, blueprint) == "LIFE_A2_TRANSFER_material_mg", "cross_ledger_a2_transfer_tamper_rejected")

func _regulatory_growth() -> void:
	var policy := _policy_fast()
	var blueprint := BP.create(Fixtures.make(5), policy)
	var endowment := B.stock(30000)
	var rich_entry := R.individual(blueprint, "org.rich", [500, 0, 500], endowment)
	var dark_entry := R.individual(blueprint, "org.dark", [500, 0, 500], endowment)
	var rich_field := _field("research.a5.rich", 800000, 900, 0)
	var dark_field := _field("research.a5.dark", 800000, 0, 0)
	for _tick in 4:
		var rr := _step(rich_field, [rich_entry]); _check(rr.success, "rich_step_success"); rich_field = rr.field; rich_entry = rr.population[0]
		var dr := _step(dark_field, [dark_entry]); _check(dr.success, "dark_step_success"); dark_field = dr.field; dark_entry = dr.population[0]
	var rich_p := H.compile(rich_entry.state.development, blueprint.genome)
	var dark_p := H.compile(dark_entry.state.development, blueprint.genome)
	_check(rich_entry.state.alive and dark_entry.state.alive, "regulation_not_forced_selection")
	_check(rich_entry.state.resource_ledger.growth_transferred.material_mg > dark_entry.state.resource_ledger.growth_transferred.material_mg, "environment_regulates_growth_budget")
	_check(rich_p.statistics.module_count > dark_p.statistics.module_count, "same_blueprint_environment_changes_body_growth")
	_check(dark_entry.state.development.spent.material_mg == 0, "dark_growth_suppressed_without_hidden_geometry")

func _resource_funded_survival() -> void:
	var policy := LH.create_default(); policy.survival.starvation_limit_ticks = 2
	var blueprint := BP.create(Fixtures.make(0), policy)
	var starved := R.individual(blueprint, "org.starved", [500, 0, 500], B.stock())
	var empty_field := _field("research.a5.starve", 0, 0, 0)
	var first := _step(empty_field, [starved]); _check(first.success and first.population[0].state.alive, "starvation_first_tick_survives")
	var second := _step(first.field, first.population); _check(second.success and not second.population[0].state.alive, "starvation_limit_causes_death")
	_check(second.population[0].state.reproduction_count == 0 and second.population.size() == 1, "death_not_topk_population_deletion")
	_check(second.population[0].state.development.modules.size() == 1, "unfunded_organism_cannot_create_body")
	var rich := R.individual(blueprint, "org.survivor", [500, 0, 500], B.stock(5000))
	var rich_field := _field("research.a5.survive", 500000, 800, 0)
	for _tick in 3:
		var r := _step(rich_field, [rich]); _check(r.success, "survival_rich_step"); rich_field = r.field; rich = r.population[0]
	_check(rich.state.alive and rich.state.starvation_ticks == 0, "funded_survival")

func _resource_funded_reproduction() -> void:
	var policy := _policy_fast()
	var blueprint := BP.create(_reproductive_genome(), policy)
	_check(BP.validate(blueprint).is_empty(), "reproductive_blueprint_valid")
	var parent := R.individual(blueprint, "org.parent", [500, 0, 500], B.stock(1000))
	var field := _field("research.a5.repro", 900000, 900, 0)
	var emitted: Array = []
	var paid_parent_states: Array = []
	for _tick in 5:
		var r := _step(field, [parent]); _check(r.success, "reproduction_step_success"); field = r.field; parent = r.population[0]
		for p in r.propagules:
			emitted.append(p)
			paid_parent_states.append(parent.state.duplicate(true))
	_check(parent.state.reproduction_count >= 1 and not emitted.is_empty(), "mature_funded_parent_reproduces")
	var first: Dictionary = emitted[0]
	var paid_parent_state: Dictionary = paid_parent_states[0]
	_check(R.validate_propagule(first, blueprint, paid_parent_state).is_empty(), "propagule_contract_valid")
	var expected: Dictionary = policy.reproduction.endowment
	_check(parent.state.resource_ledger.reproduction_transferred.material_mg >= expected.material_mg and parent.state.resource_ledger.reproduction_cost.energy_mj >= policy.reproduction.fee_energy_mj, "parent_pays_reproduction_before_emit")
	var child := R.materialize_propagule(first, blueprint, paid_parent_state)
	_check(not child.is_empty() and child.state.origin_kind == "PARENT_TRANSFER", "propagule_materializes_child")
	_check(child.state.metabolic_reserves == expected and child.state.resource_ledger.initial == expected, "child_endowment_exactly_parent_funded")
	_check(child.state.development.received == B.stock(), "child_body_has_no_free_resources")
	var poor := R.individual(blueprint, "org.poorparent", [500,0,500], B.stock(1000))
	var poor_field := _field("research.a5.poorrepro", 0, 900, 0)
	var poor_emitted := 0
	for _tick in 4:
		var pr := _step(poor_field, [poor]); _check(pr.success, "poor_repro_step_success"); poor_field = pr.field; poor = pr.population[0]; poor_emitted += pr.propagules.size()
	_check(poor_emitted == 0 and poor.state.reproduction_count == 0, "same_blueprint_cannot_reproduce_without_resource_funding")

func _population_contention_determinism() -> void:
	var policy := LH.create_default(); policy.metabolism.maintenance_energy_per_module_mj = 0; policy.metabolism.maintenance_water_per_module_mg = 0; policy.growth.transfer_permille = 0
	policy.uptake.basal_water_mg = 100; policy.uptake.basal_nutrient_mg = 100; policy.uptake.basal_organic_mg = 100
	policy.uptake.water_per_absorber_unit_mg = 0; policy.uptake.nutrient_per_absorber_unit_mg = 0; policy.uptake.organic_per_absorber_unit_mg = 0
	var blueprint := BP.create(Fixtures.make(0), policy)
	var a := R.individual(blueprint, "org.a", [500,0,500], B.stock())
	var b := R.individual(blueprint, "org.b", [500,0,500], B.stock())
	var f1 := _field("research.a5.contend", 150, 0, 0)
	var f2 := f1.duplicate(true)
	var forward := _step(f1, [a,b]); var reverse := _step(f2, [b,a])
	_check(forward.success and reverse.success and forward.field_hash == reverse.field_hash, "population_input_order_independent_field")
	_check(forward.population.size() == 2 and reverse.population.size() == 2, "contention_keeps_population_members")
	var fh := {}; var rh := {}
	for e in forward.population: fh[e.state.individual_id] = LS.state_hash(e.state, e.blueprint)
	for e in reverse.population: rh[e.state.individual_id] = LS.state_hash(e.state, e.blueprint)
	_check(fh == rh, "population_input_order_independent_life_states")
	_check(forward.population[0].state.resource_ledger.assimilated.water_mg == 75 and forward.population[1].state.resource_ledger.assimilated.water_mg == 75, "shared_resource_contention_is_pro_rata")
	var crowd: Array = []
	for i in 128:
		crowd.append(R.individual(blueprint, "crowd.%03d" % i, [500,0,500], B.stock()))
	var crowd_field := _field("research.a5.crowd", 1000000, 0, 0)
	var crowded := _step(crowd_field, crowd)
	_check(crowded.success and crowded.population.size() == 128, "bounded_128_population_step")
	_check(crowded.field.ledger.outputs.water_mg == 12800 and crowded.field.ledger.outputs.nutrient_mg == 12800 and crowded.field.ledger.outputs.organic_mg == 12800, "bounded_population_exact_field_debit")
	_check(crowded.population[0].state.individual_id == "crowd.000" and crowded.population[127].state.individual_id == "crowd.127", "bounded_population_canonical_order")

func _restart_replay() -> void:
	var blueprint := BP.create(Fixtures.make(2), _policy_fast())
	var base_entry := R.individual(blueprint, "org.restart", [500,0,500], B.stock(25000))
	var base_field := _field("research.a5.restart", 700000, 850, 0)
	var uninterrupted_entry := base_entry.duplicate(true); var uninterrupted_field := base_field.duplicate(true)
	for _tick in 4:
		var u := _step(uninterrupted_field, [uninterrupted_entry]); _check(u.success, "uninterrupted_step"); uninterrupted_field = u.field; uninterrupted_entry = u.population[0]
	var interrupted_entry := base_entry.duplicate(true); var interrupted_field := base_field.duplicate(true)
	for _tick in 2:
		var i := _step(interrupted_field, [interrupted_entry]); _check(i.success, "pre_restart_step"); interrupted_field = i.field; interrupted_entry = i.population[0]
	var life_text := LS.serialize(interrupted_entry.state, blueprint); var field_text := F.serialize(interrupted_field)
	var life_restored := LS.deserialize(life_text); var field_restored := F.deserialize(field_text)
	_check(not life_restored.is_empty() and not field_restored.is_empty(), "restart_roundtrip_valid")
	var resumed := {"blueprint": life_restored.blueprint, "state": life_restored.state}
	for _tick in 2:
		var rr := _step(field_restored, [resumed]); _check(rr.success, "post_restart_step"); field_restored = rr.field; resumed = rr.population[0]
	_check(Field.state_hash(field_restored) == Field.state_hash(uninterrupted_field), "field_restart_equals_uninterrupted")
	_check(LS.state_hash(resumed.state, resumed.blueprint) == LS.state_hash(uninterrupted_entry.state, uninterrupted_entry.blueprint), "life_restart_equals_uninterrupted")