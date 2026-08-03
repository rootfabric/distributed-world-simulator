extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const BatchScript = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const RegionScript = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")

const SCHEMA: String = "planet_simulator.matter_handoff_package.v1"
const RECORD_FIELDS: Array[String] = ["operation_id", "request_transport", "result_transport"]
const FIELDS: Array[String] = [
	"schema", "transfer_id", "body_id", "body_definition_hash", "grid_profile_hash",
	"region_transport", "source_owner_id", "source_authority_epoch", "target_owner_id",
	"target_authority_epoch", "directory_revision", "source_stream_sequence",
	"snapshot_transports", "journal_records", "batch_transports",
	"regional_state_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var snapshots: Array = Array(data.get("snapshot_transports", [])).duplicate()
	var records: Array = Array(data.get("journal_records", [])).duplicate(true)
	var batches: Array = Array(data.get("batch_transports", [])).duplicate()
	var value: Dictionary = {
		"schema": SCHEMA,
		"transfer_id": String(data.get("transfer_id", "")).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_definition_hash": String(data.get("body_definition_hash", "")).strip_edges().to_lower(),
		"grid_profile_hash": String(data.get("grid_profile_hash", "")).strip_edges().to_lower(),
		"region_transport": String(data.get("region_transport", "")),
		"source_owner_id": String(data.get("source_owner_id", "")).strip_edges().to_lower(),
		"source_authority_epoch": int(data.get("source_authority_epoch", 0)),
		"target_owner_id": String(data.get("target_owner_id", "")).strip_edges().to_lower(),
		"target_authority_epoch": int(data.get("target_authority_epoch", 0)),
		"directory_revision": int(data.get("directory_revision", 0)),
		"source_stream_sequence": int(data.get("source_stream_sequence", 0)),
		"snapshot_transports": snapshots,
		"journal_records": records,
		"batch_transports": batches,
		"regional_state_hash": String(data.get("regional_state_hash", "")).strip_edges().to_lower(),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_HANDOFF_PACKAGE_SCHEMA")
	for field in ["transfer_id", "body_id", "source_owner_id", "target_owner_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_PACKAGE_ID", {"field": field})
	for field in ["body_definition_hash", "grid_profile_hash"]:
		if not MatterUtilsScript.is_lower_hex_64(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_WORLD_HASH", {"field": field})
	for field in [
		"source_authority_epoch", "target_authority_epoch",
		"directory_revision", "source_stream_sequence",
	]:
		if not MatterUtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_PACKAGE_INTEGER", {"field": field})
	if int(value["source_authority_epoch"]) < 1 \
			or int(value["target_authority_epoch"]) <= int(value["source_authority_epoch"]) \
			or int(value["directory_revision"]) < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_PACKAGE_EPOCH")
	if typeof(value.get("region_transport")) != TYPE_STRING or String(value["region_transport"]).is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_REGION_TRANSPORT")
	var region: Dictionary = decode_region(value)
	if region.is_empty() or String(region["body_id"]) != String(value["body_id"]):
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_REGION")
	for field in ["snapshot_transports", "journal_records", "batch_transports"]:
		if typeof(value.get(field)) != TYPE_ARRAY:
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_COLLECTION", {"field": field})
	if int(value["source_stream_sequence"]) < value["journal_records"].size():
		return MatterUtilsScript.failure("MATTER_HANDOFF_SOURCE_FRONTIER_BEHIND_JOURNAL")
	var snapshot_entries: Array = []
	var previous_address_id: String = ""
	for index in range(value["snapshot_transports"].size()):
		var raw_transport = value["snapshot_transports"][index]
		if typeof(raw_transport) != TYPE_STRING or String(raw_transport).is_empty():
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_SNAPSHOT_TRANSPORT", {"index": index})
		var snapshot: Dictionary = decode_snapshot(String(raw_transport))
		if snapshot.is_empty() or int(snapshot["state_revision"]) < 1:
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_SNAPSHOT", {"index": index})
		var address_id: String = String(snapshot["address"]["address_id"])
		if index > 0 and address_id <= previous_address_id:
			return MatterUtilsScript.failure("MATTER_HANDOFF_SNAPSHOTS_NOT_SORTED_UNIQUE")
		snapshot_entries.append({
			"address_id": address_id,
			"state_revision": int(snapshot["state_revision"]),
			"snapshot_checksum": String(snapshot["checksum"]),
		})
		previous_address_id = address_id
	var journal_entries: Array = []
	var previous_operation_id: String = ""
	var created_batch_ids: Dictionary = {}
	for index in range(value["journal_records"].size()):
		var record_value = value["journal_records"][index]
		if typeof(record_value) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_JOURNAL_RECORD", {"index": index})
		var record: Dictionary = record_value
		var record_exact: Dictionary = MatterUtilsScript.validate_exact_fields(record, RECORD_FIELDS)
		if not bool(record_exact.get("success", false)):
			return record_exact
		var operation_id: String = String(record.get("operation_id", ""))
		if not MatterUtilsScript.is_canonical_id(operation_id, 2) \
				or typeof(record.get("request_transport")) != TYPE_STRING \
				or typeof(record.get("result_transport")) != TYPE_STRING:
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_JOURNAL_RECORD", {"index": index})
		if index > 0 and operation_id <= previous_operation_id:
			return MatterUtilsScript.failure("MATTER_HANDOFF_JOURNAL_NOT_SORTED_UNIQUE")
		var request: Dictionary = decode_request(String(record["request_transport"]))
		var result: Dictionary = decode_result(String(record["result_transport"]))
		if request.is_empty() or result.is_empty() \
				or String(request["operation_id"]) != operation_id \
				or String(result["operation_id"]) != operation_id:
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_JOURNAL_OPERATION", {"index": index})
		for batch_id in result["created_aggregate_ids"]:
			created_batch_ids[String(batch_id)] = true
		journal_entries.append({
			"operation_id": operation_id,
			"request_checksum": String(request["checksum"]),
			"result_checksum": String(result["checksum"]),
		})
		previous_operation_id = operation_id
	var batch_entries: Array = []
	var seen_batch_ids: Dictionary = {}
	var previous_batch_id: String = ""
	for index in range(value["batch_transports"].size()):
		var transport_value = value["batch_transports"][index]
		if typeof(transport_value) != TYPE_STRING or String(transport_value).is_empty():
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_BATCH_TRANSPORT", {"index": index})
		var batch: Dictionary = decode_batch(String(transport_value))
		if batch.is_empty():
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_BATCH", {"index": index})
		var batch_id: String = String(batch["batch_id"])
		if index > 0 and batch_id <= previous_batch_id:
			return MatterUtilsScript.failure("MATTER_HANDOFF_BATCHES_NOT_SORTED_UNIQUE")
		if not created_batch_ids.has(batch_id):
			return MatterUtilsScript.failure("MATTER_HANDOFF_ORPHAN_BATCH", {"batch_id": batch_id})
		seen_batch_ids[batch_id] = true
		batch_entries.append({"batch_id": batch_id, "batch_checksum": String(batch["checksum"])})
		previous_batch_id = batch_id
	for batch_id in created_batch_ids.keys():
		if not seen_batch_ids.has(String(batch_id)):
			return MatterUtilsScript.failure("MATTER_HANDOFF_BATCH_MISSING", {"batch_id": String(batch_id)})
	var expected_hash: String = compute_regional_state_hash(
		region, snapshot_entries, journal_entries, batch_entries
	)
	if not MatterUtilsScript.is_lower_hex_64(value.get("regional_state_hash")) \
			or String(value["regional_state_hash"]) != expected_hash:
		return MatterUtilsScript.failure("MATTER_HANDOFF_REGIONAL_STATE_HASH_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_handoff_package")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func validate_for_grid(value: Dictionary, grid_profile: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	var region: Dictionary = decode_region(value)
	var region_validation: Dictionary = RegionScript.validate_for_grid(grid_profile, region)
	if not bool(region_validation.get("success", false)):
		return region_validation
	if String(value["grid_profile_hash"]) != GridProfileScript.content_hash(grid_profile):
		return MatterUtilsScript.failure("MATTER_HANDOFF_GRID_PROFILE_HASH_MISMATCH")
	for transport_value in value["snapshot_transports"]:
		var snapshot: Dictionary = decode_snapshot(String(transport_value))
		if not RegionScript.contains_snapshot(grid_profile, region, snapshot):
			return MatterUtilsScript.failure("MATTER_HANDOFF_SNAPSHOT_OUTSIDE_REGION")
	for record_value in value["journal_records"]:
		var record: Dictionary = record_value
		var request: Dictionary = decode_request(String(record["request_transport"]))
		for address_value in request["target_bricks"]:
			var address: Dictionary = address_value
			if not RegionScript.contains_brick_address(grid_profile, region, address):
				return MatterUtilsScript.failure("MATTER_HANDOFF_JOURNAL_TARGET_OUTSIDE_REGION")
	return MatterUtilsScript.success()


static func compute_regional_state_hash(
	region: Dictionary,
	snapshot_entries: Array,
	journal_entries: Array,
	batch_entries: Array
) -> String:
	return MatterUtilsScript.payload_hash({
		"region_checksum": region.get("checksum", ""),
		"snapshots": snapshot_entries,
		"journal": journal_entries,
		"batches": batch_entries,
	})


static func decode_region(value: Dictionary) -> Dictionary:
	var raw: Dictionary = PersistenceCodecScript.decode_persistence_json(String(value.get("region_transport", "")))
	return raw if bool(RegionScript.validate(raw).get("success", false)) else {}


static func decode_snapshot(transport: String) -> Dictionary:
	var raw: Dictionary = PersistenceCodecScript.decode_persistence_json(transport)
	var value: Dictionary = PersistenceCodecScript.rehydrate_snapshot(raw)
	return value if bool(SnapshotScript.validate(value).get("success", false)) else {}


static func decode_request(transport: String) -> Dictionary:
	var raw: Dictionary = PersistenceCodecScript.decode_persistence_json(transport)
	var value: Dictionary = PersistenceCodecScript.rehydrate_request(raw)
	return value if bool(RequestScript.validate(value).get("success", false)) else {}


static func decode_result(transport: String) -> Dictionary:
	var raw: Dictionary = PersistenceCodecScript.decode_persistence_json(transport)
	var value: Dictionary = PersistenceCodecScript.rehydrate_result(raw)
	return value if bool(ResultScript.validate(value).get("success", false)) else {}


static func decode_batch(transport: String) -> Dictionary:
	var raw: Dictionary = PersistenceCodecScript.decode_persistence_json(transport)
	var value: Dictionary = PersistenceCodecScript.rehydrate_batch(raw)
	return value if bool(BatchScript.validate(value).get("success", false)) else {}
