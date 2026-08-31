extends SceneTree

const BatchScript = preload(
	"res://scripts/simulation/matter/contracts/matter_material_batch.gd"
)
const CompositionScript = preload(
	"res://scripts/simulation/matter/contracts/matter_composition.gd"
)
const ItemGraphScript = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const PolicyScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_policy.gd"
)
const AdapterScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_material_item_graph_adapter.gd"
)
const CoordinatorScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd"
)
const BubbleScript = preload("res://scripts/world/matter/lunar_matter_bubble.gd")

const PLAYER := "miner"
const ACTOR_ID := "player/miner"
const TOOL_ID := "item/tool/p7-3-test"
const SURFACE_RADIUS_M: float = 1737425.0

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_explicit_quantization_policy()
	_test_canonical_item_graph_exactly_once()
	_test_failure_is_mutation_free()
	_test_real_mw4_batch_delivery()
	print("V0-P7.3 material batch to Item Graph: PASS (%d assertions, %d failures)" % [
		_assertions, _failures,
	])
	quit(0 if _failures == 0 else 1)


func _test_explicit_quantization_policy() -> void:
	var batch := _batch(
		"matter-batch/p7-3-policy",
		"operation/p7-3/policy",
		12.75,
		[
			{"material_id": "matter/regolith-loose", "mass_fraction": 0.4},
			{"material_id": "matter/basalt", "mass_fraction": 0.6},
		]
	)
	_assert_true(not batch.is_empty(), "policy fixture batch valid")
	var planned: Dictionary = PolicyScript.plan(batch)
	_assert_success(planned, "explicit policy accepts supported lunar composition")
	var details: Dictionary = planned.get("details", {})
	_assert_true(String(details.get("policy_id", "")) == PolicyScript.POLICY_ID, "policy identity explicit")
	_assert_true(String(details.get("output_definition_id", "")) == "item/ore", "lunar geological matter maps explicitly to existing item/ore")
	_assert_true(absf(float(details.get("kg_per_item_unit", 0.0)) - 1.0) < 0.000000001, "one Item Graph ore unit represents one kilogram in P7.3 policy")
	_assert_true(int(details.get("output_quantity", -1)) == 12, "mass conversion floors to whole Item Graph units")
	_assert_true(absf(float(details.get("represented_mass_kg", -1.0)) - 12.0) < 0.000000001, "represented mass is explicit")
	_assert_true(absf(float(details.get("residual_mass_kg", -1.0)) - 0.75) < 0.000000001, "fractional residual is explicit")
	_assert_true(absf(float(details.get("conservation_error_kg", 1.0))) < 0.000000001, "removed mass closes as represented plus residual")
	_assert_true(String(details.get("delivery_status", "")) == "DELIVERABLE", "whole units are deliverable")
	var repeated: Dictionary = PolicyScript.plan(batch)
	_assert_true(repeated == planned, "same immutable batch yields byte-stable delivery plan")

	var residual_only := _batch(
		"matter-batch/p7-3-residual",
		"operation/p7-3/residual",
		0.75,
		[{"material_id": "matter/regolith-loose", "mass_fraction": 1.0}]
	)
	var residual_plan: Dictionary = PolicyScript.plan(residual_only)
	_assert_success(residual_plan, "sub-unit batch remains valid provenance")
	_assert_true(int(residual_plan.get("details", {}).get("output_quantity", -1)) == 0, "sub-unit mass does not round up")
	_assert_true(absf(float(residual_plan.get("details", {}).get("residual_mass_kg", -1.0)) - 0.75) < 0.000000001, "sub-unit batch mass is fully residual-accounted")
	_assert_true(String(residual_plan.get("details", {}).get("delivery_status", "")) == "RESIDUAL_ONLY", "sub-unit policy status explicit")

	var unsupported := _batch(
		"matter-batch/p7-3-ice",
		"operation/p7-3/ice",
		2.0,
		[{"material_id": "matter/water-ice", "mass_fraction": 1.0}]
	)
	_assert_error(PolicyScript.plan(unsupported), "P7_UNSUPPORTED_MATTER_MATERIAL", "bounded P7.3 policy rejects undeclared material mapping")
	var contract := PolicyScript.contract_report()
	_assert_true(not bool(contract.get("new_canonical_state_owned", true)), "conversion policy owns no canonical state")
	_assert_true(not bool(contract.get("delivery_receipt_store", true)), "conversion policy creates no receipt store")
	_assert_true(String(contract.get("exactly_once_owner", "")) == "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER", "existing Item Graph owns exactly-once")


