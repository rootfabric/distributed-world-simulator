extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")

const STATE_SCHEMA := "planet_simulator.construction_multiplayer_permission_store.v1"
const STATE_FIELDS: Array[String] = ["schema", "epoch", "generation", "grants", "revoked_grant_ids", "checksum"]
var _epoch := 1
var _generation := 0
var _grants: Dictionary = {}
var _revoked: Dictionary = {}

func setup(epoch: int = 1) -> Dictionary:
	if epoch < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_EPOCH")
	_epoch = epoch; _generation = 0; _grants.clear(); _revoked.clear(); return ParametricUtils.success()

func publish(grant: Dictionary) -> Dictionary:
	var checked := GrantScript.validate(grant); if not bool(checked.get("success", false)): return checked
	var grant_id := String(grant["grant_id"])
	if _grants.has(grant_id):
		if UtilsScript.canonical_json(_grants[grant_id]) == UtilsScript.canonical_json(grant): return ParametricUtils.success({"replay": true, "generation": _generation})
		return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_GRANT_CONFLICT")
	_grants[grant_id] = grant.duplicate(true); _generation += 1
	return ParametricUtils.success({"replay": false, "generation": _generation})

func revoke(grant_id: String, expected_checksum: String) -> Dictionary:
	if not _grants.has(grant_id): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_GRANT_NOT_FOUND")
	if String(_grants[grant_id]["checksum"]) != expected_checksum: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_REVOKE_PRECONDITION_MISMATCH")
	if _revoked.has(grant_id): return ParametricUtils.success({"replay": true, "generation": _generation})
	_revoked[grant_id] = true; _generation += 1
	return ParametricUtils.success({"replay": false, "generation": _generation})

func set_epoch(epoch: int) -> Dictionary:
	if epoch < _epoch: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_EPOCH_ROLLBACK")
	if epoch == _epoch: return ParametricUtils.success({"replay": true, "generation": _generation})
	_epoch = epoch; _generation += 1; return ParametricUtils.success({"replay": false, "generation": _generation})

func authorize(subject_id: String, construct_id: String, action: String, permission_epoch: int) -> Dictionary:
	if permission_epoch != _epoch: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_EPOCH_MISMATCH")
	var grant_ids: Array = _grants.keys(); grant_ids.sort()
	for grant_id in grant_ids:
		if _revoked.has(grant_id): continue
		var grant: Dictionary = _grants[grant_id]
		if GrantScript.authorizes(grant, subject_id, construct_id, action, _epoch):
			return ParametricUtils.success({"grant": grant.duplicate(true), "epoch": _epoch})
	return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_DENIED")

func get_epoch() -> int: return _epoch
func get_generation() -> int: return _generation
func get_grant(grant_id: String) -> Dictionary: return Dictionary(_grants.get(grant_id, {})).duplicate(true)

func export_state() -> Dictionary:
	var grant_ids: Array = _grants.keys(); grant_ids.sort(); var grants: Array = []
	for grant_id in grant_ids: grants.append(Dictionary(_grants[grant_id]).duplicate(true))
	var revoked: Array = _revoked.keys(); revoked.sort()
	var state := {"schema": STATE_SCHEMA, "epoch": _epoch, "generation": _generation, "grants": grants, "revoked_grant_ids": revoked, "checksum": ""}
	state["checksum"] = compute_state_checksum(state); return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var grants := {}; for grant in state["grants"]: grants[String(grant["grant_id"])] = Dictionary(grant).duplicate(true)
	var revoked := {}; for grant_id in state["revoked_grant_ids"]: revoked[String(grant_id)] = true
	_epoch = int(state["epoch"]); _generation = int(state["generation"]); _grants = grants; _revoked = revoked
	return ParametricUtils.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_MULTIPLAYER_PERMISSION_STORE_SCHEMA")
	for field in ["epoch", "generation"]:
		if not UtilsScript.is_json_integer(state.get(field)) or int(state[field]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_STORE_COUNTER")
	if typeof(state.get("grants")) != TYPE_ARRAY or typeof(state.get("revoked_grant_ids")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_STORE_COLLECTION")
	var previous := ""; var ids := {}
	for grant in state["grants"]:
		if typeof(grant) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_GRANT")
		var checked_grant := GrantScript.validate(grant); if not bool(checked_grant.get("success", false)): return checked_grant
		var grant_id := String(grant["grant_id"]); if ids.has(grant_id) or (not previous.is_empty() and grant_id < previous): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_PERMISSION_GRANTS")
		ids[grant_id] = true; previous = grant_id
	previous = ""
	for grant_id_value in state["revoked_grant_ids"]:
		if typeof(grant_id_value) != TYPE_STRING: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_REVOKED_GRANT_ID")
		var grant_id := String(grant_id_value); if not ids.has(grant_id) or (not previous.is_empty() and grant_id <= previous): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_REVOKED_GRANTS")
		previous = grant_id
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_STORE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
