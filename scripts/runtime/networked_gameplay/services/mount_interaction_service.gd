extends RefCounted

const SCHEMA := "planet_simulator.mount_interaction_service.v1"
const SUPPORTED_COMMANDS: Array[String] = ["item.mount", "item.detach"]

var _item_graph_service
var _configured := false
var _commands_routed := 0


func setup(item_graph_service_reference) -> Dictionary:
	if _configured:
		return _failure("MOUNT_INTERACTION_SERVICE_ALREADY_CONFIGURED")
	if item_graph_service_reference == null or not item_graph_service_reference.has_method("handle_command"):
		return _failure("INVALID_ITEM_GRAPH_SERVICE")
	_item_graph_service = item_graph_service_reference
	_configured = true
	return _success()


func supports(command_type: String) -> bool:
	return command_type in SUPPORTED_COMMANDS


func handle_command(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("MOUNT_INTERACTION_SERVICE_NOT_CONFIGURED")
	if not supports(String(command.get("command_type", ""))):
		return _failure("UNSUPPORTED_MOUNT_COMMAND")
	_commands_routed += 1
	return _item_graph_service.handle_command(command)


func get_report() -> Dictionary:
	return {"schema": SCHEMA, "configured": _configured, "commands_routed": _commands_routed}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
