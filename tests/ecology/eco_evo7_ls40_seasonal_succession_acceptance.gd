extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const SeasonalForcing = preload("res://scripts/ecology/shadow/eco_evo7_ls40_seasonal_forcing_v1.gd")
const StreamExecutor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")

const ECOLOGY_GENERATIONS := 6

class CorruptHashProvider:
	extends RefCounted

	func environment_for_generation(_generation_value: int, base_environment_field: Dictionary) -> Dictionary:
		var out: Dictionary = base_environment_field.duplicate(true)
		var cells: Array = out["cells"]
		var cell: Dictionary = cells[0]
		cell["soil_moisture"] = clampf(float(cell["soil_moisture"]) + 0.1, 0.0, 1.0)
		## Deliberately preserve the old cell_hash/field_hash.
		cells[0] = cell
		out["cells"] = cells
		return out

var assertions := 0
var failures: Array[String] = []
var temperate_founder_hash := ""

func _init() -> void:
	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth initializes")

	var seed_workbench = Workbench.new()
	_check(seed_workbench.setup(world), "seed Workbench initializes")
	var base_environment := seed_workbench.get_base_environment_field()
	_check(not base_environment.is_empty(), "Workbench exposes immutable LS4 base environment")

	_direct_forcing_contract(base_environment)
	_static_control_parity(world)
	var temperate_rows := _deterministic_temperate_replay(world)
	_counterfactual_divergence(world, temperate_rows)
	_stream1_compatibility(world, temperate_rows)
	_fail_closed_environment_proposal(world)
	_rehashed_static_tamper_rejected(seed_workbench, base_environment)
	_source_guards()

	world.queue_free()
	_finish()

func _direct_forcing_contract(base_environment: Dictionary) -> void:
	var static_forcing = SeasonalForcing.new()
	_check(static_forcing.setup("STATIC_CONTROL"), "STATIC_CONTROL forcing initializes")
	var static_field := static_forcing.environment_for_generation(1, base_environment)
	_check(not static_field.is_empty(), "STATIC_CONTROL produces a field")
	_check(String(static_field.get("field_hash", "")) == String(base_environment.get("field_hash", "")),
		"STATIC_CONTROL preserves exact LS3.1 field hash")
	_check(static_field == base_environment, "STATIC_CONTROL is byte-semantic duplicate of frozen base field")

	var temperate = SeasonalForcing.new()
	var monsoon = SeasonalForcing.new()
	_check(temperate.setup("TEMPERATE_SEASONAL"), "temperate forcing initializes")
	_check(monsoon.setup("MONSOON_SEASONAL"), "monsoon forcing initializes")

	var temperate_hashes := {}
	var monsoon_hashes := {}
	for generation in SeasonalForcing.CYCLE_GENERATIONS:
		var generation_value := generation + 1
		var t := temperate.environment_for_generation(generation_value, base_environment)
		var m := monsoon.environment_for_generation(generation_value, base_environment)
		_check(temperate.validate_environment_field(t), "temperate phase %d remains LS3.1-valid" % generation_value)
		_check(monsoon.validate_environment_field(m), "monsoon phase %d remains LS3.1-valid" % generation_value)
		_check(temperate.validate_static_identity(base_environment, t), "temperate phase %d preserves static physical truth" % generation_value)
		_check(monsoon.validate_static_identity(base_environment, m), "monsoon phase %d preserves static physical truth" % generation_value)
		temperate_hashes[String(t.get("field_hash", ""))] = true
		monsoon_hashes[String(m.get("field_hash", ""))] = true

	_check(temperate_hashes.size() >= 6, "temperate cycle contains multiple deterministic physical states")
	_check(monsoon_hashes.size() >= 6, "monsoon cycle contains multiple deterministic physical states")

	var replay_a := temperate.environment_for_generation(9, base_environment)
	var replay_b := temperate.environment_for_generation(9, base_environment)
	_check(replay_a == replay_b, "same base/profile/generation replays exact derived field")
	_check(String(replay_a["field_hash"]) == String(replay_b["field_hash"]), "direct forcing replay hash is exact")

	var temperate_phase := temperate.environment_for_generation(10, base_environment)
	var monsoon_phase := monsoon.environment_for_generation(10, base_environment)
	_check(String(temperate_phase["field_hash"]) != String(monsoon_phase["field_hash"]),
		"different forcing profiles produce different physical inputs")
	var overlay := monsoon.get_last_overlay()
	_check(String(overlay.get("profile_id", "")) == "MONSOON_SEASONAL", "forcing metadata binds profile")
	_check(int(overlay.get("phase_index", -1)) == 9, "forcing metadata binds deterministic phase")
	_check(String(overlay.get("base_environment_field_hash", "")) == String(base_environment["field_hash"]),
		"forcing metadata binds immutable base field")
	_check(String(overlay.get("derived_environment_field_hash", "")) == String(monsoon_phase["field_hash"]),
		"forcing metadata binds derived field")
	_check(_all_false(Dictionary(overlay.get("authorities", {}))), "forcing metadata grants no write authority")

