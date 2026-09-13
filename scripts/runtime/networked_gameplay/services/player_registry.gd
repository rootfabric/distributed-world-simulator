extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.player_registry.v1"
const DURABLE_SCHEMA := "planet_simulator.player_registry_state.v1"
var _players: Dictionary = {}
# Trusted bindings to the existing SM1 decision; staged rows are read-only.
var _live_gates: Dictionary = {}
var _live_stages: Dictionary = {}

func clear() -> void:
	_players.clear()
	_live_gates.clear()
	_live_stages.clear()

func upsert(record: Dictionary) -> Dictionary:
	var logical_id := String(record.get("logical_player_id", "")).strip_edges().to_lower()
	if logical_id.is_empty():
		return _failure("LOGICAL_PLAYER_ID_REQUIRED")
	if _live_gates.has(logical_id):
		var allowed: Dictionary = _live_gates[logical_id].authorize_record_write(record)
		if not bool(allowed.get("success", false)):
			return allowed
	_players[logical_id] = record.duplicate(true)
	return _success({"player": get_player(logical_id)})

func has_player(logical_player_id: String) -> bool:
	return not get_player(logical_player_id).is_empty()

func get_player(logical_player_id: String) -> Dictionary:
	var logical_id := logical_player_id.strip_edges().to_lower()
	if _live_gates.has(logical_id) and not _live_gates[logical_id].is_locally_ready():
		return {}
	return Dictionary(_players.get(logical_id, {})).duplicate(true)

func get_players() -> Array:
	var result: Array = []
	var ids := _players.keys()
	ids.sort()
	for logical_id in ids:
		# Snapshot readers may retain the frozen source projection until the
		# Service's explicit retirement revision. Mutation readers use get_player.
		if _live_gates.has(logical_id) and not _live_gates[logical_id].is_locally_presentable():
			continue
		result.append(Dictionary(_players[logical_id]).duplicate(true))
	return result

func export_durable_state() -> Dictionary:
	# Restart composition for live distributed leases is a later explicit gate.
	if not _live_gates.is_empty():
		return {}
	var players: Array = []
	for record_value in get_players():
		var record: Dictionary = Dictionary(record_value).duplicate(true)
		record["connected"] = false
		record["transport_session_id"] = ""
		players.append(record)
	var state: Dictionary = {"schema": DURABLE_SCHEMA, "players": players, "checksum": ""}
	return Utils.finalize_json_checksum(state)

func restore_durable_state(value: Dictionary) -> Dictionary:
	if not _live_gates.is_empty():
		return _failure("LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED")
	var validation := validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var staged: Dictionary = {}
	for record_value in value.get("players", []):
		var record: Dictionary = Dictionary(record_value).duplicate(true)
		var logical_id := String(record.get("logical_player_id", "")).strip_edges().to_lower()
		staged[logical_id] = record
	_players = staged
	return _success({"player_count": _players.size()})

