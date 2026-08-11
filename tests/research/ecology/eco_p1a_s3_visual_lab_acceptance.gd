extends SceneTree

const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const Probes = preload("res://scripts/research/ecology/controlled_trait_probes_v1.gd")
const Dataset = preload("res://scripts/research/ecology/eco_p1a_s3_lab_dataset_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")

const EXPECTED_ENVIRONMENT_HASH := "b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7"
const EXPECTED_DATASET_HASH := "dff41c7b5ae3e2744b957ea0dd81fa3830de6365711b34d66024115509aa3690"
const GRID_SIZE := 17

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_probe_contracts()
	_test_dataset_determinism()
	_test_truth_projection()
	_test_controlled_trait_probes()
	_test_source_boundaries()
	_finish()


func _test_probe_contracts() -> void:
	var validation := Probes.validate_all()
	_check(bool(validation.get("success", false)), "all controlled probes validate")
	_check(Probes.ORDER.size() == 7, "seven controlled probes")
	_check(Probes.ORDER[0] == Probes.BASE, "base probe first")
	for probe_id in Probes.ORDER:
		_check(not Probes.genome(probe_id).is_empty(), "probe genome exists: %s" % probe_id)


func _test_dataset_determinism() -> void:
	var first := Dataset.build(Probes.BASE, GRID_SIZE)
	var second := Dataset.build(Probes.BASE, GRID_SIZE)
	_check(not first.is_empty(), "base dataset builds")
	_check(not second.is_empty(), "base dataset rebuilds")
	_check(int(first.get("grid_size", 0)) == GRID_SIZE, "dataset grid size")
	_check(Array(first.get("records", [])).size() == GRID_SIZE * GRID_SIZE, "dataset record count")
	_check(String(first.get("environment_hash", "")) == EXPECTED_ENVIRONMENT_HASH, "accepted environment hash retained")
	_check(String(first.get("dataset_hash", "")) == String(second.get("dataset_hash", "")), "dataset hash deterministic")
	_check(String(first.get("dataset_hash", "")) == EXPECTED_DATASET_HASH, "accepted S3 dataset hash")
	_check(String(first.get("genome_checksum", "")) == String(Probes.genome(Probes.BASE)["checksum"]), "dataset binds probe genome")
	for view_id in Dataset.VIEW_IDS:
		_check(view_id in Dataset.VIEW_IDS, "view declared: %s" % view_id)
	for view_id in Dataset.NUMERIC_VIEW_IDS:
		var value_range: Dictionary = first.get("ranges", {}).get(view_id, {})
		_check(value_range.has("min") and value_range.has("max"), "numeric view range exists: %s" % view_id)
		_check(float(value_range.get("max", 0.0)) >= float(value_range.get("min", 0.0)), "numeric range ordered: %s" % view_id)
	var counts: Dictionary = first.get("viability_counts", {})
	_check(int(counts.get("FAVOURABLE", 0)) > 0, "dataset contains favourable patches")
	_check(int(counts.get("MARGINAL", 0)) > 0, "dataset contains marginal patches")
	_check(int(counts.get("UNSUSTAINABLE", 0)) > 0, "dataset contains unsustainable patches")


func _test_truth_projection() -> void:
	for point_name in ["river_bank", "floodplain", "wet_lowland", "lower_slope", "sunny_slope", "shaded_slope", "plateau", "dry_ridge"]:
		var record := Dataset.control_point(point_name, Probes.BASE)
		var position: Vector2 = Fixture.CONTROL_POINTS[point_name]
		var environment := Fixture.sample_at(position.x, position.y)
		var direct := ResourceModel.evaluate(environment, Probes.genome(Probes.BASE), 0.05)
		_check(String(record.get("environment_checksum", "")) == String(environment.get("checksum", "")), "lab reuses environment truth: %s" % point_name)
		_check(String(record.get("balance_checksum", "")) == String(direct.get("checksum", "")), "lab reuses resource truth: %s" % point_name)
		_check(_approx(float(record.get("net_resource_balance", 0.0)), float(direct.get("net_resource_balance", 1.0))), "lab net matches resource model: %s" % point_name)
		_check(String(record.get("dominant_limiting_factor", "")) == String(direct.get("dominant_limiting_factor", "")), "lab limiting factor matches: %s" % point_name)


