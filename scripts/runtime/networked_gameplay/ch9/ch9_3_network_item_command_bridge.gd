class_name Ch9NetworkItemCommandBridge
extends "res://scripts/runtime/networked_gameplay/m7/m7_network_item_command_bridge.gd"

const EquipmentAdapter = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_item_graph_replica_adapter.gd")
const EQUIPMENT_COMMANDS: Array[String] = [
	"equipment.equip",
	"equipment.unequip",
]

var _equipment_authoritative_async_submitted: int = 0
var _equipment_authoritative_async_send_failures: int = 0


func setup(runtime, local_player_id: String, selected_item_provider: Callable = Callable()) -> Dictionary:
	var result: Dictionary = super.setup(runtime, local_player_id, selected_item_provider)
	if not bool(result.get("success", false)):
		return result
	var equipment_adapter = EquipmentAdapter.new()
	var adapter_setup: Dictionary = equipment_adapter.setup(local_player_id)
	if not bool(adapter_setup.get("success", false)):
		stop("CH9_3_EQUIPMENT_ADAPTER_SETUP_FAILED")
		return adapter_setup
	_adapter = equipment_adapter
	return _success({
		"prediction_enabled": _prediction_enabled(),
		"character_equipment_enabled": true,
		"equipment_command_mode": _equipment_command_mode(),
		"prediction": _prediction_journal.get_report() if _prediction_journal != null else {},
	})


func submit_item_command(
	command_type: String,
	payload: Dictionary,
	operation_id: String
) -> Dictionary:
	if command_type not in EQUIPMENT_COMMANDS:
		return super.submit_item_command(command_type, payload, operation_id)
	if _runtime == null or _adapter == null:
		_rejected += 1
		return _failure("M7_ITEM_BRIDGE_NOT_CONFIGURED")
	if not _runtime.has_method("submit_equipment_command_nonblocking"):
		return super.submit_item_command(command_type, payload, operation_id)

	var normalized_operation_id: String = operation_id.strip_edges()
	if normalized_operation_id.is_empty():
		_rejected += 1
		return _failure("CH9_EQUIPMENT_OPERATION_ID_REQUIRED")

	var canonical_payload: Dictionary = payload.duplicate(true)
	if canonical_payload.has("item_id"):
		canonical_payload["item_id"] = _adapter.to_canonical_item_id(
			String(canonical_payload.get("item_id", ""))
		)

	var submitted_value = _runtime.call(
		"submit_equipment_command_nonblocking",
		command_type,
		canonical_payload,
		normalized_operation_id
	)
	if not submitted_value is Dictionary:
		_equipment_authoritative_async_send_failures += 1
		_rejected += 1
		return _failure("CH9_INVALID_EQUIPMENT_NONBLOCKING_RESULT")
	var submitted: Dictionary = Dictionary(submitted_value).duplicate(true)
	if not bool(submitted.get("success", false)):
		_equipment_authoritative_async_send_failures += 1
		_rejected += 1
		return submitted

	_equipment_authoritative_async_submitted += 1
	_submitted += 1
	return {
		"success": true,
		"error_code": "",
		"pending": true,
		"predicted": false,
		"authoritative_pending": true,
		"operation_id": normalized_operation_id,
		"details": {
			"pending": true,
			"predicted": false,
			"authoritative_pending": true,
			"command_type": command_type,
		},
	}


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["equipment_command_mode"] = _equipment_command_mode()
	report["equipment_authoritative_async_submitted"] = _equipment_authoritative_async_submitted
	report["equipment_authoritative_async_send_failures"] = _equipment_authoritative_async_send_failures
	return report


func _equipment_command_mode() -> String:
	if _runtime != null and _runtime.has_method("submit_equipment_command_nonblocking"):
		return "AUTHORITATIVE_NONBLOCKING"
	return "LEGACY_BLOCKING_FALLBACK"
