extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const MultiscaleMaterializer = preload("res://scripts/research/ecology/plant_multiscale_materializer_v1.gd")
var assertions := 0

func _init() -> void:
	var results := Probes.run_all()
	_assert(results.size() == Probes.ENVIRONMENT_ORDER.size())
	var truth_hashes := {}
	var tokens := PackedStringArray()
	for environment_name in Probes.ENVIRONMENT_ORDER:
		var item: Dictionary = results[environment_name]
		var graph: Dictionary = item["growth_graph"]
		var description: Dictionary = item["render_description"]
		var graph_snapshot := JSON.stringify(graph)
		var description_snapshot := JSON.stringify(description)
		var previous_cost := 1000000000
		var full_branches := -1
		var reduced_branches := -1
		var full_foliage := -1
		var reduced_foliage := -1
		truth_hashes[String(graph["graph_hash"])] = true
		for tier in Representation.TIER_ORDER:
			var representation := Representation.build(description, tier)
			_assert(bool(representation.get("success", false)))
			var materialization := MultiscaleMaterializer.build(description, representation)
			_assert(bool(materialization.get("success", false)))
			_assert(String(representation["ecological_truth_hash"]) == String(graph["graph_hash"]))
			_assert(String(materialization["ecological_truth_hash"]) == String(graph["graph_hash"]))
			_assert(String(materialization["representation_hash"]) == String(representation["representation_hash"]))
			_assert(String(materialization["materialization_hash"]).length() == 64)
			_assert(int(representation["cost_units"]) < previous_cost)
			previous_cost = int(representation["cost_units"])
			_assert(int(materialization["branch_primitive_count"]) == int(representation["branch_primitive_count"]))
			_assert(int(materialization["foliage_instance_count"]) == int(representation["foliage_instance_count"]))
			_assert(int(materialization["far_primitive_count"]) == int(representation["canopy_primitive_count"]) + int(representation["impostor_count"]))
			var rebuilt := MultiscaleMaterializer.build(description, representation)
			_assert(String(rebuilt["materialization_hash"]) == String(materialization["materialization_hash"]))
			if tier == Representation.TIER_0_FULL:
				full_branches = int(materialization["branch_primitive_count"])
				full_foliage = int(materialization["foliage_instance_count"])
			elif tier == Representation.TIER_1_REDUCED:
				reduced_branches = int(materialization["branch_primitive_count"])
				reduced_foliage = int(materialization["foliage_instance_count"])
			elif tier == Representation.TIER_4_POPULATION_ONLY:
				_assert(not bool(materialization["individual_node_required"]))
				_assert(materialization["branch_mesh"] == null and materialization["foliage_multimesh"] == null and materialization["far_mesh"] == null)
			tokens.append("%s|%s|%s|%s" % [environment_name, tier, String(representation["representation_hash"]), String(materialization["materialization_hash"])])
		_assert(reduced_branches <= full_branches)
		_assert(reduced_foliage <= full_foliage)
		_assert(JSON.stringify(graph) == graph_snapshot)
		_assert(JSON.stringify(description) == description_snapshot)
	_assert(truth_hashes.size() >= 4)
	var matrix_hash := "\n".join(tokens).sha256_text()
	var replay_hash := _matrix_hash(Probes.run_all())
	_assert(matrix_hash == replay_hash)
	print("ECO.PH5-S4 Contrasting Phenotype x Tier Matrix: PASS (%d assertions) matrix_hash=%s" % [assertions, matrix_hash])
	quit(0)

func _matrix_hash(results: Dictionary) -> String:
	var tokens := PackedStringArray()
	for environment_name in Probes.ENVIRONMENT_ORDER:
		var description: Dictionary = results[environment_name]["render_description"]
		for tier in Representation.TIER_ORDER:
			var representation := Representation.build(description, tier)
			var materialization := MultiscaleMaterializer.build(description, representation)
			tokens.append("%s|%s|%s|%s" % [environment_name, tier, String(representation["representation_hash"]), String(materialization["materialization_hash"])])
	return "\n".join(tokens).sha256_text()

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
