extends SceneTree

## ECO.EVO7 VIS4.0 — Truth / Contract Audit acceptance.
## This test machine-fixates the source audit only. It does not implement VIS4.1,
## does not alter biology, and does not claim graphical acceptance.

const MANIFEST_PATH := "res://config/ecology/eco-evo7-vis4-truth-contract-audit.v1.json"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		_check(false, "VIS4.0 manifest loads")
		_finish()
		return
	_m1_manifest_identity_and_authority(manifest)
	_m2_live_published_boundary(manifest)
	_m3_hidden_functional_phenotype_fields(manifest)
	_m4_realized_topology_boundary(manifest)
	_m5_hereditary_record_sources(manifest)
	_m6_evolution_mutability_truth(manifest)
	_m7_vis2_descriptor_gap(manifest)
	_m8_play0_current_bottleneck()
	_m9_ph5_reuse_and_gaps(manifest)
	_m10_mapping_policy(manifest)
	_finish()

func _load_manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _m1_manifest_identity_and_authority(manifest: Dictionary) -> void:
	_check(String(manifest.get("schema", "")) == "distributed_world_simulator.ecology.evo7_vis4_truth_contract_audit.v1", "manifest schema exact")
	_check(String(manifest.get("version", "")) == "1.0.0", "manifest version exact")
	_check(String(manifest.get("revision", "")) == "ECO.EVO7-VIS4.0.R1", "VIS4.0 revision exact")
	var base: Dictionary = manifest.get("base", {})
	_check(String(base.get("checkpoint", "")) == "PAR3 R3.2", "VIS4.0 exact predecessor checkpoint")
	_check(String(base.get("sha", "")) == "8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf", "VIS4.0 exact predecessor SHA")
	var authority: Dictionary = manifest.get("authority", {})
	_check(bool(authority.get("presentation_only", false)), "VIS4.0 declares presentation-only intent")
	for key in ["ecology_write", "genome_write", "mutation_write", "population_write", "generation_write", "persistence_write", "network_write"]:
		_check(authority.has(key) and not bool(authority[key]), "VIS4.0 owns no %s authority" % key)

