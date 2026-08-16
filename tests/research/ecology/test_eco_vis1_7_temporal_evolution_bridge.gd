extends SceneTree

const VIS17 = preload("res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_bridge.gd")
const VIS16 = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sample := EnvironmentSample.create(18.0, 31.0, 18.2, 0.76, 0.67, 0.58, 0.42, 73191, "eco-vis1.7-test")
	var profile := RendererProfile.create("BRANCH_LEAF_INSTANCED")
	var source_hash := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var g0 := VIS17.realize_at_generation(sample, profile, source_hash, "B", "alpha", 7, 0)
	var g3 := VIS17.realize_at_generation(sample, profile, source_hash, "B", "alpha", 7, 3)
	var g6 := VIS17.realize_at_generation(sample, profile, source_hash, "B", "alpha", 7, 6)
	var g12 := VIS17.realize_at_generation(sample, profile, source_hash, "B", "alpha", 7, 12)
	var legacy3 := VIS16.realize(sample, profile, source_hash, "B", "alpha", 7)
	_expect(not g0.is_empty() and not g3.is_empty() and not g6.is_empty() and not g12.is_empty(), "generation bridge realizes 0/3/6/12")
	_expect(int(g0.get("generation", -1)) == 0 and int(g12.get("generation", -1)) == 12, "generation markers are exact")
	_expect(Array(g0.get("trajectory", [])).size() == 1, "generation zero trajectory contains ancestor")
	_expect(Array(g3.get("trajectory", [])).size() == 4, "generation three trajectory has four states")
	_expect(Array(g12.get("trajectory", [])).size() == 13, "generation twelve trajectory has thirteen states")
	_expect(String(g0.get("genome_checksum", "")) == String(VIS16.create_population_baseline_genome("alpha").get("checksum", "")), "generation zero is alpha baseline")
	_expect(int(g0.get("selected_mutation_count", -1)) == 0, "generation zero has no selected mutations")
	_expect(String(g3.get("genome_checksum", "")) == String(legacy3.get("genome_checksum", "")), "generation three genome matches VIS1.6")
	_expect(String(g3.get("lineage_checksum", "")) == String(legacy3.get("lineage_checksum", "")), "generation three lineage matches VIS1.6")
	_expect(String(g3.get("phenotype_hash", "")) == String(legacy3.get("phenotype_hash", "")), "generation three phenotype matches VIS1.6")
	_expect(String(g3.get("geometry_hash", "")) == String(legacy3.get("geometry_hash", "")), "generation three geometry matches VIS1.6")
	_expect(absf(float(g3.get("final_fitness", 0.0)) - float(legacy3.get("final_fitness", 0.0))) <= 0.000000000001, "generation three fitness matches VIS1.6")
	_expect(float(g3.get("final_fitness", 0.0)) + 0.000000001 >= float(g0.get("final_fitness", 0.0)), "fitness is nondecreasing through generation three")
	_expect(float(g6.get("final_fitness", 0.0)) + 0.000000001 >= float(g3.get("final_fitness", 0.0)), "fitness is nondecreasing through generation six")
	_expect(float(g12.get("final_fitness", 0.0)) + 0.000000001 >= float(g6.get("final_fitness", 0.0)), "fitness is nondecreasing through generation twelve")
	_expect(_trajectory_prefix_matches(Array(g3.get("trajectory", [])), Array(g6.get("trajectory", []))), "generation six preserves generation three trajectory prefix")
	_expect(_trajectory_prefix_matches(Array(g6.get("trajectory", [])), Array(g12.get("trajectory", []))), "generation twelve preserves generation six trajectory prefix")
	var repeated := VIS17.realize_at_generation(sample, profile, source_hash, "B", "alpha", 7, 12)
	_expect(String(repeated.get("bridge_hash", "")) == String(g12.get("bridge_hash", "")), "generation realization is deterministic")
	_expect(String(g12.get("trajectory_hash", "")).length() == 64, "trajectory hash exists")
	_expect(not bool(g12.get("canonical_timeline_truth", true)), "timeline is explicitly lab-derived")
	_expect(VIS17.realize_at_generation(sample, profile, source_hash, "B", "alpha", 7, 13).is_empty(), "generation above maximum is rejected")
	_finish()

func _trajectory_prefix_matches(prefix: Array, full: Array) -> bool:
	if prefix.size() > full.size():
		return false
	for index in range(prefix.size()):
		if prefix[index] != full[index]:
			return false
	return true

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS1.7 bridge assertion failed: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.7 temporal bridge: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.7 temporal bridge: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
