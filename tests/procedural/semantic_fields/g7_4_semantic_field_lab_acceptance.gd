extends SceneTree

const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")

const MANIFEST_PATH := "res://config/procedural/g7-4-semantic-field-lab.v1.json"
const G73_VALIDATION_PATH := "res://validation/g7-3-cross-cell-cross-lod-invariance-validation.json"
const SCENE_PATH := "res://scenes/labs/procedural/g7_4_semantic_field_lab.tscn"
const SCRIPT_PATH := "res://scripts/labs/procedural/g7_4_semantic_field_lab_fix4.gd"
const BASE_SCRIPT_PATH := "res://scripts/labs/procedural/g7_4_semantic_field_lab.gd"
const AVAILABLE_FIELDS: Array[String] = [
	Registry.SURFACE_HEIGHT_M,
	Registry.VALLEY_INFLUENCE,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
	Registry.FLUID_SURFACE_DISTANCE_M,
]
const VOCABULARY_ONLY_FIELDS: Array[String] = [
	Registry.SLOPE,
	Registry.CURVATURE,
	Registry.DRAINAGE_POTENTIAL,
	Registry.CONTINENTALNESS,
	Registry.TEMPERATURE_BASELINE,
	Registry.MOISTURE_BASELINE,
]
const EXPECTED_LOD_STRIDES: Array[int] = [1, 2, 4, 8]
const EXPECTED_LOD_GRIDS: Array = [[33, 17], [17, 9], [9, 5], [5, 3]]

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_g73_acceptance()
	_test_registry_boundary()
	_test_scene_contract()
	_finish()


