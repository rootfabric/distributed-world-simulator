extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Bubble = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const ItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const Gate = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd")
const Router = preload("res://scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd")
const Delivery = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd")
const Slice = preload("res://scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd")

const PLAYER := "miner-b"
const ACTOR := "player/miner-b"
const PRODUCT_AUTHORITY := "authority/p7-7-b"
const PRODUCT_EPOCH := 1
const REGION_A := "matter-region/p7-7-a"
const REGION_B := "matter-region/p7-7-b"
const MATTER_OWNER := "authority/p7-7-matter-a"
const MATTER_EPOCH := 1
const SURFACE_RADIUS_M := 1737425.0
const NEAR_SINGLE_X_M := -2.40
const CROSSING_X_M := -2.35
const DIG_RADIUS_M := 0.35

var assertions := 0
var failures: Array[String] = []
var bubble = null
var graph = null
var gate = null
var router = null
var delivery = null
var slice = null
var gameplay = null
var mw10 = null
var visual_calls := 0
var tool_id := ""


class GameplayPort extends RefCounted:
	var position_body_fixed_m := Vector3.ZERO

	func get_player(logical_player_id: String) -> Dictionary:
		if logical_player_id != PLAYER:
			return {}
		return {
			"logical_player_id": PLAYER,
			"player_entity_id": ACTOR,
			"connected": true,
			"position": {
				"x": position_body_fixed_m.x,
				"y": position_body_fixed_m.y,
				"z": position_body_fixed_m.z,
			},
		}


class SM1Port extends RefCounted:
	func authorize_write(authority_id: String, authority_epoch: int) -> Dictionary:
		if authority_id != PRODUCT_AUTHORITY or authority_epoch != PRODUCT_EPOCH:
			return MatterUtils.failure("P7_7_B_SM1_TUPLE_MISMATCH")
		return MatterUtils.success()


class RegionalGate extends RefCounted:
	func authorize_mutation(_request: Dictionary) -> Dictionary:
		return MatterUtils.success({"region_id": REGION_A})

	func owner_id() -> String:
		return MATTER_OWNER

	func authority_epoch() -> int:
		return MATTER_EPOCH


class SeamRegionResolver extends RefCounted:
	func resolve_brick_address(address: Dictionary) -> Dictionary:
		var cell: Dictionary = Dictionary(address.get("cell_address", {}))
		var path: Array = Array(cell.get("path", []))
		if path.is_empty():
			return {}
		var first_child := int(path[0])
		return {"region_id": REGION_B if (first_child & 1) != 0 else REGION_A}


class ReservationInterlock extends RefCounted:
	func validate_handoff(_region_id: String) -> Dictionary:
		return MatterUtils.success()

	func reserved_transaction(_region_id: String) -> Dictionary:
		return {}


class MW10Counter extends RefCounted:
	var calls := 0

	func execute_transaction(
		_plan: Dictionary,
		_transition_prefix: String,
		_server_tick: int
	) -> Dictionary:
		calls += 1
		return MatterUtils.failure("P7_7_B_MW10_MUST_NOT_RUN")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var setup := _setup()
	_assert_ok(setup, "setup")
	if not bool(setup.get("success", false)):
		_finish()
		return

	var near := _aim_and_request(NEAR_SINGLE_X_M, "operation/p7-7-b/near-single")
	var crossing := _aim_and_request(CROSSING_X_M, "operation/p7-7-b/crossing")
	_assert(not near.is_empty(), "near-seam single-region request created")
	_assert(not crossing.is_empty(), "crossing control request created")
	if near.is_empty() or crossing.is_empty():
		_finish()
		return

	_assert(
		absf(float(near["local_x_m"])) < 4.0,
		"near-seam hit is within one level-2 cell edge of seam"
	)
	_assert(
		_region_set(near["request"]) == [REGION_A],
		"x=-2.40 canonical target set remains strictly region A"
	)
	_assert(
		_region_set(crossing["request"]) == [REGION_A, REGION_B],
		"x=-2.35 neighboring control target crosses A+B seam"
	)

	gameplay.position_body_fixed_m = near["query_result"]["details"]["position_m"]
	var before := graph.create_snapshot()
	var result: Dictionary = slice.execute_aimed_dig({
		"query_result": near["query_result"],
		"request": near["request"],
		"mw10_plan": {},
		"server_tick": 1,
		"transition_prefix": "transition/p7-7-b/near-single",
	})
	_assert_ok(result, "near-seam single-region dig")
	var details: Dictionary = Dictionary(result.get("details", {}))
	_assert(
		String(details.get("route", "")) == Router.ROUTE_SINGLE_REGION,
		"near-seam request routes through single-region MW4"
	)
	_assert(not bool(details.get("mw10_invoked", true)), "near-seam request keeps MW10 false")
	_assert(mw10.calls == 0, "MW10 coordinator not called")
	_assert(int(details.get("changed_brick_count", 0)) > 0, "MW4 changes canonical Matter bricks")
	_assert(float(details.get("removed_mass_kg", 0.0)) > 0.0, "MW4 removes canonical Matter mass")
	_assert(visual_calls == 1, "derived representation invalidation occurs once")
	var material: Dictionary = Dictionary(details.get("material_delivery", {}))
	var delivery_result: Dictionary = Dictionary(material.get("delivery", {}))
	_assert(int(delivery_result.get("output_quantity", 0)) > 0, "material reaches canonical Item Graph")
	_assert(not bool(delivery_result.get("replay", true)), "first near-seam material delivery is fresh")
	var after := graph.create_snapshot()
	_assert(int(after.get("revision", -1)) > int(before.get("revision", -1)), "Item Graph revision advances")
	_assert(String(after.get("checksum", "")) != String(before.get("checksum", "")), "Item Graph checksum changes")

	var crossing_result: Dictionary = router.execute_mutation(
		crossing["request"],
		{},
		2,
		"transition/p7-7-b/crossing-control"
	)
	_assert_error(
		crossing_result,
		"P7_6_MW10_PLAN_REQUIRED",
		"neighboring A+B control request is classified multi-region"
	)
	_assert(mw10.calls == 0, "missing plan prevents MW10 execution for crossing control")

	_finish()


