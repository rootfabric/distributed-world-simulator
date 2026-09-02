extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const BrickAddress = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const MatterRequest = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const SM1 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Router = preload("res://scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd")
const MW10Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")

const AUTHORITY_A := "authority/p7-6-a"
const AUTHORITY_B := "authority/p7-6-b"
const PLAYER := "p7-6-player"
const PLAYER_ENTITY := "player/p7-6-player"
const TOOL := "item/tool/p7-6-drill"

var assertions := 0
var failures: Array[String] = []


class ProductGate extends RefCounted:
	var sm1 = null
	var intent_calls := 0

	func _init(value) -> void:
		sm1 = value

	func authorize_product_intent(_request: Dictionary) -> Dictionary:
		intent_calls += 1
		var snapshot: Dictionary = sm1.snapshot()
		return sm1.authorize_write(
			String(snapshot.get("active_authority_id", "")),
			int(snapshot.get("authority_epoch", 0))
		)


class RegionResolver extends RefCounted:
	var region_by_address: Dictionary = {}

	func resolve_brick_address(address: Dictionary) -> Dictionary:
		var region_id := String(region_by_address.get(String(address.get("address_id", "")), ""))
		return {} if region_id.is_empty() else {"region_id": region_id}


class ReservationInterlock extends RefCounted:
	var reservations: Dictionary = {}

	func validate_handoff(region_id: String) -> Dictionary:
		if reservations.has(region_id):
			return MatterUtils.failure(
				"MATTER_CROSS_REGION_TRANSACTION_RESERVES_HANDOFF_REGION",
				{"region_id": region_id, "transaction_id": reservations[region_id]}
			)
		return MatterUtils.success()

	func reserved_transaction(region_id: String) -> Dictionary:
		if not reservations.has(region_id):
			return {}
		return {
			"region_id": region_id,
			"transaction_id": String(reservations[region_id]),
		}


class SingleExecutor extends RefCounted:
	var sm1 = null
	var calls := 0

	func _init(value) -> void:
		sm1 = value

	func execute(request: Dictionary) -> Dictionary:
		calls += 1
		var snapshot: Dictionary = sm1.snapshot()
		var authorized: Dictionary = sm1.authorize_write(
			String(snapshot.get("active_authority_id", "")),
			int(snapshot.get("authority_epoch", 0))
		)
		if not bool(authorized.get("success", false)):
			return authorized
		return MatterUtils.success({
			"operation_id": request["operation_id"],
			"owner": "MW4",
		})


class ActorHandoffExecutor extends RefCounted:
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
		var begun: Dictionary = sm1.begin_transfer(transfer_id, source, target, source_epoch)
		if not bool(begun.get("success", false)):
			return begun
		var warm_report := {
			"transfer_id": transfer_id,
			"mode": "SHADOW",
			"checksum": "%s-warm" % transfer_id.sha256_text(),
			"private_canonical_truth": false,
			"persistence_owner": "EXTERNAL",
			"counters": {"write_attempts": 0, "write_rejections": 0},
		}
		var warm: Dictionary = sm1.validate_warm_target(transfer_id, target, warm_report)
		if not bool(warm.get("success", false)):
			return warm
		var committed: Dictionary = sm1.commit_ownership(
			transfer_id, source, target, source_epoch, target_epoch
		)
		if not bool(committed.get("success", false)):
			return committed
		var token := String(committed.get("details", {}).get("commit_token", ""))
		var retired: Dictionary = sm1.retire_source(transfer_id, source, token)
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


