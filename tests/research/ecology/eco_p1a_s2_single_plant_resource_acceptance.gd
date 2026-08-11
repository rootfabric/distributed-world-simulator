extends SceneTree

const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

const EXPECTED_ENVIRONMENT_HASH := "b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7"
const EXPECTED_SIMULATION_HASH := "618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c"
const CONTROL_POINT_ORDER: Array[String] = [
	"river_bank",
	"floodplain",
	"wet_lowland",
	"lower_slope",
	"sunny_slope",
	"shaded_slope",
	"plateau",
	"dry_ridge",
]

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_parent_environment_baseline()
	_test_fixed_genome_contract()
	_test_resource_breakdown_and_niche()
	_test_patch_biomass_dynamics()
	_test_root_depth_tradeoff()
	_test_determinism_and_ownership_boundary()
	_finish()


func _test_parent_environment_baseline() -> void:
	var environment_hash := Fixture.environment_hash()
	_check(environment_hash == EXPECTED_ENVIRONMENT_HASH, "S1 accepted environment hash remains unchanged")
	_check(Fixture.ENVIRONMENT_REVISION == "ECO.P1A-S1.1", "S2 consumes accepted S1 environment revision")


func _test_fixed_genome_contract() -> void:
	var genome := PlantGenome.create_default()
	_ok(PlantGenome.validate(genome), "default fixed plant genome validates")
	_check(String(genome["genome_id"]) == PlantGenome.DEFAULT_GENOME_ID, "baseline genome id")
	_check(float(genome["height_m"]) > 0.0, "height is physical positive trait")
	_check(float(genome["root_depth_m"]) > 0.0, "root depth is physical positive trait")
	_check(int(genome["seed_count"]) > 0, "seed count is explicit trait")
	_check(String(PlantGenome.create_default()["checksum"]) == String(genome["checksum"]), "default genome checksum deterministic")

	var invalid_root := genome.duplicate(true)
	invalid_root["root_depth_m"] = -1.0
	invalid_root["checksum"] = PlantGenome.compute_checksum(invalid_root)
	_check(not _success(PlantGenome.validate(invalid_root)), "negative root depth rejected")

	var with_biome := genome.duplicate(true)
	with_biome["biome"] = "river"
	with_biome["checksum"] = PlantGenome.compute_checksum(with_biome)
	_check(not _success(PlantGenome.validate(with_biome)), "biome injection rejected by genome contract")


func _test_resource_breakdown_and_niche() -> void:
	var genome := PlantGenome.create_default()
	var balances := {}
	for name in CONTROL_POINT_ORDER:
		var environment := Fixture.control_point(name)
		var balance := ResourceModel.evaluate(environment, genome, 0.05)
		balances[name] = balance
		_ok(ResourceModel.validate(balance), "resource balance validates at %s" % name)
		_check(String(balance["environment_checksum"]) == String(environment["checksum"]), "%s binds environment checksum" % name)
		_check(String(balance["genome_checksum"]) == String(genome["checksum"]), "%s binds fixed genome checksum" % name)
		_check(float(balance["gross_photosynthetic_income"]) >= 0.0, "%s gross income non-negative" % name)
		for cost_name in [
			"maintenance_cost", "root_cost", "structural_cost", "growth_allocation_cost",
			"reproduction_allocation_cost", "water_stress_penalty", "flood_penalty", "density_cost",
		]:
			_check(float(balance[cost_name]) >= 0.0, "%s %s non-negative" % [name, cost_name])

	_check(String(balances["floodplain"]["viability_class"]) == "FAVOURABLE", "floodplain favourable for baseline genome")
	_check(String(balances["lower_slope"]["viability_class"]) == "FAVOURABLE", "lower slope favourable for baseline genome")
	_check(String(balances["sunny_slope"]["viability_class"]) == "MARGINAL", "sunny slope marginal for baseline genome")
	for name in ["river_bank", "wet_lowland", "shaded_slope", "plateau", "dry_ridge"]:
		_check(String(balances[name]["viability_class"]) == "UNSUSTAINABLE", "%s unsustainable for baseline genome" % name)

	_check(float(balances["wet_lowland"]["effective_soil_moisture"]) > float(balances["floodplain"]["effective_soil_moisture"]), "wet lowland is wetter than favourable floodplain")
	_check(float(balances["wet_lowland"]["water_stress_penalty"]) > float(balances["floodplain"]["water_stress_penalty"]), "too much water creates explicit stress")
	_check(float(balances["wet_lowland"]["flood_penalty"]) > float(balances["floodplain"]["flood_penalty"]), "flood-prone wet lowland has larger flood penalty")
	_check(float(balances["dry_ridge"]["water_stress_penalty"]) > 0.0, "dry ridge has explicit water stress")
	_check(String(balances["dry_ridge"]["dominant_limiting_factor"]) == "WATER", "dry ridge dominant limitation is water")
	_check(String(balances["river_bank"]["dominant_limiting_factor"]) == "FLOOD", "river bank dominant limitation is flood")
	_check(String(balances["shaded_slope"]["dominant_limiting_factor"]) == "LIGHT", "shaded slope dominant limitation is light")


