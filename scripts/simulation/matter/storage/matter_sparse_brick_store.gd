extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const BrickSnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")

var _configured: bool = false
var _body_definition_hash: String = ""
var _generator_version: String = ""
var _generator_seed: int = 0
var _grid_profile: Dictionary = {}
var _snapshots_by_address_id: Dictionary = {}


func configure(body: Dictionary, grid_profile: Dictionary) -> Dictionary:
	if not bool(BodyScript.validate(body).get("success", false)):
		return MatterUtilsScript.failure("INVALID_SPARSE_STORE_BODY_DEFINITION")
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_SPARSE_STORE_GRID_PROFILE")
	if not MatterUtilsScript.is_lower_hex_64(body.get("checksum")):
		return MatterUtilsScript.failure("INVALID_SPARSE_STORE_BODY_HASH")
	if String(grid_profile["body_id"]) != String(body.get("body_id", "")) \
		or String(grid_profile["body_frame_id"]) != String(body.get("body_frame_id", "")):
		return MatterUtilsScript.failure("SPARSE_STORE_BODY_GRID_MISMATCH")
	_body_definition_hash = String(body["checksum"])
	_generator_version = String(body.get("generator_version", ""))
	_generator_seed = int(body.get("generator_seed", 0))
	_grid_profile = grid_profile.duplicate(true)
	_snapshots_by_address_id.clear()
	_configured = true
	return MatterUtilsScript.success()


