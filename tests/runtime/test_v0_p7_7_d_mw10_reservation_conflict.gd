extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MatterRequest = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const BrickAddress = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const MW10Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")
const MW10AuthorityGate = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_authority_gate.gd")
const MW10Coordinator = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd")
const HandoffInterlock = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_handoff_interlock.gd")
const Router = preload("res://scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd")
const Slice = preload("res://scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd")

const ACTOR := "player/miner"
const TOOL := "item/tool/p7-7-d-drill"

var assertions := 0
var failures: Array[String] = []
var roots: Array[String] = []


class ProductGate extends RefCounted:
	var calls := 0

	func authorize_product_intent(_request: Dictionary) -> Dictionary:
		calls += 1
		return MatterUtils.success({"authorized": true})


class Resolver extends RefCounted:
	var mapping: Dictionary = {}

	func resolve_brick_address(address: Dictionary) -> Dictionary:
		var region_id := String(mapping.get(String(address.get("address_id", "")), ""))
		return {} if region_id.is_empty() else {"region_id": region_id}


class SingleExecutor extends RefCounted:
	var calls := 0

	func execute(_request: Dictionary) -> Dictionary:
		calls += 1
		return MatterUtils.success({"owner": "MW4"})


class HandoffExecutor extends RefCounted:
	var calls := 0

	func execute(_region_id: String, _context: Dictionary) -> Dictionary:
		calls += 1
		return MatterUtils.success({"owner": "SM1"})


class Runtime extends RefCounted:
	var prepare_calls := 0
	var commit_calls := 0
	var rollback_calls := 0
	var publish_calls := 0

	func prepare_region(_participant: Dictionary, _context: Dictionary) -> Dictionary:
		prepare_calls += 1
		return MatterUtils.failure("P7_7_D_PREPARE_MUST_NOT_RUN")

	func commit_region(
		_participant: Dictionary,
		_prepare_receipt: Dictionary,
		_context: Dictionary
	) -> Dictionary:
		commit_calls += 1
		return MatterUtils.failure("P7_7_D_COMMIT_MUST_NOT_RUN")

	func rollback_region(
		_participant: Dictionary,
		_prepare_receipt: Dictionary,
		_context: Dictionary
	) -> Dictionary:
		rollback_calls += 1
		return MatterUtils.failure("P7_7_D_ROLLBACK_MUST_NOT_RUN")

	func publish_invalidation(_outbox_record: Dictionary) -> Dictionary:
		publish_calls += 1
		return MatterUtils.failure("P7_7_D_PUBLISH_MUST_NOT_RUN")


class Delivery extends RefCounted:
	var calls := 0

	func deliver_committed(_request: Dictionary, _result: Dictionary) -> Dictionary:
		calls += 1
		return MatterUtils.failure("P7_7_D_DELIVERY_MUST_NOT_RUN")

	func deliver_cross_region_committed(
		_request: Dictionary,
		_physical_output: Dictionary
	) -> Dictionary:
		calls += 1
		return MatterUtils.failure("P7_7_D_DELIVERY_MUST_NOT_RUN")

	func contract_report() -> Dictionary:
		return {
			"canonical_state_owned": false,
			"exactly_once_owner": "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER",
		}