func validate_durable_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DURABLE_SCHEMA:
		return _failure("INVALID_PLAYER_REGISTRY_STATE_SCHEMA")
	if typeof(value.get("players")) != TYPE_ARRAY or typeof(value.get("checksum")) != TYPE_STRING:
		return _failure("INVALID_PLAYER_REGISTRY_STATE")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("PLAYER_REGISTRY_STATE_CHECKSUM_MISMATCH")
	var seen: Dictionary = {}
	for record_value in value.get("players", []):
		if not record_value is Dictionary:
			return _failure("INVALID_PLAYER_REGISTRY_RECORD")
		var record: Dictionary = record_value
		var logical_id := String(record.get("logical_player_id", "")).strip_edges().to_lower()
		if logical_id.is_empty() or logical_id != String(record.get("logical_player_id", "")):
			return _failure("INVALID_PLAYER_REGISTRY_RECORD_ID")
		if seen.has(logical_id):
			return _failure("DUPLICATE_PLAYER_REGISTRY_RECORD")
		if String(record.get("player_entity_id", "")) != "player/%s" % logical_id:
			return _failure("INVALID_PLAYER_ENTITY_ID")
		if int(record.get("ownership_epoch", 0)) < 1 or int(record.get("state_revision", 0)) < 1:
			return _failure("INVALID_PLAYER_REGISTRY_REVISION")
		if typeof(record.get("connected")) != TYPE_BOOL:
			return _failure("INVALID_PLAYER_CONNECTED_STATE")
		if bool(record.get("connected", true)) or not String(record.get("transport_session_id", "")).is_empty():
			return _failure("DURABLE_PLAYER_SESSION_MUST_BE_DISCONNECTED")
		if typeof(record.get("position")) != TYPE_DICTIONARY or typeof(record.get("velocity")) != TYPE_DICTIONARY:
			return _failure("INVALID_PLAYER_SPATIAL_STATE")
		if not _valid_vector3(Dictionary(record.get("position", {}))) or not _valid_vector3(Dictionary(record.get("velocity", {}))):
			return _failure("INVALID_PLAYER_SPATIAL_STATE")
		if not _finite_number(record.get("orientation_yaw")) or typeof(record.get("flashlight_enabled")) != TYPE_BOOL:
			return _failure("INVALID_PLAYER_PRESENTATION_STATE")
		if int(record.get("last_input_sequence", -1)) < 0:
			return _failure("INVALID_PLAYER_INPUT_SEQUENCE")
		if typeof(record.get("inventory")) != TYPE_ARRAY:
			return _failure("INVALID_PLAYER_INVENTORY_STATE")
		var inventory_ids: Dictionary = {}
		for item_id_value in record.get("inventory", []):
			var item_id := String(item_id_value)
			if item_id.strip_edges().is_empty() or inventory_ids.has(item_id):
				return _failure("INVALID_PLAYER_INVENTORY_STATE")
			inventory_ids[item_id] = true
		seen[logical_id] = true
	var safe := Utils.canonicalize(value, "$.player_registry")
	if not bool(safe.get("success", false)):
		return _failure("PLAYER_REGISTRY_STATE_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success({"player_count": seen.size()})

func _valid_vector3(value: Dictionary) -> bool:
	for axis in ["x", "y", "z"]:
		if not value.has(axis) or not _finite_number(value.get(axis)):
			return false
	return true

func _finite_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)

func get_report() -> Dictionary:
	return {"schema": SCHEMA, "player_count": get_players().size(), "live_binding_count": _live_gates.size(), "read_only_live_stage_count": _live_stages.size()}

func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}


func bind_live_player_gate(logical_player_id: String, gate) -> Dictionary:
	if logical_player_id.is_empty() or logical_player_id != logical_player_id.strip_edges().to_lower():
		return _failure("LIVE_PLAYER_ID_INVALID")
	if gate == null or not gate.has_method("authorize_record_write") or not gate.has_method("is_locally_ready") or not gate.has_method("is_locally_presentable") or not gate.has_method("check_transfer_phase"):
		return _failure("LIVE_PLAYER_GATE_REQUIRED")
	if _live_gates.has(logical_player_id):
		return _success({"replay": true}) if _live_gates[logical_player_id] == gate else _failure("LIVE_PLAYER_GATE_REBIND_FORBIDDEN")
	_live_gates[logical_player_id] = gate
	return _success()


func capture_live_player(logical_player_id: String, gate, transfer_id: String) -> Dictionary:
	if _live_gates.get(logical_player_id) != gate or gate == null:
		return _failure("LIVE_PLAYER_GATE_MISMATCH")
	var phase: Dictionary = gate.check_transfer_phase(transfer_id, "SOURCE_EXPORT")
	if not bool(phase.get("success", false)):
		return phase
	var record: Dictionary = Dictionary(_players.get(logical_player_id, {})).duplicate(true)
	var valid := validate_live_player_record(record)
	if not bool(valid.get("success", false)):
		return valid
	return _success({"player": record, "player_checksum": Utils.payload_hash(record)})