func _static_control_parity(world) -> void:
	var baseline = Workbench.new()
	var controlled = Workbench.new()
	_check(baseline.setup(world), "legacy baseline Workbench initializes")
	_check(controlled.setup(world), "STATIC_CONTROL Workbench initializes")
	var static_forcing = SeasonalForcing.new()
	_check(static_forcing.setup("STATIC_CONTROL"), "STATIC_CONTROL provider setup")
	_check(controlled.set_environment_forcing_provider(static_forcing), "STATIC_CONTROL provider attaches through public Workbench seam")

	for generation in 3:
		var a := baseline.advance_generations(1)
		var b := controlled.advance_generations(1)
		_check(not a.is_empty() and not b.is_empty(), "static parity generation %d completes" % (generation + 1))
		_check(_canonical_row(baseline) == _canonical_row(controlled),
			"STATIC_CONTROL preserves exact legacy canonical result generation %d" % (generation + 1))

func _deterministic_temperate_replay(world) -> Array[Dictionary]:
	var first = Workbench.new()
	var replay = Workbench.new()
	_check(first.setup(world), "temperate run A initializes")
	_check(replay.setup(world), "temperate run B initializes")
	var forcing_a = SeasonalForcing.new()
	var forcing_b = SeasonalForcing.new()
	_check(forcing_a.setup("TEMPERATE_SEASONAL"), "temperate provider A initializes")
	_check(forcing_b.setup("TEMPERATE_SEASONAL"), "temperate provider B initializes")
	_check(first.set_environment_forcing_provider(forcing_a), "temperate provider A attaches")
	_check(replay.set_environment_forcing_provider(forcing_b), "temperate provider B attaches")
	temperate_founder_hash = String(first.get_workbench_snapshot().get("hereditary_pool_hash", ""))
	_check(not temperate_founder_hash.is_empty(), "temperate founder hereditary pool is valid")
	_check(String(replay.get_workbench_snapshot().get("hereditary_pool_hash", "")) == temperate_founder_hash,
		"temperate replay starts from exact same founder heredity")

	var rows: Array[Dictionary] = []
	for generation in ECOLOGY_GENERATIONS:
		var a := first.advance_generations(1)
		var b := replay.advance_generations(1)
		_check(not a.is_empty() and not b.is_empty(), "temperate replay generation %d completes" % (generation + 1))
		var row_a := _canonical_row(first)
		var row_b := _canonical_row(replay)
		_check(row_a == row_b, "temperate replay generation %d is exact" % (generation + 1))
		rows.append(row_a.duplicate(true))
	return rows

func _counterfactual_divergence(world, temperate_rows: Array[Dictionary]) -> void:
	var monsoon = Workbench.new()
	_check(monsoon.setup(world), "monsoon counterfactual initializes")
	var forcing = SeasonalForcing.new()
	_check(forcing.setup("MONSOON_SEASONAL"), "monsoon counterfactual provider initializes")
	_check(monsoon.set_environment_forcing_provider(forcing), "monsoon provider attaches")

	var initial_heredity := String(monsoon.get_workbench_snapshot().get("hereditary_pool_hash", ""))
	_check(initial_heredity == temperate_founder_hash,
		"seasonal counterfactuals start from exact same founder heredity")
	var environment_diverged := false
	var ecology_diverged := false
	for generation in ECOLOGY_GENERATIONS:
		var result := monsoon.advance_generations(1)
		_check(not result.is_empty(), "monsoon generation %d completes" % (generation + 1))
		var row := _canonical_row(monsoon)
		var reference: Dictionary = temperate_rows[generation]
		if String(row["environment_field_hash"]) != String(reference["environment_field_hash"]):
			environment_diverged = true
		if (
			String(row["recruitment_hash"]) != String(reference["recruitment_hash"])
			or String(row["competition_hash"]) != String(reference["competition_hash"])
			or String(row["population_hash"]) != String(reference["population_hash"])
			or String(row["hereditary_pool_hash"]) != String(reference["hereditary_pool_hash"])
		):
			ecology_diverged = true

	_check(environment_diverged, "counterfactual seasonal profiles create different physical forcing")
	_check(ecology_diverged, "same founders under different seasonal forcing produce causal ecology divergence")
	_check(not initial_heredity.is_empty(), "counterfactual begins from a valid founder hereditary pool")