func _test_canonical_item_graph_exactly_once() -> void:
	var graph = _graph("authority/p7-3/item-graph/1")
	var adapter = AdapterScript.new()
	_assert_success(adapter.configure(graph), "bind canonical Item Graph")
	var batch := _batch(
		"matter-batch/p7-3/exactly-once",
		"operation/p7-3/exactly-once",
		4.4,
		[{"material_id": "matter/regolith-compacted", "mass_fraction": 1.0}]
	)
	var before: Dictionary = graph.create_snapshot()
	var delivered: Dictionary = adapter.deliver(batch, PLAYER)
	_assert_success(delivered, "first canonical Item Graph delivery")
	var first: Dictionary = delivered.get("details", {})
	_assert_true(not bool(first.get("replay", true)), "first delivery is fresh")
	_assert_true(bool(first.get("item_graph_mutated", false)), "first delivery mutates canonical Item Graph once")
	_assert_true(int(first.get("output_quantity", 0)) == 4, "Item Graph receives deterministic whole-mass quantity")
	_assert_true(
		String(first.get("source_id", "")).begins_with("%s/" % String(batch.get("batch_id", ""))),
		"canonical server-output provenance binds batch id and immutable checksum"
	)
	var after_first: Dictionary = graph.create_snapshot()
	_assert_true(String(after_first.get("checksum", "")) != String(before.get("checksum", "")), "first delivery changes canonical Item Graph checksum")
	var output_item_id := String(first.get("output_item_id", ""))
	var output_item := _find_item(after_first, output_item_id)
	_assert_true(String(output_item.get("definition_id", "")) == "item/ore", "output lives in canonical Item Graph as existing ore definition")
	_assert_true(int(output_item.get("quantity", 0)) == 4, "canonical item quantity equals delivery plan")

	var replay: Dictionary = adapter.deliver(batch, PLAYER)
	_assert_success(replay, "same batch replay succeeds")
	_assert_true(bool(replay.get("details", {}).get("replay", false)), "same batch reuses Item Graph replay ledger")
	_assert_true(not bool(replay.get("details", {}).get("item_graph_mutated", true)), "replay does not mutate Item Graph")
	_assert_true(graph.create_snapshot() == after_first, "replay is byte-stable and creates no duplicate item")
	_assert_true(String(replay.get("details", {}).get("output_item_id", "")) == output_item_id, "replay returns same output item identity")

	# Same batch identity with different immutable physical content but the same
	# floored gameplay quantity must not masquerade as an Item Graph replay.
	var conflicting_batch := _batch(
		String(batch.get("batch_id", "")),
		String(batch.get("source_operation_id", "")),
		4.8,
		[{"material_id": "matter/regolith-compacted", "mass_fraction": 1.0}]
	)
	var conflicting: Dictionary = adapter.deliver(conflicting_batch, PLAYER)
	_assert_error(conflicting, "P7_ITEM_GRAPH_OUTPUT_REJECTED", "same batch id with changed physical content fails closed")
	_assert_true(
		String(conflicting.get("details", {}).get("cause", "")) == "OPERATION_REPLAY_CONFLICT",
		"immutable batch checksum participates in canonical replay fingerprint"
	)
	_assert_true(graph.create_snapshot() == after_first, "batch-content conflict is Item Graph mutation-free")

	graph.ensure_player("other")
	var before_wrong_target: Dictionary = graph.create_snapshot()
	var wrong_target: Dictionary = adapter.deliver(batch, "other")
	_assert_error(wrong_target, "P7_ITEM_GRAPH_OUTPUT_REJECTED", "same batch cannot be redirected to a second player")
	_assert_true(String(wrong_target.get("details", {}).get("cause", "")) == "OPERATION_REPLAY_CONFLICT", "cross-player replay conflict fails closed")
	_assert_true(graph.create_snapshot() == before_wrong_target, "cross-player conflict is mutation-free")


