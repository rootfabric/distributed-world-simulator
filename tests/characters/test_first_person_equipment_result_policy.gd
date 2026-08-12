extends SceneTree

const PolicyType = preload("res://scripts/characters/interaction/first_person_equipment_result_policy.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var policy = PolicyType.new()
	var target_relation := {
		"kind": "CONTAINER",
		"container_id": "equipment/a",
		"slot_index": 1,
	}
	var network_success := {
		"success": false,
		"code": "CHARACTER_EQUIPMENT_NETWORK_APPLY_FAILED",
		"error_code": "CHARACTER_EQUIPMENT_NETWORK_APPLY_FAILED",
		"details": {
			"cause": {"success": false, "error_code": "PRESENTATION_TEST_WARNING"},
			"network_result": {"success": true, "operation_id": "op/equip/1"},
		},
	}
	var recovered: Dictionary = policy.normalize(
		network_success,
		target_relation,
		"equipment/a",
		1,
		true
	)
	_assert(bool(recovered.get("success", false)), "authority-applied presentation false-negative was not recovered")
	_assert(String(recovered.get("code", "")) == PolicyType.RECOVERED_CODE, "recovered code mismatch")
	_assert(bool(recovered.get("authority_applied", false)), "recovered result did not preserve authority success")
	_assert(recovered.get("presentation_warning", {}) is Dictionary, "presentation warning was not preserved")

	var wrong_slot: Dictionary = policy.normalize(
		network_success,
		{"kind": "CONTAINER", "container_id": "equipment/a", "slot_index": 2},
		"equipment/a",
		1,
		true
	)
	_assert(not bool(wrong_slot.get("success", false)), "slot mismatch was incorrectly recovered")

	var wrong_container: Dictionary = policy.normalize(
		network_success,
		{"kind": "CONTAINER", "container_id": "player_inventory", "slot_index": 4},
		"equipment/a",
		1,
		true
	)
	_assert(not bool(wrong_container.get("success", false)), "container mismatch was incorrectly recovered")

	var server_rejected := network_success.duplicate(true)
	server_rejected["details"]["network_result"] = {"success": false, "error_code": "SERVER_REJECTED"}
	var rejected: Dictionary = policy.normalize(
		server_rejected,
		target_relation,
		"equipment/a",
		1,
		true
	)
	_assert(not bool(rejected.get("success", false)), "server rejection was incorrectly rewritten as success")

	var ordinary_error := {"success": false, "error_code": "ITEM_NOT_FOUND"}
	var ordinary: Dictionary = policy.normalize(
		ordinary_error,
		target_relation,
		"equipment/a",
		1,
		true
	)
	_assert(String(ordinary.get("error_code", "")) == "ITEM_NOT_FOUND", "unrelated error was mutated")

	var unequip_relation := {"kind": "CONTAINER", "container_id": "player_inventory", "slot_index": 7}
	var unequip: Dictionary = policy.normalize(
		network_success,
		unequip_relation,
		"player_inventory",
		12,
		false
	)
	_assert(bool(unequip.get("success", false)), "canonical backpack unequip was not recovered when presentation slot differs")

	var report: Dictionary = policy.create_report()
	_assert(not bool(report.get("changes_network_authority", true)), "policy claims network authority")
	_assert(not bool(report.get("changes_item_authority", true)), "policy claims item authority")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FirstPerson equipment result policy: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FirstPerson equipment result policy: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