func _stream1_compatibility(world, serial_rows: Array[Dictionary]) -> void:
	var streamed = Workbench.new()
	_check(streamed.setup(world), "STREAM1 + LS4 Workbench initializes")
	var forcing = SeasonalForcing.new()
	_check(forcing.setup("TEMPERATE_SEASONAL"), "STREAM1 + LS4 forcing initializes")
	_check(streamed.set_environment_forcing_provider(forcing), "STREAM1 + LS4 forcing attaches")

	var executor = StreamExecutor.new()
	_check(executor.setup({
		"parents_per_chunk": 7,
		"audit_interval": 10,
		"audit_generation_1": true,
	}), "STREAM1 executor initializes for LS4")
	_check(streamed.set_generation_stream_executor(executor), "STREAM1 executor attaches beside LS4 forcing")

	var exact := 0
	for generation in ECOLOGY_GENERATIONS:
		var result := streamed.advance_generations(1)
		_check(not result.is_empty(), "STREAM1 + LS4 generation %d completes" % (generation + 1))
		if _canonical_row(streamed) == serial_rows[generation]:
			exact += 1
	_check(exact == ECOLOGY_GENERATIONS,
		"STREAM1 preserves exact LS4 seasonal canonical results %d/%d" % [exact, ECOLOGY_GENERATIONS])
	print("LS4.0 STREAM1 seasonal exact comparisons: %d/%d" % [exact, ECOLOGY_GENERATIONS])

func _fail_closed_environment_proposal(world) -> void:
	var wb = Workbench.new()
	_check(wb.setup(world), "fail-closed Workbench initializes")
	var corrupt = CorruptHashProvider.new()
	_check(wb.set_environment_forcing_provider(corrupt), "corrupt provider attaches to proposal seam")
	var before_workbench := wb.get_workbench_snapshot()
	var before_ecology := wb.get_ecology_snapshot()
	var before_environment := wb.get_environment_field()
	var result := wb.advance_generations(1)
	_check(result.is_empty(), "corrupt seasonal proposal is rejected")
	var after_workbench := wb.get_workbench_snapshot()
	var after_ecology := wb.get_ecology_snapshot()
	_check(int(after_workbench.get("generation", -1)) == 0, "corrupt seasonal proposal cannot advance generation")
	_check(String(after_workbench.get("environment_field_hash", "")) == String(before_workbench.get("environment_field_hash", "")),
		"corrupt seasonal proposal cannot change Workbench environment")
	_check(String(after_ecology.get("state_hash", "")) == String(before_ecology.get("state_hash", "")),
		"corrupt seasonal proposal cannot mutate ecology state")
	_check(String(after_ecology.get("postcompetition_population_hash", "")) == String(before_ecology.get("postcompetition_population_hash", "")),
		"corrupt seasonal proposal cannot mutate postcompetition population hash")
	_check(String(after_ecology.get("hereditary_pool_hash", "")) == String(before_ecology.get("hereditary_pool_hash", "")),
		"corrupt seasonal proposal cannot mutate hereditary pool")
	_check(wb.get_environment_field() == before_environment, "corrupt seasonal proposal leaves exact field bytes unchanged")

func _rehashed_static_tamper_rejected(seed_workbench, base_environment: Dictionary) -> void:
	var forcing = SeasonalForcing.new()
	_check(forcing.setup("TEMPERATE_SEASONAL"), "static-tamper forcing initializes")
	var valid_dynamic := forcing.environment_for_generation(1, base_environment)
	_check(not valid_dynamic.is_empty(), "valid dynamic field exists for static-tamper case")

	var tampered: Dictionary = valid_dynamic.duplicate(true)
	var cells: Array = tampered["cells"]
	var cell: Dictionary = cells[0]
	cell["elevation_m"] = float(cell["elevation_m"]) + 1.0
	var env_validator = EnvironmentField.new()
	cell["cell_hash"] = env_validator.call("_cell_hash", cell)
	cells[0] = cell
	tampered["cells"] = cells
	tampered["field_hash"] = env_validator.call("_field_hash", tampered)
	_check(forcing.validate_environment_field(tampered), "rehashed static tamper is internally LS3.1-valid")
	_check(not forcing.validate_static_identity(base_environment, tampered),
		"LS4 detects rehashed terrain/static-identity tamper")

	var core = LS33.new()
	_check(core.setup(
		seed_workbench.get_patch(), base_environment,
		Workbench.FOUNDER_SEED, Workbench.PLACEMENT_SEED,
		Workbench.EVOLUTION_SEED, Workbench.INITIAL_RECORDS
	), "direct LS3.3 static-fence case initializes")
	var before := core.get_snapshot()
	_check(not core.set_environment_field(tampered), "LS3.3 rejects rehashed static physical tamper")
	var after := core.get_snapshot()
	_check(String(after.get("state_hash", "")) == String(before.get("state_hash", "")),
		"LS3.3 static-tamper rejection preserves state hash")
	_check(String(after.get("population_hash", "")) == String(before.get("population_hash", "")),
		"LS3.3 static-tamper rejection preserves population hash")

