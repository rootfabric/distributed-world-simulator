extends RefCounted

const ProductionPersistence = preload("res://scripts/ecology/production/ecology_region_persistence_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p4_5_region_ownership.v1"
const VERSION := "1.0.0"
const HANDOFF_SCHEMA := "distributed_world_simulator.ecology.p4_5_region_handoff.v1"
const HANDOFF_VERSION := "1.0.0"
const PARENT_P4_4_AGGREGATE := "4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2"
const MAX_SERVER_ID_LENGTH := 128
const MAX_EXACT_EPOCH := 9007199254740991

const OWNERSHIP_FIELDS := [
	"schema",
	"version",
	"parent_p4_4_aggregate",
	"region_id",
	"owner_server_id",
	"ownership_epoch",
	"snapshot",
	"snapshot_hash",
	"ownership_hash",
]

const HANDOFF_FIELDS := [
	"schema",
	"version",
	"parent_p4_4_aggregate",
	"region_id",
	"source_owner_server_id",
	"target_owner_server_id",
	"source_epoch",
	"target_epoch",
	"source_ownership_hash",
	"snapshot",
	"snapshot_hash",
	"handoff_hash",
]

static func create_ownership(snapshot: Dictionary, owner_server_id_value, ownership_epoch_value = 0) -> Dictionary:
	if not bool(ProductionPersistence.validate_snapshot(snapshot).get("success", false)):
		return {}
	if typeof(owner_server_id_value) != TYPE_STRING:
		return {}
	var owner_server_id := String(owner_server_id_value)
	if not _is_server_id(owner_server_id):
		return {}
	if typeof(ownership_epoch_value) != TYPE_INT:
		return {}
	var epoch := int(ownership_epoch_value)
	if epoch < 0 or epoch > MAX_EXACT_EPOCH:
		return {}
	var state := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_p4_4_aggregate": PARENT_P4_4_AGGREGATE,
		"region_id": String(snapshot.get("region_id", "")),
		"owner_server_id": owner_server_id,
		"ownership_epoch": epoch,
		"snapshot": snapshot.duplicate(true),
		"snapshot_hash": String(snapshot.get("snapshot_hash", "")),
	}
	state["ownership_hash"] = compute_ownership_hash(state)
	if not bool(validate_ownership(state).get("success", false)):
		return {}
	return state

static func validate_ownership(state: Dictionary) -> Dictionary:
	if not _exact_fields(state, OWNERSHIP_FIELDS):
		return _failure("OWNERSHIP_FIELDS_MISMATCH")
	if String(state.get("schema", "")) != SCHEMA or String(state.get("version", "")) != VERSION:
		return _failure("OWNERSHIP_SCHEMA_OR_VERSION_MISMATCH")
	if String(state.get("parent_p4_4_aggregate", "")) != PARENT_P4_4_AGGREGATE:
		return _failure("OWNERSHIP_PARENT_P4_4_MISMATCH")
	if typeof(state.get("owner_server_id")) != TYPE_STRING or not _is_server_id(String(state.get("owner_server_id", ""))):
		return _failure("OWNER_SERVER_ID_INVALID")
	if typeof(state.get("ownership_epoch")) != TYPE_INT:
		return _failure("OWNERSHIP_EPOCH_TYPE_INVALID")
	var epoch := int(state.get("ownership_epoch", -1))
	if epoch < 0 or epoch > MAX_EXACT_EPOCH:
		return _failure("OWNERSHIP_EPOCH_RANGE_INVALID")
	if typeof(state.get("snapshot")) != TYPE_DICTIONARY:
		return _failure("OWNERSHIP_SNAPSHOT_TYPE_INVALID")
	var snapshot: Dictionary = Dictionary(state.get("snapshot", {}))
	if not bool(ProductionPersistence.validate_snapshot(snapshot).get("success", false)):
		return _failure("OWNERSHIP_SNAPSHOT_INVALID")
	var region_id := String(snapshot.get("region_id", ""))
	var snapshot_hash := String(snapshot.get("snapshot_hash", ""))
	if String(state.get("region_id", "")) != region_id:
		return _failure("OWNERSHIP_REGION_DERIVED_MISMATCH")
	if String(state.get("snapshot_hash", "")) != snapshot_hash:
		return _failure("OWNERSHIP_SNAPSHOT_HASH_MISMATCH")
	var expected_hash := compute_ownership_hash(state)
	if not _is_hash(expected_hash) or String(state.get("ownership_hash", "")) != expected_hash:
		return _failure("OWNERSHIP_HASH_MISMATCH")
	return {
		"success": true,
		"error": "",
		"region_id": region_id,
		"owner_server_id": String(state["owner_server_id"]),
		"ownership_epoch": epoch,
		"snapshot_hash": snapshot_hash,
		"ownership_hash": expected_hash,
	}

