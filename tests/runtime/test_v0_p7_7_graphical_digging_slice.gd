extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Bubble = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const Slice = preload("res://scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd")

const PLAYER := "miner"
const ACTOR := "player/miner"
const TOOL := "item/tool/p7-7-drill"
const SURFACE_RADIUS_M := 1737425.0

var assertions := 0
var failures: Array[String] = []


class Router extends RefCounted:
	var response = null
	var calls := 0
	var last_request: Dictionary = {}
	var last_plan: Dictionary = {}

	func execute_mutation(
		request: Dictionary,
		mw10_plan: Dictionary = {},
		_server_tick: int = 0,
		_transition_prefix: String = ""
	):
		calls += 1
		last_request = request.duplicate(true)
		last_plan = mw10_plan.duplicate(true)
		return response.duplicate(true) if typeof(response) == TYPE_DICTIONARY else response

	func contract_report() -> Dictionary:
		return {
			"canonical_state_owned": false,
			"single_region_owner": "EXISTING_P7_1_TO_MW4_PATH",
			"multi_region_owner": "MW10",
		}


class Delivery extends RefCounted:
	var response: Dictionary = MatterUtils.success({
		"matter_operation_id": "operation/placeholder",
		"delivery": {"replay": false, "output_quantity": 1},
	})
	var calls := 0
	var last_request: Dictionary = {}
	var last_result: Dictionary = {}

	func deliver_committed(request: Dictionary, result: Dictionary) -> Dictionary:
		calls += 1
		last_request = request.duplicate(true)
		last_result = result.duplicate(true)
		return response.duplicate(true)

	func contract_report() -> Dictionary:
		return {
			"canonical_state_owned": false,
			"exactly_once_owner": "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER",
		}


class VisualInvalidator extends RefCounted:
	var calls := 0
	var addresses: Array = []
	var response: Dictionary = MatterUtils.success({"invalidated": true})

	func invalidate(value: Array) -> Dictionary:
		calls += 1
		addresses = value.duplicate(true)
		return response.duplicate(true)


func _init() -> void:
	_test_configuration_and_zero_ownership()
	_test_aim_binding_fails_closed_before_route()
	_test_single_region_committed_result_drives_material_and_visual_invalidation()
	_test_delivery_and_visual_failures_propagate()
	_test_multi_region_without_canonical_physical_material_result_fails_closed()
	if failures.is_empty():
		print("V0-P7.7 graphical digging slice: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("V0-P7.7 graphical digging slice: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size()
		])
		quit(1)


func _test_configuration_and_zero_ownership() -> void:
	var slice := Slice.new()
	_assert_error(
		slice.execute_aimed_dig({}),
		"P7_7_GRAPHICAL_DIGGING_NOT_CONFIGURED",
		"unconfigured slice"
	)
	var fx := _fixture()
	_assert_ok(fx.configured, "valid P7.7 configuration")
	var contract: Dictionary = fx.slice.contract_report()
	for key in [
		"canonical_state_owned",
		"terrain_truth_owned",
		"matter_truth_owned",
		"item_graph_owned",
		"authority_owned",
		"transaction_state_owned",
		"persistence_owned",
		"replay_ledger_owned",
		"network_protocol_owned",
		"aim_truth_owned",
	]:
		_assert(not bool(contract.get(key, true)), "P7.7 owns no %s" % key)
	_assert(
		String(contract.get("multi_region_material_projection", "")) 			== "FAIL_CLOSED_UNTIL_CANONICAL_PHYSICAL_OUTPUT_AVAILABLE",
		"MW10 material gap is explicit rather than guessed"
	)


