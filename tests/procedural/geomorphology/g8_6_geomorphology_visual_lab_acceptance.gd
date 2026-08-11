extends SceneTree

const MANIFEST_PATH := "res://config/procedural/g8-6-geomorphology-visual-lab.v1.json"
const G85_VALIDATION_PATH := "res://validation/g8-5-cross-cell-cross-lod-geomorphology-invariance-validation.json"
const LAB_SCRIPT_PATH := "res://scripts/labs/procedural/g8_6_geomorphology_visual_lab.gd"
const LAB_SCENE_PATH := "res://scenes/labs/procedural/g8_6_geomorphology_visual_lab.tscn"
const EXPECTED_G85_HEAD := "6cc0c2b5ff1bc21a5b488a8492ef8cce28fa4736"
const EXPECTED_STRIDES: Array[int] = [1, 2, 4, 8]

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_parent()
	_test_manifest()
	_test_presentation_boundary()
	_finish()


func _test_parent() -> void:
	_check(FileAccess.file_exists(G85_VALIDATION_PATH), "G8.5 validation exists")
	var value = JSON.parse_string(FileAccess.get_file_as_string(G85_VALIDATION_PATH))
	_check(value is Dictionary, "G8.5 validation parses")
	if value is Dictionary:
		_check(String(value.get("decision", "")) == "ACCEPTED", "G8.5 parent accepted")
		_check(String(value.get("automated_evidence", {}).get("tested_head", "")) == EXPECTED_G85_HEAD, "G8.5 accepted tested head pinned")


func _test_manifest() -> void:
	_check(FileAccess.file_exists(MANIFEST_PATH), "G8.6 manifest exists")
	var value = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_check(value is Dictionary, "G8.6 manifest parses")
	if not (value is Dictionary):
		return
	var manifest: Dictionary = value
	_check(String(manifest.get("checkpoint", "")) == "g8.6-geomorphology-visual-lab", "G8.6 checkpoint")
	_check(String(manifest.get("status", "")) in ["IMPLEMENTED_CANDIDATE", "AUTOMATED_ACCEPTED_MANUAL_PENDING", "ACCEPTED"], "G8.6 status supports acceptance lifecycle")
	_check(String(manifest.get("lab_kind", "")) == "DERIVED_PRESENTATION_LOCAL_RIVER_CORRIDOR", "local corridor lab kind")
	_check(int(manifest.get("corridor", {}).get("sample_count", 0)) == 561, "canonical sample count pinned")
	var source_grid: Array = manifest.get("corridor", {}).get("source_grid", [])
	_check(source_grid.size() == 2 and int(source_grid[0]) == 33 and int(source_grid[1]) == 17, "source grid pinned")
	_check(Array(manifest.get("canonical_inputs", [])).size() == 4, "four canonical G8 inputs")
	_check(Array(manifest.get("views", [])).size() == 7, "seven graphical views")
	var lod_policy: Dictionary = manifest.get("presentation_lod", {})
	var strides: Array[int] = []
	for level_value in lod_policy.get("levels", []):
		if level_value is Dictionary:
			strides.append(int(Dictionary(level_value).get("stride", 0)))
	_check(strides == EXPECTED_STRIDES, "derived presentation LOD strides pinned")
	_check(not bool(lod_policy.get("changes_canonical_geomorphology", true)), "presentation LOD cannot change canonical geomorphology")
	var boundaries: Dictionary = manifest.get("architecture_boundaries", {})
	_check(bool(boundaries.get("presentation_only", false)), "G8.6 is presentation only")
	_check(not bool(boundaries.get("surface_cell_is_geomorphology_identity", true)), "SurfaceCellKey excluded from geomorphology identity")
	_check(not bool(boundaries.get("lod_is_geomorphology_identity", true)), "LOD excluded from geomorphology identity")
	_check(not bool(boundaries.get("cube_face_is_geomorphology_identity", true)), "cube face excluded from geomorphology identity")
	_check(not bool(boundaries.get("presentation_mesh_is_truth", true)), "presentation mesh is not truth")
	_check(not bool(boundaries.get("creates_seam_fixing_truth", true)), "lab creates no seam-fixing truth")


func _test_presentation_boundary() -> void:
	_check(FileAccess.file_exists(LAB_SCRIPT_PATH), "G8.6 lab script exists")
	_check(FileAccess.file_exists(LAB_SCENE_PATH), "G8.6 lab scene exists")
	var source := FileAccess.get_file_as_string(LAB_SCRIPT_PATH)
	var scene := FileAccess.get_file_as_string(LAB_SCENE_PATH)
	_check(source.find("ErosionDeposition.apply") >= 0, "lab evaluates accepted G8.4 deformation")
	_check(source.find("canonical_truth_hash") >= 0, "lab exposes canonical truth hash")
	_check(source.find("show_resolved_geometry") >= 0, "lab has source/resolved presentation toggle")
	_check(source.find("PRESENTATION_LOD_STRIDES") >= 0, "lab has derived presentation LOD")
	_check(source.find("seam_overlay") >= 0, "lab has PX/PZ diagnostic seam overlay")
	_check(scene.find("g8_6_geomorphology_visual_lab.gd") >= 0, "scene binds G8.6 script")
	for forbidden in ["MatterTransaction", "AuthorityRegion", "InterestRegion", "ENetMultiplayerPeer", "save_game", "persist_mutation"]:
		_check(source.find(forbidden) < 0, "visual lab excludes runtime ownership token %s" % forbidden)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("G8.6 FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("G8.6 Geomorphology Visual Lab Contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G8.6 Geomorphology Visual Lab Contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
