extends SceneTree

const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const RuntimeRequest = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const CompileRequest = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")

const SIZE := 32
const SECTION_SIZE := 8.0
const CUT_SIZE := 4

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_local_incremental_matches_full_compile()
	_finish()

func _test_local_incremental_matches_full_compile() -> void:
	var original := _build_snapshot(1)
	_ok(Snapshot.validate(original), "original snapshot validates")
	_assert(Array(original["parts"]).size() == SIZE * SIZE * SIZE, "original cube part count")

	var controller = Controller.new()
	root.add_child(controller)
	var initial := controller.compile_construct(_compile_request(original))
	_ok(initial, "initial C22 compile")
	var initial_manifest: Dictionary = initial["manifest"]
	_assert(int(initial_manifest["total_section_count"]) == 64, "32m cube has 64 sections at 8m")

	var mutated_result := _build_mutated_snapshot(original)
	var mutated: Dictionary = mutated_result["snapshot"]
	var dirty_part_ids: Array = mutated_result["dirty_part_ids"]
	_ok(Snapshot.validate(mutated), "mutated snapshot validates")
	_assert(dirty_part_ids.size() == CUT_SIZE * CUT_SIZE * CUT_SIZE, "64 removed parts declared dirty")
	_assert(Array(mutated["parts"]).size() == SIZE * SIZE * SIZE - CUT_SIZE * CUT_SIZE * CUT_SIZE, "mutated part count")

	var incremental := controller.recompile_incremental(_compile_request(mutated), dirty_part_ids)
	_ok(incremental, "production incremental rebuild")
	_assert(bool(incremental.get("incremental_fast_path", false)), "local fast path selected")
	var stats: Dictionary = incremental["stats"]
	_assert(bool(stats.get("incremental_fast_path", false)), "stats record fast path")
	_assert(not bool(stats.get("full_compile_used", true)), "full compile not used")
	_assert(not bool(stats.get("full_snapshot_scan_used", true)), "full snapshot scan not used")
	_assert(int(stats.get("base_dirty_section_count", -1)) == 1, "corner cut starts in one base section")
	_assert(int(stats.get("rebuild_section_count", -1)) == 8, "neighbor-safe rebuild limited to eight sections")
	_assert(int(stats.get("reused_section_count", -1)) == 56, "fifty-six unchanged sections reused")
	_assert(int(stats.get("context_section_count", -1)) == 27, "context bounded to 27 sections")
	_assert(int(stats.get("context_section_count", 0)) < int(initial_manifest["total_section_count"]), "context remains below full construct section count")
	_assert(int(stats.get("snapshot_binary_search_lookups", 0)) > 0, "snapshot uses indexed binary lookup work")

	var reference_controller = Controller.new()
	root.add_child(reference_controller)
	var reference := reference_controller.compile_construct(_compile_request(mutated))
	_ok(reference, "reference full compile of mutated snapshot")
	var incremental_manifest: Dictionary = incremental["manifest"]
	var reference_manifest: Dictionary = reference["manifest"]
	_assert(String(incremental_manifest["source_checksum"]) == String(mutated["checksum"]), "incremental manifest pins mutated checksum")
	_assert(String(incremental_manifest["shell_artifact_id"]) == String(reference_manifest["shell_artifact_id"]), "incremental shell matches full compile")
	_assert(_section_artifact_map(incremental_manifest) == _section_artifact_map(reference_manifest), "all incremental section artifacts match full compile")
	_assert(String(controller.get_topology(String(mutated["construct_id"]))["checksum"]) == String(reference_controller.get_topology(String(mutated["construct_id"]))["checksum"]), "incremental topology matches full compile")
	var plan: Dictionary = incremental["invalidation_plan"]
	_assert(Array(plan["dirty_section_ids"]).size() == 8, "invalidation is bounded to rebuilt section neighborhood")
	_assert(bool(plan["shell_rebuilt"]), "root shell rebuilt after visible corner cut")

	var policy_changed_snapshot := Snapshot.create(
		String(mutated["construct_id"]),
		String(mutated["root_item_instance_id"]),
		3,
		String(mutated["build_state"]),
		Array(mutated["parts"]).duplicate(true),
		Array(mutated["bonds"]).duplicate(true),
		Dictionary(mutated["compiled_facets"]).duplicate(true)
	)
	var changed_request := _compile_request(policy_changed_snapshot, 4.0)
	var fallback := controller.recompile_incremental(changed_request, [String(Array(policy_changed_snapshot["parts"])[0]["part_id"])])
	_ok(fallback, "unsupported policy change falls back safely")
	_assert(not bool(fallback.get("incremental_fast_path", true)), "policy change uses full fallback")
	_assert(String(fallback.get("fallback_reason", "")) == "COMPILE_POLICY_CHANGED", "fallback reason observable")

	controller.queue_free()
	reference_controller.queue_free()

func _build_snapshot(revision: int) -> Dictionary:
	var parts: Array = []
	for z in range(SIZE):
		for y in range(SIZE):
			for x in range(SIZE):
				parts.append(_part(x, y, z))
	return Snapshot.create(
		"construct/c22/incremental-grid",
		"item/c22/incremental-grid/root",
		revision,
		"OPERATIONAL",
		parts,
		[],
		{"c22_incremental_test": true}
	)

func _build_mutated_snapshot(original: Dictionary) -> Dictionary:
	var parts: Array = []
	var dirty: Array = []
	for part_value in original["parts"]:
		var part: Dictionary = part_value
		var position: Array = part["local_position_m"]
		if int(round(float(position[0]))) < CUT_SIZE and int(round(float(position[1]))) < CUT_SIZE and int(round(float(position[2]))) < CUT_SIZE:
			dirty.append(String(part["part_id"]))
			continue
		parts.append(part.duplicate(true))
	dirty.sort()
	return {
		"snapshot": Snapshot.create(
			String(original["construct_id"]),
			String(original["root_item_instance_id"]),
			2,
			"OPERATIONAL",
			parts,
			[],
			Dictionary(original["compiled_facets"]).duplicate(true)
		),
		"dirty_part_ids": dirty,
	}

func _part(x: int, y: int, z: int) -> Dictionary:
	var suffix := "x%03d-y%03d-z%03d" % [x, y, z]
	return Part.create(
		"part/c22/incremental/%s" % suffix,
		"item/c22/incremental/%s" % suffix,
		"STRUCTURAL_CELL",
		"structure",
		100.0,
		[float(x), float(y), float(z)],
		{
			"geometry": {"bounding_box_m": [1.0, 1.0, 1.0]},
			"condition": "INTACT",
			"proxy_material_key": "structure",
		}
	)

func _compile_request(snapshot: Dictionary, section_size: float = SECTION_SIZE) -> Dictionary:
	var runtime := RuntimeRequest.create(snapshot)
	return CompileRequest.create(runtime, 1, CompileRequest.OWNER, "server/c22-incremental-test", section_size, 80.0, 250.0, 1000.0, [], [])

func _section_artifact_map(manifest: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for ref_value in manifest["section_artifacts"]:
		var ref: Dictionary = ref_value
		result[String(ref["section_id"])] = String(ref["artifact_id"])
	return result

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C22 incremental local rebuild: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C22 incremental local rebuild: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
