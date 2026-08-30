extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_authority_envelope.v1"
const RECORD_FIELDS: Array[String] = ["source_domain", "source_id", "authority_epoch", "owner_id"]
const FIELDS: Array[String] = [
	"schema", "execution_owner", "source_authority_frontier",
	"mutable_source_ids", "readonly_source_ids", "authority_epoch_binding",
	"distributed_execution_protocol", "checksum",
]

static func create(execution_owner: String, source_authority_frontier: Array, mutable_source_ids: Array, readonly_source_ids: Array = [], distributed_execution_protocol: String = "") -> Dictionary:
	var records := Utils.sorted_dicts(source_authority_frontier, "source_id")
	records.sort_custom(func(a, b): return _record_key(a) < _record_key(b))
	var mutable_ids := Utils.sorted_strings(mutable_source_ids)
	var readonly_ids := Utils.sorted_strings(readonly_source_ids)
	var value: Dictionary = {
		"schema": SCHEMA,
		"execution_owner": execution_owner,
		"source_authority_frontier": records,
		"mutable_source_ids": mutable_ids,
		"readonly_source_ids": readonly_ids,
		"authority_epoch_binding": Utils.canonical_hash(records),
		"distributed_execution_protocol": distributed_execution_protocol,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_AUTHORITY_ENVELOPE_SCHEMA")
	if not Utils.is_canonical_id(value.get("execution_owner"), 2):
		return Utils.failure("INVALID_BAKE_EXECUTION_OWNER")
	if typeof(value.get("source_authority_frontier")) != TYPE_ARRAY or value["source_authority_frontier"].is_empty():
		return Utils.failure("INVALID_SOURCE_AUTHORITY_FRONTIER")
	var keys: Array = []
	var previous := ""
	for index in range(value["source_authority_frontier"].size()):
		var raw = value["source_authority_frontier"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_SOURCE_AUTHORITY_RECORD", {"index": index})
		var record: Dictionary = raw
		checked = Utils.validate_exact_fields(record, RECORD_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_source_domain(record.get("source_domain")) or not Utils.is_canonical_id(record.get("source_id"), 2):
			return Utils.failure("INVALID_SOURCE_AUTHORITY_RECORD", {"index": index})
		if not Utils.is_json_integer(record.get("authority_epoch")) or int(record["authority_epoch"]) < 1:
			return Utils.failure("INVALID_SOURCE_AUTHORITY_EPOCH", {"index": index})
		if not Utils.is_canonical_id(record.get("owner_id"), 2):
			return Utils.failure("INVALID_SOURCE_AUTHORITY_OWNER", {"index": index})
		var current := _record_key(record)
		if index > 0 and current <= previous:
			return Utils.failure("SOURCE_AUTHORITY_FRONTIER_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
		keys.append(Utils.source_key(String(record["source_domain"]), String(record["source_id"])))
	checked = Utils.validate_sorted_unique_strings(value.get("mutable_source_ids"), true)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_sorted_unique_strings(value.get("readonly_source_ids"), true)
	if not bool(checked.get("success", false)):
		return checked
	var declared: Array = []
	for source_id in value["mutable_source_ids"]:
		if value["readonly_source_ids"].has(source_id):
			return Utils.failure("AUTHORITY_SOURCE_MUTABILITY_OVERLAP")
		declared.append(source_id)
	for source_id in value["readonly_source_ids"]:
		declared.append(source_id)
	declared.sort()
	var expected := keys.duplicate()
	expected.sort()
	if declared != expected:
		return Utils.failure("AUTHORITY_SOURCE_COVERAGE_MISMATCH")
	if not Utils.is_lower_hex_64(value.get("authority_epoch_binding")):
		return Utils.failure("INVALID_AUTHORITY_EPOCH_BINDING")
	if String(value["authority_epoch_binding"]) != Utils.canonical_hash(value["source_authority_frontier"]):
		return Utils.failure("AUTHORITY_EPOCH_BINDING_MISMATCH")
	if typeof(value.get("distributed_execution_protocol")) != TYPE_STRING:
		return Utils.failure("INVALID_DISTRIBUTED_EXECUTION_PROTOCOL")
	return Utils.validate_checksum(value)

static func validate_b0_safety(value: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	if not String(value["distributed_execution_protocol"]).is_empty():
		return Utils.failure("UNSUPPORTED_DISTRIBUTED_BAKE_PROTOCOL")
	for record in value["source_authority_frontier"]:
		var source_key := Utils.source_key(String(record["source_domain"]), String(record["source_id"]))
		if value["mutable_source_ids"].has(source_key) and String(record["owner_id"]) != String(value["execution_owner"]):
			return Utils.failure("AUTHORITY_ENVELOPE_CROSSED", {"source_id": source_key})
	return Utils.success()

static func authority_epoch_for(value: Dictionary, source_domain: String, source_id: String) -> int:
	for record in value.get("source_authority_frontier", []):
		if String(record.get("source_domain", "")) == source_domain and String(record.get("source_id", "")) == source_id:
			return int(record.get("authority_epoch", -1))
	return -1

static func _record_key(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return str(value)
	return "%s|%s" % [String(value.get("source_domain", "")), String(value.get("source_id", ""))]
