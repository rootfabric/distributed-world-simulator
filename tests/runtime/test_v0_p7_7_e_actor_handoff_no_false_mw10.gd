extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const BrickAddress = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const MatterRequest = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const SM1 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Router = preload("res://scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd")
const MW10Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")

const AUTHORITY_A := "authority/p7-7-e-a"
const AUTHORITY_B := "authority/p7-7-e-b"
const PLAYER := "p7-7-e-player"
const PLAYER_ENTITY := "player/p7-7-e-player"
const TOOL := "item/tool/p7-7-e-drill"

var assertions := 0
var failures: Array[String] = []


class ProductGate extends RefCounted:
	var sm1 = null
	var calls := 0

	func _init(value) -> void:
		sm1 = value

	func authorize_product_intent(_request: Dictionary) -> Dictionary:
		calls += 1
		var snapshot: Dictionary = sm1.snapshot()
		return sm1.authorize_write(
			String(snapshot.get("active_authority_id", "")),
			int(snapshot.get("authority_epoch", 0))
		)


class Resolver extends RefCounted:
	var mapping: Dictionary = {}

	func resolve_brick_address(address: Dictionary) -> Dictionary:
		var region_id := String(mapping.get(String(address.get("address_id", "")), ""))
		return {} if region_id.is_empty() else {"region_id": region_id}


class SingleExecutor extends RefCounted:
	var sm1 = null
	var calls := 0
	var last_request: Dictionary = {}

	func _init(value) -> void:
		sm1 = value

	func execute(request: Dictionary) -> Dictionary:
		calls += 1
		last_request = request.duplicate(true)
		var snapshot: Dictionary = sm1.snapshot()
		var authorized: Dictionary = sm1.authorize_write(
			String(snapshot.get("active_authority_id", "")),
			int(snapshot.get("authority_epoch", 0))
		)
		if not bool(authorized.get("success", false)):
			return authorized
		return MatterUtils.success({
			"owner": "MW4",
			"operation_id": String(request.get("operation_id", "")),
			"active_authority_id": String(snapshot.get("active_authority_id", "")),
			"authority_epoch": int(snapshot.get("authority_epoch", 0)),
		})


class HandoffExecutor extends RefCounted:
	var sm1 = null
	var calls := 0

	func _init(value) -> void:
		sm1 = value

	func execute(_region_id: String, context: Dictionary) -> Dictionary:
		calls += 1
		var snapshot: Dictionary = sm1.snapshot()
		var source := String(snapshot.get("active_authority_id", ""))
		var source_epoch := int(snapshot.get("authority_epoch", 0))
		var target := String(context.get("target_authority_id", ""))
		var target_epoch := int(context.get("target_authority_epoch", 0))
		var transfer_id := String(context.get("transfer_id", ""))
		var begun: Dictionary = sm1.begin_transfer(
			transfer_id, source, target, source_epoch
		)
		if not bool(begun.get("success", false)):
			return begun
		var warm_report := {
			"transfer_id": transfer_id,
			"mode": "SHADOW",
			"checksum": "%s-warm" % transfer_id.sha256_text(),
			"private_canonical_truth": false,
			"persistence_owner": "EXTERNAL",
			"counters": {
				"write_attempts": 0,
				"write_rejections": 0,
			},
		}
		var warm: Dictionary = sm1.validate_warm_target(
			transfer_id, target, warm_report
		)
		if not bool(warm.get("success", false)):
			return warm
		var committed: Dictionary = sm1.commit_ownership(
			transfer_id, source, target, source_epoch, target_epoch
		)
		if not bool(committed.get("success", false)):
			return committed
		var token := String(committed.get("details", {}).get("commit_token", ""))
		var retired: Dictionary = sm1.retire_source(
			transfer_id, source, token
		)
		if not bool(retired.get("success", false)):
			return retired
		var activated: Dictionary = sm1.activate_target(
			transfer_id, target, target_epoch, token
		)
		if not bool(activated.get("success", false)):
			return activated
		return MatterUtils.success({
			"active_authority_id": target,
			"authority_epoch": target_epoch,
		})


class MW10Counter extends RefCounted:
	var calls := 0

	func execute_transaction(
		_plan: Dictionary,
		_transition_prefix: String,
		_server_tick: int
	) -> Dictionary:
		calls += 1
		return MatterUtils.failure("P7_7_E_MW10_MUST_NOT_RUN")


