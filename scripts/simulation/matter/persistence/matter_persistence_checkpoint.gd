extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const StoreScript = preload("res://scripts/simulation/matter/storage/matter_sparse_brick_store.gd")
const ReceiverScript = preload("res://scripts/simulation/matter/mutation/matter_material_receiver.gd")
const JournalScript = preload("res://scripts/simulation/matter/mutation/matter_mutation_journal.gd")

const SCHEMA: String = "planet_simulator.matter_persistence_checkpoint.v1"
const FIELDS: Array[String] = [
	"schema",
	"checkpoint_id",
	"generation",
	"body_id",
	"body_definition_hash",
	"generator_version",
	"generator_seed",
	"grid_profile_hash",
	"cell_level",
	"container_id",
	"server_tick",
	"previous_checkpoint_checksum",
	"store_state",
	"receiver_state",
	"journal_state",
	"checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"checkpoint_id": String(data.get("checkpoint_id", "")).strip_edges().to_lower(),
		"generation": int(data.get("generation", 0)),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_definition_hash": String(data.get("body_definition_hash", "")).strip_edges().to_lower(),
		"generator_version": String(data.get("generator_version", "")).strip_edges(),
		"generator_seed": int(data.get("generator_seed", 0)),
		"grid_profile_hash": String(data.get("grid_profile_hash", "")).strip_edges().to_lower(),
		"cell_level": int(data.get("cell_level", 0)),
		"container_id": String(data.get("container_id", "")).strip_edges().to_lower(),
		"server_tick": int(data.get("server_tick", 0)),
		"previous_checkpoint_checksum": String(data.get("previous_checkpoint_checksum", "")).strip_edges().to_lower(),
		"store_state": Dictionary(data.get("store_state", {})).duplicate(true),
		"receiver_state": Dictionary(data.get("receiver_state", {})).duplicate(true),
		"journal_state": Dictionary(data.get("journal_state", {})).duplicate(true),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_PERSISTENCE_CHECKPOINT_SCHEMA")
	if not MatterUtilsScript.is_canonical_id(value.get("checkpoint_id"), 2) \
		or not MatterUtilsScript.is_canonical_id(value.get("body_id"), 2) \
		or not MatterUtilsScript.is_lower_hex_64(value.get("body_definition_hash")) \
		or not MatterUtilsScript.is_semantic_version(value.get("generator_version")) \
		or not MatterUtilsScript.is_json_integer(value.get("generator_seed")) \
		or not MatterUtilsScript.is_lower_hex_64(value.get("grid_profile_hash")) \
		or not MatterUtilsScript.is_canonical_id(value.get("container_id"), 2):
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_CHECKPOINT_IDENTITY")
	for field in ["generation", "cell_level", "server_tick"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_INTEGER", {"field": field})
	if int(value["generation"]) < 1 or int(value["cell_level"]) < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_GENERATION_OR_LEVEL")
	var previous_checksum: String = String(value.get("previous_checkpoint_checksum", ""))
	if int(value["generation"]) == 1:
		if not previous_checksum.is_empty():
			return MatterUtilsScript.failure("FIRST_MATTER_CHECKPOINT_HAS_PREVIOUS")
	elif not MatterUtilsScript.is_lower_hex_64(previous_checksum):
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_PREVIOUS_CHECKSUM_REQUIRED")
	if typeof(value.get("store_state")) != TYPE_DICTIONARY \
		or typeof(value.get("receiver_state")) != TYPE_DICTIONARY \
		or typeof(value.get("journal_state")) != TYPE_DICTIONARY:
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_COMPONENT_STATE")
	var store_validation: Dictionary = StoreScript.validate_persistence_state(value["store_state"])
	if not bool(store_validation.get("success", false)):
		return store_validation
	var receiver_validation: Dictionary = ReceiverScript.validate_persistence_state(value["receiver_state"])
	if not bool(receiver_validation.get("success", false)):
		return receiver_validation
	var journal_validation: Dictionary = JournalScript.validate_persistence_state(value["journal_state"])
	if not bool(journal_validation.get("success", false)):
		return journal_validation
	if String(value["store_state"]["body_definition_hash"]) != String(value["body_definition_hash"]) \
		or String(value["store_state"]["generator_version"]) != String(value["generator_version"]) \
		or int(value["store_state"]["generator_seed"]) != int(value["generator_seed"]) \
		or String(value["store_state"]["grid_profile_hash"]) != String(value["grid_profile_hash"]):
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_STORE_IDENTITY_MISMATCH")
	if String(value["receiver_state"]["container_id"]) != String(value["container_id"]):
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_RECEIVER_IDENTITY_MISMATCH")
	var cross_validation: Dictionary = _validate_cross_links(value)
	if not bool(cross_validation.get("success", false)):
		return cross_validation
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_persistence_checkpoint")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func validate_progression(next_value: Dictionary, current_value: Dictionary) -> Dictionary:
	var next_validation: Dictionary = validate(next_value)
	if not bool(next_validation.get("success", false)):
		return next_validation
	var current_validation: Dictionary = validate(current_value)
	if not bool(current_validation.get("success", false)):
		return current_validation
	if int(next_value["generation"]) != int(current_value["generation"]) + 1:
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_GENERATION_NOT_INCREMENTED")
	if String(next_value["previous_checkpoint_checksum"]) != String(current_value["checksum"]):
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_CHAIN_MISMATCH")
	for field in [
		"body_id", "body_definition_hash", "generator_version", "generator_seed",
		"grid_profile_hash", "cell_level", "container_id",
	]:
		if next_value[field] != current_value[field]:
			return MatterUtilsScript.failure("MATTER_CHECKPOINT_IDENTITY_CHANGED", {"field": field})
	if int(next_value["server_tick"]) < int(current_value["server_tick"]):
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_TICK_ROLLBACK")
	return MatterUtilsScript.success()


static func _validate_cross_links(value: Dictionary) -> Dictionary:
	var snapshots_by_address: Dictionary = {}
	for snapshot in value["store_state"]["snapshots"]:
		snapshots_by_address[String(snapshot["address"]["address_id"])] = snapshot
	var batches_by_id: Dictionary = {}
	for batch in value["receiver_state"]["batches"]:
		batches_by_id[String(batch["batch_id"])] = batch
	var committed_operations: Dictionary = {}
	for record in value["journal_state"]["records"]:
		var operation_id: String = String(record["operation_id"])
		var request: Dictionary = record["request"]
		var result: Dictionary = record["result"]
		if String(request["body_id"]) != String(value["body_id"]):
			return MatterUtilsScript.failure("MATTER_CHECKPOINT_REQUEST_BODY_MISMATCH")
		if String(result["status"]) != "COMMITTED":
			continue
		committed_operations[operation_id] = result
		for changed in result["changed_bricks"]:
			var address_id: String = String(changed["address"]["address_id"])
			if not snapshots_by_address.has(address_id):
				return MatterUtilsScript.failure("MATTER_CHECKPOINT_CHANGED_BRICK_MISSING", {"address_id": address_id})
			if int(snapshots_by_address[address_id]["state_revision"]) < int(changed["new_revision"]):
				return MatterUtilsScript.failure("MATTER_CHECKPOINT_CHANGED_BRICK_REVISION_ROLLBACK")
		for batch_id in result["created_aggregate_ids"]:
			if not batches_by_id.has(String(batch_id)):
				return MatterUtilsScript.failure("MATTER_CHECKPOINT_CREATED_BATCH_MISSING", {"batch_id": batch_id})
			if String(batches_by_id[String(batch_id)]["source_operation_id"]) != operation_id:
				return MatterUtilsScript.failure("MATTER_CHECKPOINT_BATCH_OPERATION_MISMATCH")
	for batch_id in batches_by_id.keys():
		var batch: Dictionary = batches_by_id[batch_id]
		var source_operation_id: String = String(batch["source_operation_id"])
		if String(batch["source_body_id"]) != String(value["body_id"]):
			return MatterUtilsScript.failure("MATTER_CHECKPOINT_BATCH_BODY_MISMATCH")
		if not committed_operations.has(source_operation_id):
			return MatterUtilsScript.failure("MATTER_CHECKPOINT_ORPHAN_BATCH", {"batch_id": batch_id})
		if not Array(committed_operations[source_operation_id]["created_aggregate_ids"]).has(String(batch_id)):
			return MatterUtilsScript.failure("MATTER_CHECKPOINT_BATCH_NOT_DECLARED_BY_RESULT")
	return MatterUtilsScript.success()
