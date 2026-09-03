extends RefCounted

## P7.7 graphical digging product composition.
##
## This adapter owns no canonical state. It consumes:
## - the exact result returned by the existing continuous Matter query plus the\n##   canonical Matter request whose swept shape contains that query hit;
## - the P7.6 route executor, which preserves P7.1->MW4 for one region and MW10
##   for true multi-region operations;
## - the existing P7.3 material delivery coordinator;
## - a presentation invalidation callback which must only invalidate derived
##   representation after a canonical Matter commit.
##
## P7.7-A intentionally supports the complete single-region visible/material
## path first. A true MW10 route must expose a canonical MatterMaterialBatch-
## compatible committed output before P7.7 may deliver inventory material.
## Current MW10 terminal operation results do not carry that physical batch
## metadata, so the adapter fails closed instead of inventing it.

const MatterRequest = preload(
	"res://scripts/simulation/matter/contracts/matter_mutation_request.gd"
)
const MatterResult = preload(
	"res://scripts/simulation/matter/contracts/matter_mutation_result.gd"
)

const AIM_SOURCE_CANONICAL_MATTER_QUERY := "CANONICAL_MATTER_QUERY"
const ROUTE_SINGLE_REGION := "MW4_SINGLE_REGION"
const ROUTE_MULTI_REGION := "MW10_CROSS_REGION"

var _configured := false
var _router = null
var _material_delivery = null
var _representation_invalidator := Callable()


func configure(router, material_delivery, representation_invalidator: Callable) -> Dictionary:
	if _configured:
		return _failure("P7_7_GRAPHICAL_DIGGING_ALREADY_CONFIGURED")
	if router == null 			or not router.has_method("execute_mutation") 			or not router.has_method("contract_report"):
		return _failure("P7_7_P7_6_ROUTER_REQUIRED")
	if material_delivery == null 			or not material_delivery.has_method("deliver_committed") 			or not material_delivery.has_method("contract_report"):
		return _failure("P7_7_MATERIAL_DELIVERY_REQUIRED")
	if not representation_invalidator.is_valid():
		return _failure("P7_7_REPRESENTATION_INVALIDATOR_REQUIRED")
	_router = router
	_material_delivery = material_delivery
	_representation_invalidator = representation_invalidator
	_configured = true
	return _success(contract_report())