static func compute_ownership_hash(state: Dictionary) -> String:
	var canonical := [
		String(state.get("schema", "")),
		String(state.get("version", "")),
		String(state.get("parent_p4_4_aggregate", "")),
		String(state.get("region_id", "")),
		String(state.get("owner_server_id", "")),
		state.get("ownership_epoch", -1),
		String(state.get("snapshot_hash", "")),
	]
	return JSON.stringify(canonical).sha256_text()

static func authorize(state: Dictionary, server_id_value, expected_epoch_value, expected_ownership_hash_value, expected_snapshot_hash_value) -> bool:
	if not bool(validate_ownership(state).get("success", false)):
		return false
	if typeof(server_id_value) != TYPE_STRING or typeof(expected_epoch_value) != TYPE_INT or typeof(expected_ownership_hash_value) != TYPE_STRING:
		return false
	if String(server_id_value) != String(state["owner_server_id"]):
		return false
	if int(expected_epoch_value) != int(state["ownership_epoch"]):
		return false
	if String(expected_ownership_hash_value) != String(state["ownership_hash"]):
		return false
	if typeof(expected_snapshot_hash_value) != TYPE_STRING:
		return false
	var expected_ownership_hash := String(expected_ownership_hash_value)
	var expected_snapshot_hash := String(expected_snapshot_hash_value)
	if not _is_hash(expected_ownership_hash) or not _is_hash(expected_snapshot_hash):
		return false
	if expected_snapshot_hash != String(state["snapshot_hash"]):
		return false
	return true

static func commit_snapshot(state: Dictionary, server_id_value, expected_epoch_value, expected_ownership_hash_value, new_snapshot: Dictionary) -> Dictionary:
	if not authorize(state, server_id_value, expected_epoch_value, expected_ownership_hash_value, String(state.get("snapshot_hash", ""))):
		return {}
	if not bool(ProductionPersistence.validate_snapshot(new_snapshot).get("success", false)):
		return {}
	if String(new_snapshot.get("region_id", "")) != String(state.get("region_id", "")):
		return {}
	return create_ownership(new_snapshot, String(state["owner_server_id"]), int(state["ownership_epoch"]))

static func prepare_handoff(state: Dictionary, target_owner_server_id_value) -> Dictionary:
	if not bool(validate_ownership(state).get("success", false)):
		return {}
	if typeof(target_owner_server_id_value) != TYPE_STRING:
		return {}
	var target := String(target_owner_server_id_value)
	if not _is_server_id(target) or target == String(state["owner_server_id"]):
		return {}
	var source_epoch := int(state["ownership_epoch"])
	if source_epoch >= MAX_EXACT_EPOCH:
		return {}
	var package := {
		"schema": HANDOFF_SCHEMA,
		"version": HANDOFF_VERSION,
		"parent_p4_4_aggregate": PARENT_P4_4_AGGREGATE,
		"region_id": String(state["region_id"]),
		"source_owner_server_id": String(state["owner_server_id"]),
		"target_owner_server_id": target,
		"source_epoch": source_epoch,
		"target_epoch": source_epoch + 1,
		"source_ownership_hash": String(state["ownership_hash"]),
		"snapshot": Dictionary(state["snapshot"]).duplicate(true),
		"snapshot_hash": String(state["snapshot_hash"]),
	}
	package["handoff_hash"] = compute_handoff_hash(package)
	if not bool(validate_handoff(package, state).get("success", false)):
		return {}
	return package

