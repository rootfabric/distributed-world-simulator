extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MatterRequest = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const BrickAddress = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")
const AuthorityGate = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_authority_gate.gd")
const MW10Coordinator = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd")
const PhysicalOutput = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_physical_output.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const ItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const DeliveryCoordinator = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd")
const Slice = preload("res://scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd")

const PLAYER := "miner"
const ACTOR := "player/miner"

var assertions := 0
var failures: Array[String] = []
var roots: Array[String] = []


class Runtime extends RefCounted:
	var prepared: Dictionary = {}

	func prepare_region(participant: Dictionary, context: Dictionary) -> Dictionary:
		var region_id := String(participant["region_id"])
		var key := "%s|%s" % [context["transaction_id"], region_id]
		if not prepared.has(key):
			var previous: Dictionary = participant["previous_source_revision"]
			prepared[key] = SourceRevision.create(
				"MATTER",
				String(previous["source_id"]),
				int(previous["authority_epoch"]),
				int(previous["source_revision"]) + 1,
				MatterUtils.payload_hash([key, "c2-prepared-source"]),
				MatterUtils.payload_hash([key, "c2-prepared-dependency"])
			)
		return MatterUtils.success({
			"source_revision": prepared[key],
			"runtime_state_hash": MatterUtils.payload_hash([key, "c2-prepared-state"]),
		})

	func commit_region(participant: Dictionary, prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		var physical: Dictionary = Fixture.physical_commit_details(
			participant, prepare_receipt, context
		)
		if physical.is_empty():
			return MatterUtils.failure("C2_TEST_PHYSICAL_OUTPUT_CREATION_FAILED")
		physical["runtime_state_hash"] = MatterUtils.payload_hash([
			context["transaction_id"],
			participant["region_id"],
			"c2-committed",
			context["global_commit_hash"],
		])
		return MatterUtils.success(physical)

	func rollback_region(participant: Dictionary, _prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		return MatterUtils.success({
			"source_revision": participant["previous_source_revision"],
			"runtime_state_hash": MatterUtils.payload_hash([
				context["transaction_id"], participant["region_id"], "c2-rollback"
			]),
		})

	func publish_invalidation(_outbox_record: Dictionary) -> Dictionary:
		return MatterUtils.success({"published": true})


class EmptyReceiver extends RefCounted:
	func get_batch(_batch_id: String) -> Dictionary:
		return {}


class MatterService extends RefCounted:
	var receiver := EmptyReceiver.new()

	func material_receiver():
		return receiver


class Router extends RefCounted:
	var response: Dictionary = {}
	var calls := 0

	func execute_mutation(
		_request: Dictionary,
		_plan: Dictionary = {},
		_server_tick: int = 0,
		_transition_prefix: String = ""
	) -> Dictionary:
		calls += 1
		return response.duplicate(true)

	func contract_report() -> Dictionary:
		return {
			"canonical_state_owned": false,
			"multi_region_owner": "MW10",
		}


class Visual extends RefCounted:
	var calls := 0
	var addresses: Array = []

	func invalidate(values: Array) -> Dictionary:
		calls += 1
		addresses = values.duplicate(true)
		return MatterUtils.success({"invalidated": values.size()})


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var plan: Dictionary = Fixture.plan_ab(
		"matter-transaction/p7-7-c2",
		"matter-operation/p7-7-c2"
	)
	_assert(not plan.is_empty(), "C2 MW10 plan created")
	var request: Dictionary = _request(plan, ACTOR)
	_assert_ok(MatterRequest.validate(request), "C2 canonical Matter request")

	var runtime := Runtime.new()
	var mw10 = _mw10(_root("c2"), runtime)
	_assert_ok(mw10.initialize(Fixture.CHECKPOINT_ID, 20), "C2 MW10 initialize")
	var committed: Dictionary = mw10.execute_transaction(plan, "transition/p7-7-c2", 30)
	_assert_ok(committed, "C2 MW10 transaction commits")
	var physical_output: Dictionary = Dictionary(
		committed.get("details", {}).get("physical_output", {})
	)
	_assert_ok(PhysicalOutput.validate(physical_output), "C2 durable physical output validates")
	_assert(Array(physical_output["participant_outputs"]).size() == 2, "C2 physical output has A+B participants")
	_assert(absf(float(physical_output["total_mass_kg"]) - 10.0) <= 0.000001, "C2 physical output mass is 10 kg")

	var graph := ItemGraph.new()
	_assert_ok(graph.setup("authority/p7-7-c2-item-graph", 1), "C2 canonical Item Graph setup")
	graph.ensure_player(PLAYER)
	var delivery := DeliveryCoordinator.new()
	_assert_ok(delivery.configure(MatterService.new(), graph), "C2 bind existing P7.3 coordinator")
	var delivery_contract: Dictionary = delivery.contract_report()
	_assert(
		String(delivery_contract.get("cross_region_matter_owner", "")) == "MW10_DURABLE_PHYSICAL_OUTPUT",
		"C2 delivery declares MW10 physical source"
	)
	_assert(
		String(delivery_contract.get("exactly_once_owner", "")) == "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER",
		"C2 exactly-once remains Item Graph owned"
	)
	_assert(not bool(delivery_contract.get("delivery_receipt_store", true)), "C2 adds no delivery receipt store")

	var router := Router.new()
	router.response = MatterUtils.success({
		"route": Slice.ROUTE_MULTI_REGION,
		"region_ids": [Fixture.REGION_A, Fixture.REGION_B],
		"mw10_invoked": true,
		"execution_result": committed,
	})
	var visual := Visual.new()
	var slice := Slice.new()
	_assert_ok(
		slice.configure(router, delivery, Callable(visual, "invalidate")),
		"C2 graphical slice configure"
	)
	var binding := {
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
		"server_tick": 100,
		"transition_prefix": "transition/p7-7-c2-product",
	}

	var before: Dictionary = graph.create_snapshot()
	var first: Dictionary = slice.execute_aimed_dig(binding)
	_assert_ok(first, "C2 first A+B graphical delivery")
	var first_details: Dictionary = Dictionary(first.get("details", {}))
	_assert(String(first_details.get("route", "")) == Slice.ROUTE_MULTI_REGION, "C2 route is MW10")
	_assert(bool(first_details.get("mw10_invoked", false)), "C2 reports MW10 invoked")
	_assert(String(first_details.get("visible_hole_source", "")) == "CANONICAL_MW10_PHYSICAL_OUTPUT", "C2 visible hole derives from MW10 physical output")
	_assert(String(first_details.get("inventory_source", "")) == "CANONICAL_ITEM_GRAPH", "C2 inventory remains Item Graph")
	_assert(int(first_details.get("changed_brick_count", 0)) == 2, "C2 aggregates A+B canonical changed bricks")
	_assert(absf(float(first_details.get("removed_mass_kg", 0.0)) - 10.0) <= 0.000001, "C2 reports durable total removed mass")
	var material: Dictionary = Dictionary(first_details.get("material_delivery", {}))
	_assert(int(material.get("participant_delivery_count", 0)) == 2, "C2 delivers two canonical regional batches")
	_assert(int(material.get("fresh_delivery_count", 0)) == 2, "C2 first delivery has two fresh batches")
	_assert(int(material.get("replay_delivery_count", -1)) == 0, "C2 first delivery has no batch replay")
	_assert(int(material.get("total_output_quantity", 0)) == 10, "C2 Item Graph receives 7+3 ore units")
	var deliveries: Array = material.get("deliveries", [])
	_assert(deliveries.size() == 2, "C2 delivery receipt view has A+B")
	_assert(String(deliveries[0].get("region_id", "")) == Fixture.REGION_A, "C2 delivers A first deterministically")
	_assert(String(deliveries[1].get("region_id", "")) == Fixture.REGION_B, "C2 delivers B second deterministically")
	_assert(visual.calls == 1 and visual.addresses.size() == 2, "C2 visual invalidation covers A+B once")
	var after_first: Dictionary = graph.create_snapshot()
	_assert(String(after_first.get("checksum", "")) != String(before.get("checksum", "")), "C2 first delivery mutates canonical Item Graph")
	_assert(_ore_quantity(after_first) == 10, "C2 canonical Item Graph contains exactly 10 ore units")

	var replay: Dictionary = slice.execute_aimed_dig(binding)
	_assert_ok(replay, "C2 exact graphical replay")
	var replay_material: Dictionary = Dictionary(
		replay.get("details", {}).get("material_delivery", {})
	)
	_assert(int(replay_material.get("participant_delivery_count", 0)) == 2, "C2 replay covers both batches")
	_assert(int(replay_material.get("fresh_delivery_count", -1)) == 0, "C2 replay creates no fresh batch output")
	_assert(int(replay_material.get("replay_delivery_count", 0)) == 2, "C2 replay is exactly-once for both batches")
	_assert(graph.create_snapshot() == after_first, "C2 replay leaves Item Graph byte-identical")
	_assert(_ore_quantity(graph.create_snapshot()) == 10, "C2 replay does not duplicate ore")
	_assert(visual.calls == 2, "C2 replay may re-drive derived visual invalidation without canonical duplication")

	graph.ensure_player("other")
	var wrong_request := _request(plan, "player/other")
	var before_conflict: Dictionary = graph.create_snapshot()
	var redirected: Dictionary = delivery.deliver_cross_region_committed(
		wrong_request, physical_output
	)
	_assert(not bool(redirected.get("success", false)), "C2 same batches cannot redirect to another player")
	_assert(String(redirected.get("error_code", "")) == "P7_ITEM_GRAPH_OUTPUT_REJECTED", "C2 redirect rejected by canonical Item Graph")
	_assert(graph.create_snapshot() == before_conflict, "C2 redirect conflict is mutation-free")

	_cleanup()
	if failures.is_empty():
		print("V0-P7.7-C2 MW10 physical output to P7.3: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("V0-P7.7-C2 MW10 physical output to P7.3: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size()
		])
		quit(1)


func _request(plan: Dictionary, actor_id: String) -> Dictionary:
	var targets: Array = []
	var expected: Dictionary = {}
	var index := 0
	for raw_participant in Array(plan.get("participants", [])):
		var participant: Dictionary = raw_participant
		var address: Dictionary = BrickAddress.create(
			participant["region_root_address"],
			1,
			index,
			0,
			0
		)
		targets.append(address)
		expected[String(address["address_id"])] = 0
		index += 1
	return MatterRequest.create({
		"operation_id": plan["operation_id"],
		"body_id": plan["body_id"],
		"actor_id": actor_id,
		"tool_id": "item/tool/p7-7-c2-drill",
		"operation_type": "EXCAVATE",
		"target_bricks": targets,
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


func _mw10(root: String, runtime: Runtime):
	var gate := AuthorityGate.new()
	_assert_ok(gate.configure(Fixture.lease_provider()), "C2 authority gate configure")
	var coordinator := MW10Coordinator.new()
	_assert_ok(coordinator.configure(root, gate, runtime), "C2 MW10 coordinator configure")
	return coordinator


func _ore_quantity(snapshot: Dictionary) -> int:
	var total := 0
	for raw_item in Array(snapshot.get("items", [])):
		if typeof(raw_item) == TYPE_DICTIONARY \
				and String(raw_item.get("definition_id", "")) == "item/ore":
			total += int(raw_item.get("quantity", 0))
	return total


func _root(label: String) -> String:
	var path := ProjectSettings.globalize_path(
		"user://p7-7-%s-%d" % [label, Time.get_ticks_usec()]
	)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	roots.append(path)
	return path


func _cleanup() -> void:
	for root in roots:
		_remove_tree(root)


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


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failures.append(message)