func _m2_live_published_boundary(manifest: Dictionary) -> void:
	var ls34 := _source("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
	var evaluation := _between(ls34, "var evaluation := {", "evaluation[\"evaluation_hash\"]")
	_check(not evaluation.is_empty(), "LS3.4 evaluation block located")
	for field_name in _strings(manifest.get("live_published_fields", [])):
		_check(evaluation.contains("\"%s\"" % field_name), "LS3.4 publishes %s" % field_name)

func _m3_hidden_functional_phenotype_fields(manifest: Dictionary) -> void:
	var fp := _source("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
	var ls34 := _source("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
	var evaluation := _between(ls34, "var evaluation := {", "evaluation[\"evaluation_hash\"]")
	for field_name in _strings(manifest.get("functional_phenotype_computed_not_published", [])):
		_check(fp.contains("\"%s\"" % field_name), "FunctionalPhenotype computes/seals %s" % field_name)
		_check(not evaluation.contains("\"%s\"" % field_name), "LS3.4 does not publish hidden field %s" % field_name)
	_check(fp.contains("var realized_crown_radius :="), "crown radius is genuinely computed, not a documentation-only field")
	_check(fp.contains("var crown_density :="), "crown density is genuinely computed")
	_check(fp.contains("var structural_investment :="), "structural investment is genuinely compiled")

func _m4_realized_topology_boundary(manifest: Dictionary) -> void:
	var ph2 := _source("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
	var ls34 := _source("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
	var evaluation := _between(ls34, "var evaluation := {", "evaluation[\"evaluation_hash\"]")
	_check(ph2.contains("\"realized_development_traits\": realized"), "PH2 owns exact realized development traits")
	_check(ph2.contains("\"growth_graph\": graph"), "PH2 builds exact realized GrowthGraph")
	for field_name in _strings(manifest.get("realized_topology_computed_not_published", [])):
		_check(ph2.contains(field_name), "PH2 realized topology contains %s" % field_name)
		_check(not evaluation.contains("\"%s\"" % field_name), "LS3.4 evaluation does not expose realized topology field %s" % field_name)
	_check(ph2.contains("shade_branch_suppression"), "PH2 topology responds to shade")
	_check(ph2.contains("light_branching"), "PH2 topology responds to light")
	_check(ph2.contains("drought_suppression"), "PH2 topology responds to drought")

func _m5_hereditary_record_sources(manifest: Dictionary) -> void:
	var traits := _source("res://scripts/research/ecology/plant_development_traits_v1.gd")
	var ext := _source("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
	var lineage := _source("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
	var hereditary: Dictionary = manifest.get("hereditary_record_fields", {})
	for field_name in _strings(hereditary.get("dev_traits", [])):
		_check(traits.contains("\"%s\"" % field_name), "PH0 hereditary contract contains %s" % field_name)
	for field_name in _strings(hereditary.get("ext_traits", [])):
		_check(ext.contains("\"%s\"" % field_name), "EVO7 hereditary extension contains %s" % field_name)
	for field_name in _strings(hereditary.get("identity", [])):
		_check(lineage.contains("\"%s\"" % field_name), "hereditary bundle carries identity field %s" % field_name)

func _m6_evolution_mutability_truth(manifest: Dictionary) -> void:
	var lineage := _source("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
	var axes := _between(lineage, "const AXIS_NAMES", "static func default_policy")
	var kernel := _source("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
	var mutable: Dictionary = manifest.get("evolution_mutability", {})
	for field_name in _strings(mutable.get("mutable_in_evo7_r1", [])):
		if field_name == "root_depth_m":
			_check(kernel.contains("\"root_depth_m\""), "root_depth_m remains mutable through genome kernel")
		else:
			_check(axes.contains(field_name), "EVO7 R1 mutation authority contains %s" % field_name)
	for field_name in _strings(mutable.get("heritable_but_not_mutated_in_evo7_r1", [])):
		_check(not axes.contains(field_name), "%s is heritable PH0 structure but not an EVO7 R1 mutation axis" % field_name)

func _m7_vis2_descriptor_gap(manifest: Dictionary) -> void:
	var vis2 := _source("res://scripts/labs/ecology/eco_evo7_vis2_phenotype_render_adapter.gd")
	var descriptor_fields := _between(vis2, "const DESCRIPTOR_FIELDS", "func build")
	_check(not descriptor_fields.is_empty(), "VIS2 descriptor field block located")
	for field_name in ["phenotype_hash", "realized_height_m", "leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m", "root_shoot_ratio"]:
		_check(descriptor_fields.contains(field_name), "VIS2 currently carries %s" % field_name)
	for field_name in ["individual_seed", "realized_crown_radius_m", "realized_crown_density", "structural_investment", "growth_graph_hash", "plasticity_phenotype_hash"]:
		_check(not descriptor_fields.contains(field_name), "VIS2 currently lacks %s as audited" % field_name)

func _m8_play0_current_bottleneck() -> void:
	var play0 := _source("res://scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd")
	_check(play0.contains("BoxMesh.new()"), "PLAY0 currently uses BoxMesh stem")
	_check(play0.contains("SphereMesh.new()"), "PLAY0 currently uses SphereMesh crown")
	_check(play0.contains("leaf_area_index_proxy"), "PLAY0 current crown heuristic reads LAI")
	_check(not play0.contains("realized_crown_radius_m"), "PLAY0 current primary path ignores realized crown radius")
	_check(not play0.contains("plant_multiscale_materializer_v1.gd"), "PLAY0 current primary path does not yet consume PH5 multiscale materializer")

func _m9_ph5_reuse_and_gaps(manifest: Dictionary) -> void:
	var graph := _source("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
	var render := _source("res://scripts/research/ecology/plant_render_description_v1.gd")
	var multiscale := _source("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
	var materializer := _source("res://scripts/research/ecology/plant_3d_materializer_v1.gd")
	var ph5: Dictionary = manifest.get("ph5_reuse", {})
	for component in _strings(ph5.get("components", [])):
		_check(FileAccess.file_exists("res://scripts/research/ecology/%s" % component), "PH5 capability donor exists: %s" % component)
	_check(graph.contains("individual_seed") and graph.contains("branch_probability") and graph.contains("branch_angle_deg"), "GrowthGraph is deterministic and topology-driven")
	_check(render.contains("\"derived_representation\": true"), "PH5 render description is derived")
	_check(multiscale.contains("\"ecological_truth_hash\""), "PH5 LOD keeps truth hash separate")
	_check(materializer.contains("ArrayMesh") and materializer.contains("MultiMesh"), "PH5 materializer provides branch mesh and instanced foliage")
	_check(render.contains("var base_radius := 0.035 if main_axis else 0.014"), "PH5 branch radius is currently fixed presentation logic")
	_check(render.contains("var leaf_count := 0 if index == 0 else (1 if main_axis else 2)"), "PH5 foliage anchor count is currently fixed by segment class")
	_check(not render.contains("structural_investment"), "PH5 render description does not yet consume structural investment")
	_check(not render.contains("realized_crown_density"), "PH5 render description does not yet consume realized crown density")
	_check(not render.contains("leaf_conservative_strategy"), "PH5 render description does not yet consume leaf strategy")

func _m10_mapping_policy(manifest: Dictionary) -> void:
	var mappings_value = manifest.get("visual_mappings", [])
	_check(mappings_value is Array, "visual mappings are an array")
	if not mappings_value is Array:
		return
	var mappings: Array = mappings_value
	var by_property := {}
	for value in mappings:
		_check(value is Dictionary, "visual mapping entry is a dictionary")
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		var property_name := String(item.get("visual_property", ""))
		_check(not property_name.is_empty() and not by_property.has(property_name), "visual mapping property unique: %s" % property_name)
		by_property[property_name] = item
	for required in ["height", "crown_width", "crown_density", "leaf_area", "structural_cue", "branch_topology", "individual_variation", "topology_seal"]:
		_check(by_property.has(required), "mapping contains %s" % required)
	if by_property.has("branch_topology"):
		var topology: Dictionary = by_property["branch_topology"]
		_check(String(topology.get("preferred_source", "")) == "PH2.realized_development_traits", "exact live branch topology prefers realized PH2 traits")
		_check(String(topology.get("status", "")) == "VIS4_1_REALIZED_TOPOLOGY_EVIDENCE_REQUIRED", "branch topology gap routes to VIS4.1 evidence")
	var forbidden := _strings(manifest.get("forbidden", []))
	_check(forbidden.has("renderer recomputes functional phenotype"), "renderer phenotype recomputation explicitly forbidden")
	_check(forbidden.has("TREE_BUSH_GRASS canonical classes"), "canonical morphology classes explicitly forbidden")

func _source(path: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	_check(not source.is_empty(), "source exists: %s" % path)
	return source

func _between(source: String, start_token: String, end_token: String) -> String:
	var start := source.find(start_token)
	if start < 0:
		return ""
	var end := source.find(end_token, start + start_token.length())
	if end < 0:
		return ""
	return source.substr(start, end - start)

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
		print("ECO.EVO7 VIS4.0 Truth / Contract Audit: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS4.0 FAIL: %s" % failure)
	print("ECO.EVO7 VIS4.0 Truth / Contract Audit: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