class Visual extends RefCounted:
	var calls := 0

	func invalidate(_addresses: Array) -> Dictionary:
		calls += 1
		return MatterUtils.failure("P7_7_D_VISUAL_MUST_NOT_RUN")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var active_plan: Dictionary = MW10Fixture.plan_ab(
		"matter-transaction/p7-7-d-active",
		"matter-operation/p7-7-d-active",
		30
	)
	_assert(not active_plan.is_empty(), "D active A+B plan created")

	var authority_gate := MW10AuthorityGate.new()
	_assert_ok(authority_gate.configure(MW10Fixture.lease_provider()), "D MW10 authority gate")
	var runtime := Runtime.new()
	var mw10 := MW10Coordinator.new()
	_assert_ok(mw10.configure(_root("mw10"), authority_gate, runtime), "D MW10 coordinator")
	_assert_ok(mw10.initialize("matter-cross-region-checkpoint/p7-7-d", 20), "D MW10 initialize")
	var begun: Dictionary = mw10.begin_transaction(
		active_plan,
		"transition/p7-7-d-active-begin",
		30
	)
	_assert_ok(begun, "D active A+B transaction reserves regions")
	_assert(Array(mw10.checkpoint().get("region_reservations", [])).size() == 2, "D active transaction owns two reservations")
	_assert(runtime.prepare_calls == 0 and runtime.commit_calls == 0, "D active reservation has not mutated Matter")

	var interlock := HandoffInterlock.new()
	_assert_ok(interlock.configure(mw10), "D reservation interlock")
	var address_a := _address(active_plan, MW10Fixture.REGION_A, 0)
	var address_b := _address(active_plan, MW10Fixture.REGION_B, 1)
	var resolver := Resolver.new()
	resolver.mapping[String(address_a["address_id"])] = MW10Fixture.REGION_A
	resolver.mapping[String(address_b["address_id"])] = MW10Fixture.REGION_B
	var single := SingleExecutor.new()
	var handoff := HandoffExecutor.new()
	var product_gate := ProductGate.new()
	var router := Router.new()
	_assert_ok(router.configure(
		product_gate,
		resolver,
		Callable(single, "execute"),
		Callable(handoff, "execute"),
		mw10,
		interlock
	), "D P7.6 router")

	var delivery := Delivery.new()
	var visual := Visual.new()
	var slice := Slice.new()
	_assert_ok(slice.configure(router, delivery, Callable(visual, "invalidate")), "D graphical slice")

	var b_request := _request(
		"matter-operation/p7-7-d-b-only",
		String(active_plan["body_id"]),
		[address_b]
	)
	var before_checkpoint: Dictionary = mw10.checkpoint()
	var b_conflict: Dictionary = slice.execute_aimed_dig(_binding(b_request, {}))
	_assert_error(
		b_conflict,
		"P7_6_SINGLE_REGION_RESERVED_BY_MW10",
		"D B-only dig during A+B reservation"
	)
	_assert(single.calls == 0, "D reservation blocks B-only dig before MW4")
	_assert(runtime.prepare_calls == 0 and runtime.commit_calls == 0, "D B-only conflict causes no MW10 runtime mutation")
	_assert(delivery.calls == 0, "D B-only conflict causes no material delivery")
	_assert(visual.calls == 0, "D B-only conflict causes no visual success")
	_assert(mw10.checkpoint() == before_checkpoint, "D B-only conflict leaves MW10 checkpoint byte-identical")

	var conflict_plan: Dictionary = MW10Fixture.plan_ab(
		"matter-transaction/p7-7-d-conflict",
		"matter-operation/p7-7-d-conflict",
		31
	)
	_assert(not conflict_plan.is_empty(), "D second A+B plan created")
	var ab_request := _request(
		String(conflict_plan["operation_id"]),
		String(conflict_plan["body_id"]),
		[address_a, address_b]
	)
	var multi_before: Dictionary = mw10.checkpoint()
	var ab_conflict: Dictionary = slice.execute_aimed_dig(
		_binding(ab_request, conflict_plan)
	)
	_assert_error(
		ab_conflict,
		"MATTER_CROSS_REGION_REGION_ALREADY_RESERVED",
		"D second A+B dig during active reservation"
	)
	_assert(product_gate.calls == 1, "D second A+B reaches product authorization exactly once")
	_assert(runtime.prepare_calls == 0, "D second A+B conflict stops before prepare")
	_assert(runtime.commit_calls == 0, "D second A+B conflict stops before regional commit")
	_assert(runtime.rollback_calls == 0, "D second A+B conflict needs no rollback because nothing mutated")
	_assert(runtime.publish_calls == 0, "D second A+B conflict publishes no invalidation")
	_assert(delivery.calls == 0, "D second A+B conflict delivers no material")
	_assert(visual.calls == 0, "D second A+B conflict reports no visual success")
	_assert(single.calls == 0, "D second A+B conflict never falls back to MW4")
	_assert(mw10.checkpoint() == multi_before, "D second A+B conflict leaves checkpoint byte-identical")
	_assert(
		String(interlock.reserved_transaction(MW10Fixture.REGION_A).get("transaction_id", ""))
			== String(active_plan["transaction_id"]),
		"D A reservation remains owned by original transaction"
	)
	_assert(
		String(interlock.reserved_transaction(MW10Fixture.REGION_B).get("transaction_id", ""))
			== String(active_plan["transaction_id"]),
		"D B reservation remains owned by original transaction"
	)

	_cleanup()
	_finish()


func _address(plan: Dictionary, region_id: String, x: int) -> Dictionary:
	var participant: Dictionary = {}
	for raw_participant in Array(plan.get("participants", [])):
		if String(raw_participant.get("region_id", "")) == region_id:
			participant = raw_participant
			break
	return BrickAddress.create(
		participant["region_root_address"],
		1,
		x,
		0,
		0
	)


func _request(operation_id: String, body_id: String, addresses: Array) -> Dictionary:
	var expected: Dictionary = {}
	for raw_address in addresses:
		var address: Dictionary = raw_address
		expected[String(address["address_id"])] = 0
	return MatterRequest.create({
		"operation_id": operation_id,
		"body_id": body_id,
		"actor_id": ACTOR,
		"tool_id": TOOL,
		"operation_type": "EXCAVATE",
		"target_bricks": addresses,
		"expected_revision_by_address": expected,
		"shape": MatterRequest.create_shape(
			"CAPSULE",
			[0.0, 0.0, 0.0],
			[1.0, 0.0, 0.0],
			1.0
		),
		"source_container_id": "",
		"destination_container_id": "",
		"requested_mass_kg": 0.0,
		"energy_budget_j": 1000.0,
		"client_tick": 1,
	})


func _binding(request: Dictionary, plan: Dictionary) -> Dictionary:
	return {
		"query_result": {
			"success": true,
			"error_code": "",
			"details": {
				"hit": true,
				"position_m": Vector3.ZERO,
				"sample": {"signed_distance_m": 0.0},
			},
		},
		"request": request,
		"mw10_plan": plan,
		"server_tick": 40,
		"transition_prefix": "transition/p7-7-d",
	}


func _root(label: String) -> String:
	var path := ProjectSettings.globalize_path(
		"user://p7-7-d-%s-%d" % [label, Time.get_ticks_usec()]
	)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	roots.append(path)
	return path


func _cleanup() -> void:
	for path in roots:
		_remove_tree(path)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P7.7-D MW10 reservation conflict: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("V0-P7.7-D MW10 reservation conflict: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size(),
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
	if not condition:
		failures.append(message)
