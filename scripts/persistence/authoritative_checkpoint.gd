extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

const SCHEMA: String = "planet_simulator.authoritative_checkpoint.v1"
const SCHEMA_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"checkpoint_id",
	"generation",
	"previous_generation",
	"authority_owner_id",
	"authority_epoch",
	"server_tick",
	"state_revision",
	"logical_session_id",
	"committed_operation_id",
	"committed_at_tick",
	"authority_state",
	"replay_state",
	"checksum",
]


static func create(
	checkpoint_id: String,
	generation: int,
	previous_generation: int,
	authority_state: Dictionary,
	replay_state: Dictionary,
	committed_operation_id: String,
	committed_at_tick: int
) -> Dictionary:
	var snapshot: Dictionary = Dictionary(authority_state.get("current_snapshot", {}))
	var value: Dictionary = {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"checkpoint_id": checkpoint_id,
		"generation": generation,
		"previous_generation": previous_generation,
		"authority_owner_id": String(authority_state.get("authority_owner_id", "")),
		"authority_epoch": int(authority_state.get("authority_epoch", 0)),
		"server_tick": int(authority_state.get("server_tick", -1)),
		"state_revision": int(snapshot.get("state_revision", -1)),
		"logical_session_id": String(authority_state.get("session_id", "")),
		"committed_operation_id": committed_operation_id,
		"committed_at_tick": committed_at_tick,
		"authority_state": authority_state.duplicate(true),
		"replay_state": replay_state.duplicate(true),
		"checksum": "",
	}
	# Bind the checksum to the exact JSON-safe representation written to disk.
	return UtilsScript.finalize_json_checksum(value)


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return _failure(String(exact.get("error_code", "INVALID_CHECKPOINT_FIELDS")), String(exact.get("message", "Invalid checkpoint fields")))
	if typeof(value["schema"]) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AUTHORITATIVE_CHECKPOINT_SCHEMA", "Unsupported authoritative checkpoint schema")
	if not UtilsScript.is_json_integer(value["schema_version"]) or int(value["schema_version"]) != SCHEMA_VERSION:
		return _failure("UNSUPPORTED_AUTHORITATIVE_CHECKPOINT_VERSION", "Unsupported authoritative checkpoint version")
	for field in ["checkpoint_id", "authority_owner_id", "logical_session_id"]:
		if typeof(value[field]) != TYPE_STRING or not _is_canonical_id(String(value[field])):
			return _failure("INVALID_AUTHORITATIVE_CHECKPOINT_ID", "%s is not canonical" % field)
	if typeof(value["committed_operation_id"]) != TYPE_STRING:
		return _failure("INVALID_COMMITTED_OPERATION_ID", "committed_operation_id must be a String")
	if not String(value["committed_operation_id"]).is_empty() and not _is_canonical_id(String(value["committed_operation_id"])):
		return _failure("INVALID_COMMITTED_OPERATION_ID", "committed_operation_id is not canonical")
	for field in ["generation", "previous_generation", "authority_epoch", "server_tick", "state_revision", "committed_at_tick"]:
		if not UtilsScript.is_json_integer(value[field]):
			return _failure("INVALID_AUTHORITATIVE_CHECKPOINT_INTEGER", "%s must be an integer" % field)
	if int(value["generation"]) < 1 or int(value["previous_generation"]) < 0:
		return _failure("INVALID_AUTHORITATIVE_CHECKPOINT_GENERATION", "generation is invalid")
	if int(value["previous_generation"]) >= int(value["generation"]):
		return _failure("INVALID_AUTHORITATIVE_CHECKPOINT_GENERATION", "previous_generation must be lower than generation")
	if int(value["authority_epoch"]) < 1 or int(value["server_tick"]) < 0 or int(value["state_revision"]) < 0:
		return _failure("INVALID_AUTHORITATIVE_CHECKPOINT_REVISION", "authority/revision/tick values are invalid")
	if int(value["committed_at_tick"]) < 0 or int(value["committed_at_tick"]) > int(value["server_tick"]):
		return _failure("INVALID_AUTHORITATIVE_COMMIT_TICK", "committed_at_tick is invalid")
	if typeof(value["authority_state"]) != TYPE_DICTIONARY or typeof(value["replay_state"]) != TYPE_DICTIONARY:
		return _failure("INVALID_AUTHORITATIVE_CHECKPOINT_STATE", "checkpoint state sections must be objects")
	var safe: Dictionary = UtilsScript.canonicalize(value, "$.authoritative_checkpoint")
	if not bool(safe.get("success", false)):
		return _failure("AUTHORITATIVE_CHECKPOINT_NOT_JSON_SAFE", String(safe.get("error", "Checkpoint is not JSON-safe")))
	var authority_state: Dictionary = value["authority_state"]
	var snapshot_value = authority_state.get("current_snapshot", {})
	if not snapshot_value is Dictionary:
		return _failure("INVALID_AUTHORITATIVE_SNAPSHOT", "authority_state.current_snapshot must be an object")
	var snapshot: Dictionary = snapshot_value
	var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return _failure("INVALID_AUTHORITATIVE_SNAPSHOT", String(snapshot_validation.get("message", "Invalid entity snapshot")))
	if String(snapshot["authority_owner_id"]) != String(value["authority_owner_id"]):
		return _failure("AUTHORITATIVE_OWNER_MISMATCH", "checkpoint owner does not match entity snapshot")
	if int(snapshot["authority_epoch"]) != int(value["authority_epoch"]):
		return _failure("AUTHORITATIVE_EPOCH_MISMATCH", "checkpoint epoch does not match entity snapshot")
	if int(snapshot["server_tick"]) != int(value["server_tick"]):
		return _failure("AUTHORITATIVE_TICK_MISMATCH", "checkpoint tick does not match entity snapshot")
	if int(snapshot["state_revision"]) != int(value["state_revision"]):
		return _failure("AUTHORITATIVE_REVISION_MISMATCH", "checkpoint revision does not match entity snapshot")
	if String(authority_state.get("session_id", "")) != String(value["logical_session_id"]):
		return _failure("AUTHORITATIVE_SESSION_MISMATCH", "checkpoint session does not match authority state")
	if typeof(value["checksum"]) != TYPE_STRING or not _is_sha256(String(value["checksum"])):
		return _failure("INVALID_AUTHORITATIVE_CHECKPOINT_CHECKSUM", "checkpoint checksum must be lowercase SHA-256")
	if String(value["checksum"]) != compute_checksum(value):
		return _failure("AUTHORITATIVE_CHECKPOINT_CHECKSUM_MISMATCH", "checkpoint checksum mismatch")
	return {"success": true, "error_code": "", "message": ""}


