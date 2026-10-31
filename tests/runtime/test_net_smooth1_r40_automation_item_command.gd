extends SceneTree

# NET-SMOOTH1 R4.0 durable-workload diagnostics: the automation item.command
# seam must be a strict allowlist of real authoritative Item Graph commands,
# must reject unknown payloads/types, and must never treat a rejection as a
# committed durable mutation.

const App = preload("res://scripts/app/earth_mvp_app.gd")

var assertions := 0
var failures: Array[String] = []


class FakeItemRuntime:
	extends RefCounted

	var calls: Array[Dictionary] = []
	var revision := 7
	var replay_operation_ids := {"operation/m6/r40/dup": true}

	func get_item_graph_snapshot() -> Dictionary:
		return {"revision": revision}

	func execute_item_command_blocking(
		command_type: String, payload: Dictionary, operation_id: String
	) -> Dictionary:
		calls.append({
			"command_type": command_type,
			"payload": payload.duplicate(true),
			"operation_id": operation_id,
		})
		if String(operation_id) in replay_operation_ids:
			return {"success": true, "error_code": "", "details": {
				"operation_id": operation_id, "result": {"replay": true}}}
		revision += 1
		return {"success": true, "error_code": "", "details": {
			"operation_id": operation_id, "result": {"replay": false}}}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _init() -> void:
	var app = App.new()
	var runtime := FakeItemRuntime.new()
	app.m3_multiplayer_client_runtime = runtime
	app._m3_attached = true

	var blocked: Dictionary = app.automation_submit_item_command({
		"command_type": "item.grant_debug",
		"payload": {"definition_id": "item/beacon", "quantity": 1},
	})
	_assert(
		not bool(blocked.get("success", false))
		and String(blocked.get("error_code", "")) == "AUTOMATION_ITEM_COMMAND_NOT_ALLOWED",
		"non-allowlisted command type is rejected"
	)

	var unknown: Dictionary = app.automation_submit_item_command({
		"command_type": "item.drop",
		"payload": {"item_id": "item/x", "quantity": 1, "transform": {}},
	})
	_assert(
		not bool(unknown.get("success", false))
		and String(unknown.get("error_code", "")) == "AUTOMATION_ITEM_COMMAND_NOT_ALLOWED",
		"world-mutating drop is outside the allowlist"
	)

	var missing: Dictionary = app.automation_submit_item_command({
		"command_type": "inventory.select_hotbar",
		"payload": {},
	})
	_assert(
		not bool(missing.get("success", false))
		and String(missing.get("error_code", "")) == "AUTOMATION_ITEM_PAYLOAD_FIELD_REQUIRED",
		"missing required payload field is rejected"
	)

	var extra: Dictionary = app.automation_submit_item_command({
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 2, "item_id": "item/shared/ore/1"},
	})
	_assert(
		not bool(extra.get("success", false))
		and String(extra.get("error_code", "")) == "AUTOMATION_ITEM_PAYLOAD_FIELD_NOT_ALLOWED",
		"extra payload field is rejected"
	)

	var ok: Dictionary = app.automation_submit_item_command({
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 2},
		"operation_id": "operation/m6/r40/fresh",
	})
	_assert(bool(ok.get("success", false)), "allowlisted select_hotbar is submitted")
	_assert(
		int(ok.get("details", {}).get("item_graph_revision_before", -1)) == 7
		and int(ok.get("details", {}).get("item_graph_revision_after", -1)) == 8,
		"item graph revision advanced across the commit"
	)
	_assert(
		not bool(ok.get("details", {}).get("replay", true)),
		"fresh operation is not a replay"
	)

	var dup: Dictionary = app.automation_submit_item_command({
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 2},
		"operation_id": "operation/m6/r40/dup",
	})
	_assert(bool(dup.get("success", false)), "duplicate operation_id replays successfully")
	_assert(
		bool(dup.get("details", {}).get("replay", false))
		and int(dup.get("details", {}).get("item_graph_revision_before", -1))
			== int(dup.get("details", {}).get("item_graph_revision_after", -2)),
		"replayed duplicate does not mutate the world twice"
	)

	app.free()
	print("NET-SMOOTH1 R4.0 automation item command allowlist: %d assertions, %d failures" % [
		assertions, failures.size()
	])
	var code := 0 if failures.is_empty() else 1
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(code)