func _canonical_row(wb) -> Dictionary:
	var workbench := wb.get_workbench_snapshot()
	var ecology := wb.get_ecology_snapshot()
	return {
		"generation": int(workbench.get("generation", -1)),
		"environment_field_hash": String(workbench.get("environment_field_hash", "")),
		"ecology_state_hash": String(workbench.get("ecology_state_hash", "")),
		"population_hash": String(workbench.get("population_hash", "")),
		"hereditary_pool_hash": String(workbench.get("hereditary_pool_hash", "")),
		"classification_hash": String(workbench.get("classification_hash", "")),
		"candidate_pool_hash": String(ecology.get("candidate_pool_hash", "")),
		"dispersal_pool_hash": String(ecology.get("dispersal_pool_hash", "")),
		"recruitment_hash": String(ecology.get("recruitment_hash", "")),
		"competition_hash": String(ecology.get("competition_hash", "")),
	}

func _all_false(value: Dictionary) -> bool:
	if value.is_empty():
		return false
	for flag in value.values():
		if typeof(flag) != TYPE_BOOL or bool(flag):
			return false
	return true

func _source_guards() -> void:
	var forcing_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/shadow/eco_evo7_ls40_seasonal_forcing_v1.gd")
	var forcing_lower := forcing_source.to_lower()
	_check(not forcing_source.contains(".step_generation("), "LS4 forcing cannot advance ecology")
	_check(not forcing_source.contains("reproduce_bundle("), "LS4 forcing owns no reproduction")
	_check(not forcing_lower.contains("mutation_seed") and not forcing_lower.contains("dispersal_seed"),
		"LS4 forcing owns no mutation/dispersal identity")
	_check(not forcing_lower.contains("fileaccess") and not forcing_lower.contains("diraccess") and not forcing_lower.contains("multiplayer"),
		"LS4 forcing owns no persistence/network path")
	for forbidden_label in ["desert-like", "wetland-like", "forest-like", "grass/shrub-like", "alpine-like", "ecotone"]:
		_check(not forcing_lower.contains(forbidden_label), "LS4 forcing never reads post-hoc biome label %s" % forbidden_label)

	var ls33_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
	var setter_start := ls33_source.find("func set_environment_field(")
	var setter_end := ls33_source.find("\nfunc ", setter_start + 1)
	var setter_body := ls33_source.substr(setter_start, setter_end - setter_start)
	_check(setter_start >= 0 and setter_end > setter_start, "LS3.3 exposes one bounded environment setter")
	_check(not setter_body.contains("generation =") and not setter_body.contains("records ="),
		"LS3.3 environment setter cannot advance or replace population")
	_check(setter_body.contains("STATIC_ENVIRONMENT_CELL_FIELDS"),
		"LS3.3 environment setter enforces static physical identity")

	var ls34_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
	_check(ls34_source.count("func set_environment_field(") == 1,
		"LS3.4 exposes exactly one LS4 environment pass-through")
	var workbench_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
	_check(workbench_source.count("func set_environment_forcing_provider(") == 1,
		"Workbench exposes exactly one LS4 forcing provider seam")
	_check(workbench_source.count(".environment_for_generation(") == 1,
		"Workbench has exactly one seasonal proposal call site")

	var observatory_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd")
	_check(observatory_source.contains('String(ecology_snapshot.get("environment_field_hash", "")) != current_environment_hash'),
		"spatial observatory binds every dynamic environment to exact ecology snapshot")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 LS4.0 Seasonal Forcing / Succession: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LS4.0 FAIL: %s" % failure)
	print("ECO.EVO7 LS4.0 Seasonal Forcing / Succession: FAIL (%d assertions, %d failures)" % [
		assertions, failures.size()
	])
	quit(1)