func _test_failure_is_mutation_free() -> void:
	var graph = _graph("authority/p7-3/full-inventory")
	for index in range(32):
		var filled: Dictionary = graph.apply_server_output(
			"operation/p7-3/fill/%d" % index,
			PLAYER,
			"item/filler",
			1,
			"source/p7-3/fill/%d" % index
		)
		_assert_success(filled, "fill inventory slot %d" % index)
	var before: Dictionary = graph.create_snapshot()
	var adapter = AdapterScript.new()
	_assert_success(adapter.configure(graph), "bind full canonical Item Graph")
	var batch := _batch(
		"matter-batch/p7-3/full",
		"operation/p7-3/full",
		3.2,
		[{"material_id": "matter/fractured-basalt", "mass_fraction": 1.0}]
	)
	var rejected: Dictionary = adapter.deliver(batch, PLAYER)
	_assert_error(rejected, "P7_ITEM_GRAPH_OUTPUT_REJECTED", "full inventory rejects delivery")
	_assert_true(String(rejected.get("details", {}).get("cause", "")) == "CONTAINER_FULL", "canonical Item Graph owns capacity rejection")
	_assert_true(graph.create_snapshot() == before, "delivery rejection does not mutate Item Graph")

	var residual_batch := _batch(
		"matter-batch/p7-3/residual-adapter",
		"operation/p7-3/residual-adapter",
		0.2,
		[{"material_id": "matter/basalt", "mass_fraction": 1.0}]
	)
	var residual: Dictionary = adapter.deliver(residual_batch, PLAYER)
	_assert_success(residual, "residual-only batch needs no inventory capacity")
	_assert_true(not bool(residual.get("details", {}).get("item_graph_mutated", true)), "residual-only delivery does not mutate Item Graph")
	_assert_true(graph.create_snapshot() == before, "residual-only accounting leaves Item Graph byte-identical")


func _test_real_mw4_batch_delivery() -> void:
	var bubble = BubbleScript.new()
	_assert_success(bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
		"half_extent_m": 32.0,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 3,
		"brick_interior_resolution": 8,
		"ghost_border_samples": 1,
	}), "configure real P7 lunar Matter bubble")
	var center := bubble.anchor_body_fixed_m()
	var request := bubble.create_excavation_request(
		"operation/p7-3/real-mw4",
		ACTOR_ID,
		TOOL_ID,
		center + Vector3(2.5, -0.5, 0.0),
		center + Vector3(3.5, -0.5, 0.0),
		0.75,
		1000000000.0,
		1
	)
	_assert_true(not request.is_empty(), "real MW4 excavation request created")
	var result: Dictionary = bubble.execute(request)
	_assert_true(String(result.get("status", "")) == "COMMITTED", "real MW4 excavation commits")
	_assert_true(Array(result.get("created_aggregate_ids", [])).size() == 1, "real MW4 emits exactly one MatterMaterialBatch")
	var batch_id := String(Array(result.get("created_aggregate_ids", []))[0])
	var receiver = bubble.excavation_service().material_receiver()
	var batch: Dictionary = receiver.get_batch(batch_id)
	_assert_true(not batch.is_empty(), "real committed batch retained by existing MW4 receiver")
	_assert_true(String(batch.get("source_operation_id", "")) == String(request.get("operation_id", "")), "batch provenance binds exact Matter operation")
	_assert_true(absf(float(batch.get("total_mass_kg", 0.0)) - float(result.get("removed_mass_kg", 0.0))) < 0.001, "MW4 removed mass equals batch mass")
	var receiver_before: Dictionary = receiver.export_persistence_state()

	# Cross-domain failure safety: Matter is already committed when Item Graph
	# delivery is attempted. A full canonical inventory must reject the output
	# without mutating either Item Graph or the existing MW4 receiver batch, so a
	# later retry against available capacity can recover using the same batch.
	var full_graph = _graph("authority/p7-3/real-full")
	_assert_true(_fill_inventory(full_graph), "fill canonical inventory for real post-Matter failure")
	var full_coordinator = CoordinatorScript.new()
	_assert_success(
		full_coordinator.configure(bubble.excavation_service(), full_graph),
		"configure failure-path coordinator over existing owners"
	)
	var full_graph_before: Dictionary = full_graph.create_snapshot()
	var rejected_delivery: Dictionary = full_coordinator.deliver_committed(request, result)
	_assert_error(
		rejected_delivery,
		"P7_ITEM_GRAPH_OUTPUT_REJECTED",
		"committed Matter batch survives canonical inventory capacity rejection"
	)
	_assert_true(
		String(rejected_delivery.get("details", {}).get("cause", "")) == "CONTAINER_FULL",
		"real failure is owned by canonical Item Graph capacity"
	)
	_assert_true(full_graph.create_snapshot() == full_graph_before, "real failed delivery is Item Graph mutation-free")
	_assert_true(receiver.export_persistence_state() == receiver_before, "real failed delivery preserves MW4 batch for retry")

	var graph = _graph("authority/p7-3/real")
	var coordinator = CoordinatorScript.new()
	_assert_success(coordinator.configure(bubble.excavation_service(), graph), "configure stateless P7.3 coordinator over existing owners")
	var contract := coordinator.contract_report()
	_assert_true(not bool(contract.get("canonical_state_owned", true)), "coordinator owns no canonical state")
	_assert_true(not bool(contract.get("delivery_receipt_store", true)), "coordinator has no delivery receipt store")
	var delivered: Dictionary = coordinator.deliver_committed(request, result)
	_assert_success(delivered, "real MW4 batch delivers into canonical Item Graph")
	var delivery: Dictionary = delivered.get("details", {}).get("delivery", {})
	_assert_true(int(delivery.get("output_quantity", 0)) > 0, "real lunar excavation produces gameplay ore units")
	_assert_true(absf(
		float(delivery.get("total_mass_kg", 0.0))
		- float(delivery.get("represented_mass_kg", 0.0))
		- float(delivery.get("residual_mass_kg", 0.0))
	) < 0.000000001, "real batch mass conserved through represented plus residual accounting")
	_assert_true(float(delivery.get("residual_mass_kg", -1.0)) >= 0.0 and float(delivery.get("residual_mass_kg", 2.0)) < 1.0 + 0.000000001, "real residual is bounded below one policy unit")
	_assert_true(receiver.export_persistence_state() == receiver_before, "Item Graph delivery does not mutate Matter receiver provenance")
	var graph_after: Dictionary = graph.create_snapshot()
	var item := _find_item(graph_after, String(delivery.get("output_item_id", "")))
	_assert_true(not item.is_empty(), "real Matter output item exists in canonical graph")
	_assert_true(int(item.get("quantity", -1)) == int(delivery.get("output_quantity", -2)), "real output quantity matches conserved delivery plan")

	var replay: Dictionary = coordinator.deliver_committed(request, result)
	_assert_success(replay, "real committed batch delivery replay succeeds")
	_assert_true(bool(replay.get("details", {}).get("delivery", {}).get("replay", false)), "real delivery replay is exactly-once")
	_assert_true(graph.create_snapshot() == graph_after, "real delivery replay does not duplicate inventory")
	_assert_true(receiver.export_persistence_state() == receiver_before, "delivery replay leaves Matter receiver byte-identical")

	var fake_request := request.duplicate(true)
	fake_request["actor_id"] = "player/other"
	# Rebuild checksum by using the canonical request constructor is intentionally
	# not attempted here: a tampered request must fail validation before delivery.
	_assert_error(coordinator.deliver_committed(fake_request, result), "P7_INVALID_MATTER_REQUEST", "tampered actor request cannot redirect real batch")


