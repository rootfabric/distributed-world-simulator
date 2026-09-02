extends RefCounted

## P7.6 is a stateless routing composition over existing owners.
##
## Actor seam crossing is delegated to the existing SM1/MW8/MW9 product path.
## A one-region Matter mutation is delegated unchanged to the existing
## P7.1 -> MW4 execution path. Only a single canonical mutation whose target
## bricks resolve to two or more authority regions may enter MW10.
##
## This adapter owns no Matter state, authority lease, handoff state,
## transaction journal, replay ledger, persistence, Item Graph, or network
## protocol.

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MatterRequest = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const MatterAuthorityLease = preload("res://scripts/simulation/matter/handoff/matter_authority_lease.gd")
const MW10Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")

const ROUTE_ACTOR_HANDOFF := "SM1_MW8_MW9_HANDOFF"
const ROUTE_SINGLE_REGION := "MW4_SINGLE_REGION"
const ROUTE_MULTI_REGION := "MW10_CROSS_REGION"

var _configured := false
var _product_gate = null
var _region_resolver = null
var _single_region_executor := Callable()
var _actor_handoff_executor := Callable()
var _mw10_coordinator = null
var _reservation_interlock = null


func configure(
	product_gate,
	region_resolver,
	single_region_executor: Callable,
	actor_handoff_executor: Callable,
	mw10_coordinator,
	reservation_interlock
) -> Dictionary:
	if _configured:
		return _failure("P7_6_COMPOSITION_ALREADY_CONFIGURED")
	if product_gate == null or not product_gate.has_method("authorize_product_intent"):
		return _failure("P7_6_PRODUCT_INTENT_GATE_REQUIRED")
	if region_resolver == null or not region_resolver.has_method("resolve_brick_address"):
		return _failure("P7_6_MW8_REGION_RESOLVER_REQUIRED")
	if not single_region_executor.is_valid():
		return _failure("P7_6_SINGLE_REGION_EXECUTOR_REQUIRED")
	if not actor_handoff_executor.is_valid():
		return _failure("P7_6_ACTOR_HANDOFF_EXECUTOR_REQUIRED")
	if mw10_coordinator == null or not mw10_coordinator.has_method("execute_transaction"):
		return _failure("P7_6_MW10_COORDINATOR_REQUIRED")
	if reservation_interlock == null \
			or not reservation_interlock.has_method("validate_handoff") \
			or not reservation_interlock.has_method("reserved_transaction"):
		return _failure("P7_6_MW10_RESERVATION_INTERLOCK_REQUIRED")
	_product_gate = product_gate
	_region_resolver = region_resolver
	_single_region_executor = single_region_executor
	_actor_handoff_executor = actor_handoff_executor
	_mw10_coordinator = mw10_coordinator
	_reservation_interlock = reservation_interlock
	_configured = true
	return _success({
		"canonical_state_owned": false,
		"durable_state_owned": false,
		"transaction_state_owned": false,
	})


func execute_actor_handoff(region_id: String, handoff_context: Dictionary = {}) -> Dictionary:
	if not _configured:
		return _failure("P7_6_COMPOSITION_NOT_CONFIGURED")
	var normalized_region := region_id.strip_edges().to_lower()
	if not MatterUtils.is_canonical_id(normalized_region, 2):
		return _failure("P7_6_HANDOFF_REGION_ID_INVALID")
	var interlock_value = _reservation_interlock.validate_handoff(normalized_region)
	var interlock_check := _require_success(
		interlock_value,
		"P7_6_MW10_HANDOFF_INTERLOCK_REJECTED"
	)
	if not bool(interlock_check.get("success", false)):
		return interlock_check
	var execution_value = _actor_handoff_executor.call(
		normalized_region,
		handoff_context.duplicate(true)
	)
	var execution_check := _executor_result(
		execution_value,
		"P7_6_ACTOR_HANDOFF_EXECUTOR_INVALID_RESULT"
	)
	if not bool(execution_check.get("success", false)):
		return execution_check
	return _success({
		"route": ROUTE_ACTOR_HANDOFF,
		"region_id": normalized_region,
		"mw10_invoked": false,
		"execution_result": execution_check["details"]["value"],
	})


