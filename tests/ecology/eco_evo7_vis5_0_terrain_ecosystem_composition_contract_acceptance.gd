extends SceneTree

## ECO.EVO7 VIS5.0 — Terrain / Ecosystem Composition Contract Audit.
##
## This gate freezes the first post-VIS4 visual boundary. It does not add a new
## ecology authority, does not change PERF2.4, and does not claim PLAY1
## acceptance. It distinguishes accepted evolved PH5 plants from terrain-owned
## scenery donors before any mixed-strata composition is implemented.

const MANIFEST_PATH := "res://config/ecology/eco-evo7-vis5-terrain-ecosystem-composition-audit.v1.json"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		_check(false, "VIS5.0 manifest loads")
		_finish()
		return
	_m1_identity_and_authority(manifest)
	_m2_parallel_perf_boundary(manifest)
	_m3_vis4_surface_binding()
	_m4_earth_surface_contract()
	_m5_ground_cover_donor_boundary(manifest)
	_m6_legacy_region_donor_boundary(manifest)
	_m7_composition_policy(manifest)
	_m8_ladder(manifest)
	_m9_forbidden(manifest)
	_finish()


func _load_manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _m1_identity_and_authority(manifest: Dictionary) -> void:
	_check(
		String(manifest.get("schema", "")) == "distributed_world_simulator.ecology.evo7_vis5_terrain_ecosystem_composition_audit.v1",
		"VIS5.0 manifest schema exact"
	)
	_check(String(manifest.get("version", "")) == "1.0.0", "VIS5.0 manifest version exact")
	_check(String(manifest.get("revision", "")) == "ECO.EVO7-VIS5.0.R1", "VIS5.0 revision exact")
	var base: Dictionary = manifest.get("base", {})
	_check(String(base.get("checkpoint", "")) == "VIS4.9 CLOSED", "VIS5.0 starts after closed VIS4.9")
	_check(
		String(base.get("closure_head", "")) == "8f0d6f464e098aa6b8f74ec7e86093cffb6bb1e3",
		"VIS5.0 exact visual closure HEAD"
	)
	_check(
		String(base.get("exact_tested_vis4_9_head", "")) == "ab44617d8961add81a6c9f245c99d0b68eaeab52",
		"VIS5.0 preserves exact-tested VIS4.9 subject"
	)
	var authority: Dictionary = manifest.get("authority", {})
	_check(bool(authority.get("presentation_only", false)), "VIS5.0 is presentation-only")
	for key in [
		"ecology_write",
		"genome_write",
		"mutation_write",
		"population_write",
		"generation_write",
		"terrain_write",
		"persistence_write",
		"network_write",
		"perf2_4_write",
	]:
		_check(authority.has(key) and not bool(authority[key]), "VIS5.0 owns no %s authority" % key)


func _m2_parallel_perf_boundary(manifest: Dictionary) -> void:
	var policy: Dictionary = manifest.get("parallel_policy", {})
	_check(bool(policy.get("may_develop_while_perf2_4_verifies", false)), "VIS5 may develop while PERF2.4 verifies")
	_check(bool(policy.get("perf2_sim_contract_unchanged", false)), "PERF2.SIM contract unchanged")
	_check(bool(policy.get("perf2_4_thresholds_unchanged", false)), "PERF2.4 thresholds unchanged")
	_check(bool(policy.get("perf2_conv_final_join_required", false)), "PERF2.CONV remains final join")
	_check(not bool(policy.get("play1_acceptance_before_perf2_conv", true)), "PLAY1 cannot be accepted before PERF2.CONV")


func _m3_vis4_surface_binding() -> void:
	var renderer := _source("res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd")
	_check(renderer.contains("GridAppearance"), "VIS4 PH5 renderer keeps accepted GridAppearance donor")
	_check(
		renderer.contains("var base_world: Vector3 = earth_world.get_surface_point(up)"),
		"VIS4 canonical plant base already follows real terrain elevation"
	)
	_check(
		renderer.contains("var visual_base_world: Vector3 = earth_world.get_surface_point(visual_direction)"),
		"VIS4 visual scatter is reprojected onto real terrain elevation"
	)
	_check(renderer.contains("source_growth_graph_hash"), "VIS4 plant geometry remains GrowthGraph-bound")
	_check(renderer.contains("materialization_hash"), "VIS4 plant materialization remains sealed")


func _m4_earth_surface_contract() -> void:
	var earth := _source("res://scripts/world/earth/procedural_earth_world.gd")
	_check(earth.contains("func get_surface_height(direction_value: Vector3) -> float:"), "Earth exposes exact surface height")
	_check(earth.contains("func get_surface_point(direction_value: Vector3) -> Vector3:"), "Earth exposes exact surface point")
	_check(earth.contains("func get_surface_state(direction: Vector3, lod_level: int = 0) -> Dictionary:"), "Earth exposes surface state")
	_check(earth.contains("pipeline.sample(direction_value.normalized(), 0)"), "surface height comes from terrain pipeline")
	_check(earth.contains("state.get(\"grass_density\""), "Earth surface state includes grass-density scenery signal")
	_check(earth.contains("state.get(\"tree_density\""), "Earth surface state includes tree-density scenery signal")


