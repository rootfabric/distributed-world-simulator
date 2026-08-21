extends SceneTree

const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Skeleton = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const Probes = preload("res://scripts/research/ecology/plant_growth_graph_controlled_probes_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var results := Probes.run_all()
	_check(results.size() == 9, "nine controlled morphology cases")
	for name in results.keys():
		var graph: Dictionary = results[name]
		_check(not graph.is_empty(), "%s graph exists" % name)
		_check(String(graph.get("graph_hash", "")).length() == 64, "%s graph hash" % name)
		_check(bool(graph.get("derived_representation", false)), "%s graph remains derived representation" % name)
		_check(Array(graph.get("segments", [])).size() > 0, "%s has segments" % name)
		_check(int(graph.get("metrics", {}).get("segment_count", 0)) == Array(graph.get("segments", [])).size(), "%s segment metrics exact" % name)
		_check(float(graph.get("metrics", {}).get("height_m", 0.0)) > 0.0, "%s positive height" % name)

	var base_traits := Traits.create_default()
	var a := Skeleton.build(base_traits, Probes.DEFAULT_INDIVIDUAL_SEED)
	var b := Skeleton.build(base_traits, Probes.DEFAULT_INDIVIDUAL_SEED)
	var c := Skeleton.build(base_traits, Probes.DEFAULT_INDIVIDUAL_SEED + 1)
	_check(String(a["graph_hash"]) == String(b["graph_hash"]), "same genome/traits/individual seed exact graph replay")
	_check(String(a["graph_hash"]) != String(c["graph_hash"]), "individual seed changes stochastic realization")
	_check(String(a["development_traits_checksum"]) == String(base_traits["checksum"]), "graph binds exact development traits")

	var low_apical: Dictionary = results["APICAL_LOW"]["metrics"]
	var high_apical: Dictionary = results["APICAL_HIGH"]["metrics"]
	_check(int(low_apical["lateral_branch_count"]) > int(high_apical["lateral_branch_count"]), "lower apical dominance increases branching")
	_check(float(low_apical["total_length_m"]) > float(high_apical["total_length_m"]), "lower apical dominance produces more shoot length")

	var low_branch: Dictionary = results["BRANCH_LOW"]["metrics"]
	var high_branch: Dictionary = results["BRANCH_HIGH"]["metrics"]
	_check(int(high_branch["lateral_branch_count"]) > int(low_branch["lateral_branch_count"]), "higher branch probability increases branch count")
	_check(int(high_branch["lateral_segment_count"]) > int(low_branch["lateral_segment_count"]), "higher branch probability increases lateral segments")

	var narrow: Dictionary = results["ANGLE_NARROW"]["metrics"]
	var wide: Dictionary = results["ANGLE_WIDE"]["metrics"]
	_check(float(wide["mean_lateral_angle_deg"]) > float(narrow["mean_lateral_angle_deg"]) + 30.0, "branch-angle trait produces continuous angular morphology change")
	_check(float(wide["horizontal_radius_m"]) > float(narrow["horizontal_radius_m"]), "wide branches increase crown radius")

	var short_i: Dictionary = results["INTERNODE_SHORT"]["metrics"]
	var long_i: Dictionary = results["INTERNODE_LONG"]["metrics"]
	_check(int(short_i["main_axis_segment_count"]) > int(long_i["main_axis_segment_count"]), "short internodes create more main-axis segments")
	_check(absf(float(short_i["height_m"]) - float(long_i["height_m"])) < 1e-9, "internode probe preserves inherited max height")

	# Smooth transition, not type switching: sweep branch probability and require nondecreasing branch count.
	var previous_count := -1
	for p in [0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95]:
		var traits := Traits.with_trait(base_traits, "branch_probability", p, "/sweep")
		var graph := Skeleton.build(traits, Probes.DEFAULT_INDIVIDUAL_SEED)
		var count := int(graph["metrics"]["lateral_branch_count"])
		_check(count >= previous_count, "branch probability sweep nondecreasing at %.2f" % p)
		previous_count = count

	_test_graph_integrity(a)
	_test_source_boundaries()
	print("ECO.PH1 base_graph_hash=%s base_metrics=%s" % [String(a["graph_hash"]), str(a["metrics"])])
	print("ECO.PH1 probe_hashes=%s" % str(_probe_hashes(results)))
	_finish()

func _test_graph_integrity(graph: Dictionary) -> void:
	var seen := {}
	for segment in Array(graph["segments"]):
		var s: Dictionary = segment
		var id := String(s["segment_id"])
		_check(not seen.has(id), "segment ids stable and unique: %s" % id)
		var parent := String(s["parent_segment_id"])
		_check(parent.is_empty() or seen.has(parent), "parent precedes child: %s" % id)
		_check(float(s["length_m"]) > 0.0, "segment has positive length: %s" % id)
		seen[id] = true

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd").to_lower()
	for forbidden in ["treegenerator", "bushgenerator", "grassgenerator", "plant_type", "biome", "species", "meshinstance", "multimesh", "camera", "authority", "network", "persistence"]:
		_check(not source.contains(forbidden), "skeleton source excludes %s" % forbidden)
	_check(source.contains("create_empty_growth_graph"), "skeleton delegates derived GrowthGraph contract")

func _probe_hashes(results: Dictionary) -> Dictionary:
	var hashes := {}
	for name in results.keys():
		hashes[name] = String(results[name]["graph_hash"])
	return hashes

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.PH1 Deterministic GrowthGraph Skeleton: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.PH1 FAIL: %s" % failure)
	print("ECO.PH1 Deterministic GrowthGraph Skeleton: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