func _test_controlled_trait_probes() -> void:
	var base_dry := Dataset.control_point("dry_ridge", Probes.BASE)
	var drought_dry := Dataset.control_point("dry_ridge", Probes.DROUGHT_TOLERANT)
	_check(float(drought_dry["net_resource_balance"]) > float(base_dry["net_resource_balance"]), "drought tolerant probe improves dry ridge")

	var base_floodplain := Dataset.control_point("floodplain", Probes.BASE)
	var deep_floodplain := Dataset.control_point("floodplain", Probes.DEEP_ROOT)
	_check(float(deep_floodplain["net_resource_balance"]) < float(base_floodplain["net_resource_balance"]), "deep roots cost more on wet floodplain")

	var base_shade := Dataset.control_point("shaded_slope", Probes.BASE)
	var shade_probe := Dataset.control_point("shaded_slope", Probes.SHADE_TOLERANT)
	_check(float(shade_probe["net_resource_balance"]) > float(base_shade["net_resource_balance"]), "shade tolerant probe improves shaded slope")

	var base_sun := Dataset.control_point("sunny_slope", Probes.BASE)
	var sun_probe := Dataset.control_point("sunny_slope", Probes.SUN_FAVORED)
	_check(float(sun_probe["net_resource_balance"]) > float(base_sun["net_resource_balance"]), "sun-favored probe improves sunny slope")

	var base_wet := Dataset.control_point("floodplain", Probes.BASE)
	var water_probe := Dataset.control_point("floodplain", Probes.WATER_LOVING)
	_check(float(water_probe["net_resource_balance"]) != float(base_wet["net_resource_balance"]), "water-loving probe changes wet-site response")

	var shallow_dry := Dataset.control_point("dry_ridge", Probes.SHALLOW_ROOT)
	var deep_dry := Dataset.control_point("dry_ridge", Probes.DEEP_ROOT)
	_check(float(deep_dry["net_resource_balance"]) > float(shallow_dry["net_resource_balance"]), "deep root probe beats shallow root on dry ridge")

	var probe_hashes := {}
	for probe_id in Probes.ORDER:
		var dataset := Dataset.build(probe_id, 9, 12)
		_check(not dataset.is_empty(), "probe dataset builds: %s" % probe_id)
		var hash := String(dataset.get("dataset_hash", ""))
		_check(hash.length() == 64, "probe dataset hash shape: %s" % probe_id)
		_check(not probe_hashes.has(hash), "probe dataset hash distinct: %s" % probe_id)
		probe_hashes[hash] = true


func _test_source_boundaries() -> void:
	var dataset_source := FileAccess.get_file_as_string("res://scripts/research/ecology/eco_p1a_s3_lab_dataset_v1.gd")
	var lab_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_p1a_s3_visual_lab.gd")
	for forbidden in ["biome ==", "biome_id", "mutation", "natural_selection", "speciation", "AuthorityRegion", "ENetMultiplayerPeer", "MaterialDefinitionId"]:
		_check(dataset_source.find(forbidden) < 0, "dataset excludes forbidden ownership/logic: %s" % forbidden)
	_check(lab_source.find("PlantResourceModelV1") < 0, "visual lab does not implement duplicate named resource model")
	_check(lab_source.find("gross_photosynthetic_income =") < 0, "visual lab does not recompute photosynthesis truth")
	_check(lab_source.find("soil_moisture :=") < 0, "visual lab does not recompute environment truth")
	_check(lab_source.find("Dataset.build") >= 0, "visual lab consumes derived dataset")


func _approx(a: float, b: float, tolerance: float = 0.000000001) -> bool:
	return absf(a - b) <= tolerance


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		var dataset := Dataset.build(Probes.BASE, GRID_SIZE)
		print("ECO.P1A-S3 dataset_hash=%s" % String(dataset.get("dataset_hash", "")))
		print("ECO.P1A-S3 Diagnostic Visual Lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1A-S3 FAIL: %s" % failure)
	print("ECO.P1A-S3 Diagnostic Visual Lab: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
