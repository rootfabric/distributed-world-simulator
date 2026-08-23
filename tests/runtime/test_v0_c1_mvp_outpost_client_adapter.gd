extends SceneTree

const AdapterScript = preload("res://scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd")
const CommandScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")

var assertions := 0
var failures: Array[String] = []


class FakeRuntime extends RefCounted:
	var session: Dictionary = {
		"client_id": "client/m3/a",
		"session_id": "session/m3/a/1",
		"session_epoch": 1,
		"permission_epoch": 1,
		"next_sequence": 0,
	}
	var bundle: Dictionary = {}
	var captured_command: Dictionary = {}
	var captured_operation_id := ""

	func get_construction_session() -> Dictionary:
		return session.duplicate(true)

	func get_construction_bundle() -> Dictionary:
		return bundle.duplicate(true)

	func execute_construction_command_blocking(command: Dictionary, operation_id: String = "") -> Dictionary:
		captured_command = command.duplicate(true)
		captured_operation_id = operation_id
		return {"success": true, "error_code": "", "details": {}}


func _init() -> void:
	var runtime = FakeRuntime.new()
	runtime.bundle = BundleScript.create(0, [], [])
	var adapter = AdapterScript.new()
	_assert(bool(adapter.setup(runtime).get("success", false)), "adapter setup")
	var initial: Dictionary = adapter.get_status()
	_assert(bool(initial.get("ready", false)), "construction session ready")
	_assert(int(initial.get("next_stage_index", -1)) == 0, "empty world starts at foundation")
	var built: Dictionary = adapter.build_next_stage_blocking()
	_assert(bool(built.get("success", false)), "foundation command submitted")
	_assert(bool(CommandScript.validate(runtime.captured_command).get("success", false)), "foundation command is canonical")
	_assert(String(runtime.captured_command.get("construct_id", "")) == AdapterScript.CONSTRUCT_ID, "command targets MVP outpost")
	_assert(int(runtime.captured_command.get("sequence", -1)) == 0, "first construction sequence is zero")
	var payload: Dictionary = runtime.captured_command.get("payload", {})
	_assert(int(payload.get("stage_index", -1)) == 0, "foundation stage index")
	_assert(Array(payload.get("provided_capabilities", [])).has("FASTEN"), "foundation provides FASTEN")
	_assert(String(runtime.captured_operation_id).begins_with("operation/"), "outer M3 operation is canonical")

	runtime.session["next_sequence"] = 1
	runtime.bundle = BundleScript.create(1, [], [_foundation_snapshot()])
	var shell: Dictionary = adapter.get_status()
	_assert(int(shell.get("completed_stage_count", 0)) == 1, "foundation snapshot advances progress")
	_assert(int(shell.get("next_stage_index", -1)) == 1, "shell is next")
	_finish()


func _foundation_snapshot() -> Dictionary:
	var part := PartScript.create(
		AdapterScript.FOUNDATION_PART_ID,
		"item/mvp/earth-outpost/foundation",
		"FOUNDATION",
		"base",
		80.0,
		[0.0, 0.0, 0.0],
		{"geometry": {"bounding_box_m": [6.0, 0.5, 6.0]}, "proxy_material_key": "hull"}
	)
	return SnapshotScript.create(
		AdapterScript.CONSTRUCT_ID,
		"item/mvp/earth-outpost/root",
		1,
		"OPERATIONAL",
		[part],
		[],
		{"mvp": "earth-c22-outpost"}
	)


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-C1 MVP outpost client adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-C1 MVP outpost client adapter: FAIL (%d failures)" % failures.size())
	quit(1)