func _test_aim_binding_fails_closed_before_route() -> void:
	var fx := _fixture()
	var missing_query: Dictionary = fx.binding.duplicate(true)
	missing_query.erase("query_result")
	_assert_error(
		fx.slice.execute_aimed_dig(missing_query),
		"P7_7_CANONICAL_MATTER_QUERY_RESULT_REQUIRED",
		"missing canonical Matter query result"
	)
	_assert(fx.router.calls == 0, "missing query never reaches router")

	var miss: Dictionary = fx.binding.duplicate(true)
	var miss_query: Dictionary = Dictionary(miss["query_result"]).duplicate(true)
	var miss_details: Dictionary = Dictionary(miss_query["details"]).duplicate(true)
	miss_details["hit"] = false
	miss_query["details"] = miss_details
	miss["query_result"] = miss_query
	_assert_error(
		fx.slice.execute_aimed_dig(miss),
		"P7_7_CANONICAL_SURFACE_HIT_REQUIRED",
		"canonical query miss"
	)
	_assert(fx.router.calls == 0, "query miss never reaches router")

	var drift: Dictionary = fx.binding.duplicate(true)
	var drift_query: Dictionary = Dictionary(drift["query_result"]).duplicate(true)
	var drift_details: Dictionary = Dictionary(drift_query["details"]).duplicate(true)
	drift_details["position_m"] = Vector3(1000000.0, 1000000.0, 1000000.0)
	drift_query["details"] = drift_details
	drift["query_result"] = drift_query
	_assert_error(
		fx.slice.execute_aimed_dig(drift),
		"P7_7_QUERY_HIT_OUTSIDE_REQUEST_SHAPE",
		"query/request target drift"
	)
	_assert(fx.router.calls == 0, "query/request drift never reaches router")


func _test_single_region_committed_result_drives_material_and_visual_invalidation() -> void:
	var fx := _fixture()
	fx.router.response = MatterUtils.success({
		"route": Slice.ROUTE_SINGLE_REGION,
		"region_ids": ["matter-region/p7-7-a"],
		"mw10_invoked": false,
		"execution_result": fx.result,
	})
	fx.delivery.response = MatterUtils.success({
		"matter_operation_id": String(fx.request["operation_id"]),
		"delivery": {
			"replay": false,
			"item_graph_mutated": true,
			"output_quantity": 1,
		},
	})
	var executed: Dictionary = fx.slice.execute_aimed_dig(fx.binding)
	_assert_ok(executed, "single-region graphical dig")
	var details: Dictionary = executed.get("details", {})
	_assert(String(details.get("route", "")) == Slice.ROUTE_SINGLE_REGION, "single route preserved")
	_assert(not bool(details.get("mw10_invoked", true)), "single route never reports MW10")
	_assert(fx.router.calls == 1, "router called once")
	_assert(fx.delivery.calls == 1, "material delivery called exactly once")
	_assert(fx.visual.calls == 1, "representation invalidation called exactly once")
	_assert(
		fx.visual.addresses.size() == Array(fx.result.get("changed_bricks", [])).size(),
		"all canonical changed bricks drive visual invalidation"
	)
	_assert(
		String(details.get("visible_hole_source", "")) == "CANONICAL_MATTER_RESULT",
		"visible hole source is canonical Matter"
	)
	_assert(
		String(details.get("inventory_source", "")) == "CANONICAL_ITEM_GRAPH",
		"inventory source remains canonical Item Graph"
	)
	_assert(
		String(fx.delivery.last_request.get("operation_id", "")) 			== String(fx.request.get("operation_id", "")),
		"delivery receives exact canonical operation"
	)
	_assert(
		String(fx.delivery.last_result.get("checksum", "")) 			== String(fx.result.get("checksum", "")),
		"delivery receives exact canonical Matter result"
	)


func _test_delivery_and_visual_failures_propagate() -> void:
	var delivery_fx := _fixture()
	delivery_fx.router.response = MatterUtils.success({
		"route": Slice.ROUTE_SINGLE_REGION,
		"region_ids": ["matter-region/p7-7-a"],
		"mw10_invoked": false,
		"execution_result": delivery_fx.result,
	})
	delivery_fx.delivery.response = MatterUtils.failure("P7_ITEM_GRAPH_OUTPUT_REJECTED")
	_assert_error(
		delivery_fx.slice.execute_aimed_dig(delivery_fx.binding),
		"P7_ITEM_GRAPH_OUTPUT_REJECTED",
		"canonical Item Graph rejection"
	)
	_assert(delivery_fx.visual.calls == 0, "visual completion not reported after delivery rejection")

	var visual_fx := _fixture()
	visual_fx.router.response = MatterUtils.success({
		"route": Slice.ROUTE_SINGLE_REGION,
		"region_ids": ["matter-region/p7-7-a"],
		"mw10_invoked": false,
		"execution_result": visual_fx.result,
	})
	visual_fx.visual.response = MatterUtils.failure("P7_7_TEST_INVALIDATION_REJECTED")
	_assert_error(
		visual_fx.slice.execute_aimed_dig(visual_fx.binding),
		"P7_7_TEST_INVALIDATION_REJECTED",
		"representation invalidation failure"
	)
	_assert(visual_fx.delivery.calls == 1, "canonical material commit/delivery is not rolled back by presentation failure")
	_assert(visual_fx.visual.calls == 1, "presentation invalidation attempted once")


