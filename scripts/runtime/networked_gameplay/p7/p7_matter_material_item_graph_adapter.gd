extends RefCounted

const DeliveryPolicyScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_policy.gd"
)

var _configured := false
var _item_graph = null


func configure(item_graph) -> Dictionary:
	if _configured:
		return _failure("P7_MATERIAL_DELIVERY_ALREADY_CONFIGURED")
	if item_graph == null \
		or not item_graph.has_method("preflight_server_output") \
		or not item_graph.has_method("apply_server_output") \
		or not item_graph.has_method("create_snapshot"):
		return _failure("P7_CANONICAL_ITEM_GRAPH_REQUIRED")
	_item_graph = item_graph
	_configured = true
	return _success(contract_report())


func plan_delivery(batch: Dictionary) -> Dictionary:
	return DeliveryPolicyScript.plan(batch)


func deliver(batch: Dictionary, logical_player_id: String) -> Dictionary:
	if not _configured:
		return _failure("P7_MATERIAL_DELIVERY_NOT_CONFIGURED")
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return _failure("P7_MATERIAL_DELIVERY_PLAYER_REQUIRED")
	var planned: Dictionary = DeliveryPolicyScript.plan(batch)
	if not bool(planned.get("success", false)):
		return planned
	var plan: Dictionary = Dictionary(planned.get("details", {})).duplicate(true)
	var quantity := int(plan.get("output_quantity", 0))
	if quantity == 0:
		plan["logical_player_id"] = player_id
		plan["item_graph_mutated"] = false
		plan["replay"] = false
		return _success(plan)

	var output_operation_id := String(plan["output_operation_id"])
	var definition_id := String(plan["output_definition_id"])
	var source_id := String(plan["source_id"])
	var preflight: Dictionary = _item_graph.preflight_server_output(
		output_operation_id,
		player_id,
		definition_id,
		quantity,
		source_id
	)
	if not bool(preflight.get("success", false)):
		return _failure("P7_ITEM_GRAPH_OUTPUT_REJECTED", {
			"cause": String(preflight.get("error_code", "SERVER_OUTPUT_REJECTED")),
			"batch_id": String(plan["batch_id"]),
			"output_operation_id": output_operation_id,
		})
	var output: Dictionary = _item_graph.apply_server_output(
		output_operation_id,
		player_id,
		definition_id,
		quantity,
		source_id
	)
	if not bool(output.get("success", false)):
		return _failure("P7_ITEM_GRAPH_OUTPUT_REJECTED", {
			"cause": String(output.get("error_code", "SERVER_OUTPUT_REJECTED")),
			"batch_id": String(plan["batch_id"]),
			"output_operation_id": output_operation_id,
		})
	var output_details: Dictionary = Dictionary(output.get("details", {}))
	plan["logical_player_id"] = player_id
	plan["output_item_id"] = String(
		output_details.get("output_item_id", output_details.get("item_id", ""))
	)
	plan["target_slot_index"] = int(output_details.get("target_slot_index", -1))
	plan["item_graph_revision"] = int(output.get("revision", -1))
	plan["item_graph_tick"] = int(output.get("tick", -1))
	plan["item_graph_mutated"] = not bool(output.get("replay", false))
	plan["replay"] = bool(output.get("replay", false))
	return _success(plan)


func contract_report() -> Dictionary:
	var report: Dictionary = DeliveryPolicyScript.contract_report()
	report["configured"] = _configured
	report["canonical_item_graph_bound"] = _item_graph != null
	report["canonical_state_owned"] = false
	return report


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