func _m5_ground_cover_donor_boundary(manifest: Dictionary) -> void:
	var placement := _source("res://scripts/world/vegetation/earth_placement_system.gd")
	_check(placement.contains("func _generate_grass("), "EarthPlacementSystem contains dense grass generator")
	_check(placement.contains("state.get(\"grass_density\""), "grass donor consumes procedural grass density")
	_check(placement.contains("RandomNumberGenerator.new()"), "grass donor uses presentation RNG")
	_check(placement.contains("get_grass_mesh(type_id)"), "grass donor already batches reusable grass assets")
	_check(placement.contains("MultiMesh.new()"), "grass donor uses MultiMesh batching")
	_check(placement.contains("func _generate_trees("), "same donor also contains procedural tree placement")
	_check(placement.contains("state.get(\"tree_density\""), "procedural tree placement consumes terrain tree density")

	var policy: Dictionary = manifest.get("composition_policy", {})
	_check(
		String(policy.get("procedural_trees_in_vis5", "")) == "FORBIDDEN_UNTIL_EXPLICIT_SOURCE_BINDING",
		"VIS5 forbids duplicate procedural trees"
	)
	_check(
		String(policy.get("ground_cover_before_ecological_binding", "")) == "ALLOWED_ONLY_AS_EXPLICIT_NONCANONICAL_SCENERY",
		"ground cover remains explicitly noncanonical until ecology binding exists"
	)


func _m6_legacy_region_donor_boundary(manifest: Dictionary) -> void:
	var legacy := _source("res://scripts/labs/ecology/eco_evo4_b6_region_lab.gd")
	_check(legacy.contains("ECO.EVO4/E4.B6"), "EVO4 B6 donor remains visibly legacy")
	_check(legacy.contains("MANIFEST_PATH"), "EVO4 B6 is manifest-driven")
	_check(legacy.contains("MultiMesh.new()"), "EVO4 B6 proves dense per-variant MultiMesh batching")
	_check(legacy.contains("PlaneMesh.new()"), "EVO4 B6 old region lab uses a flat presentation ground")

	var donors_value = manifest.get("capability_donors", [])
	_check(donors_value is Array, "VIS5.0 donor list is an array")
	if not donors_value is Array:
		return
	var donors: Dictionary = {}
	for value in Array(donors_value):
		_check(value is Dictionary, "VIS5.0 donor entry is a dictionary")
		if value is Dictionary:
			var donor: Dictionary = value
			donors[String(donor.get("id", ""))] = donor
	for required in ["EARTH_PLACEMENT_GRASS", "EVO4_B6_REGION", "VIS4_PH5"]:
		_check(donors.has(required), "VIS5.0 donor declared: %s" % required)
	if donors.has("EVO4_B6_REGION"):
		_check(
			String(Dictionary(donors["EVO4_B6_REGION"]).get("truth_status", "")) == "LEGACY_PRESENTATION_DONOR_ONLY",
			"EVO4 B6 cannot become current ecology truth"
		)


func _m7_composition_policy(manifest: Dictionary) -> void:
	var policy: Dictionary = manifest.get("composition_policy", {})
	_check(String(policy.get("canonical_macro_plants", "")) == "VIS4 PH5 only", "canonical macro plants stay VIS4 PH5")
	_check(String(policy.get("terrain_source", "")) == "ProceduralEarthWorld", "terrain remains ProceduralEarthWorld")
	_check(String(policy.get("surface_position", "")) == "get_surface_point(direction)", "surface placement path exact")
	_check(String(policy.get("surface_state", "")) == "get_surface_state(direction, lod)", "surface state path exact")
	_check(bool(policy.get("no_tree_bush_grass_taxonomy", false)), "VIS5 adds no TREE/BUSH/GRASS ecology taxonomy")
	_check(bool(policy.get("no_random_shape_used_as_ecology_diversity", false)), "random scenery cannot count as ecology diversity")

	var play0 := _source("res://scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd")
	_check(not play0.contains("earth_placement_system.gd"), "accepted PLAY0 does not already mix procedural vegetation donor into VIS4 truth")


func _m8_ladder(manifest: Dictionary) -> void:
	var ladder_value = manifest.get("implementation_ladder", [])
	_check(ladder_value is Array, "VIS5 implementation ladder is an array")
	if not ladder_value is Array:
		return
	var names: Dictionary = {}
	for value in Array(ladder_value):
		_check(value is Dictionary, "VIS5 ladder entry is a dictionary")
		if value is Dictionary:
			var item: Dictionary = value
			names[String(item.get("checkpoint", ""))] = String(item.get("name", ""))
	for checkpoint in ["VIS5.0", "VIS5.1", "VIS5.2", "VIS5.3", "VIS5.4", "VIS5.5"]:
		_check(names.has(checkpoint), "VIS5 ladder contains %s" % checkpoint)
	_check(names.get("VIS5.1", "") == "Terrain Surface Frame Adapter", "VIS5.1 next implementation is surface-frame adapter")
	_check(names.get("VIS5.3", "") == "Mixed-Strata Composition Lab", "VIS5.3 owns combined visual lab")


func _m9_forbidden(manifest: Dictionary) -> void:
	var forbidden := _strings(manifest.get("forbidden", []))
	for required in [
		"modify PERF2.4 thresholds or benchmark subject",
		"replace VIS4 Descriptor V2 with procedural vegetation density",
		"render procedural Earth trees as if they were evolved VIS4 individuals",
		"treat decorative grass instances as biological individuals",
		"introduce TREE_BUSH_GRASS canonical ecology classes",
		"feed presentation RNG, LOD, grass placement or visual scatter back into ecology state",
		"claim PLAY1 performance acceptance before PERF2.CONV",
	]:
		_check(forbidden.has(required), "VIS5.0 forbids: %s" % required)


func _source(path: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	_check(not source.is_empty(), "source exists: %s" % path)
	return source


func _strings(value) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item in Array(value):
		result.append(String(item))
	return result


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 VIS5.0 Terrain / Ecosystem Composition Contract Audit: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS5.0 FAIL: %s" % failure)
	print(
		"ECO.EVO7 VIS5.0 Terrain / Ecosystem Composition Contract Audit: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
