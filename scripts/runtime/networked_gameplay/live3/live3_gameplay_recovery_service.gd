extends "res://scripts/runtime/networked_gameplay/p5/networked_gameplay_service_p5.gd"

const Live3ConstructionPort = preload("res://scripts/runtime/networked_gameplay/live3/live3_construction_recovery_port.gd")
const LIVE3_FIELD := "live3_construction"

# A pending value exists only while M6 restores a fresh, non-serving process.
# Once bound, exports always read the live native owners, never this DTO.
var _live3_pending: Dictionary = {}
var _live3_port

func bind_live3_construction(bridge) -> Dictionary:
	if _live3_port != null:
		return _failure("LIVE3_CONSTRUCTION_ALREADY_BOUND")
	var port = Live3ConstructionPort.new()
	var bound: Dictionary = port.bind(bridge, get_canonical_item_graph_port())
	if not bool(bound.get("success", false)):
		return bound
	if not _live3_pending.is_empty():
		var restored: Dictionary = port.restore_state(_live3_pending, _authority_owner_id, _authority_epoch)
		if not bool(restored.get("success", false)):
			return restored
	else:
		var initial: Dictionary = port.export_state()
		var constructs: Array = initial.get("authority", {}).get("construct_store", {}).get("constructs", [])
		if not constructs.is_empty():
			return _failure("LIVE3_CONSTRUCTION_CHECKPOINT_REQUIRED")
	_live3_port = port
	_live3_pending.clear()
	return _success({"native_construction_bound": true, "second_canonical_owner": false})

func live3_recovery_pending() -> bool:
	return not _live3_pending.is_empty()

func export_durable_state() -> Dictionary:
	var state: Dictionary = super.export_durable_state()
	if state.is_empty():
		return state
	var construction: Dictionary = _live3_port.export_state() if _live3_port != null else _live3_pending
	if not construction.is_empty():
		state[LIVE3_FIELD] = construction.duplicate(true)
		state["checksum"] = ""
		return Utils.finalize_json_checksum(state)
	return state

func validate_durable_state(value: Dictionary) -> Dictionary:
	var checked: Dictionary = super.validate_durable_state(value)
	if not bool(checked.get("success", false)):
		return checked
	if value.has(LIVE3_FIELD):
		if not value[LIVE3_FIELD] is Dictionary:
			return _failure("LIVE3_CONSTRUCTION_SECTION_INVALID")
		return Live3ConstructionPort.validate_state(
			value[LIVE3_FIELD], String(value.get("authority_owner_id", "")), int(value.get("authority_epoch", 0))
		)
	return _success()

func restore_durable_state(value: Dictionary) -> Dictionary:
	if _live3_port != null:
		return _failure("LIVE3_RECOVERY_REQUIRES_FRESH_NON_SERVING_OWNER")
	var restored: Dictionary = super.restore_durable_state(value)
	if not bool(restored.get("success", false)):
		return restored
	_live3_pending = Dictionary(value.get(LIVE3_FIELD, {})).duplicate(true)
	return restored

func handle_join_command(command: Dictionary) -> Dictionary:
	if live3_recovery_pending():
		return _failure("LIVE3_CONSTRUCTION_REBIND_REQUIRED")
	return super.handle_join_command(command)

func shutdown() -> Dictionary:
	_live3_port = null
	_live3_pending.clear()
	return super.shutdown()