func _test_multi_region_without_canonical_physical_material_result_fails_closed() -> void:
	var fx := _fixture()
	fx.binding["mw10_plan"] = {
		"schema": "test-only-mw10-plan-envelope",
	}
	fx.router.response = MatterUtils.success({
		"route": Slice.ROUTE_MULTI_REGION,
		"region_ids": ["matter-region/p7-7-a", "matter-region/p7-7-b"],
		"mw10_invoked": true,
		"execution_result": MatterUtils.success({
			"result": {
				"schema": "planet_simulator.matter_cross_region_operation_result.v1",
				"operation_id": String(fx.request["operation_id"]),
			},
		}),
	})
	var result: Dictionary = fx.slice.execute_aimed_dig(fx.binding)
	_assert_error(
		result,
		"P7_7_MULTI_REGION_MATERIAL_RESULT_REQUIRED",
		"MW10 route without physical batch-compatible Matter result"
	)
	_assert(fx.router.calls == 1, "true multi route reaches P7.6 router")
	_assert(fx.delivery.calls == 0, "P7.7 never invents multi-region material delivery")
	_assert(fx.visual.calls == 0, "P7.7 does not claim full visible product success without material bridge")


func _fixture() -> Dictionary:
	var pair := _committed_pair()
	_assert(not pair.is_empty(), "real MW4 fixture produces committed pair")
	var router := Router.new()
	var delivery := Delivery.new()
	var visual := VisualInvalidator.new()
	var slice := Slice.new()
	var configured: Dictionary = slice.configure(
		router,
		delivery,
		Callable(visual, "invalidate")
	)
	var request: Dictionary = pair.get("request", {})
	var result: Dictionary = pair.get("result", {})
	return {
		"slice": slice,
		"router": router,
		"delivery": delivery,
		"visual": visual,
		"configured": configured,
		"request": request,
		"result": result,
		"binding": {
			"query_result": pair.get("query_result", {}),
			"request": request,
			"mw10_plan": {},
			"server_tick": 1,
			"transition_prefix": "transition/p7-7/test",
		},
	}


func _committed_pair() -> Dictionary:
	var bubble = Bubble.new()
	var configured: Dictionary = bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
		"half_extent_m": 32.0,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 3,
		"brick_interior_resolution": 8,
		"ghost_border_samples": 1,
	})
	if not bool(configured.get("success", false)):
		return {}
	var center: Vector3 = bubble.anchor_body_fixed_m()
	var query_result: Dictionary = bubble.query_service().raycast(
		center + Vector3(0.0, 12.0, 0.0),
		Vector3.DOWN,
		24.0,
		bubble.mutation_level(),
		0.25,
		0.25,
		256
	)
	if not bool(query_result.get("success", false)) \
			or not bool(Dictionary(query_result.get("details", {})).get("hit", false)):
		return {}
	var hit_position_m: Vector3 = Dictionary(query_result["details"])["position_m"]
	var request: Dictionary = bubble.create_excavation_request(
		"operation/p7-7/single",
		ACTOR,
		TOOL,
		hit_position_m + Vector3.UP * 0.5,
		hit_position_m + Vector3.DOWN * 2.0,
		0.75,
		1000000000.0,
		1
	)
	if request.is_empty():
		return {}
	var result: Dictionary = bubble.execute(request)
	if String(result.get("status", "")) != "COMMITTED":
		return {}
	return {
		"query_result": query_result,
		"request": request,
		"result": result,
	}


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)), "%s rejects" % message)
	_assert(
		String(result.get("error_code", "")) == error_code,
		"%s error=%s actual=%s" % [
			message,
			error_code,
			String(result.get("error_code", "")),
		]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failures.append(message)
