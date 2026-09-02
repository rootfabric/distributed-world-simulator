extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ExecutionArtifact = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_artifact_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_execution_lifecycle.v1"
const CREATED := "CREATED"
const CERTIFIED := "CERTIFIED"
const READY := "READY"
const ACTIVE := "ACTIVE"
const STALE := "STALE"
const INVALID := "INVALID"
const STATES: Array[String] = [ACTIVE, CERTIFIED, CREATED, INVALID, READY, STALE]
const TERMINAL_STATES: Array[String] = [INVALID, STALE]
const FIELDS: Array[String] = [
	"schema", "execution_artifact_hash", "source_binding_checksum", "rom_descriptor_hash",
	"state", "activation_count", "last_accepted_step", "terminal_reason",
	"terminal_region_id", "recovery_action", "checksum",
]

static func create(artifact: Dictionary) -> Dictionary:
	var checked := ExecutionArtifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return {}
	var value := {
		"schema": SCHEMA,
		"execution_artifact_hash": String(artifact["artifact_hash"]),
		"source_binding_checksum": String(artifact["source_binding_checksum"]),
		"rom_descriptor_hash": String(artifact["rom_descriptor_hash"]),
		"state": CREATED,
		"activation_count": 0,
		"last_accepted_step": -1,
		"terminal_reason": "NONE",
		"terminal_region_id": "NONE",
		"recovery_action": "NONE",
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_EXECUTION_LIFECYCLE_SCHEMA")
	for field in ["execution_artifact_hash", "source_binding_checksum", "rom_descriptor_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_LIFECYCLE_HASH", {"field": field})
	if not STATES.has(String(value.get("state", ""))):
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_LIFECYCLE_STATE")
	if not Utils.is_json_integer(value.get("activation_count")) or int(value["activation_count"]) < 0:
		return Utils.failure("INVALID_DYNAMIC_ROM_ACTIVATION_COUNT")
	if not Utils.is_json_integer(value.get("last_accepted_step")) or int(value["last_accepted_step"]) < -1:
		return Utils.failure("INVALID_DYNAMIC_ROM_LAST_ACCEPTED_STEP")
	for field in ["terminal_reason", "recovery_action"]:
		if typeof(value.get(field)) != TYPE_STRING:
			return Utils.failure("INVALID_DYNAMIC_ROM_LIFECYCLE_STRING", {"field": field})
	var state := String(value["state"])
	var reason := String(value["terminal_reason"])
	var region := String(value["terminal_region_id"])
	var recovery := String(value["recovery_action"])
	if TERMINAL_STATES.has(state):
		if reason == "NONE" or not Utils.is_upper_kind(reason):
			return Utils.failure("DYNAMIC_ROM_TERMINAL_STATE_MISSING_REASON")
		if not ["FULL_FALLBACK", "LOCAL_UNBAKE_REQUIRED", "REBUILD_REQUIRED"].has(recovery):
			return Utils.failure("DYNAMIC_ROM_TERMINAL_STATE_MISSING_RECOVERY")
		if region != "NONE" and not Utils.is_canonical_id(region, 2):
			return Utils.failure("INVALID_DYNAMIC_ROM_TERMINAL_REGION")
	else:
		if reason != "NONE" or region != "NONE" or recovery != "NONE":
			return Utils.failure("NONTERMINAL_DYNAMIC_ROM_HAS_TERMINAL_METADATA")
	if state == CREATED and int(value["activation_count"]) != 0:
		return Utils.failure("CREATED_DYNAMIC_ROM_ALREADY_ACTIVATED")
	if state in [CERTIFIED, READY] and int(value["activation_count"]) != 0:
		return Utils.failure("PREACTIVE_DYNAMIC_ROM_ALREADY_ACTIVATED")
	if state == ACTIVE and int(value["activation_count"]) < 1:
		return Utils.failure("ACTIVE_DYNAMIC_ROM_MISSING_ACTIVATION")
	return Utils.validate_checksum(value)

static func certify(lifecycle: Dictionary, artifact: Dictionary) -> Dictionary:
	var checked := _bound(lifecycle, artifact)
	if not bool(checked.get("success", false)):
		return checked
	if String(lifecycle["state"]) != CREATED:
		return Utils.failure("DYNAMIC_ROM_CERTIFY_REQUIRES_CREATED")
	return _transition(lifecycle, CERTIFIED)

static func mark_ready(lifecycle: Dictionary, artifact: Dictionary) -> Dictionary:
	var checked := _bound(lifecycle, artifact)
	if not bool(checked.get("success", false)):
		return checked
	if String(lifecycle["state"]) != CERTIFIED:
		return Utils.failure("DYNAMIC_ROM_READY_REQUIRES_CERTIFIED")
	return _transition(lifecycle, READY)

static func activate(lifecycle: Dictionary, artifact: Dictionary) -> Dictionary:
	var checked := _bound(lifecycle, artifact)
	if not bool(checked.get("success", false)):
		return checked
	if String(lifecycle["state"]) != READY:
		return Utils.failure("DYNAMIC_ROM_ACTIVATE_REQUIRES_READY")
	var next := lifecycle.duplicate(true)
	next["state"] = ACTIVE
	next["activation_count"] = int(next["activation_count"]) + 1
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate(next)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"lifecycle": next, "transition": "READY->ACTIVE"})