static func validate_handoff(package: Dictionary, current_state: Dictionary) -> Dictionary:
	if not _exact_fields(package, HANDOFF_FIELDS):
		return _failure("HANDOFF_FIELDS_MISMATCH")
	if not bool(validate_ownership(current_state).get("success", false)):
		return _failure("HANDOFF_CURRENT_OWNERSHIP_INVALID")
	if String(package.get("schema", "")) != HANDOFF_SCHEMA or String(package.get("version", "")) != HANDOFF_VERSION:
		return _failure("HANDOFF_SCHEMA_OR_VERSION_MISMATCH")
	if String(package.get("parent_p4_4_aggregate", "")) != PARENT_P4_4_AGGREGATE:
		return _failure("HANDOFF_PARENT_P4_4_MISMATCH")
	if typeof(package.get("source_owner_server_id")) != TYPE_STRING or not _is_server_id(String(package.get("source_owner_server_id", ""))):
		return _failure("HANDOFF_SOURCE_SERVER_INVALID")
	if typeof(package.get("target_owner_server_id")) != TYPE_STRING or not _is_server_id(String(package.get("target_owner_server_id", ""))):
		return _failure("HANDOFF_TARGET_SERVER_INVALID")
	if String(package.get("source_owner_server_id", "")) == String(package.get("target_owner_server_id", "")):
		return _failure("HANDOFF_TARGET_EQUALS_SOURCE")
	if typeof(package.get("source_epoch")) != TYPE_INT or typeof(package.get("target_epoch")) != TYPE_INT:
		return _failure("HANDOFF_EPOCH_TYPE_INVALID")
	var source_epoch := int(package.get("source_epoch", -1))
	var target_epoch := int(package.get("target_epoch", -1))
	if source_epoch < 0 or source_epoch >= MAX_EXACT_EPOCH or target_epoch != source_epoch + 1:
		return _failure("HANDOFF_EPOCH_TRANSITION_INVALID")
	if typeof(package.get("snapshot")) != TYPE_DICTIONARY:
		return _failure("HANDOFF_SNAPSHOT_TYPE_INVALID")
	var snapshot: Dictionary = Dictionary(package.get("snapshot", {}))
	if not bool(ProductionPersistence.validate_snapshot(snapshot).get("success", false)):
		return _failure("HANDOFF_SNAPSHOT_INVALID")
	if String(package.get("region_id", "")) != String(snapshot.get("region_id", "")):
		return _failure("HANDOFF_REGION_DERIVED_MISMATCH")
	if String(package.get("snapshot_hash", "")) != String(snapshot.get("snapshot_hash", "")):
		return _failure("HANDOFF_SNAPSHOT_HASH_DERIVED_MISMATCH")
	if String(package.get("region_id", "")) != String(current_state.get("region_id", "")):
		return _failure("HANDOFF_CURRENT_REGION_MISMATCH")
	if String(package.get("source_owner_server_id", "")) != String(current_state.get("owner_server_id", "")):
		return _failure("HANDOFF_CURRENT_OWNER_MISMATCH")
	if source_epoch != int(current_state.get("ownership_epoch", -1)):
		return _failure("HANDOFF_CURRENT_EPOCH_MISMATCH")
	if String(package.get("source_ownership_hash", "")) != String(current_state.get("ownership_hash", "")):
		return _failure("HANDOFF_STALE_SOURCE_OWNERSHIP")
	if String(package.get("snapshot_hash", "")) != String(current_state.get("snapshot_hash", "")):
		return _failure("HANDOFF_STALE_SOURCE_SNAPSHOT")
	var expected_hash := compute_handoff_hash(package)
	if not _is_hash(expected_hash) or String(package.get("handoff_hash", "")) != expected_hash:
		return _failure("HANDOFF_HASH_MISMATCH")
	return {
		"success": true,
		"error": "",
		"region_id": String(package["region_id"]),
		"source_owner_server_id": String(package["source_owner_server_id"]),
		"target_owner_server_id": String(package["target_owner_server_id"]),
		"source_epoch": source_epoch,
		"target_epoch": target_epoch,
		"snapshot_hash": String(package["snapshot_hash"]),
		"handoff_hash": expected_hash,
	}

static func compute_handoff_hash(package: Dictionary) -> String:
	var canonical := [
		String(package.get("schema", "")),
		String(package.get("version", "")),
		String(package.get("parent_p4_4_aggregate", "")),
		String(package.get("region_id", "")),
		String(package.get("source_owner_server_id", "")),
		String(package.get("target_owner_server_id", "")),
		package.get("source_epoch", -1),
		package.get("target_epoch", -1),
		String(package.get("source_ownership_hash", "")),
		String(package.get("snapshot_hash", "")),
	]
	return JSON.stringify(canonical).sha256_text()

static func accept_handoff(current_state: Dictionary, package: Dictionary, accepting_server_id_value) -> Dictionary:
	var validation := validate_handoff(package, current_state)
	if not bool(validation.get("success", false)):
		return {}
	if typeof(accepting_server_id_value) != TYPE_STRING:
		return {}
	var accepting_server_id := String(accepting_server_id_value)
	if accepting_server_id != String(package["target_owner_server_id"]):
		return {}
	return create_ownership(Dictionary(package["snapshot"]), accepting_server_id, int(package["target_epoch"]))

static func extract_snapshot(state: Dictionary) -> Dictionary:
	if not bool(validate_ownership(state).get("success", false)):
		return {}
	return Dictionary(state["snapshot"]).duplicate(true)

static func _is_server_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_SERVER_ID_LENGTH or value != value.strip_edges():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 46 or code == 58 or code == 95
		if not allowed:
			return false
	return true

static func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

static func _exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func _failure(error: String) -> Dictionary:
	return {"success": false, "error": "ECO_P4_5_" + error}
