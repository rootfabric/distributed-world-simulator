extends RefCounted

const RequestScript = preload(
	"res://scripts/simulation/matter/contracts/matter_mutation_request.gd"
)
const ResultScript = preload(
	"res://scripts/simulation/matter/contracts/matter_mutation_result.gd"
)
const BatchScript = preload(
	"res://scripts/simulation/matter/contracts/matter_material_batch.gd"
)
const CrossRegionPhysicalOutputScript = preload(
	"res://scripts/simulation/matter/transactions/distributed/matter_cross_region_physical_output.gd"
)
const AdapterScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_material_item_graph_adapter.gd"
)

var _configured := false
var _matter_service = null
var _adapter = null


func configure(matter_service, item_graph) -> Dictionary:
	if _configured:
		return _failure("P7_MATERIAL_COORDINATOR_ALREADY_CONFIGURED")
	if matter_service == null \
		or not matter_service.has_method("material_receiver") \
		or matter_service.material_receiver() == null \
		or not matter_service.material_receiver().has_method("get_batch"):
		return _failure("P7_MATTER_MATERIAL_RECEIVER_REQUIRED")
	var adapter = AdapterScript.new()
	var adapter_setup: Dictionary = adapter.configure(item_graph)
	if not bool(adapter_setup.get("success", false)):
		return adapter_setup
	_matter_service = matter_service
	_adapter = adapter
	_configured = true
	return _success(contract_report())


