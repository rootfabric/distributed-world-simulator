extends SceneTree

const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_starvation_window_excludes_reproduction()
	print("EVO_ARCH2_A5_RM17 assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _genome() -> Dictionary:
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0, 20, 0], 1, 6000), P.action("retire")])
	var start := P.rule("start", [P.action("differentiate", "reproductive", [0, 10, 0], 1), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "start")
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 12, "max_depth": 2, "rules": [start, leaf]}, "RM-A5-17 starvation reproduction window witness")

func _policy() -> Dictionary:
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 5000
	policy.uptake.basal_nutrient_mg = 5000
	policy.uptake.basal_organic_mg = 5000
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 2500
	policy.growth.transfer_permille = 500
	policy.growth.max_transfer = B.stock(20000)
	policy.survival.starvation_limit_ticks = 3
	policy.reproduction.maturity_ticks = 1
	policy.reproduction.interval_ticks = 1
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = B.stock()
	policy.reproduction.fee_energy_mj = 0
	return policy

func _field(owner: String, stock: int) -> Dictionary:
	return Field.create(owner, 1, [0, 0, 0], 1000, 1, 1, F.stock(stock), F.stock(1000000), F.signals(900, 500, 0, 0))

func _starvation_window_excludes_reproduction() -> void:
	var blueprint := BP.create(_genome(), _policy())
	var entry := R.individual(blueprint, "rm17.parent", [500, 0, 500], B.stock(1000))
	_check(not blueprint.is_empty() and not entry.is_empty(), "starvation_window_entry_valid")
	if entry.is_empty(): return

	var rich := _field("rm17.rich.field", 900000)
	var reproduced := R.step_population(rich, [entry], rich.owner_token, rich.owner_epoch, rich.revision)
	_check(reproduced.success and reproduced.propagules.size() == 1 and reproduced.population[0].state.reproduction_count == 1, "reproduction_before_starvation_success")
	if not reproduced.success: return
	_check(LS.validate(reproduced.population[0].state, blueprint).is_empty(), "pre_starvation_reproduction_state_valid")

	var empty1 := _field("rm17.empty1.field", 0)
	var starved1 := R.step_population(empty1, reproduced.population, empty1.owner_token, empty1.owner_epoch, empty1.revision)
	_check(starved1.success and starved1.propagules.is_empty() and starved1.population[0].state.alive and starved1.population[0].state.starvation_ticks == 1, "first_unpaid_maintenance_tick_blocks_reproduction")
	if not starved1.success: return
	var state1: Dictionary = starved1.population[0].state
	_check(LS.validate(state1, blueprint).is_empty(), "first_starvation_boundary_state_valid")
	var impossible1: Dictionary = state1.duplicate(true)
	impossible1.next_reproduction_tick = 3
	_check(LS.validate(impossible1, blueprint) == "LIFE_REPRODUCTION_STARVATION_WINDOW", "reproduction_on_current_starvation_tick_rejected")
	_check(LS.serialize(impossible1, blueprint).is_empty(), "current_starvation_tick_history_not_serializable")

	var empty2 := _field("rm17.empty2.field", 0)
	var starved2 := R.step_population(empty2, starved1.population, empty2.owner_token, empty2.owner_epoch, empty2.revision)
	_check(starved2.success and starved2.propagules.is_empty() and starved2.population[0].state.alive and starved2.population[0].state.starvation_ticks == 2, "second_unpaid_maintenance_tick_blocks_reproduction")
	if not starved2.success: return
	var state2: Dictionary = starved2.population[0].state
	_check(LS.validate(state2, blueprint).is_empty(), "second_starvation_boundary_state_valid")
	var impossible2: Dictionary = state2.duplicate(true)
	impossible2.next_reproduction_tick = 3
	_check(LS.validate(impossible2, blueprint) == "LIFE_REPRODUCTION_STARVATION_WINDOW", "reproduction_inside_multi_tick_starvation_window_rejected")
	var last_reproduction_tick: int = state2.next_reproduction_tick - blueprint.life_history.reproduction.interval_ticks
	_check(last_reproduction_tick == state2.age_ticks - state2.starvation_ticks, "actual_history_stays_on_last_paid_boundary")

	var text := LS.serialize(state2, blueprint)
	_check(not text.is_empty(), "starvation_boundary_state_serializes")
	var restored := LS.deserialize(text)
	_check(not restored.is_empty() and LS.state_hash(restored.state, restored.blueprint) == LS.state_hash(state2, blueprint), "starvation_boundary_roundtrip_exact")