func _fill_inventory(graph) -> bool:
	for index in range(32):
		var filled: Dictionary = graph.apply_server_output(
			"operation/p7-3/real-fill/%d" % index,
			PLAYER,
			"item/filler",
			1,
			"source/p7-3/real-fill/%d" % index
		)
		if not bool(filled.get("success", false)):
			return false
	return true


func _graph(authority_id: String):
	var graph = ItemGraphScript.new()
	_assert_success(graph.setup(authority_id, 1), "setup canonical Item Graph")
	graph.ensure_player(PLAYER)
	return graph


func _batch(
	batch_id: String,
	operation_id: String,
	mass_kg: float,
	components: Array
) -> Dictionary:
	var composition := CompositionScript.create(components)
	if not bool(CompositionScript.validate(composition).get("success", false)):
		return {}
	var batch := BatchScript.create({
		"batch_id": batch_id,
		"container_id": "container/p7-3/test",
		"source_body_id": "body/moon",
		"source_operation_id": operation_id,
		"total_mass_kg": mass_kg,
		"bulk_volume_m3": maxf(mass_kg / 1500.0, 0.000001),
		"composition": composition,
		"temperature_k": 150.0,
	})
	return batch if bool(BatchScript.validate(batch).get("success", false)) else {}


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert_true(not bool(result.get("success", false)), "%s rejects" % message)
	_assert_true(
		String(result.get("error_code", "")) == error_code,
		"%s error=%s actual=%s" % [
			message,
			error_code,
			String(result.get("error_code", "")),
		]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P7.3] %s" % message)