func _test_patch_biomass_dynamics() -> void:
	var genome := PlantGenome.create_default()
	var simulations := {}
	for name in CONTROL_POINT_ORDER:
		var simulation := PatchSimulator.simulate(Fixture.control_point(name), genome)
		simulations[name] = simulation
		_check(not simulation.is_empty(), "%s simulation produced result" % name)
		_check(int(simulation["seasons"]) == PatchSimulator.DEFAULT_SEASONS, "%s season count" % name)
		_check(Array(simulation["biomass_series"]).size() == PatchSimulator.DEFAULT_SEASONS + 1, "%s biomass time series complete" % name)
		_check(Array(simulation["net_balance_series"]).size() == PatchSimulator.DEFAULT_SEASONS, "%s net balance time series complete" % name)
		_check(float(simulation["final_biomass_kg_m2"]) >= 0.0, "%s final biomass non-negative" % name)
		_check(float(simulation["peak_biomass_kg_m2"]) <= PatchSimulator.MAX_BIOMASS_KG_M2, "%s biomass bounded" % name)
		_check(int(simulation["productive_seasons"]) + int(simulation["stress_seasons"]) == PatchSimulator.DEFAULT_SEASONS, "%s season accounting complete" % name)
		_check(String(simulation["checksum"]) == PatchSimulator.compute_checksum(simulation), "%s simulation checksum validates" % name)

	_check(float(simulations["lower_slope"]["final_biomass_kg_m2"]) > float(simulations["sunny_slope"]["final_biomass_kg_m2"]), "favourable lower slope supports more biomass than marginal sunny slope")
	_check(float(simulations["floodplain"]["final_biomass_kg_m2"]) > float(simulations["sunny_slope"]["final_biomass_kg_m2"]), "favourable floodplain supports more biomass than marginal sunny slope")
	_check(float(simulations["sunny_slope"]["final_biomass_kg_m2"]) > 0.10, "marginal sunny slope remains viable but limited")
	for name in ["river_bank", "wet_lowland", "shaded_slope", "plateau", "dry_ridge"]:
		_check(float(simulations[name]["final_biomass_kg_m2"]) < 0.001, "%s unsustainable biomass collapses" % name)

	var total_final_biomass := 0.0
	var total_peak_biomass := 0.0
	for name in CONTROL_POINT_ORDER:
		total_final_biomass += float(simulations[name]["final_biomass_kg_m2"])
		total_peak_biomass += float(simulations[name]["peak_biomass_kg_m2"])
	_check(total_final_biomass > 1.0, "fixture control points retain non-zero living biomass")
	_check(total_peak_biomass <= PatchSimulator.MAX_BIOMASS_KG_M2 * float(CONTROL_POINT_ORDER.size()), "aggregate biomass remains bounded")