func _test_manifest() -> void:
	_assert(FileAccess.file_exists(MANIFEST_PATH), "G7.4 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_assert(parsed is Dictionary, "G7.4 manifest parses")
	if not (parsed is Dictionary):
		return
	var manifest: Dictionary = parsed
	_assert(String(manifest.get("checkpoint", "")) == "g7.4-semantic-field-lab", "G7.4 checkpoint id")
	_assert(String(manifest.get("status", "")) in ["IMPLEMENTED_CANDIDATE", "ACCEPTED"], "G7.4 status supports candidate to accepted transition")
	_assert(String(manifest.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-10-R2", "G7.4 uses active R2 revision")
	_assert(String(manifest.get("script", "")) == SCRIPT_PATH, "G7.4 manifest points to Fix4 presentation wrapper")
	_assert(String(manifest.get("base_script", "")) == BASE_SCRIPT_PATH, "G7.4 manifest retains the accepted semantic lab base script")
	_assert(Array(manifest.get("visualized_fields", [])) == AVAILABLE_FIELDS, "G7.4 visualized field list is exact")
	_assert(Array(manifest.get("vocabulary_only_not_faked", [])) == VOCABULARY_ONLY_FIELDS, "G7.4 explicitly lists vocabulary-only fields")
	var grid: Dictionary = manifest.get("sample_grid", {})
	_assert(int(grid.get("latitude_segments", -1)) == 16, "G7.4 latitude segments pinned")
	_assert(int(grid.get("longitude_segments", -1)) == 32, "G7.4 longitude segments pinned")
	_assert(int(grid.get("expected_vertices", -1)) == 561, "G7.4 expected semantic sample count pinned")
	var lod: Dictionary = manifest.get("presentation_lod", {})
	_assert(String(lod.get("mode", "")) == "CAMERA_DISTANCE_DERIVED", "G7.4 presentation LOD is camera-distance derived")
	_assert(int(lod.get("semantic_source_sample_count", -1)) == 561, "G7.4 all presentation LODs reuse 561 semantic records")
	_assert(bool(lod.get("reuses_same_semantic_records", false)), "G7.4 presentation LOD reuses same semantic records")
	_assert(not bool(lod.get("changes_canonical_semantics", true)), "presentation LOD cannot change canonical semantics")
	_assert(not bool(lod.get("changes_semantic_query", true)), "presentation LOD cannot change semantic query")
	_assert(not bool(lod.get("changes_feature_identity", true)), "presentation LOD cannot change feature identity")
	_assert(not bool(lod.get("changes_fluid_identity", true)), "presentation LOD cannot change fluid identity")
	_assert(not bool(lod.get("included_in_canonical_checksum", true)), "presentation LOD excluded from canonical checksum")
	var levels: Array = lod.get("levels", [])
	_assert(levels.size() == 4, "G7.4 exposes four visible presentation LOD levels")
	if levels.size() == 4:
		var strides: Array[int] = []
		var grids: Array = []
		for index in range(levels.size()):
			var level: Dictionary = levels[index]
			_assert(int(level.get("lod", -1)) == index, "G7.4 presentation LOD%d id" % index)
			strides.append(int(level.get("stride", 0)))
			var mesh_grid: Array = level.get("mesh_grid", [])
			if mesh_grid.size() == 2:
				grids.append([int(mesh_grid[0]), int(mesh_grid[1])])
			else:
				grids.append([])
		_assert(strides == EXPECTED_LOD_STRIDES, "G7.4 presentation LOD strides are 1/2/4/8")
		_assert(grids == EXPECTED_LOD_GRIDS, "G7.4 presentation LOD grids are 33x17 -> 5x3")

	var fix4: Dictionary = manifest.get("presentation_fix4", {})
	var shell: Dictionary = fix4.get("surface_shell", {})
	var river: Dictionary = fix4.get("river_overlay", {})
	_assert(String(shell.get("mode", "")) == "HEIGHT_RANGE_DERIVED_UNIFORM_RADIAL_LIFT", "Fix4 uses a uniform height-range-derived presentation shell lift")
	_assert(float(shell.get("minimum_vertex_clearance_display_units", 0.0)) >= 0.07, "Fix4 reserves enough vertex clearance above the debug sphere")
	_assert(bool(shell.get("includes_coarse_chord_guard", false)), "Fix4 shell includes a coarse-LOD chord guard")
	_assert(bool(shell.get("preserves_relative_height_shape", false)), "Fix4 shell preserves relative semantic height shape")
	_assert(String(river.get("source", "")) == "ACCEPTED_CANONICAL_RIVER_CENTERLINE_SPLINE", "Fix4 river overlay derives from the accepted canonical centerline")
	_assert(String(river.get("geometry", "")) == "TRIANGLE_STRIP_DIAGNOSTIC_RIBBON", "Fix4 river overlay is a visible diagnostic ribbon")
	_assert(not bool(river.get("represents_physical_river_width", true)), "Fix4 diagnostic ribbon does not pretend to be physical river width")
	_assert(float(river.get("clearance_above_patch_display_units", 0.0)) > 0.0, "Fix4 river ribbon is lifted above the patch")
	_assert(not bool(fix4.get("changes_canonical_semantics", true)), "Fix4 cannot change canonical semantics")
	_assert(not bool(fix4.get("changes_semantic_query", true)), "Fix4 cannot change canonical semantic queries")
	_assert(not bool(fix4.get("changes_feature_identity", true)), "Fix4 cannot create or change FeatureId")
	_assert(not bool(fix4.get("changes_fluid_identity", true)), "Fix4 cannot create or change FluidRegionId")
	_assert(not bool(fix4.get("included_in_canonical_checksum", true)), "Fix4 presentation is excluded from canonical checksums")

	var presentation: Dictionary = manifest.get("presentation_contract", {})
	_assert(not bool(presentation.get("field_selection_changes_canonical_query", true)), "field selector cannot change canonical query")
	_assert(not bool(presentation.get("field_selection_changes_geometry", true)), "field selector cannot change geometry")
	_assert(bool(presentation.get("field_selection_changes_only_derived_color", false)), "field selector changes derived color only")
	_assert(not bool(presentation.get("camera_changes_canonical_semantics", true)), "camera cannot change canonical semantics")
	_assert(not bool(presentation.get("presentation_lod_changes_canonical_semantics", true)), "presentation LOD cannot own semantic truth")
	_assert(bool(presentation.get("presentation_lod_reuses_same_semantic_records", false)), "presentation LOD uses the same semantic record source")
	_assert(not bool(presentation.get("visual_colors_in_canonical_checksum", true)), "visual colors excluded from canonical checksum")
	_assert(not bool(presentation.get("mesh_density_in_canonical_checksum", true)), "mesh density excluded from canonical checksum")
	_assert(not bool(presentation.get("presentation_shell_in_canonical_checksum", true)), "Fix4 presentation shell excluded from canonical checksum")
	_assert(not bool(presentation.get("river_overlay_geometry_in_canonical_checksum", true)), "Fix4 river ribbon excluded from canonical checksum")
	_assert(not bool(presentation.get("creates_new_feature_identity", true)), "G7.4 creates no production FeatureId ownership")
	_assert(not bool(presentation.get("creates_new_fluid_identity", true)), "G7.4 creates no FluidRegionId ownership")


func _test_g73_acceptance() -> void:
	_assert(FileAccess.file_exists(G73_VALIDATION_PATH), "G7.3 validation exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(G73_VALIDATION_PATH))
	_assert(parsed is Dictionary, "G7.3 validation parses")
	if parsed is Dictionary:
		_assert(String(parsed.get("decision", "")) == "ACCEPTED", "G7.3 is accepted before G7.4")
		_assert(int(parsed.get("windows_evidence", {}).get("focused_assertions", 0)) == 122, "G7.3 122-assertion proof retained")
		_assert(String(parsed.get("windows_evidence", {}).get("world_core_regression", "")) == "PASS", "G7.3 world regression retained")


func _test_registry_boundary() -> void:
	_assert(bool(Registry.validate_registry().get("success", false)), "semantic registry validates")
	for field_id in AVAILABLE_FIELDS:
		var descriptor := Registry.descriptor(field_id)
		var availability := String(descriptor.get("metadata", {}).get("availability", ""))
		_assert(availability != Registry.VOCABULARY_ONLY, "%s is backed by accepted semantics" % field_id)
	for field_id in VOCABULARY_ONLY_FIELDS:
		var descriptor := Registry.descriptor(field_id)
		var availability := String(descriptor.get("metadata", {}).get("availability", ""))
		_assert(availability == Registry.VOCABULARY_ONLY, "%s remains vocabulary-only and must not be faked" % field_id)


func _test_scene_contract() -> void:
	_assert(FileAccess.file_exists(BASE_SCRIPT_PATH), "G7.4 base lab script exists")
	_assert(ResourceLoader.exists(BASE_SCRIPT_PATH), "G7.4 base lab script is loadable")
	_assert(FileAccess.file_exists(SCRIPT_PATH), "G7.4 Fix4 lab script exists")
	_assert(ResourceLoader.exists(SCRIPT_PATH), "G7.4 Fix4 lab script is loadable")
	_assert(FileAccess.file_exists(SCENE_PATH), "G7.4 lab scene exists")
	var packed = ResourceLoader.load(SCENE_PATH)
	_assert(packed is PackedScene, "G7.4 scene loads as PackedScene")
	if not (packed is PackedScene):
		return
	var root: Node = packed.instantiate()
	_assert(root.name == "G74SemanticFieldLab", "G7.4 scene root")
	_assert(root.get_node_or_null("Planet") is MeshInstance3D, "G7.4 scene has planet")
	_assert(root.get_node_or_null("Camera3D") is Camera3D, "G7.4 scene has camera")
	_assert(root.get_node_or_null("HUD/Panel/Margin/VBox/Status") is Label, "G7.4 scene has semantic HUD")
	var root_script = root.get_script()
	_assert(root_script != null and String(root_script.resource_path) == SCRIPT_PATH, "G7.4 scene uses expected Fix4 wrapper script")
	root.free()


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("G7.4 Semantic Field Lab contracts: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