static func accept_step(lifecycle: Dictionary, artifact: Dictionary, step_index: int) -> Dictionary:
	var checked := _bound(lifecycle, artifact)
	if not bool(checked.get("success", false)):
		return checked
	if String(lifecycle["state"]) != ACTIVE:
		return Utils.failure("DYNAMIC_ROM_STEP_ACCEPT_REQUIRES_ACTIVE")
	if not Utils.is_json_integer(step_index) or step_index < 0 or step_index <= int(lifecycle["last_accepted_step"]):
		return Utils.failure("INVALID_DYNAMIC_ROM_ACCEPTED_STEP_ORDER")
	var next := lifecycle.duplicate(true)
	next["last_accepted_step"] = step_index
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate(next)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"lifecycle": next, "transition": "ACTIVE->ACTIVE"})

static func mark_stale(
	lifecycle: Dictionary,
	artifact: Dictionary,
	reason: String,
	recovery_action: String = "REBUILD_REQUIRED"
) -> Dictionary:
	return _terminal(lifecycle, artifact, STALE, reason, "NONE", recovery_action)

static func mark_invalid(
	lifecycle: Dictionary,
	artifact: Dictionary,
	reason: String,
	region_id: String,
	recovery_action: String
) -> Dictionary:
	return _terminal(lifecycle, artifact, INVALID, reason, region_id, recovery_action)

static func can_execute(lifecycle: Dictionary, artifact: Dictionary) -> Dictionary:
	var checked := _bound(lifecycle, artifact)
	if not bool(checked.get("success", false)):
		return checked
	if String(lifecycle["state"]) != ACTIVE:
		return Utils.failure("DYNAMIC_ROM_EXECUTION_FORBIDDEN", {
			"state": lifecycle["state"],
			"reason": lifecycle["terminal_reason"],
			"recovery_action": lifecycle["recovery_action"],
		})
	return Utils.success({"execution_allowed": true, "state": ACTIVE})

static func _terminal(
	lifecycle: Dictionary,
	artifact: Dictionary,
	target_state: String,
	reason: String,
	region_id: String,
	recovery_action: String
) -> Dictionary:
	var checked := _bound(lifecycle, artifact)
	if not bool(checked.get("success", false)):
		return checked
	if TERMINAL_STATES.has(String(lifecycle["state"])):
		return Utils.success({"lifecycle": lifecycle.duplicate(true), "transition": "%s->%s" % [lifecycle["state"], lifecycle["state"]]})
	if String(lifecycle["state"]) != ACTIVE:
		return Utils.failure("DYNAMIC_ROM_TERMINAL_TRANSITION_REQUIRES_ACTIVE")
	if not Utils.is_upper_kind(reason) or reason == "NONE":
		return Utils.failure("INVALID_DYNAMIC_ROM_TERMINAL_REASON")
	if region_id != "NONE" and not Utils.is_canonical_id(region_id, 2):
		return Utils.failure("INVALID_DYNAMIC_ROM_TERMINAL_REGION")
	if not ["FULL_FALLBACK", "LOCAL_UNBAKE_REQUIRED", "REBUILD_REQUIRED"].has(recovery_action):
		return Utils.failure("INVALID_DYNAMIC_ROM_RECOVERY_ACTION")
	var next := lifecycle.duplicate(true)
	next["state"] = target_state
	next["terminal_reason"] = reason
	next["terminal_region_id"] = region_id
	next["recovery_action"] = recovery_action
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate(next)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"lifecycle": next, "transition": "ACTIVE->%s" % target_state})

static func _transition(lifecycle: Dictionary, target_state: String) -> Dictionary:
	var next := lifecycle.duplicate(true)
	var previous := String(next["state"])
	next["state"] = target_state
	next["checksum"] = Utils.compute_checksum(next)
	var checked := validate(next)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"lifecycle": next, "transition": "%s->%s" % [previous, target_state]})

static func _bound(lifecycle: Dictionary, artifact: Dictionary) -> Dictionary:
	var checked := validate(lifecycle)
	if not bool(checked.get("success", false)):
		return checked
	checked = ExecutionArtifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	if String(lifecycle["execution_artifact_hash"]) != String(artifact["artifact_hash"]):
		return Utils.failure("DYNAMIC_ROM_LIFECYCLE_ARTIFACT_MISMATCH")
	if String(lifecycle["source_binding_checksum"]) != String(artifact["source_binding_checksum"]):
		return Utils.failure("DYNAMIC_ROM_LIFECYCLE_SOURCE_MISMATCH")
	if String(lifecycle["rom_descriptor_hash"]) != String(artifact["rom_descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_LIFECYCLE_DESCRIPTOR_MISMATCH")
	return Utils.success()