static func validate_progression(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_validation: Dictionary = validate(candidate)
	if not bool(candidate_validation.get("success", false)):
		return candidate_validation
	var current_validation: Dictionary = validate(current)
	if not bool(current_validation.get("success", false)):
		return _failure("CURRENT_AUTHORITATIVE_CHECKPOINT_INVALID", "Current checkpoint is invalid")
	if int(candidate["generation"]) <= int(current["generation"]):
		return _failure("AUTHORITATIVE_GENERATION_ROLLBACK", "checkpoint generation must increase")
	if int(candidate["previous_generation"]) != int(current["generation"]):
		return _failure("AUTHORITATIVE_GENERATION_GAP", "previous_generation must reference current generation")
	if int(candidate["authority_epoch"]) < int(current["authority_epoch"]):
		return _failure("AUTHORITATIVE_EPOCH_ROLLBACK", "authority epoch cannot decrease")
	if (
		String(candidate["authority_owner_id"]) != String(current["authority_owner_id"])
		and int(candidate["authority_epoch"]) <= int(current["authority_epoch"])
	):
		return _failure("AUTHORITATIVE_OWNER_CHANGED_WITHOUT_EPOCH", "authority owner change requires a higher epoch")
	if int(candidate["state_revision"]) < int(current["state_revision"]):
		return _failure("AUTHORITATIVE_REVISION_ROLLBACK", "state revision cannot decrease")
	if int(candidate["server_tick"]) < int(current["server_tick"]):
		return _failure("AUTHORITATIVE_TICK_ROLLBACK", "server tick cannot decrease")
	if int(candidate["state_revision"]) == int(current["state_revision"]):
		var candidate_snapshot: Dictionary = candidate["authority_state"].get("current_snapshot", {})
		var current_snapshot: Dictionary = current["authority_state"].get("current_snapshot", {})
		if _revision_semantic_hash(candidate_snapshot) != _revision_semantic_hash(current_snapshot):
			# R4.2-P0: keep the exact fail-closed progression invariant. Diagnose
			# only the first changed field path; never log snapshot values, ids,
			# or the full durable payload. No normalization rule is relaxed.
			var candidate_semantic: Dictionary = _revision_semantic_projection(candidate_snapshot)
			var current_semantic: Dictionary = _revision_semantic_projection(current_snapshot)
			var mismatch_path: String = _first_revision_difference(
				candidate_semantic, current_semantic, "$", 0
			)
			return _failure(
				"SAME_REVISION_AUTHORITATIVE_MUTATION",
				"same revision cannot contain a different semantic snapshot; first_changed_path=%s" % mismatch_path
			)
	return {"success": true, "error_code": "", "message": ""}


static func _revision_semantic_hash(snapshot: Dictionary) -> String:
	return UtilsScript.payload_hash(_revision_semantic_projection(snapshot))


static func _revision_semantic_projection(snapshot: Dictionary) -> Dictionary:
	var semantic: Dictionary = snapshot.duplicate(true)
	semantic.erase("checksum")
	semantic.erase("snapshot_id")
	semantic.erase("server_tick")
	var spatial_ref_value = semantic.get("spatial_ref", {})
	if spatial_ref_value is Dictionary:
		var spatial_ref: Dictionary = Dictionary(spatial_ref_value).duplicate(true)
		spatial_ref.erase("sample_time_s")
		semantic["spatial_ref"] = spatial_ref
	var components_value = semantic.get("domain_components", {})
	if components_value is Dictionary:
		var components: Dictionary = Dictionary(components_value).duplicate(true)
		var gameplay_value = components.get("networked_gameplay_state", {})
		if gameplay_value is Dictionary:
			var gameplay: Dictionary = Dictionary(gameplay_value).duplicate(true)
			gameplay.erase("server_tick")
			# R3C2-R2: ownership.server_tick mirrors the moving fixed tick at
			# export time exactly like the top-level server_tick above. It is
			# tick-derived metadata, not a canonical mutation; ownership
			# revision and player rows stay protected by the same projection.
			var ownership_value = gameplay.get("ownership", {})
			if ownership_value is Dictionary:
				var ownership: Dictionary = Dictionary(ownership_value).duplicate(true)
				ownership.erase("server_tick")
				# R3C21-R2: ownership.checksum is derived over the mirrored
				# server_tick above, so it changes with pure time progression
				# at a constant state_revision. Erase it like every other
				# derived checksum; ownership.revision and player rows remain
				# protected by this projection.
				ownership.erase("checksum")
				gameplay["ownership"] = ownership
			gameplay.erase("checksum")
			components["networked_gameplay_state"] = gameplay
		components.erase("durable_state_checksum")
		semantic["domain_components"] = components
	return semantic


# Debugging-only path oracle for a rejected checkpoint. Deterministic order,
# bounded traversal, and NO values. Unknown map keys (e.g. player/session IDs)
# are redacted from logs. This is never consulted by progression acceptance.
static func debug_all_revision_difference_paths(left: Variant, right: Variant) -> Array:
	var paths: Array = []
	_collect_revision_differences(left, right, "$", 0, paths)
	if paths.is_empty():
		paths.append("$")
	return paths


static func _collect_revision_differences(
	left: Variant, right: Variant, path: String, depth: int, paths: Array
) -> void:
	if left == right or paths.size() >= 64:
		return
	if typeof(left) != typeof(right) or depth >= 16:
		paths.append(path)
		return
	if left is Dictionary:
		var left_map: Dictionary = left
		var right_map: Dictionary = right
		var keys: Array = left_map.keys()
		keys.sort()
		# Keep the same checksum-deferred ordering as the first-diff oracle.
		if keys.has("checksum"):
			keys.erase("checksum")
			keys.append("checksum")
		for index in range(mini(keys.size(), 256)):
			var key: Variant = keys[index]
			var next_path: String = "%s.%s" % [path, _revision_diagnostic_key(String(key))]
			if not right_map.has(key):
				paths.append(next_path)
				continue
			_collect_revision_differences(left_map[key], right_map[key], next_path, depth + 1, paths)
		var right_keys: Array = right_map.keys()
		right_keys.sort()
		for index in range(mini(right_keys.size(), 256)):
			var key: Variant = right_keys[index]
			if not left_map.has(key):
				paths.append("%s.%s" % [path, _revision_diagnostic_key(String(key))])
	elif left is Array:
		var left_array: Array = left
		var right_array: Array = right
		for index in range(mini(mini(left_array.size(), right_array.size()), 256)):
			_collect_revision_differences(
				left_array[index], right_array[index], "%s[%d]" % [path, index], depth + 1, paths
			)
		if left_array.size() != right_array.size():
			paths.append("%s[length]" % path)
		return
	else:
		paths.append(path)


static func _first_revision_difference(left: Variant, right: Variant, path: String, depth: int) -> String:
	if left == right:
		return ""
	if typeof(left) != typeof(right) or depth >= 16:
		return path
	if left is Dictionary:
		var left_map: Dictionary = left
		var right_map: Dictionary = right
		var keys: Array = left_map.keys()
		keys.sort()
		# Prefer the causal field over a nested derived checksum.
		# The checksum remains part of the canonical semantic hash.
		if keys.has("checksum"):
			keys.erase("checksum")
			keys.append("checksum")
		for index in range(mini(keys.size(), 256)):
			var key: Variant = keys[index]
			var next_path: String = "%s.%s" % [path, _revision_diagnostic_key(String(key))]
			if not right_map.has(key):
				return next_path
			var nested: String = _first_revision_difference(left_map[key], right_map[key], next_path, depth + 1)
			if not nested.is_empty():
				return nested
		var right_keys: Array = right_map.keys()
		right_keys.sort()
		for index in range(mini(right_keys.size(), 256)):
			var key: Variant = right_keys[index]
			if not left_map.has(key):
				return "%s.%s" % [path, _revision_diagnostic_key(String(key))]
	elif left is Array:
		var left_array: Array = left
		var right_array: Array = right
		for index in range(mini(mini(left_array.size(), right_array.size()), 256)):
			var next_path: String = "%s[%d]" % [path, index]
			var nested: String = _first_revision_difference(
				left_array[index], right_array[index], next_path, depth + 1
			)
			if not nested.is_empty():
				return nested
	return path


static func _revision_diagnostic_key(key: String) -> String:
	# Fixed schema names only: arbitrary dictionary keys can contain player
	# identities or raw operator input and must not escape into a report.
	const FIELDS: Array[String] = [
		"schema", "schema_version", "entity_id", "entity_type",
		"authority_state", "domain_components", "networked_gameplay_state",
		"authority_owner_id", "authority_epoch", "revision", "state_revision",
		"region_id", "topology_adapter", "profile", "players", "ownership",
		"shared_item", "canonical_item_graph", "resource_mining",
		"position", "velocity", "orientation_yaw", "connected", "inventory",
		"last_input_sequence", "state_revision", "server_tick", "tick",
		"checksum", "snapshot", "state", "player", "logical_player_id",
		"item_id", "session_id", "transport_session_id", "last_operation_id",
		"ownership_epoch", "records", "entries", "items", "hotbar",
		"status", "region", "x", "y", "z"
	]
	return key if key in FIELDS else "{map-key}"


static func _is_canonical_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["/", "_", ".", "-"]):
			return false
	return true


static func _is_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "f")):
			return false
	return true


static func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message}
