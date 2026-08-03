extends RefCounted

const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const CommandScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const C3Fixture = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const C9Fixture = preload("res://tests/construction/fixtures/c9_damage_split_repair_fixture.gd")
const C11Fixture = preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")

const CLIENT_A := "client/c12/alpha"
const CLIENT_B := "client/c12/beta"
const SESSION_A := "session/c12/alpha"
const SESSION_B := "session/c12/beta"

static func grants(epoch: int = 1) -> Array:
	return [
		GrantScript.create("permission/c12/alpha/all", CLIENT_A, "*", [GrantScript.ACTION_BUILD, GrantScript.ACTION_EDIT, GrantScript.ACTION_DAMAGE, GrantScript.ACTION_REPAIR, GrantScript.ACTION_READ], epoch),
		GrantScript.create("permission/c12/beta/edit-build", CLIENT_B, "*", [GrantScript.ACTION_BUILD, GrantScript.ACTION_EDIT, GrantScript.ACTION_READ], epoch),
	]

static func build_command(session: Dictionary, sequence: int, stage_index: int, expected_generation: int, expected_checksum: String = "") -> Dictionary:
	var operation_id := "operation/c12/build/stage-%d" % stage_index
	return CommandScript.create(
		"multiplayer-command/c12/build/%d" % stage_index,
		String(session["client_id"]), String(session["session_id"]), int(session["session_epoch"]), sequence,
		GrantScript.ACTION_BUILD, C3Fixture.CONSTRUCT_ID, expected_checksum, expected_generation, int(session["permission_epoch"]),
		{"build_plan_id": C3Fixture.BUILD_PLAN_ID, "stage_index": stage_index, "operation_id": operation_id, "provided_capabilities": ["FASTEN"] if stage_index < 2 else ["INSPECT"], "options": {}}
	)

static func edit_command(session: Dictionary, sequence: int, key: String, graph: Dictionary, expected_generation: int, length_m: float, edit_index: int = 1) -> Dictionary:
	var request := C11Fixture.request(key, graph, [C11Fixture.move_end(0, [length_m, 0.0, 0.0])], [C11Fixture.min_segment(0.5)], edit_index)
	return CommandScript.create(
		"multiplayer-command/c12/edit/%s/%d" % [key, edit_index],
		String(session["client_id"]), String(session["session_id"]), int(session["session_epoch"]), sequence,
		GrantScript.ACTION_EDIT, String(graph["snapshot"]["construct_id"]), String(graph["snapshot"]["checksum"]), expected_generation, int(session["permission_epoch"]),
		{"plan_id": "plan/c12/edit/%s/%d" % [key, edit_index], "request": request, "failure_mode": ""}
	)

static func damage_command(session: Dictionary, sequence: int, key: String, snapshot: Dictionary, expected_generation: int) -> Dictionary:
	var request := C9Fixture.request(key, snapshot)
	var operation_id := "operation/c12/damage/%s" % key
	return CommandScript.create(
		"multiplayer-command/c12/damage/%s/%s" % [key, String(session["client_id"]).replace("/", "-")],
		String(session["client_id"]), String(session["session_id"]), int(session["session_epoch"]), sequence,
		GrantScript.ACTION_DAMAGE, String(snapshot["construct_id"]), String(snapshot["checksum"]), expected_generation, int(session["permission_epoch"]),
		{"plan_id": "plan/c12/damage/%s" % key, "operation_id": operation_id, "request": request, "failure_mode": ""}
	)

static func repair_command(session: Dictionary, sequence: int, key: String, repair_plan: Dictionary, snapshot_checksum: String, expected_generation: int) -> Dictionary:
	var operation_id := "operation/c12/repair/%s" % key
	return CommandScript.create(
		"multiplayer-command/c12/repair/%s/%s" % [key, String(session["client_id"]).replace("/", "-")],
		String(session["client_id"]), String(session["session_id"]), int(session["session_epoch"]), sequence,
		GrantScript.ACTION_REPAIR, String(repair_plan["target_construct_id"]), snapshot_checksum, expected_generation, int(session["permission_epoch"]),
		{"plan_id": "plan/c12/repair/%s" % key, "operation_id": operation_id, "repair_plan": repair_plan, "failure_mode": ""}
	)
