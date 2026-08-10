extends SceneTree

const Probe = preload("res://scripts/labs/t1/ts0/ts0_local_dirty_rebuild_probe.gd")
const BASE_CONFIG := "res://config/construction/ts0-large-structural-visual-lab.v1.json"
const STAGE_CONFIG := "res://config/construction/ts0-local-dirty-rebuild.v1.json"

var assertions := 0
var failures := 0

func _init() -> void:
	var base = JSON.parse_string(FileAccess.get_file_as_string(BASE_CONFIG))
	var stage = JSON.parse_string(FileAccess.get_file_as_string(STAGE_CONFIG))
	_check(typeof(base) == TYPE_DICTIONARY, "base config")
	_check(typeof(stage) == TYPE_DICTIONARY, "stage config")
	var profile: Dictionary = base["profiles"][String(stage["profile"])]
	var dims: Array = profile["dimensions"]
	var mutation: Dictionary = base["mutation_probe"]
	var remove_dims: Array = mutation["dimensions"]
	var started := Time.get_ticks_msec()
	var result := Probe.run_cube_corner_probe(
		Vector3i(int(dims[0]), int(dims[1]), int(dims[2])),
		int(stage["section_size_cells"]),
		int(stage["cluster_edge_sections"]),
		Vector3i(int(remove_dims[0]), int(remove_dims[1]), int(remove_dims[2]))
	)
	var elapsed_ms := Time.get_ticks_msec() - started
	_check(bool(result.get("success", false)), "probe success")
	var a: Dictionary = stage["acceptance"]
	_check(int(result["initial_part_count"]) == int(a["expected_initial_parts"]), "initial part count")
	_check(int(result["removed_part_count"]) == int(a["expected_removed_parts"]), "removed part count")
	_check(int(result["removed_part_count"]) == int(mutation["expected_removed_parts"]), "mutation contract")
	_check(int(result["current_part_count"]) == int(a["expected_initial_parts"]) - int(a["expected_removed_parts"]), "current part count")
	_check(int(result["total_section_count"]) == int(a["expected_total_sections"]), "total sections")
	_check(int(result["base_dirty_section_count"]) == int(a["expected_base_dirty_sections"]), "base dirty sections")
	_check(int(result["rebuild_section_count"]) == int(a["expected_rebuild_sections"]), "rebuild sections")
	_check(int(result["removed_section_count"]) == int(a["expected_removed_sections"]), "removed sections")
	_check(int(result["reused_section_count"]) == int(a["expected_reused_sections"]), "reused sections")
	_check(int(result["dirty_cluster_count"]) == int(a["expected_dirty_clusters"]), "dirty clusters")
	_check(float(result["affected_section_ratio"]) <= float(a["max_affected_section_ratio"]), "affected ratio bounded")
	_check(bool(result["full_snapshot_part_scan_required"]) == bool(a["full_snapshot_part_scan_for_rebuild"]), "no full snapshot scan")
	_check(bool(result["full_c22_compile_required"]) == bool(a["full_c22_compile_for_rebuild"]), "no full c22 compile")
	_check(int(result["scanned_rebuild_cells"]) <= int(result["rebuild_section_count"]) * 512, "bounded cell scan")
	_check(int(result["context_occupancy_cells"]) < int(result["initial_part_count"]) / 3, "context smaller than construct")
	var records: Dictionary = result["section_records"]
	_check(not records.has("5/5/5"), "empty corner section removed")
	_check(records.has("4/4/4"), "neighbor section rebuilt")
	_check(int(records["4/4/4"]["merged_quad_count"]) > 0, "new exposed surface exists")
	var valid_quads := true
	for record_value in records.values():
		for batch in record_value["material_batches"]:
			for quad in batch["quads"]:
				if String(quad.get("kind", "")) != "GRID_QUAD" or int(quad.get("width", 0)) < 1 or int(quad.get("height", 0)) < 1:
					valid_quads = false
	_check(valid_quads, "rebuilt quads are C24 grid compatible")
	_check(Array(result["dirty_cluster_keys"]).size() == 1, "one cluster key")
	_check(String(result["dirty_cluster_keys"][0]) == "1/1/1", "corner cluster identity")
	print("TS0.3 metric elapsed_ms=%d rebuild_sections=%d reused=%d dirty_clusters=%d scanned_cells=%d context_cells=%d" % [elapsed_ms, int(result["rebuild_section_count"]), int(result["reused_section_count"]), int(result["dirty_cluster_count"]), int(result["scanned_rebuild_cells"]), int(result["context_occupancy_cells"])])
	if failures == 0:
		print("TS0.3 local mutation dirty-section rebuild: PASS (%d assertions)" % assertions)
	else:
		push_error("TS0.3 local mutation dirty-section rebuild: FAIL (%d failures / %d assertions)" % [failures, assertions])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(label)