func deliver_committed(request: Dictionary, result: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("P7_MATERIAL_COORDINATOR_NOT_CONFIGURED")
	if not bool(RequestScript.validate(request).get("success", false)):
		return _failure("P7_INVALID_MATTER_REQUEST")
	if not bool(ResultScript.validate(result).get("success", false)):
		return _failure("P7_INVALID_MATTER_RESULT")
	if String(request["operation_id"]) != String(result["operation_id"]):
		return _failure("P7_MATTER_RESULT_OPERATION_MISMATCH")
	if String(result["status"]) != "COMMITTED":
		return _failure("P7_MATTER_RESULT_NOT_COMMITTED")
	var aggregate_ids: Array = result["created_aggregate_ids"]
	if aggregate_ids.size() != 1:
		return _failure("P7_MATTER_BATCH_CARDINALITY_INVALID", {
			"aggregate_count": aggregate_ids.size(),
		})
	var batch_id := String(aggregate_ids[0])
	var batch: Dictionary = _matter_service.material_receiver().get_batch(batch_id)
	if not bool(BatchScript.validate(batch).get("success", false)):
		return _failure("P7_MATTER_BATCH_NOT_AVAILABLE", {"batch_id": batch_id})
	if String(batch["source_operation_id"]) != String(request["operation_id"]):
		return _failure("P7_MATTER_BATCH_OPERATION_MISMATCH", {"batch_id": batch_id})
	if absf(float(batch["total_mass_kg"]) - float(result["removed_mass_kg"])) > 0.001:
		return _failure("P7_MATTER_BATCH_RESULT_MASS_MISMATCH", {
			"batch_mass_kg": float(batch["total_mass_kg"]),
			"removed_mass_kg": float(result["removed_mass_kg"]),
		})
	var actor_check: Dictionary = _logical_player_id(request)
	if not bool(actor_check.get("success", false)):
		return actor_check
	var logical_player_id := String(actor_check["details"]["logical_player_id"])
	var delivered: Dictionary = _adapter.deliver(batch, logical_player_id)
	if not bool(delivered.get("success", false)):
		return delivered
	return _success({
		"matter_operation_id": String(request["operation_id"]),
		"batch_id": batch_id,
		"logical_player_id": logical_player_id,
		"delivery": Dictionary(delivered.get("details", {})).duplicate(true),
	})


func deliver_cross_region_committed(
	request: Dictionary,
	physical_output: Dictionary
) -> Dictionary:
	if not _configured:
		return _failure("P7_MATERIAL_COORDINATOR_NOT_CONFIGURED")
	if not bool(RequestScript.validate(request).get("success", false)):
		return _failure("P7_INVALID_MATTER_REQUEST")
	var checked: Dictionary = CrossRegionPhysicalOutputScript.validate(physical_output)
	if not bool(checked.get("success", false)):
		return _failure("P7_INVALID_MW10_PHYSICAL_OUTPUT", {"cause": checked})
	var plan: Dictionary = physical_output["plan"]
	if String(plan.get("operation_id", "")) != String(request.get("operation_id", "")):
		return _failure("P7_MW10_PHYSICAL_OUTPUT_OPERATION_MISMATCH")
	if String(plan.get("body_id", "")) != String(request.get("body_id", "")):
		return _failure("P7_MW10_PHYSICAL_OUTPUT_BODY_MISMATCH")
	var actor_check: Dictionary = _logical_player_id(request)
	if not bool(actor_check.get("success", false)):
		return actor_check
	var logical_player_id := String(actor_check["details"]["logical_player_id"])
	var deliveries: Array = []
	var total_output_quantity := 0
	var fresh_delivery_count := 0
	var replay_delivery_count := 0
	for raw_output in Array(physical_output.get("participant_outputs", [])):
		if typeof(raw_output) != TYPE_DICTIONARY:
			return _failure("P7_MW10_PARTICIPANT_PHYSICAL_OUTPUT_INVALID")
		var participant_output: Dictionary = raw_output
		var batch: Dictionary = Dictionary(participant_output.get("material_batch", {}))
		var delivered: Dictionary = _adapter.deliver(batch, logical_player_id)
		if not bool(delivered.get("success", false)):
			var failed: Dictionary = delivered.duplicate(true)
			var details: Dictionary = Dictionary(failed.get("details", {})).duplicate(true)
			details["failed_region_id"] = String(participant_output.get("region_id", ""))
			details["completed_deliveries"] = deliveries.duplicate(true)
			failed["details"] = details
			return failed
		var delivery: Dictionary = Dictionary(delivered.get("details", {})).duplicate(true)
		deliveries.append({
			"region_id": String(participant_output.get("region_id", "")),
			"batch_id": String(batch.get("batch_id", "")),
			"batch_checksum": String(batch.get("checksum", "")),
			"delivery": delivery,
		})
		total_output_quantity += int(delivery.get("output_quantity", 0))
		if bool(delivery.get("replay", false)):
			replay_delivery_count += 1
		else:
			fresh_delivery_count += 1
	return _success({
		"matter_operation_id": String(request["operation_id"]),
		"transaction_id": String(plan.get("transaction_id", "")),
		"physical_output_checksum": String(physical_output.get("checksum", "")),
		"logical_player_id": logical_player_id,
		"participant_delivery_count": deliveries.size(),
		"fresh_delivery_count": fresh_delivery_count,
		"replay_delivery_count": replay_delivery_count,
		"total_output_quantity": total_output_quantity,
		"deliveries": deliveries,
	})


func _logical_player_id(request: Dictionary) -> Dictionary:
	var actor_id := String(request.get("actor_id", ""))
	if not actor_id.begins_with("player/") or actor_id.length() <= "player/".length():
		return _failure("P7_MATTER_ACTOR_IDENTITY_INVALID")
	var logical_player_id := actor_id.substr("player/".length())
	if logical_player_id.is_empty() or logical_player_id != logical_player_id.strip_edges().to_lower():
		return _failure("P7_MATTER_ACTOR_IDENTITY_INVALID")
	return _success({"logical_player_id": logical_player_id})


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"matter_owner": "MW4_MATERIAL_RECEIVER",
		"cross_region_matter_owner": "MW10_DURABLE_PHYSICAL_OUTPUT",
		"cross_region_delivery_mode": "CANONICAL_PARTICIPANT_BATCHES_IN_REGION_ORDER",
		"item_owner": "CANONICAL_ITEM_GRAPH",
		"exactly_once_owner": "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER",
		"canonical_state_owned": false,
		"delivery_receipt_store": false,
		"adapter": _adapter.contract_report() if _adapter != null else {},
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