func validate_live_player_record(record: Dictionary) -> Dictionary:
	var fields: Array[String] = ["logical_player_id", "player_entity_id", "transport_session_id", "ownership_epoch", "connected", "position", "velocity", "inventory", "last_input_sequence", "state_revision", "orientation_yaw", "flashlight_enabled"]
	if record.size() != fields.size():
		return _failure("LIVE_PLAYER_RECORD_FIELDS_INVALID")
	for field in fields:
		if not record.has(field):
			return _failure("LIVE_PLAYER_RECORD_FIELDS_INVALID")
	if record.get("connected") != true or typeof(record.get("transport_session_id")) != TYPE_STRING or not String(record["transport_session_id"]).begins_with("transport-session/"):
		return _failure("LIVE_PLAYER_SESSION_REQUIRED")
	for field in ["ownership_epoch", "state_revision", "last_input_sequence"]:
		var value = record.get(field)
		if not _finite_number(value) or float(value) != floorf(float(value)) or float(value) < (0.0 if field == "last_input_sequence" else 1.0) or float(value) > 9007199254740991.0:
			return _failure("LIVE_PLAYER_INTEGER_INVALID", {"field": field})
	var disconnected := record.duplicate(true)
	disconnected["connected"] = false
	disconnected["transport_session_id"] = ""
	var dto := Utils.finalize_json_checksum({"schema": DURABLE_SCHEMA, "players": [disconnected], "checksum": ""})
	return validate_durable_state(dto)


func stage_live_player(logical_player_id: String, gate, transfer_id: String, record: Dictionary) -> Dictionary:
	if gate == null or _live_gates.get(logical_player_id) != gate:
		return _failure("LIVE_PLAYER_GATE_MISMATCH")
	var phase: Dictionary = gate.check_transfer_phase(transfer_id, "TARGET_STAGE")
	if not bool(phase.get("success", false)):
		return phase
	var valid := validate_live_player_record(record)
	if not bool(valid.get("success", false)):
		return valid
	if record["logical_player_id"] != logical_player_id:
		return _failure("LIVE_PLAYER_SUBJECT_MISMATCH")
	var normalized := record.duplicate(true)
	for field in ["ownership_epoch", "last_input_sequence", "state_revision"]:
		normalized[field] = int(normalized[field])
	var digest := Utils.payload_hash(normalized)
	if _live_stages.has(logical_player_id):
		var old: Dictionary = _live_stages[logical_player_id]
		return _success({"replay": true, "checksum": digest}) if old["transfer_id"] == transfer_id and old["checksum"] == digest else _failure("LIVE_PLAYER_STAGE_CONFLICT")
	_live_stages[logical_player_id] = {"transfer_id": transfer_id, "checksum": digest, "record": normalized}
	return _success({"checksum": digest})


func preflight_live_player_install(logical_player_id: String, gate, transfer_id: String, commit_token: String) -> Dictionary:
	if gate == null or _live_gates.get(logical_player_id) != gate:
		return _failure("LIVE_PLAYER_GATE_MISMATCH")
	var proof: Dictionary = gate.check_transfer_phase(transfer_id, "TARGET_INSTALL", commit_token)
	if not bool(proof.get("success", false)):
		return proof
	var staged: Dictionary = _live_stages.get(logical_player_id, {})
	if staged.get("transfer_id") != transfer_id or Utils.payload_hash(staged.get("record", {})) != staged.get("checksum"):
		return _failure("LIVE_PLAYER_STAGE_REQUIRED")
	return _success()


func install_live_player(logical_player_id: String, gate, transfer_id: String, commit_token: String) -> Dictionary:
	var checked := preflight_live_player_install(logical_player_id, gate, transfer_id, commit_token)
	if not bool(checked.get("success", false)):
		return checked
	_players[logical_player_id] = Dictionary(_live_stages[logical_player_id]["record"]).duplicate(true)
	_live_stages.erase(logical_player_id)
	return _success()


func discard_live_player_stage(logical_player_id: String, gate, transfer_id: String) -> Dictionary:
	if gate == null or _live_gates.get(logical_player_id) != gate:
		return _failure("LIVE_PLAYER_GATE_MISMATCH")
	var stage: Dictionary = _live_stages.get(logical_player_id, {})
	if not stage.is_empty() and stage.get("transfer_id") != transfer_id:
		return _failure("LIVE_PLAYER_STAGE_CONFLICT")
	_live_stages.erase(logical_player_id)
	return _success()
