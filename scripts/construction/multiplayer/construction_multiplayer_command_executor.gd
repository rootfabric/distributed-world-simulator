extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")

var _adapter
var _build_process
var _geometry_process
var _damage_process

func setup(adapter, build_process, geometry_process, damage_process) -> Dictionary:
	if adapter == null or not adapter.has_method("get_generation") or not adapter.has_method("get_construct_snapshot") or not adapter.has_method("export_state") or not adapter.has_method("has_terminal_operation"):
		return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_EXECUTOR_ADAPTER_REQUIRED")
	if build_process == null or not build_process.has_method("advance_stage"): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_BUILD_PROCESS_REQUIRED")
	if geometry_process == null or not geometry_process.has_method("apply_edit"): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_GEOMETRY_PROCESS_REQUIRED")
	if damage_process == null or not damage_process.has_method("apply_damage") or not damage_process.has_method("apply_repair"): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_DAMAGE_PROCESS_REQUIRED")
	_adapter = adapter; _build_process = build_process; _geometry_process = geometry_process; _damage_process = damage_process
	return ParametricUtils.success()

func execute(command: Dictionary, trusted_context: Dictionary = {}) -> Dictionary:
	var action := String(command["action"]); var payload: Dictionary = command["payload"]
	match action:
		GrantScript.ACTION_BUILD:
			var checked := _exact_payload(payload, ["build_plan_id", "stage_index", "operation_id", "provided_capabilities", "options"]); if not bool(checked.get("success", false)): return checked
			if String(command["construct_id"]) != String(payload.get("construct_id", command["construct_id"])): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_TARGET_MISMATCH")
			if _build_process.has_method("advance_stage_for_actor"):
				return _build_process.advance_stage_for_actor(
					String(trusted_context.get("logical_player_id", "")),
					String(payload["build_plan_id"]),
					int(payload["stage_index"]),
					String(payload["operation_id"]),
					Array(payload["provided_capabilities"]),
					Dictionary(payload["options"])
				)
			return _build_process.advance_stage(String(payload["build_plan_id"]), int(payload["stage_index"]), String(payload["operation_id"]), Array(payload["provided_capabilities"]), Dictionary(payload["options"]))
		GrantScript.ACTION_EDIT:
			var checked := _exact_payload(payload, ["plan_id", "request", "failure_mode"]); if not bool(checked.get("success", false)): return checked
			if typeof(payload.get("request")) != TYPE_DICTIONARY or String(payload["request"].get("construct_id", "")) != String(command["construct_id"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_TARGET_MISMATCH")
			return _geometry_process.apply_edit(String(payload["plan_id"]), Dictionary(payload["request"]), String(payload["failure_mode"]))
		GrantScript.ACTION_DAMAGE:
			var checked := _exact_payload(payload, ["plan_id", "operation_id", "request", "failure_mode"]); if not bool(checked.get("success", false)): return checked
			if typeof(payload.get("request")) != TYPE_DICTIONARY or String(payload["request"].get("construct_id", "")) != String(command["construct_id"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_TARGET_MISMATCH")
			return _damage_process.apply_damage(String(payload["plan_id"]), String(payload["operation_id"]), Dictionary(payload["request"]), String(payload["failure_mode"]))
		GrantScript.ACTION_REPAIR:
			var checked := _exact_payload(payload, ["plan_id", "operation_id", "repair_plan", "failure_mode"]); if not bool(checked.get("success", false)): return checked
			if typeof(payload.get("repair_plan")) != TYPE_DICTIONARY or String(payload["repair_plan"].get("target_construct_id", "")) != String(command["construct_id"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_TARGET_MISMATCH")
			return _damage_process.apply_repair(String(payload["plan_id"]), String(payload["operation_id"]), Dictionary(payload["repair_plan"]), String(payload["failure_mode"]))
		_:
			return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_ACTION")

func has_committed_operation(command: Dictionary) -> bool:
	var operation_id := _domain_operation_id(command)
	return not operation_id.is_empty() and _adapter.has_terminal_operation(operation_id)

func get_generation() -> int: return _adapter.get_generation()
func get_construct_snapshot(construct_id: String) -> Dictionary: return _adapter.get_construct_snapshot(construct_id)
func export_state_bundle() -> Dictionary:
	var state: Dictionary = _adapter.export_state()
	return BundleScript.create(int(state.get("generation", 0)), Array(state.get("items", [])), Array(state.get("constructs", [])))

func _domain_operation_id(command: Dictionary) -> String:
	var payload: Dictionary = command.get("payload", {})
	if String(command.get("action", "")) == GrantScript.ACTION_EDIT and typeof(payload.get("request")) == TYPE_DICTIONARY: return String(payload["request"].get("operation_id", ""))
	return String(payload.get("operation_id", ""))

static func _exact_payload(payload: Dictionary, fields: Array[String]) -> Dictionary:
	if payload.size() != fields.size(): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_PAYLOAD_FIELDS")
	for field in fields:
		if not payload.has(field): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_PAYLOAD_FIELDS")
	return ParametricUtils.success()