func _setup() -> Dictionary:
	bubble = Bubble.new()
	var bubble_setup: Dictionary = bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
		"half_extent_m": 8.0,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 2,
		"brick_interior_resolution": 4,
		"ghost_border_samples": 1,
	})
	if not bool(bubble_setup.get("success", false)):
		return bubble_setup

	graph = ItemGraph.new()
	var graph_setup: Dictionary = graph.setup("authority/p7-7-b-item-graph", 1)
	if not bool(graph_setup.get("success", false)):
		return graph_setup
	graph.ensure_player(PLAYER)
	var created: Dictionary = graph.apply_server_output(
		"operation/p7-7-b/tool",
		PLAYER,
		"item/tool/mining",
		1,
		"source/p7-7-b"
	)
	if not bool(created.get("success", false)):
		return created
	tool_id = String(created.get("details", {}).get("output_item_id", ""))
	var equipped: Dictionary = graph.execute(
		PLAYER,
		1,
		"operation/p7-7-b/equip",
		"item.equip",
		{"item_id": tool_id, "slot_id": "tool/main"}
	)
	if not bool(equipped.get("success", false)):
		return equipped

	gameplay = GameplayPort.new()
	gate = Gate.new()
	var gate_setup: Dictionary = gate.configure(
		gameplay,
		graph,
		SM1Port.new(),
		RegionalGate.new(),
		PRODUCT_AUTHORITY,
		PRODUCT_EPOCH,
		6.0,
		Callable(self, "_project_player_position")
	)
	if not bool(gate_setup.get("success", false)):
		return gate_setup

	mw10 = MW10Counter.new()
	router = Router.new()
	var router_setup: Dictionary = router.configure(
		gate,
		SeamRegionResolver.new(),
		Callable(self, "_execute_single_region"),
		Callable(self, "_handoff_forbidden"),
		mw10,
		ReservationInterlock.new()
	)
	if not bool(router_setup.get("success", false)):
		return router_setup

	delivery = Delivery.new()
	var delivery_setup: Dictionary = delivery.configure(
		bubble.excavation_service(),
		graph
	)
	if not bool(delivery_setup.get("success", false)):
		return delivery_setup

	slice = Slice.new()
	return slice.configure(
		router,
		delivery,
		Callable(self, "_invalidate_representation")
	)


func _aim_and_request(local_x_m: float, operation_id: String) -> Dictionary:
	var center: Vector3 = bubble.anchor_body_fixed_m()
	var query: Dictionary = bubble.query_service().raycast(
		center + Vector3(local_x_m, 6.0, 0.0),
		Vector3.DOWN,
		12.0,
		bubble.mutation_level(),
		0.2,
		0.1,
		256
	)
	if not bool(query.get("success", false)) 			or not bool(Dictionary(query.get("details", {})).get("hit", false)):
		return {}
	var hit: Vector3 = query["details"]["position_m"]
	var request: Dictionary = bubble.create_excavation_request(
		operation_id,
		ACTOR,
		tool_id,
		hit + Vector3.UP * 0.25,
		hit + Vector3.DOWN * 1.5,
		DIG_RADIUS_M,
		1000000000.0,
		1
	)
	if request.is_empty():
		return {}
	return {
		"query_result": query,
		"request": request,
		"local_x_m": hit.x - center.x,
	}


func _region_set(request: Dictionary) -> Array:
	var unique: Dictionary = {}
	var resolver := SeamRegionResolver.new()
	for address_value in Array(request.get("target_bricks", [])):
		var resolved: Dictionary = resolver.resolve_brick_address(address_value)
		var region_id := String(resolved.get("region_id", ""))
		if not region_id.is_empty():
			unique[region_id] = true
	var regions: Array = unique.keys()
	regions.sort()
	return regions


func _execute_single_region(request: Dictionary) -> Dictionary:
	var authorized: Dictionary = gate.authorize_mutation(request)
	if not bool(authorized.get("success", false)):
		return authorized
	var result: Dictionary = bubble.execute(request)
	if String(result.get("status", "")) != "COMMITTED":
		return MatterUtils.failure("P7_7_B_MW4_NOT_COMMITTED", {"matter_result": result})
	return MatterUtils.success({"matter_result": result})


func _handoff_forbidden(_region_id: String, _context: Dictionary) -> Dictionary:
	return MatterUtils.failure("P7_7_B_HANDOFF_OUTSIDE_SCOPE")


func _invalidate_representation(_addresses: Array) -> Dictionary:
	visual_calls += 1
	return MatterUtils.success({"invalidated": true})


func _project_player_position(player: Dictionary, _request: Dictionary) -> Dictionary:
	var position: Dictionary = player.get("position", {})
	return {
		"success": true,
		"error_code": "",
		"position_m": [
			float(position.get("x", 0.0)),
			float(position.get("y", 0.0)),
			float(position.get("z", 0.0)),
		],
	}


func _finish() -> void:
	if failures.is_empty():
		print("V0-P7.7-B seam-near single-region: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("V0-P7.7-B seam-near single-region: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size()
		])
		quit(1)


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