func _test_root_depth_tradeoff() -> void:
	var base := PlantGenome.create_default()
	var shallow := PlantGenome.with_root_depth(base, 0.35, "/shallow-root")
	var deep := PlantGenome.with_root_depth(base, 1.60, "/deep-root")
	var extreme := PlantGenome.with_root_depth(base, 2.20, "/extreme-root")
	for genome in [shallow, deep, extreme]:
		_ok(PlantGenome.validate(genome), "root-depth probe genome validates")

	var dry_environment := Fixture.control_point("dry_ridge")
	var sunny_environment := Fixture.control_point("sunny_slope")
	var wet_environment := Fixture.control_point("floodplain")
	var shallow_dry := ResourceModel.evaluate(dry_environment, shallow, 0.05)
	var deep_dry := ResourceModel.evaluate(dry_environment, deep, 0.05)
	var shallow_wet := ResourceModel.evaluate(wet_environment, shallow, 0.05)
	var deep_wet := ResourceModel.evaluate(wet_environment, deep, 0.05)
	var deep_sunny := ResourceModel.evaluate(sunny_environment, deep, 0.05)
	var extreme_sunny := ResourceModel.evaluate(sunny_environment, extreme, 0.05)

	_check(float(deep_dry["effective_soil_moisture"]) > float(shallow_dry["effective_soil_moisture"]), "deeper roots recover more effective moisture on dry ridge")
	_check(float(deep_dry["net_resource_balance"]) > float(shallow_dry["net_resource_balance"]), "deeper roots improve dry-ridge resource balance")
	_check(float(deep_dry["root_cost"]) > float(shallow_dry["root_cost"]), "deeper roots have explicit higher cost")
	_check(float(shallow_wet["net_resource_balance"]) > float(deep_wet["net_resource_balance"]), "deep roots are not free on already-wet favourable ground")
	_check(float(extreme_sunny["root_cost"]) > float(deep_sunny["root_cost"]), "extreme roots cost more than deep roots")
	_check(float(deep_sunny["net_resource_balance"]) > float(extreme_sunny["net_resource_balance"]), "root-depth benefit saturates and extreme roots become worse")


func _test_determinism_and_ownership_boundary() -> void:
	var genome := PlantGenome.create_default()
	var tokens_a := PackedStringArray()
	var tokens_b := PackedStringArray()
	for name in CONTROL_POINT_ORDER:
		var environment := Fixture.control_point(name)
		var balance_a := ResourceModel.evaluate(environment, genome, 0.05)
		var balance_b := ResourceModel.evaluate(environment, genome, 0.05)
		_check(String(balance_a["checksum"]) == String(balance_b["checksum"]), "%s resource balance deterministic" % name)
		var simulation_a := PatchSimulator.simulate(environment, genome)
		var simulation_b := PatchSimulator.simulate(environment, genome)
		_check(String(simulation_a["checksum"]) == String(simulation_b["checksum"]), "%s patch simulation deterministic" % name)
		tokens_a.append("%s:%s:%s" % [name, String(balance_a["checksum"]), String(simulation_a["checksum"])])
		tokens_b.append("%s:%s:%s" % [name, String(balance_b["checksum"]), String(simulation_b["checksum"])])
	var simulation_hash_a := "\n".join(tokens_a).sha256_text()
	var simulation_hash_b := "\n".join(tokens_b).sha256_text()
	_check(simulation_hash_a == simulation_hash_b, "fixture resource/simulation hash deterministic")
	print("ECO.P1A-S2 simulation_hash=%s" % simulation_hash_a)
	_check(simulation_hash_a == EXPECTED_SIMULATION_HASH, "accepted S2 simulation hash")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_genome_v1.gd")
	source += FileAccess.get_file_as_string("res://scripts/research/ecology/plant_resource_model_v1.gd")
	source += FileAccess.get_file_as_string("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")
	for forbidden in [
		"Camera3D", "SurfaceCellKey", "surface_cell_key", "AuthorityRegion", "InterestRegion",
		"ENetMultiplayerPeer", "MaterialDefinitionId", "river_plant", "dry_plant", "forest_tree",
		"biome ==", "biome_id", "fitness =",
	]:
		_check(source.find(forbidden) < 0, "S2 research model excludes %s" % forbidden)


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s (%s)" % [label, String(result.get("error_code", ""))])


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.P1A-S2 Single-Plant Resource Model: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1A-S2 FAIL: %s" % failure)
	print("ECO.P1A-S2 Single-Plant Resource Model: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