func execute_aimed_dig(aim_binding: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("P7_7_GRAPHICAL_DIGGING_NOT_CONFIGURED")
	var binding_check := _validate_aim_binding(aim_binding)
	if not bool(binding_check.get("success", false)):
		return binding_check

	var request: Dictionary = aim_binding["request"]
	var mw10_plan: Dictionary = Dictionary(aim_binding.get("mw10_plan", {})).duplicate(true)
	var server_tick := int(aim_binding.get("server_tick", 0))
	var transition_prefix := String(aim_binding.get("transition_prefix", ""))

	var routed_value = _router.execute_mutation(
		request.duplicate(true),
		mw10_plan,
		server_tick,
		transition_prefix
	)
	if typeof(routed_value) != TYPE_DICTIONARY:
		return _failure("P7_7_ROUTE_INVALID_RESULT")
	var routed: Dictionary = routed_value
	if not bool(routed.get("success", false)):
		return routed.duplicate(true)
	var route_details_value = routed.get("details", null)
	if typeof(route_details_value) != TYPE_DICTIONARY:
		return _failure("P7_7_ROUTE_DETAILS_REQUIRED")
	var route_details: Dictionary = route_details_value
	var route := String(route_details.get("route", ""))
	if route not in [ROUTE_SINGLE_REGION, ROUTE_MULTI_REGION]:
		return _failure("P7_7_MUTATION_ROUTE_UNSUPPORTED", {"route": route})

	var result_value = _find_matter_result(route_details.get("execution_result", null))
	if typeof(result_value) != TYPE_DICTIONARY:
		if route == ROUTE_MULTI_REGION:
			return _failure("P7_7_MULTI_REGION_MATERIAL_RESULT_REQUIRED", {
				"route": route,
				"mw10_invoked": bool(route_details.get("mw10_invoked", false)),
				"reason": "MW10 terminal output has no canonical MatterMaterialBatch-compatible physical output yet",
			})
		return _failure("P7_7_CANONICAL_MATTER_RESULT_REQUIRED")
	var result: Dictionary = result_value
	var result_check: Dictionary = MatterResult.validate(result)
	if not bool(result_check.get("success", false)):
		return _failure("P7_7_CANONICAL_MATTER_RESULT_INVALID", {"cause": result_check})
	if String(result.get("operation_id", "")) != String(request.get("operation_id", "")):
		return _failure("P7_7_MATTER_RESULT_OPERATION_MISMATCH")
	if String(result.get("status", "")) != "COMMITTED":
		return _failure("P7_7_MATTER_RESULT_NOT_COMMITTED")

	var delivered_value = _material_delivery.deliver_committed(
		request.duplicate(true),
		result.duplicate(true)
	)
	if typeof(delivered_value) != TYPE_DICTIONARY:
		return _failure("P7_7_MATERIAL_DELIVERY_INVALID_RESULT")
	var delivered: Dictionary = delivered_value
	if not bool(delivered.get("success", false)):
		return delivered.duplicate(true)

	var changed_addresses: Array = []
	for changed_value in Array(result.get("changed_bricks", [])):
		if typeof(changed_value) != TYPE_DICTIONARY:
			return _failure("P7_7_CHANGED_BRICK_INVALID")
		var changed: Dictionary = changed_value
		var address_value = changed.get("address", null)
		if typeof(address_value) != TYPE_DICTIONARY:
			return _failure("P7_7_CHANGED_BRICK_ADDRESS_REQUIRED")
		changed_addresses.append(Dictionary(address_value).duplicate(true))

	var invalidated_value = _representation_invalidator.call(changed_addresses.duplicate(true))
	if typeof(invalidated_value) != TYPE_DICTIONARY:
		return _failure("P7_7_REPRESENTATION_INVALIDATION_INVALID_RESULT")
	var invalidated: Dictionary = invalidated_value
	if not bool(invalidated.get("success", false)):
		return invalidated.duplicate(true)

	var delivery_details: Dictionary = Dictionary(delivered.get("details", {})).duplicate(true)
	return _success({
		"operation_id": String(request["operation_id"]),
		"route": route,
		"mw10_invoked": bool(route_details.get("mw10_invoked", false)),
		"changed_brick_count": changed_addresses.size(),
		"changed_brick_addresses": changed_addresses,
		"removed_mass_kg": float(result.get("removed_mass_kg", 0.0)),
		"material_delivery": delivery_details,
		"representation_invalidation": Dictionary(invalidated.get("details", {})).duplicate(true),
		"visible_hole_source": "CANONICAL_MATTER_RESULT",
		"inventory_source": "CANONICAL_ITEM_GRAPH",
		"aim_source": AIM_SOURCE_CANONICAL_MATTER_QUERY,
	})


func contract_report() -> Dictionary:
	var router_contract: Dictionary = _router.contract_report() if _router != null else {}
	var delivery_contract: Dictionary = _material_delivery.contract_report() 		if _material_delivery != null else {}
	return {
		"schema": "planet_simulator.p7_7_graphical_digging_slice.v1",
		"configured": _configured,
		"canonical_state_owned": false,
		"terrain_truth_owned": false,
		"matter_truth_owned": false,
		"item_graph_owned": false,
		"authority_owned": false,
		"transaction_state_owned": false,
		"persistence_owned": false,
		"replay_ledger_owned": false,
		"network_protocol_owned": false,
		"aim_truth_owned": false,
		"aim_binding_owner": "EXISTING_CONTINUOUS_MATTER_QUERY_RESULT",
		"single_region_owner": "P7_1_TO_MW4",
		"multi_region_owner": "P7_6_TO_MW10",
		"material_owner": "P7_3_TO_CANONICAL_ITEM_GRAPH",
		"visible_hole_owner": "CANONICAL_MATTER_PLUS_RL2_RL3",
		"multi_region_material_projection": "FAIL_CLOSED_UNTIL_CANONICAL_PHYSICAL_OUTPUT_AVAILABLE",
		"router_contract": router_contract.duplicate(true),
		"material_delivery_contract": delivery_contract.duplicate(true),
	}


func _validate_aim_binding(value: Dictionary) -> Dictionary:
	var query_value = value.get("query_result", null)
	if typeof(query_value) != TYPE_DICTIONARY:
		return _failure("P7_7_CANONICAL_MATTER_QUERY_RESULT_REQUIRED")
	var query: Dictionary = query_value
	if not bool(query.get("success", false)):
		return _failure("P7_7_CANONICAL_MATTER_QUERY_FAILED")
	var query_details_value = query.get("details", null)
	if typeof(query_details_value) != TYPE_DICTIONARY:
		return _failure("P7_7_CANONICAL_MATTER_QUERY_DETAILS_REQUIRED")
	var query_details: Dictionary = query_details_value
	if not bool(query_details.get("hit", false)):
		return _failure("P7_7_CANONICAL_SURFACE_HIT_REQUIRED")
	var hit_value = query_details.get("position_m", null)
	if typeof(hit_value) != TYPE_VECTOR3:
		return _failure("P7_7_CANONICAL_HIT_POSITION_REQUIRED")
	var hit_position_m: Vector3 = hit_value
	if not _finite_vector(hit_position_m):
		return _failure("P7_7_CANONICAL_HIT_POSITION_INVALID")
	var sample_value = query_details.get("sample", null)
	if typeof(sample_value) != TYPE_DICTIONARY or Dictionary(sample_value).is_empty():
		return _failure("P7_7_CANONICAL_HIT_SAMPLE_REQUIRED")
	var sdf_value = Dictionary(sample_value).get("signed_distance_m", null)
	var sdf_type := typeof(sdf_value)
	if sdf_type != TYPE_INT and sdf_type != TYPE_FLOAT:
		return _failure("P7_7_CANONICAL_HIT_SAMPLE_INVALID")
	if not is_finite(float(sdf_value)):
		return _failure("P7_7_CANONICAL_HIT_SAMPLE_INVALID")

	var request_value = value.get("request", null)
	if typeof(request_value) != TYPE_DICTIONARY:
		return _failure("P7_7_MATTER_REQUEST_REQUIRED")
	var request: Dictionary = request_value
	var request_check: Dictionary = MatterRequest.validate(request)
	if not bool(request_check.get("success", false)):
		return _failure("P7_7_MATTER_REQUEST_INVALID", {"cause": request_check})
	if String(request.get("operation_type", "")) != "EXCAVATE":
		return _failure("P7_7_EXCAVATION_REQUEST_REQUIRED")
	var shape: Dictionary = request["shape"]
	if String(shape.get("kind", "")) != "CAPSULE":
		return _failure("P7_7_CAPSULE_EXCAVATION_REQUIRED")
	if not _query_hit_inside_capsule(hit_position_m, shape):
		return _failure("P7_7_QUERY_HIT_OUTSIDE_REQUEST_SHAPE")

	var plan_value = value.get("mw10_plan", {})
	if typeof(plan_value) != TYPE_DICTIONARY:
		return _failure("P7_7_MW10_PLAN_INVALID")
	var tick_value = value.get("server_tick", 0)
	if typeof(tick_value) != TYPE_INT or int(tick_value) < 0:
		return _failure("P7_7_SERVER_TICK_INVALID")
	if typeof(value.get("transition_prefix", "")) != TYPE_STRING:
		return _failure("P7_7_TRANSITION_PREFIX_INVALID")
	return _success()


func _query_hit_inside_capsule(hit_position_m: Vector3, shape: Dictionary) -> bool:
	var start_array: Array = Array(shape.get("start_position_m", []))
	var end_array: Array = Array(shape.get("end_position_m", []))
	if start_array.size() != 3 or end_array.size() != 3:
		return false
	var start_m := _vector3(start_array)
	var end_m := _vector3(end_array)
	if not _finite_vector(start_m) or not _finite_vector(end_m):
		return false
	var radius_m := float(shape.get("radius_m", 0.0))
	if radius_m <= 0.0:
		return false
	var segment := end_m - start_m
	var closest := start_m
	if segment.length_squared() > 0.000000000001:
		var t := clampf(
			(hit_position_m - start_m).dot(segment) / segment.length_squared(),
			0.0,
			1.0
		)
		closest = start_m + segment * t
	return hit_position_m.distance_to(closest) <= radius_m + 0.000001


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _vector3(value: Array) -> Vector3:
	if value.size() != 3:
		return Vector3(INF, INF, INF)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _find_matter_result(value):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var candidate: Dictionary = value
	if String(candidate.get("schema", "")) == MatterResult.SCHEMA:
		return candidate.duplicate(true)
	for key in ["result", "matter_result"]:
		var nested = candidate.get(key, null)
		if typeof(nested) == TYPE_DICTIONARY 				and String(Dictionary(nested).get("schema", "")) == MatterResult.SCHEMA:
			return Dictionary(nested).duplicate(true)
	var details_value = candidate.get("details", null)
	if typeof(details_value) == TYPE_DICTIONARY:
		var details: Dictionary = details_value
		for key in ["result", "matter_result"]:
			var nested = details.get(key, null)
			if typeof(nested) == TYPE_DICTIONARY 					and String(Dictionary(nested).get("schema", "")) == MatterResult.SCHEMA:
				return Dictionary(nested).duplicate(true)
	return null


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