func execute_mutation(
	request: Dictionary,
	mw10_plan: Dictionary = {},
	server_tick: int = 0,
	transition_prefix: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("P7_6_COMPOSITION_NOT_CONFIGURED")
	var request_check: Dictionary = MatterRequest.validate(request)
	if not bool(request_check.get("success", false)):
		return _failure("P7_6_MATTER_REQUEST_INVALID", {"cause": request_check})
	if server_tick < 0:
		return _failure("P7_6_SERVER_TICK_INVALID")

	var classification := _classify_regions(request)
	if not bool(classification.get("success", false)):
		return classification
	var region_ids: Array = classification["details"]["region_ids"]
	if region_ids.size() == 1:
		if not mw10_plan.is_empty():
			return _failure("P7_6_MW10_PLAN_FOR_SINGLE_REGION_FORBIDDEN")
		return _execute_single_region(request, String(region_ids[0]))

	if mw10_plan.is_empty():
		return _failure("P7_6_MW10_PLAN_REQUIRED")
	return _execute_multi_region(
		request,
		mw10_plan,
		region_ids,
		server_tick,
		transition_prefix
	)


func contract_report() -> Dictionary:
	return {
		"schema": "planet_simulator.p7_6_seam_multi_region_composition.v1",
		"canonical_state_owned": false,
		"durable_state_owned": false,
		"replay_ledger_owned": false,
		"transaction_state_owned": false,
		"handoff_state_owned": false,
		"authority_owned": false,
		"matter_contract_owned": false,
		"item_graph_owned": false,
		"network_protocol_owned": false,
		"actor_handoff_owner": "SM1_MW8_MW9",
		"single_region_owner": "EXISTING_P7_1_TO_MW4_PATH",
		"multi_region_owner": "MW10",
		"actor_seam_implies_mw10": false,
		"mw10_minimum_target_regions": 2,
	}


func _execute_single_region(request: Dictionary, region_id: String) -> Dictionary:
	var reservation_value = _reservation_interlock.reserved_transaction(region_id)
	if typeof(reservation_value) != TYPE_DICTIONARY:
		return _failure("P7_6_MW10_RESERVATION_QUERY_INVALID_RESULT")
	var reservation: Dictionary = reservation_value
	if not reservation.is_empty():
		return _failure("P7_6_SINGLE_REGION_RESERVED_BY_MW10", {
			"region_id": region_id,
			"transaction_id": String(reservation.get("transaction_id", "")),
		})
	var execution_value = _single_region_executor.call(request.duplicate(true))
	var execution_check := _executor_result(
		execution_value,
		"P7_6_SINGLE_REGION_EXECUTOR_INVALID_RESULT"
	)
	if not bool(execution_check.get("success", false)):
		return execution_check
	return _success({
		"route": ROUTE_SINGLE_REGION,
		"region_ids": [region_id],
		"mw10_invoked": false,
		"execution_result": execution_check["details"]["value"],
	})


func _execute_multi_region(
	request: Dictionary,
	plan: Dictionary,
	region_ids: Array,
	server_tick: int,
	transition_prefix: String
) -> Dictionary:
	var intent_value = _product_gate.authorize_product_intent(request)
	var intent_check := _require_success(
		intent_value,
		"P7_6_PRODUCT_INTENT_NOT_AUTHORIZED"
	)
	if not bool(intent_check.get("success", false)):
		return intent_check

	var plan_check: Dictionary = MW10Plan.validate(plan)
	if not bool(plan_check.get("success", false)):
		return _failure("P7_6_MW10_PLAN_INVALID", {"cause": plan_check})
	if String(plan.get("operation_id", "")) != String(request["operation_id"]):
		return _failure("P7_6_MW10_PLAN_OPERATION_MISMATCH")
	if String(plan.get("body_id", "")) != String(request["body_id"]):
		return _failure("P7_6_MW10_PLAN_BODY_MISMATCH")
	var plan_regions: Array = MW10Plan.participant_region_ids(plan)
	if plan_regions != region_ids:
		return _failure("P7_6_MW10_PLAN_REGION_SET_MISMATCH", {
			"request_regions": region_ids,
			"plan_regions": plan_regions,
		})

	var prefix := transition_prefix.strip_edges().to_lower()
	if prefix.is_empty():
		prefix = "transition/p7-6/%s" % String(request["operation_id"]).sha256_text()
	var execution_value = _mw10_coordinator.execute_transaction(
		plan.duplicate(true),
		prefix,
		server_tick
	)
	var execution_check := _require_success(
		execution_value,
		"P7_6_MW10_EXECUTION_INVALID_RESULT"
	)
	if not bool(execution_check.get("success", false)):
		return execution_check
	return _success({
		"route": ROUTE_MULTI_REGION,
		"region_ids": region_ids.duplicate(),
		"mw10_invoked": true,
		"execution_result": execution_check["details"]["value"],
	})


func _classify_regions(request: Dictionary) -> Dictionary:
	var unique: Dictionary = {}
	for raw_address in Array(request.get("target_bricks", [])):
		var address: Dictionary = raw_address
		var resolution_value = _region_resolver.resolve_brick_address(address.duplicate(true))
		if typeof(resolution_value) != TYPE_DICTIONARY:
			return _failure("P7_6_MW8_REGION_RESOLUTION_INVALID_RESULT")
		var resolution: Dictionary = resolution_value
		if resolution.is_empty():
			return _failure("P7_6_MATTER_TARGET_OUTSIDE_AUTHORITY_REGIONS", {
				"address_id": String(address.get("address_id", "")),
			})
		var region_id := _region_id_from_resolution(resolution)
		if not MatterUtils.is_canonical_id(region_id, 2):
			return _failure("P7_6_MW8_REGION_RESOLUTION_INVALID", {
				"address_id": String(address.get("address_id", "")),
			})
		unique[region_id] = true
	var region_ids: Array = unique.keys()
	region_ids.sort()
	if region_ids.is_empty():
		return _failure("P7_6_MATTER_REGION_SET_EMPTY")
	return _success({"region_ids": region_ids})


func _region_id_from_resolution(resolution: Dictionary) -> String:
	var direct := String(resolution.get("region_id", "")).strip_edges().to_lower()
	if not direct.is_empty():
		return direct
	var region: Dictionary = MatterAuthorityLease.decode_region(resolution)
	return String(region.get("region_id", "")).strip_edges().to_lower()


func _executor_result(value, fallback_error: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(fallback_error)
	var result: Dictionary = value
	if result.has("success") and not bool(result.get("success", false)):
		return result.duplicate(true) if not String(result.get("error_code", "")).is_empty() \
			else _failure(fallback_error)
	return _success({"value": result.duplicate(true)})


func _require_success(value, fallback_error: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(fallback_error)
	var result: Dictionary = value
	if not bool(result.get("success", false)):
		return result.duplicate(true) if not String(result.get("error_code", "")).is_empty() \
			else _failure(fallback_error)
	return _success({"value": result.duplicate(true)})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