class Interlock extends RefCounted:
	var handoff_checks := 0
	var reservation_queries := 0

	func validate_handoff(region_id: String) -> Dictionary:
		handoff_checks += 1
		return MatterUtils.success({"region_id": region_id})

	func reserved_transaction(_region_id: String) -> Dictionary:
		reservation_queries += 1
		return {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sm1 := SM1.new()
	_assert_ok(sm1.configure(AUTHORITY_A, 1, {
		"logical_player_id": PLAYER,
		"player_entity_id": PLAYER_ENTITY,
		"last_input_sequence": 1,
		"last_operation_id": "operation/p7-7-e/seed",
	}), "E SM1 configure")

	var product_gate := ProductGate.new(sm1)
	var resolver := Resolver.new()
	var address_a := _address(0)
	var address_b := _address(1)
	resolver.mapping[String(address_a["address_id"])] = MW10Fixture.REGION_A
	resolver.mapping[String(address_b["address_id"])] = MW10Fixture.REGION_B
	var single := SingleExecutor.new(sm1)
	var handoff := HandoffExecutor.new(sm1)
	var mw10 := MW10Counter.new()
	var interlock := Interlock.new()
	var router := Router.new()
	_assert_ok(router.configure(
		product_gate,
		resolver,
		Callable(single, "execute"),
		Callable(handoff, "execute"),
		mw10,
		interlock
	), "E P7.6 router configure")

	var before: Dictionary = sm1.snapshot()
	_assert(String(before.get("active_authority_id", "")) == AUTHORITY_A, "E starts under authority A")
	_assert(int(before.get("authority_epoch", 0)) == 1, "E starts at epoch 1")

	var handoff_result: Dictionary = router.execute_actor_handoff(
		MW10Fixture.REGION_B,
		{
			"transfer_id": "transfer/p7-7-e/a-b",
			"target_authority_id": AUTHORITY_B,
			"target_authority_epoch": 2,
		}
	)
	_assert_ok(handoff_result, "E A→B actor handoff")
	_assert(
		String(handoff_result.get("details", {}).get("route", ""))
			== Router.ROUTE_ACTOR_HANDOFF,
		"E handoff route is SM1/MW8/MW9"
	)
	_assert(
		not bool(handoff_result.get("details", {}).get("mw10_invoked", true)),
		"E actor handoff reports MW10 false"
	)
	_assert(handoff.calls == 1, "E handoff executor called exactly once")
	_assert(interlock.handoff_checks == 1, "E handoff checks MW10 reservation interlock")
	_assert(mw10.calls == 0, "E actor seam crossing does not call MW10")

	var after_handoff: Dictionary = sm1.snapshot()
	_assert(
		String(after_handoff.get("active_authority_id", "")) == AUTHORITY_B,
		"E active authority moved to B"
	)
	_assert(
		int(after_handoff.get("authority_epoch", 0)) == 2,
		"E active authority epoch advanced to 2"
	)

	var b_request := _request(
		[address_b],
		"matter-operation/p7-7-e-b-only"
	)
	var b_only: Dictionary = router.execute_mutation(b_request)
	_assert_ok(b_only, "E post-handoff B-only dig")
	_assert(
		String(b_only.get("details", {}).get("route", ""))
			== Router.ROUTE_SINGLE_REGION,
		"E B-only dig routes to existing MW4"
	)
	_assert(
		not bool(b_only.get("details", {}).get("mw10_invoked", true)),
		"E B-only dig reports MW10 false"
	)
	_assert(single.calls == 1, "E B-only MW4 executor called exactly once")
	_assert(
		String(single.last_request.get("operation_id", ""))
			== String(b_request.get("operation_id", "")),
		"E MW4 receives exact canonical B-only request"
	)
	_assert(product_gate.calls == 0, "E single-region route does not invoke multi-region product gate")
	_assert(interlock.reservation_queries == 1, "E B-only path checks reservation interlock once")
	_assert(mw10.calls == 0, "E B-only dig still never calls MW10")

	var execution: Dictionary = Dictionary(
		b_only.get("details", {}).get("execution_result", {})
	)
	var execution_details: Dictionary = Dictionary(execution.get("details", {}))
	_assert(
		String(execution_details.get("owner", "")) == "MW4",
		"E downstream owner is MW4"
	)
	_assert(
		String(execution_details.get("active_authority_id", "")) == AUTHORITY_B,
		"E MW4 executes under post-handoff authority B"
	)
	_assert(
		int(execution_details.get("authority_epoch", 0)) == 2,
		"E MW4 executes under post-handoff epoch 2"
	)

	_finish()


func _request(
	targets: Array,
	operation_id: String
) -> Dictionary:
	var expected: Dictionary = {}
	for raw_address in targets:
		var address: Dictionary = raw_address
		expected[String(address["address_id"])] = 0
	var value: Dictionary = MatterRequest.create({
		"operation_id": operation_id,
		"body_id": MW10Fixture.BODY_ID,
		"actor_id": PLAYER_ENTITY,
		"tool_id": TOOL,
		"operation_type": "EXCAVATE",
		"target_bricks": targets,
		"expected_revision_by_address": expected,
		"shape": MatterRequest.create_shape(
			"CAPSULE",
			[0.0, 0.0, 0.0],
			[1.0, 0.0, 0.0],
			0.5
		),
		"source_container_id": "",
		"destination_container_id": "",
		"requested_mass_kg": 0.0,
		"energy_budget_j": 1000.0,
		"client_tick": 10,
	})
	_assert_ok(MatterRequest.validate(value), "E canonical Matter request")
	return value


func _address(index: int) -> Dictionary:
	var cell: Dictionary = CellAddress.create(
		"universe",
		"p77e",
		"asteroid",
		"matter",
		1,
		"asteroid-mw10",
		[index]
	)
	return BrickAddress.create(cell, 0, 0, 0, 0)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P7.7-E actor handoff no false MW10: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("V0-P7.7-E actor handoff no false MW10: FAIL (%d assertions, %d failures)" % [
			assertions,
			failures.size(),
		])
		quit(1)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