func put(snapshot: Dictionary) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("SPARSE_STORE_NOT_CONFIGURED")
	var validation: Dictionary = _validate_snapshot_for_store(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var address_id: String = String(snapshot["address"]["address_id"])
	if _snapshots_by_address_id.has(address_id):
		var existing: Dictionary = _snapshots_by_address_id[address_id]
		var existing_revision: int = int(existing["state_revision"])
		var incoming_revision: int = int(snapshot["state_revision"])
		if incoming_revision < existing_revision:
			return MatterUtilsScript.failure("STALE_MATTER_BRICK_REVISION")
		if incoming_revision == existing_revision:
			if String(existing["checksum"]) == String(snapshot["checksum"]) \
				and existing == snapshot:
				return MatterUtilsScript.success({"status": "IDEMPOTENT"})
			return MatterUtilsScript.failure("SAME_REVISION_MATTER_BRICK_CONFLICT")
	_snapshots_by_address_id[address_id] = snapshot.duplicate(true)
	return MatterUtilsScript.success({"status": "STORED"})


func put_many_atomic(
	snapshots: Array,
	expected_revision_by_address: Dictionary
) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("SPARSE_STORE_NOT_CONFIGURED")
	if snapshots.is_empty():
		return MatterUtilsScript.failure("EMPTY_ATOMIC_MATTER_BRICK_WRITE")
	var staged_by_address_id: Dictionary = {}
	for index in range(snapshots.size()):
		var snapshot = snapshots[index]
		if typeof(snapshot) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_ATOMIC_MATTER_BRICK", {"index": index})
		var validation: Dictionary = _validate_snapshot_for_store(snapshot)
		if not bool(validation.get("success", false)):
			return validation
		var address_id: String = String(snapshot["address"]["address_id"])
		if staged_by_address_id.has(address_id):
			return MatterUtilsScript.failure("DUPLICATE_ATOMIC_MATTER_BRICK", {"address_id": address_id})
		if not expected_revision_by_address.has(address_id) \
			or not MatterUtilsScript.is_json_integer(expected_revision_by_address[address_id]) \
			or int(expected_revision_by_address[address_id]) < 0:
			return MatterUtilsScript.failure("MISSING_ATOMIC_MATTER_EXPECTED_REVISION", {
				"address_id": address_id,
			})
		var expected_revision: int = int(expected_revision_by_address[address_id])
		var current_revision: int = revision_for_address_id(address_id)
		if current_revision != expected_revision:
			return MatterUtilsScript.failure("ATOMIC_MATTER_REVISION_MISMATCH", {
				"address_id": address_id,
				"expected_revision": expected_revision,
				"current_revision": current_revision,
			})
		if int(snapshot["state_revision"]) != expected_revision + 1:
			return MatterUtilsScript.failure("ATOMIC_MATTER_REVISION_NOT_INCREMENTED", {
				"address_id": address_id,
			})
		staged_by_address_id[address_id] = Dictionary(snapshot).duplicate(true)
	if staged_by_address_id.size() != expected_revision_by_address.size():
		return MatterUtilsScript.failure("ATOMIC_MATTER_EXPECTED_REVISION_SET_MISMATCH")
	var address_ids: Array = staged_by_address_id.keys()
	address_ids.sort()
	for address_id in address_ids:
		_snapshots_by_address_id[address_id] = staged_by_address_id[address_id]
	return MatterUtilsScript.success({
		"status": "COMMITTED",
		"address_ids": address_ids,
	})


func rollback_many_atomic(
	previous_snapshot_by_address_id: Dictionary,
	committed_revision_by_address_id: Dictionary
) -> Dictionary:
	if not _configured or previous_snapshot_by_address_id.size() != committed_revision_by_address_id.size():
		return MatterUtilsScript.failure("INVALID_ATOMIC_MATTER_ROLLBACK")
	var address_ids: Array = committed_revision_by_address_id.keys()
	address_ids.sort()
	for address_id in address_ids:
		if not previous_snapshot_by_address_id.has(address_id) \
			or not MatterUtilsScript.is_json_integer(committed_revision_by_address_id[address_id]):
			return MatterUtilsScript.failure("INVALID_ATOMIC_MATTER_ROLLBACK_ENTRY")
		if revision_for_address_id(String(address_id)) != int(committed_revision_by_address_id[address_id]):
			return MatterUtilsScript.failure("ATOMIC_MATTER_ROLLBACK_REVISION_MISMATCH", {
				"address_id": String(address_id),
			})
	for address_id in address_ids:
		var previous = previous_snapshot_by_address_id[address_id]
		var expected_previous_revision: int = int(
			committed_revision_by_address_id[address_id]
		) - 1
		if expected_previous_revision < 0:
			return MatterUtilsScript.failure("INVALID_ATOMIC_MATTER_ROLLBACK_REVISION")
		if typeof(previous) == TYPE_DICTIONARY and not Dictionary(previous).is_empty():
			var validation: Dictionary = _validate_snapshot_for_store(previous)
			if not bool(validation.get("success", false)):
				return validation
			if String(previous["address"]["address_id"]) != String(address_id):
				return MatterUtilsScript.failure("ATOMIC_MATTER_ROLLBACK_ADDRESS_MISMATCH", {
					"address_id": String(address_id),
				})
			if int(previous["state_revision"]) != expected_previous_revision:
				return MatterUtilsScript.failure("ATOMIC_MATTER_ROLLBACK_PREVIOUS_REVISION_MISMATCH", {
					"address_id": String(address_id),
				})
		elif expected_previous_revision != 0:
			return MatterUtilsScript.failure("ATOMIC_MATTER_ROLLBACK_SNAPSHOT_MISSING", {
				"address_id": String(address_id),
			})
	for address_id in address_ids:
		var previous_to_restore = previous_snapshot_by_address_id[address_id]
		if typeof(previous_to_restore) == TYPE_DICTIONARY \
			and not Dictionary(previous_to_restore).is_empty():
			_snapshots_by_address_id[address_id] = Dictionary(previous_to_restore).duplicate(true)
		else:
			_snapshots_by_address_id.erase(address_id)
	return MatterUtilsScript.success({"status": "ROLLED_BACK"})


func get_snapshot(address: Dictionary) -> Dictionary:
	if not _configured \
		or not bool(BrickLayoutScript.validate_brick_address(_grid_profile, address).get("success", false)):
		return {}
	var address_id: String = String(address["address_id"])
	return Dictionary(_snapshots_by_address_id.get(address_id, {})).duplicate(true)


func get_snapshot_by_address_id(address_id: String) -> Dictionary:
	if not _configured:
		return {}
	return Dictionary(_snapshots_by_address_id.get(address_id, {})).duplicate(true)


func has(address: Dictionary) -> bool:
	if not _configured \
		or not bool(BrickLayoutScript.validate_brick_address(_grid_profile, address).get("success", false)):
		return false
	return _snapshots_by_address_id.has(String(address["address_id"]))


func revision(address: Dictionary) -> int:
	if not _configured \
		or not bool(BrickLayoutScript.validate_brick_address(_grid_profile, address).get("success", false)):
		return -1
	return revision_for_address_id(String(address["address_id"]))


func revision_for_address_id(address_id: String) -> int:
	if not _configured or not _snapshots_by_address_id.has(address_id):
		return 0
	return int(_snapshots_by_address_id[address_id]["state_revision"])


func has_address_id(address_id: String) -> bool:
	return _configured and _snapshots_by_address_id.has(address_id)


func erase(address: Dictionary, expected_revision: int) -> Dictionary:
	if not _configured \
		or not bool(BrickLayoutScript.validate_brick_address(_grid_profile, address).get("success", false)):
		return MatterUtilsScript.failure("INVALID_SPARSE_STORE_ADDRESS")
	var address_id: String = String(address["address_id"])
	if not _snapshots_by_address_id.has(address_id):
		return MatterUtilsScript.success({"status": "ABSENT"})
	var existing: Dictionary = _snapshots_by_address_id[address_id]
	if int(existing["state_revision"]) != expected_revision:
		return MatterUtilsScript.failure("MATTER_BRICK_ERASE_REVISION_MISMATCH")
	_snapshots_by_address_id.erase(address_id)
	return MatterUtilsScript.success({"status": "ERASED"})


func size() -> int:
	return _snapshots_by_address_id.size()


func address_ids() -> Array:
	var result: Array = _snapshots_by_address_id.keys()
	result.sort()
	return result


func content_hash() -> String:
	if not _configured:
		return ""
	var entries: Array = []
	for address_id in address_ids():
		var snapshot: Dictionary = _snapshots_by_address_id[address_id]
		entries.append({
			"address_id": String(address_id),
			"state_revision": int(snapshot["state_revision"]),
			"snapshot_checksum": String(snapshot["checksum"]),
		})
	return MatterUtilsScript.payload_hash({
		"body_definition_hash": _body_definition_hash,
		"grid_profile_hash": GridProfileScript.content_hash(_grid_profile),
		"entries": entries,
	})


func clear() -> void:
	_snapshots_by_address_id.clear()


func _validate_snapshot_for_store(snapshot: Dictionary) -> Dictionary:
	if not bool(BrickSnapshotScript.validate(snapshot).get("success", false)):
		return MatterUtilsScript.failure("INVALID_SPARSE_STORE_SNAPSHOT")
	if String(snapshot["body_definition_hash"]) != _body_definition_hash:
		return MatterUtilsScript.failure("SPARSE_STORE_BODY_HASH_MISMATCH")
	if String(snapshot["generator_version"]) != _generator_version \
		or int(snapshot["generator_seed"]) != _generator_seed:
		return MatterUtilsScript.failure("SPARSE_STORE_GENERATOR_MISMATCH")
	if int(snapshot["sample_count"]) != GridProfileScript.sample_count(_grid_profile):
		return MatterUtilsScript.failure("SPARSE_STORE_BRICK_LAYOUT_MISMATCH", {
			"actual_sample_count": int(snapshot["sample_count"]),
			"expected_sample_count": GridProfileScript.sample_count(_grid_profile),
		})
	return BrickLayoutScript.validate_brick_address(_grid_profile, snapshot["address"])
