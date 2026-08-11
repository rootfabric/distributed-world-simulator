extends SceneTree

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const Profile = preload("res://scripts/research/ecology/plant_morphology_resource_profile_v1.gd")
const Probes = preload("res://scripts/research/ecology/plant_morphology_resource_probes_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var profile := Profile.create_default()
	_check(bool(Profile.validate(profile).get("success", false)), "default PH3 profile valid")
	_check(String(profile["checksum"]).length() == 64, "PH3 profile checksum")
	var suite := Probes.run_suite()
	_check(suite.size() == 32, "4 environments x 8 morphology variants")
	for key in suite.keys():
		var item: Dictionary = suite[key]
		var coupling: Dictionary = item["coupling"]
		_check(not item["phenotype"].is_empty(), "%s phenotype exists" % key)
		_check(not coupling.is_empty(), "%s coupling exists" % key)
		_check(String(coupling.get("coupling_hash", "")).length() == 64, "%s coupling hash" % key)
		_check(String(coupling.get("resource_balance_checksum", "")).length() == 64, "%s parent resource checksum" % key)
		_check(is_finite(float(coupling.get("coupled_net_resource_balance", NAN))), "%s finite coupled balance" % key)

	# Accepted P1 result is consumed as immutable parent evidence, not rewritten.
	var reference_case: Dictionary = suite["REFERENCE/BASE"]
	var recomputed := ResourceModel.evaluate(reference_case["environment"], Genome.create_default())
	_check(String(recomputed["checksum"]) == String(reference_case["coupling"]["resource_balance_checksum"]), "PH3 preserves exact accepted P1 resource result checksum")

	# Height trade-off: more height buys shade access but pays super-linear structure.
	var shade_low := _c(suite, "SHADE/HEIGHT_LOW")
	var shade_high := _c(suite, "SHADE/HEIGHT_HIGH")
	_check(float(shade_high["height_light_access_benefit"]) > float(shade_low["height_light_access_benefit"]), "height raises shade light-access benefit")
	_check(float(shade_high["structural_cost"]) > float(shade_low["structural_cost"]), "height raises structural cost")

	# Crown trade-off: wide crowns capture more light, but become expensive under drought.
	var sun_narrow := _c(suite, "SUN/CROWN_NARROW")
	var sun_wide := _c(suite, "SUN/CROWN_WIDE")
	var dry_narrow := _c(suite, "DRY/CROWN_NARROW")
	var dry_wide := _c(suite, "DRY/CROWN_WIDE")
	_check(float(sun_wide["crown_light_capture_benefit"]) > float(sun_narrow["crown_light_capture_benefit"]), "crown spread raises light capture")
	_check(float(dry_wide["crown_water_cost"]) > float(dry_narrow["crown_water_cost"]), "wide crown raises drought water cost")
	_check(float(dry_wide["morphology_delta"]) < float(sun_wide["morphology_delta"]), "same wide crown is more expensive under drought")

	# Branching trade-off: more branching captures more light but pays construction/maintenance.
	var branch_low := _c(suite, "SUN/BRANCH_LOW")
	var branch_high := _c(suite, "SUN/BRANCH_HIGH")
	_check(float(branch_high["branch_light_capture_benefit"]) > float(branch_low["branch_light_capture_benefit"]), "branching raises light capture")
	_check(float(branch_high["branch_construction_cost"]) > float(branch_low["branch_construction_cost"]), "branching raises construction cost")
	_check(float(branch_high["branch_maintenance_cost"]) >= float(branch_low["branch_maintenance_cost"]), "branching does not reduce branch maintenance cost")

	# Bigger is not free: extreme morphology must lose to a balanced phenotype in reference conditions.
	var balanced := _c(suite, "REFERENCE/BASE")
	var giant := _c(suite, "REFERENCE/GIANT_DENSE")
	_check(float(giant["morphology_benefit"]) > float(balanced["morphology_benefit"]), "giant dense morphology gains more gross morphology benefit")
	_check(float(giant["morphology_cost"]) > float(balanced["morphology_cost"]), "giant dense morphology pays more morphology cost")
	_check(float(giant["morphology_delta"]) < float(balanced["morphology_delta"]), "bigger is not always better")

	# Same suite replay is exact.
	var replay := Probes.run_suite()
	for key in suite.keys():
		_check(String(_c(suite, key)["coupling_hash"]) == String(_c(replay, key)["coupling_hash"]), "%s exact replay" % key)

	_test_source_boundaries()
	print("ECO.PH3 profile_hash=%s" % String(profile["checksum"]))
	print("ECO.PH3 reference_hash=%s" % String(balanced["coupling_hash"]))
	print("ECO.PH3 giant_hash=%s" % String(giant["coupling_hash"]))
	print("ECO.PH3 tradeoffs=%s" % str({
		"height": {"low_benefit": shade_low["height_light_access_benefit"], "high_benefit": shade_high["height_light_access_benefit"], "low_cost": shade_low["structural_cost"], "high_cost": shade_high["structural_cost"]},
		"crown": {"sun_wide_benefit": sun_wide["crown_light_capture_benefit"], "dry_narrow_water_cost": dry_narrow["crown_water_cost"], "dry_wide_water_cost": dry_wide["crown_water_cost"]},
		"branch": {"low_benefit": branch_low["branch_light_capture_benefit"], "high_benefit": branch_high["branch_light_capture_benefit"], "low_cost": branch_low["branch_construction_cost"], "high_cost": branch_high["branch_construction_cost"]},
		"bigger_not_free": {"balanced_delta": balanced["morphology_delta"], "giant_delta": giant["morphology_delta"]},
	}))
	_finish()

func _c(suite: Dictionary, key: String) -> Dictionary:
	return suite[key]["coupling"]

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd").to_lower()
	_check(source.contains("plant_resource_model_v1.gd"), "PH3 consumes accepted P1 ResourceModel")
	_check(not source.contains("treegenerator"), "PH3 excludes tree generator class")
	_check(not source.contains("bushgenerator"), "PH3 excludes bush generator class")
	_check(not source.contains("grassgenerator"), "PH3 excludes grass generator class")
	for forbidden in ["meshinstance", "multimesh", "camera", "authority", "network", "persistence"]:
		_check(not source.contains(forbidden), "PH3 source excludes %s" % forbidden)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.PH3 Morphology-to-Resource Coupling: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.PH3 FAIL: %s" % failure)
	print("ECO.PH3 Morphology-to-Resource Coupling: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
