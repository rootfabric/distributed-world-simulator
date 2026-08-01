extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const SCHEMA := "planet_simulator.construction_authority_record.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "owner_server_id", "owner_cell_id", "authority_epoch", "state", "migration_id", "target_server_id", "section_coordinator_server_id", "replica_server_ids", "lease_expires_tick", "construct_checksum", "metadata", "checksum"]
const ACTIVE := "ACTIVE"
const MIGRATING := "MIGRATING"
const TAKEOVER_PENDING := "TAKEOVER_PENDING"
const STATES := [ACTIVE, MIGRATING, TAKEOVER_PENDING]

static func create(construct_id: String, owner_server_id: String, owner_cell_id: String, authority_epoch: int, construct_checksum: String, replica_server_ids: Array = [], lease_expires_tick: int = 0, section_coordinator_server_id: String = "", metadata: Dictionary = {}, state: String = ACTIVE, migration_id: String = "", target_server_id: String = "") -> Dictionary:
	var replicas := P.sorted_strings(replica_server_ids)
	var result := {"schema": SCHEMA, "construct_id": construct_id, "owner_server_id": owner_server_id, "owner_cell_id": owner_cell_id, "authority_epoch": authority_epoch, "state": state, "migration_id": migration_id, "target_server_id": target_server_id, "section_coordinator_server_id": section_coordinator_server_id if not section_coordinator_server_id.is_empty() else owner_server_id, "replica_server_ids": replicas, "lease_expires_tick": lease_expires_tick, "construct_checksum": construct_checksum, "metadata": metadata.duplicate(true), "checksum": ""}
	result["checksum"] = compute_checksum(result)
	return result

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return P.failure("UNSUPPORTED_CONSTRUCTION_AUTHORITY_RECORD_SCHEMA")
	if not P.path_id(String(value.get("construct_id", "")), "construct/"): return P.failure("INVALID_CONSTRUCTION_AUTHORITY_CONSTRUCT_ID")
	for field in ["owner_server_id", "section_coordinator_server_id"]:
		if not P.path_id(String(value.get(field, "")), "server/"): return P.failure("INVALID_CONSTRUCTION_AUTHORITY_SERVER_ID")
	if not P.path_id(String(value.get("owner_cell_id", "")), "cell/"): return P.failure("INVALID_CONSTRUCTION_AUTHORITY_CELL_ID")
	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1: return P.failure("INVALID_CONSTRUCTION_AUTHORITY_EPOCH")
	if not Utils.is_json_integer(value.get("lease_expires_tick")) or int(value["lease_expires_tick"]) < 0: return P.failure("INVALID_CONSTRUCTION_AUTHORITY_LEASE")
	var state := String(value.get("state", ""))
	if not STATES.has(state): return P.failure("INVALID_CONSTRUCTION_AUTHORITY_STATE")
	var migration_id := String(value.get("migration_id", "")); var target := String(value.get("target_server_id", ""))
	if state == ACTIVE and (not migration_id.is_empty() or not target.is_empty()): return P.failure("INVALID_ACTIVE_CONSTRUCTION_AUTHORITY_FENCE")
	if state != ACTIVE:
		if not P.path_id(migration_id, "authority-migration/") or not P.path_id(target, "server/") or target == String(value["owner_server_id"]): return P.failure("INVALID_CONSTRUCTION_AUTHORITY_MIGRATION_FENCE")
	if typeof(value.get("replica_server_ids")) != TYPE_ARRAY: return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REPLICAS")
	var previous := ""
	for raw in value["replica_server_ids"]:
		var server := String(raw)
		if not P.path_id(server, "server/") or server == String(value["owner_server_id"]) or (not previous.is_empty() and server <= previous): return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_REPLICAS")
		previous = server
	if String(value.get("construct_checksum", "")).length() != 64: return P.failure("INVALID_CONSTRUCTION_AUTHORITY_CONSTRUCT_CHECKSUM")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(Utils.canonicalize(value["metadata"]).get("success", false)): return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_METADATA")
	if String(value.get("checksum", "")) != compute_checksum(value): return P.failure("CONSTRUCTION_AUTHORITY_RECORD_CHECKSUM_MISMATCH")
	return P.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
