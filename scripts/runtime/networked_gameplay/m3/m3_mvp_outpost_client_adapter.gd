extends RefCounted

# Thin V0 composition adapter. It creates canonical Construction commands from
# the session/bundle replicated by M3; it owns no construct state and performs
# no local Construction mutation.
const CommandScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")

const CONSTRUCT_ID := "construct/mvp/earth-outpost"
const BUILD_PLAN_ID := "build-plan/mvp/earth-outpost"
const FOUNDATION_PART_ID := "part/mvp/outpost/foundation"
const WALL_PART_IDS: Array[String] = [
	"part/mvp/outpost/wall-n",
	"part/mvp/outpost/wall-s",
	"part/mvp/outpost/wall-e",
	"part/mvp/outpost/wall-w",
]
const ROOF_PART_ID := "part/mvp/outpost/roof"
const STAGE_LABELS: Array[String] = ["фундамент", "стены", "крыша"]

var _runtime
var _session_id := ""
var _local_next_sequence := 0


func setup(runtime) -> Dictionary:
	if (
		runtime == null
		or not runtime.has_method("get_construction_session")
		or not runtime.has_method("get_construction_bundle")
		or not runtime.has_method("execute_construction_command_blocking")
	):
		return _failure("V0_OUTPOST_CONSTRUCTION_RUNTIME_REQUIRED")
	_runtime = runtime
	_sync_sequence_from_runtime()
	return _success()


func get_status() -> Dictionary:
	if _runtime == null:
		return {
			"ready": false,
			"complete": false,
			"next_stage_index": 0,
			"next_stage_label": STAGE_LABELS[0],
			"completed_stage_count": 0,
			"server_generation": -1,
			"construct_checksum": "",
		}
	var bundle: Dictionary = _runtime.get_construction_bundle()
	var snapshot := _find_outpost_snapshot(bundle)
	var part_ids := _part_id_set(snapshot)
	var completed := 0
	if part_ids.has(FOUNDATION_PART_ID):
		completed = 1
		var shell_complete := true
		for part_id in WALL_PART_IDS:
			if not part_ids.has(part_id):
				shell_complete = false
				break
		if shell_complete:
			completed = 2
			if part_ids.has(ROOF_PART_ID):
				completed = 3
	var complete := completed >= STAGE_LABELS.size()
	return {
		"ready": not _runtime.get_construction_session().is_empty(),
		"complete": complete,
		"next_stage_index": -1 if complete else completed,
		"next_stage_label": "готово" if complete else STAGE_LABELS[completed],
		"completed_stage_count": completed,
		"server_generation": int(bundle.get("server_generation", -1)),
		"construct_checksum": String(snapshot.get("checksum", "")),
	}


func build_next_stage_blocking() -> Dictionary:
	if _runtime == null:
		return _failure("V0_OUTPOST_CONSTRUCTION_NOT_CONFIGURED")
	_sync_sequence_from_runtime()
	var status := get_status()
	if not bool(status.get("ready", false)):
		return _failure("V0_OUTPOST_CONSTRUCTION_SESSION_NOT_READY")
	if bool(status.get("complete", false)):
		return _failure("V0_OUTPOST_ALREADY_COMPLETE", status)
	var stage_index := int(status.get("next_stage_index", -1))
	if stage_index < 0 or stage_index >= STAGE_LABELS.size():
		return _failure("V0_OUTPOST_INVALID_NEXT_STAGE", status)

	var session: Dictionary = _runtime.get_construction_session()
	var bundle: Dictionary = _runtime.get_construction_bundle()
	var sequence := maxi(int(session.get("next_sequence", 0)), _local_next_sequence)
	var client_id := String(session.get("client_id", ""))
	var session_id := String(session.get("session_id", ""))
	var id_token := client_id.replace("/", "-")
	var stage_operation_id := "operation/mvp/outpost/%s/stage-%d/seq-%d" % [
		id_token, stage_index, sequence
	]
	var command_id := "multiplayer-command/mvp/outpost/%s/stage-%d/seq-%d" % [
		id_token, stage_index, sequence
	]
	var provided_capabilities: Array = ["INSPECT"] if stage_index == 2 else ["FASTEN"]
	var command := CommandScript.create(
		command_id,
		client_id,
		session_id,
		int(session.get("session_epoch", 0)),
		sequence,
		GrantScript.ACTION_BUILD,
		CONSTRUCT_ID,
		String(status.get("construct_checksum", "")),
		int(bundle.get("server_generation", -1)),
		int(session.get("permission_epoch", 0)),
		{
			"build_plan_id": BUILD_PLAN_ID,
			"stage_index": stage_index,
			"operation_id": stage_operation_id,
			"provided_capabilities": provided_capabilities,
			"options": {},
		},
		{"v0_checkpoint": "V0-C1"}
	)
	var outer_operation_id := "operation/m3/%s/v0-outpost/%d/%d" % [
		id_token, stage_index, sequence
	]
	var submitted: Dictionary = _runtime.execute_construction_command_blocking(
		command,
		outer_operation_id
	)
	if not bool(submitted.get("success", false)):
		return submitted
	_local_next_sequence = sequence + 1
	return _success({
		"stage_index": stage_index,
		"stage_label": STAGE_LABELS[stage_index],
		"command_id": command_id,
		"operation_id": outer_operation_id,
		"result": submitted.duplicate(true),
	})


func _sync_sequence_from_runtime() -> void:
	if _runtime == null:
		return
	var session: Dictionary = _runtime.get_construction_session()
	if session.is_empty():
		return
	var current_session_id := String(session.get("session_id", ""))
	if current_session_id != _session_id:
		_session_id = current_session_id
		_local_next_sequence = int(session.get("next_sequence", 0))
	else:
		_local_next_sequence = maxi(
			_local_next_sequence,
			int(session.get("next_sequence", 0))
		)


func _find_outpost_snapshot(bundle: Dictionary) -> Dictionary:
	for value in bundle.get("constructs", []):
		if value is Dictionary and String(value.get("construct_id", "")) == CONSTRUCT_ID:
			return Dictionary(value).duplicate(true)
	return {}


func _part_id_set(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for value in snapshot.get("parts", []):
		if value is Dictionary:
			result[String(value.get("part_id", ""))] = true
	return result


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
