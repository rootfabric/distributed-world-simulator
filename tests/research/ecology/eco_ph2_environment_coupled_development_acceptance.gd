extends SceneTree

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Profile = preload("res://scripts/research/ecology/plant_development_plasticity_profile_v1.gd")
const Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var inherited := Traits.create_default()
	var inherited_snapshot := JSON.stringify(inherited)
	var genome := Genome.create_default()
	var genome_snapshot := JSON.stringify(genome)
	var profile := Profile.create_default()
	_check(bool(Profile.validate(profile).get("success", false)), "default plasticity profile valid")
	_check(String(profile["checksum"]).length() == 64, "plasticity profile checksum")

	var results := Probes.run_all()
	_check(results.size() == Probes.PROBE_ORDER.size(), "all controlled PH2 cases generated")
	for name in Probes.PROBE_ORDER:
		var result: Dictionary = results[name]
		_check(not result.is_empty(), "%s phenotype exists" % name)
		_check(String(result.get("phenotype_hash", "")).length() == 64, "%s phenotype hash" % name)
		_check(String(result.get("genome_checksum", "")) == String(genome["checksum"]), "%s genome checksum preserved" % name)
		_check(String(result.get("inherited_traits_checksum", "")) == String(inherited["checksum"]), "%s inherited traits preserved" % name)
		_check(String(result.get("response_profile_checksum", "")) == String(profile["checksum"]), "%s response profile preserved" % name)
		_check(bool(result.get("growth_graph", {}).get("derived_representation", false)), "%s graph remains derived" % name)
		_check(String(result.get("growth_graph", {}).get("graph_hash", "")).length() == 64, "%s graph hash" % name)
		_check(String(result.get("realized_development_traits", {}).get("checksum", "")).length() == 64, "%s realized traits checksum" % name)

	_check(JSON.stringify(inherited) == inherited_snapshot, "plasticity does not mutate inherited development traits")
	_check(JSON.stringify(genome) == genome_snapshot, "plasticity does not mutate genome")

	var replay := Probes.run_all()
	for name in Probes.PROBE_ORDER:
		_check(String(results[name]["phenotype_hash"]) == String(replay[name]["phenotype_hash"]), "%s exact deterministic replay" % name)

	var reference: Dictionary = results["REFERENCE"]["realized_development_traits"]
	var shade: Dictionary = results["SHADE"]["realized_development_traits"]
	var sun: Dictionary = results["SUN"]["realized_development_traits"]
	var dry: Dictionary = results["DRY"]["realized_development_traits"]
	var poor: Dictionary = results["NUTRIENT_POOR"]["realized_development_traits"]
	var rich: Dictionary = results["NUTRIENT_RICH"]["realized_development_traits"]
	var flooded: Dictionary = results["FLOODED"]["realized_development_traits"]

	_check(float(shade["max_height_m"]) > float(reference["max_height_m"]), "shade elongation increases realized max height")
	_check(float(shade["internode_length_m"]) > float(reference["internode_length_m"]), "shade elongation increases internode length")
	_check(float(shade["apical_dominance"]) > float(reference["apical_dominance"]), "shade raises realized apical dominance")
	_check(float(shade["branch_probability"]) < float(reference["branch_probability"]), "shade suppresses branching")
	_check(float(shade["crown_spread_m"]) < float(reference["crown_spread_m"]), "shade narrows crown spread")

	_check(float(sun["branch_probability"]) > float(reference["branch_probability"]), "high light raises branching")
	_check(float(sun["apical_dominance"]) < float(reference["apical_dominance"]), "high light lowers apical dominance")
	_check(float(sun["crown_spread_m"]) > float(reference["crown_spread_m"]), "high light expands crown")

	_check(float(dry["max_height_m"]) < float(reference["max_height_m"]), "drought suppresses realized height")
	_check(float(dry["branch_probability"]) < float(reference["branch_probability"]), "drought suppresses branching")
	_check(float(dry["crown_spread_m"]) < float(reference["crown_spread_m"]), "drought suppresses crown spread")
	_check(float(dry["branch_length_ratio"]) < float(reference["branch_length_ratio"]), "drought suppresses branch extension")

	_check(float(rich["max_height_m"]) > float(poor["max_height_m"]), "nutrient availability changes realized height")
	_check(float(rich["branch_probability"]) > float(poor["branch_probability"]), "nutrient availability changes branching")
	_check(float(rich["branch_length_ratio"]) > float(poor["branch_length_ratio"]), "nutrient availability changes branch extension")

	_check(float(flooded["max_height_m"]) < float(reference["max_height_m"]), "flood stress suppresses height")
	_check(float(flooded["branch_probability"]) < float(reference["branch_probability"]), "flood stress suppresses branching")
	_check(float(flooded["crown_spread_m"]) < float(reference["crown_spread_m"]), "flood stress suppresses crown spread")

	var ref_graph: Dictionary = results["REFERENCE"]["growth_graph"]
	var shade_graph: Dictionary = results["SHADE"]["growth_graph"]
	var sun_graph: Dictionary = results["SUN"]["growth_graph"]
	var dry_graph: Dictionary = results["DRY"]["growth_graph"]
	_check(String(ref_graph["graph_hash"]) != String(shade_graph["graph_hash"]), "same inherited program produces different shade phenotype")
	_check(String(ref_graph["graph_hash"]) != String(sun_graph["graph_hash"]), "same inherited program produces different sun phenotype")
	_check(String(ref_graph["graph_hash"]) != String(dry_graph["graph_hash"]), "same inherited program produces different dry phenotype")
	_check(float(shade_graph["metrics"]["height_m"]) > float(ref_graph["metrics"]["height_m"]), "shade graph is taller")
	_check(float(dry_graph["metrics"]["height_m"]) < float(ref_graph["metrics"]["height_m"]), "dry graph is shorter")
	_check(float(sun_graph["metrics"]["horizontal_radius_m"]) > float(shade_graph["metrics"]["horizontal_radius_m"]), "sun phenotype spreads wider than shade phenotype")

	_test_source_boundaries()
	print("ECO.PH2 phenotype_hashes=%s" % str(_hashes(results)))
	print("ECO.PH2 realized_metrics=%s" % str(_metrics(results)))
	_finish()

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd").to_lower()
	for forbidden in ["treegenerator", "bushgenerator", "grassgenerator", "plant_type", "biome", "species", "meshinstance", "multimesh", "camera", "authority", "network", "persistence"]:
		_check(not source.contains(forbidden), "PH2 source excludes %s" % forbidden)
	_check(source.contains("environment_sample"), "PH2 consumes EnvironmentSample contract")
	_check(source.contains("skeleton.build"), "PH2 delegates phenotype geometry to accepted PH1 skeleton")
	_check(not source.contains("plant_resource_model"), "PH2 does not modify accepted P1 resource equations")

func _hashes(results: Dictionary) -> Dictionary:
	var hashes := {}
	for name in Probes.PROBE_ORDER:
		hashes[name] = String(results[name]["phenotype_hash"])
	return hashes

func _metrics(results: Dictionary) -> Dictionary:
	var values := {}
	for name in Probes.PROBE_ORDER:
		var result: Dictionary = results[name]
		values[name] = {
			"traits": result["realized_development_traits"],
			"graph": result["growth_graph"]["metrics"],
		}
	return values

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.PH2 Environment-Coupled Development: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.PH2 FAIL: %s" % failure)
	print("ECO.PH2 Environment-Coupled Development: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
