extends RefCounted

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/compilation/construction_capability_compiler.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

var construct_id: String = ""
var root_item_instance_id: String = ""
var state_revision: int = 0
var build_state: String = "PLANNED"
var _parts: Dictionary = {}
var _bonds: Dictionary = {}
var _compiled_facets: Dictionary = {}
var _operation_fingerprints: Dictionary = {}

func setup(new_construct_id: String, new_root_item_instance_id: String) -> Dictionary:
	if not construct_id.is_empty():
		return _failure("CONSTRUCT_ALREADY_INITIALIZED")
	if not new_construct_id.begins_with("construct/"):
		return _failure("INVALID_CONSTRUCT_ID")
	if not new_root_item_instance_id.begins_with("item/"):
		return _failure("INVALID_ROOT_ITEM_INSTANCE_ID")
	construct_id = new_construct_id
	root_item_instance_id = new_root_item_instance_id
	_compile()
	return _success()

func add_part(operation_id: String, base_revision: int, part: Dictionary) -> Dictionary:
	var replay: Dictionary = _begin_operation(operation_id, base_revision, "add_part", part)
	if not bool(replay.get("success", false)) or bool(replay.get("replay", false)):
		return replay
	var validation: Dictionary = PartScript.validate(part)
	if not bool(validation.get("success", false)):
		return validation
	var part_id: String = String(part["part_id"])
	if _parts.has(part_id):
		return _failure("PART_ALREADY_EXISTS")
	for existing in _parts.values():
		if String(existing["item_instance_id"]) == String(part["item_instance_id"]):
			return _failure("ITEM_ALREADY_ATTACHED")
	_parts[part_id] = part.duplicate(true)
	_commit_operation(operation_id, String(replay.get("fingerprint", "")))
	return _success({"state_revision": state_revision})

func add_bond(operation_id: String, base_revision: int, bond: Dictionary) -> Dictionary:
	var replay: Dictionary = _begin_operation(operation_id, base_revision, "add_bond", bond)
	if not bool(replay.get("success", false)) or bool(replay.get("replay", false)):
		return replay
	var validation: Dictionary = BondScript.validate(bond)
	if not bool(validation.get("success", false)):
		return validation
	var bond_id: String = String(bond["bond_id"])
	if _bonds.has(bond_id):
		return _failure("BOND_ALREADY_EXISTS")
	if not _parts.has(String(bond["part_a_id"])) or not _parts.has(String(bond["part_b_id"])):
		return _failure("BOND_REFERENCES_UNKNOWN_PART")
	_bonds[bond_id] = bond.duplicate(true)
	_commit_operation(operation_id, String(replay.get("fingerprint", "")))
	return _success({"state_revision": state_revision})

func set_build_state(operation_id: String, base_revision: int, next_state: String) -> Dictionary:
	var replay: Dictionary = _begin_operation(operation_id, base_revision, "set_build_state", {"next_state": next_state})
	if not bool(replay.get("success", false)) or bool(replay.get("replay", false)):
		return replay
	if not SnapshotScript.VALID_BUILD_STATES.has(next_state):
		return _failure("INVALID_BUILD_STATE")
	if next_state == "OPERATIONAL":
		var compiled_result: Dictionary = CapabilityCompilerScript.compile(_part_array(), _bond_array())
		if not bool(compiled_result.get("success", false)):
			return compiled_result
		var compiled: Dictionary = compiled_result["compiled"]
		if not bool(compiled.get("connected", false)) or not bool(compiled.get("stable", false)):
			return _failure("CONSTRUCT_NOT_OPERATIONAL")
	build_state = next_state
	_commit_operation(operation_id, String(replay.get("fingerprint", "")))
	return _success({"state_revision": state_revision, "build_state": build_state})

func break_bond(operation_id: String, base_revision: int, bond_id: String) -> Dictionary:
	var replay: Dictionary = _begin_operation(operation_id, base_revision, "break_bond", {"bond_id": bond_id})
	if not bool(replay.get("success", false)) or bool(replay.get("replay", false)):
		return replay
	if not _bonds.has(bond_id):
		return _failure("BOND_NOT_FOUND")
	var bond: Dictionary = _bonds[bond_id].duplicate(true)
	if String(bond["state"]) == "BROKEN":
		return _failure("BOND_ALREADY_BROKEN")
	bond["state"] = "BROKEN"
	_bonds[bond_id] = bond
	build_state = "DAMAGED"
	_commit_operation(operation_id, String(replay.get("fingerprint", "")))
	return _success({"state_revision": state_revision, "build_state": build_state})

func export_snapshot() -> Dictionary:
	return SnapshotScript.create(
		construct_id,
		root_item_instance_id,
		state_revision,
		build_state,
		_part_array(),
		_bond_array(),
		_compiled_facets
	)

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var candidate_parts: Dictionary = {}
	for part in snapshot["parts"]:
		candidate_parts[String(part["part_id"])] = part.duplicate(true)
	var candidate_bonds: Dictionary = {}
	for bond in snapshot["bonds"]:
		candidate_bonds[String(bond["bond_id"])] = bond.duplicate(true)
	construct_id = String(snapshot["construct_id"])
	root_item_instance_id = String(snapshot["root_item_instance_id"])
	state_revision = int(snapshot["state_revision"])
	build_state = String(snapshot["build_state"])
	_parts = candidate_parts
	_bonds = candidate_bonds
	_compiled_facets = snapshot["compiled_facets"].duplicate(true)
	_operation_fingerprints.clear()
	return _success()

func get_compiled_facets() -> Dictionary:
	return _compiled_facets.duplicate(true)

func _begin_operation(operation_id: String, base_revision: int, operation_kind: String, payload: Dictionary) -> Dictionary:
	if construct_id.is_empty():
		return _failure("CONSTRUCT_NOT_INITIALIZED")
	if operation_id.strip_edges().is_empty():
		return _failure("EMPTY_OPERATION_ID")
	var fingerprint: String = UtilsScript.payload_hash({"kind": operation_kind, "payload": payload})
	if fingerprint.is_empty():
		return _failure("OPERATION_NOT_JSON_SAFE")
	if _operation_fingerprints.has(operation_id):
		if String(_operation_fingerprints[operation_id]) == fingerprint:
			return {"success": true, "error_code": "", "message": "", "replay": true, "state_revision": state_revision}
		return _failure("OPERATION_REPLAY_CONFLICT")
	if base_revision != state_revision:
		return _failure("STALE_CONSTRUCT_REVISION")
	return {"success": true, "error_code": "", "message": "", "replay": false, "fingerprint": fingerprint}

func _commit_operation(operation_id: String, fingerprint: String = "") -> void:
	if not fingerprint.is_empty():
		_operation_fingerprints[operation_id] = fingerprint
	state_revision += 1
	_compile()

func _compile() -> void:
	var result: Dictionary = CapabilityCompilerScript.compile(_part_array(), _bond_array())
	_compiled_facets = result.get("compiled", {}) if bool(result.get("success", false)) else {}

func _part_array() -> Array:
	var ids: Array = _parts.keys()
	ids.sort()
	var output: Array = []
	for part_id in ids:
		output.append(_parts[part_id].duplicate(true))
	return output

func _bond_array() -> Array:
	var ids: Array = _bonds.keys()
	ids.sort()
	var output: Array = []
	for bond_id in ids:
		output.append(_bonds[bond_id].duplicate(true))
	return output

func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