class MW10Coordinator extends RefCounted:
	var calls := 0
	var operation_results: Dictionary = {}

	func execute_transaction(plan: Dictionary, transition_prefix: String, server_tick: int) -> Dictionary:
		calls += 1
		var operation_id := String(plan.get("operation_id", ""))
		if operation_results.has(operation_id):
			return MatterUtils.success({
				"replay": true,
				"result": operation_results[operation_id],
			})
		var result := {
			"operation_id": operation_id,
			"transaction_id": String(plan.get("transaction_id", "")),
			"transition_prefix": transition_prefix,
			"server_tick": server_tick,
			"owner": "MW10",
		}
		operation_results[operation_id] = result.duplicate(true)
		return MatterUtils.success({"replay": false, "result": result})


func _init() -> void:
	_test_configuration()
	_test_actor_handoff_then_single_region()
	_test_transfer_gap_fences_both_routes()
	_test_true_multi_region_routes_only_to_mw10()
	_test_reservation_interlocks()
	_test_plan_binding_and_zero_ownership()
	if failures.is_empty():
		print("V0-P7.6 seam + multi-region composition: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	for failure in failures:
		push_error(failure)
	print("V0-P7.6 seam + multi-region composition: FAIL (%d assertions, %d failures)" % [
		assertions, failures.size()
	])
	quit(1)


func _test_configuration() -> void:
	var router := Router.new()
	_assert_error(
		router.execute_mutation(_request([_address(0)])),
		"P7_6_COMPOSITION_NOT_CONFIGURED",
		"unconfigured mutation route"
	)
	var fx := _fixture()
	_assert(bool(fx.configured.get("success", false)), "valid composition config accepted")
	var duplicate: Dictionary = fx.router.configure(
		fx.product_gate, fx.resolver, Callable(fx.single, "execute"),
		Callable(fx.handoff, "execute"), fx.mw10, fx.interlock
	)
	_assert_error(duplicate, "P7_6_COMPOSITION_ALREADY_CONFIGURED", "duplicate configure")


func _test_actor_handoff_then_single_region() -> void:
	var fx := _fixture()
	var handoff: Dictionary = fx.router.execute_actor_handoff(MW10Fixture.REGION_B, {
		"transfer_id": "transfer/p7-6/a-b",
		"target_authority_id": AUTHORITY_B,
		"target_authority_epoch": 2,
	})
	_assert_ok(handoff, "actor A->B seam handoff")
	_assert(String(handoff.details.get("route", "")) == Router.ROUTE_ACTOR_HANDOFF, "actor seam uses SM1/MW8/MW9 route")
	_assert(not bool(handoff.details.get("mw10_invoked", true)), "actor seam does not imply MW10")
	_assert(fx.mw10.calls == 0, "actor seam does not call MW10 coordinator")
	var active: Dictionary = fx.sm1.snapshot()
	_assert(String(active.get("active_authority_id", "")) == AUTHORITY_B and int(active.get("authority_epoch", 0)) == 2, "SM1 active tuple moved to B/2")

	var single: Dictionary = fx.router.execute_mutation(_request([fx.address_b]))
	_assert_ok(single, "post-handoff B-only mutation")
	_assert(String(single.details.get("route", "")) == Router.ROUTE_SINGLE_REGION, "B-only mutation stays ordinary MW4")
	_assert(fx.single.calls == 1, "single-region executor called exactly once")
	_assert(fx.mw10.calls == 0, "single-region mutation never invokes MW10")


func _test_transfer_gap_fences_both_routes() -> void:
	var fx := _fixture()
	var begun: Dictionary = fx.sm1.begin_transfer(
		"transfer/p7-6/gap", AUTHORITY_A, AUTHORITY_B, 1
	)
	_assert_ok(begun, "SM1 transfer gap opened")
	var single: Dictionary = fx.router.execute_mutation(_request([fx.address_a]))
	_assert_error(single, "SM1_AUTHORITY_TRANSFER_WRITE_FENCED", "single-region mutation during transfer gap")
	_assert(fx.single.calls == 1, "ordinary single route reached existing SM1 fence")
	var multi_request := _request([fx.address_a, fx.address_b], "matter-operation/p7-6-gap-ab")
	var multi: Dictionary = fx.router.execute_mutation(
		multi_request,
		MW10Fixture.plan_ab("matter-transaction/p7-6-gap-ab", multi_request.operation_id, 30),
		30,
		"transition/p7-6-gap"
	)
	_assert_error(multi, "SM1_AUTHORITY_TRANSFER_WRITE_FENCED", "multi-region mutation during transfer gap")
	_assert(fx.mw10.calls == 0, "MW10 not invoked after SM1 product-intent fence")


func _test_true_multi_region_routes_only_to_mw10() -> void:
	var fx := _fixture()
	var request := _request([fx.address_a, fx.address_b], "matter-operation/p7-6-ab")
	var plan: Dictionary = MW10Fixture.plan_ab(
		"matter-transaction/p7-6-ab", request.operation_id, 30
	)
	var result: Dictionary = fx.router.execute_mutation(
		request, plan, 30, "transition/p7-6-ab"
	)
	_assert_ok(result, "true A+B mutation")
	_assert(String(result.details.get("route", "")) == Router.ROUTE_MULTI_REGION, "A+B mutation routes to MW10")
	_assert(bool(result.details.get("mw10_invoked", false)), "A+B route records MW10 invocation")
	_assert(Array(result.details.get("region_ids", [])) == [MW10Fixture.REGION_A, MW10Fixture.REGION_B], "A+B region set is deterministic")
	_assert(fx.product_gate.intent_calls == 1, "multi-region route checks product intent exactly once")
	_assert(fx.single.calls == 0, "multi-region route bypasses ordinary single-region executor")
	_assert(fx.mw10.calls == 1, "MW10 coordinator called exactly once")

	var replay: Dictionary = fx.router.execute_mutation(
		request, plan, 31, "transition/p7-6-ab-replay"
	)
	_assert_ok(replay, "multi-region replay")
	_assert(String(replay.details.get("route", "")) == Router.ROUTE_MULTI_REGION, "replay remains MW10-owned")
	_assert(fx.single.calls == 0, "replay never falls back to single-region path")


func _test_reservation_interlocks() -> void:
	var fx := _fixture()
	fx.interlock.reservations[MW10Fixture.REGION_B] = "matter-transaction/p7-6-reserved"
	var handoff: Dictionary = fx.router.execute_actor_handoff(MW10Fixture.REGION_B, {
		"transfer_id": "transfer/p7-6/reserved",
		"target_authority_id": AUTHORITY_B,
		"target_authority_epoch": 2,
	})
	_assert_error(
		handoff,
		"MATTER_CROSS_REGION_TRANSACTION_RESERVES_HANDOFF_REGION",
		"MW10 reservation blocks actor handoff"
	)
	_assert(fx.handoff.calls == 0, "blocked handoff never reaches SM1/MW8/MW9 executor")
	var single: Dictionary = fx.router.execute_mutation(_request([fx.address_b]))
	_assert_error(single, "P7_6_SINGLE_REGION_RESERVED_BY_MW10", "MW10 reservation blocks conflicting B-only mutation")
	_assert(fx.single.calls == 0, "reserved single-region mutation never executes")


func _test_plan_binding_and_zero_ownership() -> void:
	var fx := _fixture()
	var request := _request([fx.address_a, fx.address_b], "matter-operation/p7-6-bind")
	var missing: Dictionary = fx.router.execute_mutation(request, {}, 30)
	_assert_error(missing, "P7_6_MW10_PLAN_REQUIRED", "multi-region request without MW10 plan")
	var single_with_plan: Dictionary = fx.router.execute_mutation(
		_request([fx.address_a]),
		MW10Fixture.plan_ab("matter-transaction/p7-6-extra", "matter-operation/p7-6-single-a", 30),
		30
	)
	_assert_error(single_with_plan, "P7_6_MW10_PLAN_FOR_SINGLE_REGION_FORBIDDEN", "single-region route cannot smuggle MW10 plan")

	var wrong_operation: Dictionary = MW10Fixture.plan_ab(
		"matter-transaction/p7-6-wrong-op", "matter-operation/p7-6-other", 30
	)
	_assert_error(
		fx.router.execute_mutation(request, wrong_operation, 30),
		"P7_6_MW10_PLAN_OPERATION_MISMATCH",
		"MW10 plan exact operation binding"
	)
	var wrong_regions: Dictionary = MW10Fixture.plan_bc(
		"matter-transaction/p7-6-wrong-regions", request.operation_id, 30
	)
	_assert_error(
		fx.router.execute_mutation(request, wrong_regions, 30),
		"P7_6_MW10_PLAN_REGION_SET_MISMATCH",
		"MW10 plan exact region-set binding"
	)
	_assert(fx.mw10.calls == 0, "invalid plans never reach MW10 coordinator")

	var report: Dictionary = fx.router.contract_report()
	for field in [
		"canonical_state_owned", "durable_state_owned", "replay_ledger_owned",
		"transaction_state_owned", "handoff_state_owned", "authority_owned",
		"matter_contract_owned", "item_graph_owned", "network_protocol_owned",
	]:
		_assert(not bool(report.get(field, true)), "P7.6 owns no %s" % field)
	_assert(not bool(report.get("actor_seam_implies_mw10", true)), "contract forbids seam=>MW10 shortcut")
	_assert(int(report.get("mw10_minimum_target_regions", 0)) == 2, "MW10 requires at least two target regions")


func _fixture() -> Dictionary:
	var sm1 := SM1.new()
	var configured: Dictionary = sm1.configure(AUTHORITY_A, 1, {
		"logical_player_id": PLAYER,
		"player_entity_id": PLAYER_ENTITY,
		"last_input_sequence": 1,
		"last_operation_id": "operation/p7-6/seed",
	})
	_assert_ok(configured, "SM1 fixture configured")
	var product_gate := ProductGate.new(sm1)
	var resolver := RegionResolver.new()
	var address_a := _address(0)
	var address_b := _address(1)
	resolver.region_by_address[address_a.address_id] = MW10Fixture.REGION_A
	resolver.region_by_address[address_b.address_id] = MW10Fixture.REGION_B
	var single := SingleExecutor.new(sm1)
	var handoff := ActorHandoffExecutor.new(sm1)
	var mw10 := MW10Coordinator.new()
	var interlock := ReservationInterlock.new()
	var router := Router.new()
	var router_config: Dictionary = router.configure(
		product_gate,
		resolver,
		Callable(single, "execute"),
		Callable(handoff, "execute"),
		mw10,
		interlock
	)
	return {
		"configured": router_config,
		"router": router,
		"sm1": sm1,
		"product_gate": product_gate,
		"resolver": resolver,
		"single": single,
		"handoff": handoff,
		"mw10": mw10,
		"interlock": interlock,
		"address_a": address_a,
		"address_b": address_b,
	}


func _request(
	targets: Array,
	operation_id: String = "matter-operation/p7-6-single"
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
			"CAPSULE", [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 0.5
		),
		"source_container_id": "",
		"destination_container_id": "",
		"requested_mass_kg": 0.0,
		"energy_budget_j": 1000.0,
		"client_tick": 10,
	})
	_assert(bool(MatterRequest.validate(value).get("success", false)), "test Matter request validates")
	return value


func _address(index: int) -> Dictionary:
	var cell: Dictionary = CellAddress.create(
		"universe", "p76", "asteroid", "matter", 1, "asteroid-mw10", [index]
	)
	return BrickAddress.create(cell, 0, 0, 0, 0)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [
		message, String(result.get("error_code", ""))
	])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)), "%s rejects" % message)
	_assert(String(result.get("error_code", "")) == error_code, "%s expected=%s actual=%s" % [
		message, error_code, String(result.get("error_code", ""))
	])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
