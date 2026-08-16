extends SceneTree

const CanonicalItemGraph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const ResourceMiningService = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_service.gd"
)
const EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)
const ResourceSnapshot = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_snapshot.gd"
)

const NODE_ID := "resource/earth/ore-demo/1"
const AUTHORITY_ID := "authority/v0-p3/domain-test"

var assertions := 0
var failures: Array[String] = []


class FakeRejectingItemGraph:
	extends RefCounted
	var preflight_calls := 0
	var apply_calls := 0

	func preflight_server_output(
		_operation_id: String,
		_logical_player_id: String,
		_definition_id: String,
		_quantity: int,
		_source_id: String = ""
	) -> Dictionary:
		preflight_calls += 1
		return {"success": false, "error_code": "FORCED_OUTPUT_REJECTION", "details": {}}

	func apply_server_output(
		_operation_id: String,
		_logical_player_id: String,
		_definition_id: String,
		_quantity: int,
		_source_id: String = ""
	) -> Dictionary:
		apply_calls += 1
		return {"success": false, "error_code": "UNEXPECTED_APPLY", "details": {}}


func _init() -> void:
	_test_catalog_and_earth_projection()
	_test_trusted_item_output_is_not_client_routable()
	_test_mine_replay_and_rejection_purity()
	_test_output_preflight_failure_is_atomic()
	_test_fresh_recovery_preserves_replay()
	_finish()


func _test_catalog_and_earth_projection() -> void:
	var context := _new_context()
	if context.is_empty():
		return
	var service = context["service"]
	var resolver = context["resolver"]
	var snapshot: Dictionary = service.create_snapshot()
	_assert(bool(ResourceSnapshot.validate(snapshot).get("success", false)), "resource snapshot validates")
	_assert(int(snapshot.get("generation", 0)) == 1, "initial resource generation is one")
	var node: Dictionary = service.get_node(NODE_ID)
	_assert(int(node.get("remaining_units", -1)) == 8, "canonical ore node starts with eight units")
	_assert(String(node.get("output_definition_id", "")) == "item/ore", "canonical ore node outputs item/ore")
	var resolved: Dictionary = resolver.resolve_planar(Dictionary(node.get("spatial", {})))
	_assert(bool(resolved.get("success", false)), "Earth-fixed resource position resolves into MVP tangent plane")
	if bool(resolved.get("success", false)):
		var target: Dictionary = Dictionary(resolved.get("details", {}).get("planar_position", {}))
		var distance_from_spawn := sqrt(
			float(target.get("x", 0.0)) * float(target.get("x", 0.0))
			+ float(target.get("z", 0.0)) * float(target.get("z", 0.0))
		)
		_assert(distance_from_spawn > 5.0 and distance_from_spawn < 10.0, "first ore node is near but not inside spawn mining range")


func _test_trusted_item_output_is_not_client_routable() -> void:
	var context := _new_context()
	if context.is_empty():
		return
	var graph = context["graph"]
	var before: Dictionary = graph.create_snapshot()
	var attempted: Dictionary = graph.execute(
		"a",
		1,
		"operation/v0-p3/client-server-output",
		"server.output",
		{"definition_id": "item/ore", "quantity": 1},
		{}
	)
	_assert(not bool(attempted.get("success", false)), "client execute cannot invoke trusted server output")
	_assert(String(attempted.get("error_code", "")) == "UNSUPPORTED_ITEM_COMMAND", "client trusted-output attempt is rejected by ordinary command dispatch")
	var after: Dictionary = graph.create_snapshot()
	_assert(String(after.get("checksum", "")) == String(before.get("checksum", "")), "client trusted-output attempt leaves canonical Item Graph checksum unchanged")
	_assert(int(after.get("revision", -1)) == int(before.get("revision", -2)), "client trusted-output attempt leaves Item Graph revision unchanged")
	_assert(int(after.get("tick", -1)) == int(before.get("tick", -2)), "client trusted-output attempt leaves Item Graph tick unchanged")


func _test_mine_replay_and_rejection_purity() -> void:
	var context := _new_context()
	if context.is_empty():
		return
	var graph = context["graph"]
	var service = context["service"]
	var resolver = context["resolver"]
	var player_position := _target_position(service, resolver)
	if player_position.is_empty():
		return
	var before_resource: Dictionary = service.create_snapshot()
	var before_item: Dictionary = graph.create_snapshot()
	var operation_id := "operation/v0-p3/domain/mine-1"
	var payload := {"resource_node_id": NODE_ID, "requested_units": 1}
	var mined: Dictionary = service.mine("a", operation_id, payload, player_position)
	_assert(bool(mined.get("success", false)), "one-unit resource.mine succeeds in range")
	if not bool(mined.get("success", false)):
		return
	var details: Dictionary = Dictionary(mined.get("details", {}))
	_assert(int(details.get("remaining_units", -1)) == 7, "successful mine decrements resource from eight to seven")
	_assert(String(details.get("output_definition_id", "")) == "item/ore", "successful mine reports canonical ore output definition")
	_assert(int(details.get("output_quantity", 0)) == 1, "successful mine credits exactly one ore quantity")
	var output_item_id := String(details.get("output_item_id", ""))
	_assert(not output_item_id.is_empty(), "successful mine returns deterministic output item identity")
	var after_resource: Dictionary = service.create_snapshot()
	var after_item: Dictionary = graph.create_snapshot()
	_assert(int(after_resource.get("generation", 0)) == int(before_resource.get("generation", 0)) + 1, "successful mine advances resource generation exactly once")
	_assert(int(after_item.get("revision", 0)) == int(before_item.get("revision", 0)) + 1, "successful mine advances Item Graph revision exactly once")
	_assert(int(after_item.get("tick", 0)) == int(before_item.get("tick", 0)) + 1, "successful mine advances Item Graph tick exactly once")
	var output_item := _find_item(after_item, output_item_id)
	_assert(not output_item.is_empty(), "mined output exists in canonical Item Graph")
	_assert(String(output_item.get("definition_id", "")) == "item/ore" and int(output_item.get("quantity", 0)) == 1, "mined output is one canonical item/ore")
	var output_location: Dictionary = Dictionary(output_item.get("location", {}))
	_assert(String(output_location.get("kind", "")) == "INVENTORY" and String(output_location.get("player_id", "")) == "a" and int(output_location.get("slot_index", -1)) >= 0, "mined output is credited to a real canonical player inventory slot")

	var replay_resource_before: Dictionary = service.create_snapshot()
	var replay_item_before: Dictionary = graph.create_snapshot()
	var replay: Dictionary = service.mine("a", operation_id, payload, player_position)
	_assert(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "exact resource.mine replay succeeds as replay")
	_assert(String(replay.get("details", {}).get("output_item_id", "")) == output_item_id, "exact replay returns identical output item identity")
	_assert(service.create_snapshot() == replay_resource_before, "exact replay does not deplete resource twice")
	_assert(graph.create_snapshot() == replay_item_before, "exact replay does not mint ore twice")

	var conflict_resource_before: Dictionary = service.create_snapshot()
	var conflict_item_before: Dictionary = graph.create_snapshot()
	var conflict: Dictionary = service.mine("a", operation_id, {"resource_node_id": NODE_ID, "requested_units": 2}, player_position)
	_assert(not bool(conflict.get("success", false)) and String(conflict.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT", "same operation id with different mining payload is rejected")
	_assert(service.create_snapshot() == conflict_resource_before and graph.create_snapshot() == conflict_item_before, "conflicting replay is mutation-free across resource and Item Graph")

	_assert_rejection_is_canonical_pure(service, graph, "operation/v0-p3/domain/zero", {"resource_node_id": NODE_ID, "requested_units": 0}, player_position, "INVALID_MINING_QUANTITY", "zero quantity")
	_assert_rejection_is_canonical_pure(service, graph, "operation/v0-p3/domain/oversize", {"resource_node_id": NODE_ID, "requested_units": 99}, player_position, "INVALID_MINING_QUANTITY", "oversize quantity")
	_assert_rejection_is_canonical_pure(service, graph, "operation/v0-p3/domain/missing", {"resource_node_id": "resource/earth/missing", "requested_units": 1}, player_position, "RESOURCE_NOT_FOUND", "missing resource")
	_assert_rejection_is_canonical_pure(service, graph, "operation/v0-p3/domain/range", {"resource_node_id": NODE_ID, "requested_units": 1}, {"x": float(player_position["x"]) + 100.0, "y": 0.0, "z": float(player_position["z"])}, "RESOURCE_OUT_OF_RANGE", "out-of-range resource")
	_assert_rejection_is_canonical_pure(service, graph, "operation/v0-p3/domain/authority-field", {"resource_node_id": NODE_ID, "requested_units": 1, "remaining_units": 999}, player_position, "INVALID_RESOURCE_COMMAND", "client authority field")


func _test_output_preflight_failure_is_atomic() -> void:
	var resolver = EarthResourceSpatialResolver.new()
	_assert(bool(resolver.setup().get("success", false)), "atomicity resolver configures")
	var fake_graph = FakeRejectingItemGraph.new()
	var service = ResourceMiningService.new()
	_assert(bool(service.setup(AUTHORITY_ID, 1, fake_graph, resolver).get("success", false)), "resource service accepts bounded rejecting Item Graph port")
	var player_position := _target_position(service, resolver)
	if player_position.is_empty():
		return
	var before := service.create_snapshot()
	var rejected: Dictionary = service.mine(
		"a",
		"operation/v0-p3/domain/output-reject",
		{"resource_node_id": NODE_ID, "requested_units": 1},
		player_position
	)
	_assert(not bool(rejected.get("success", false)) and String(rejected.get("error_code", "")) == "RESOURCE_OUTPUT_REJECTED", "Item Graph preflight failure rejects mining")
	_assert(service.create_snapshot() == before, "Item Graph preflight failure leaves resource state untouched")
	_assert(fake_graph.preflight_calls == 1 and fake_graph.apply_calls == 0, "failed output preflight never reaches Item Graph mutation call")


func _test_fresh_recovery_preserves_replay() -> void:
	var context := _new_context()
	if context.is_empty():
		return
	var graph = context["graph"]
	var service = context["service"]
	var resolver = context["resolver"]
	var player_position := _target_position(service, resolver)
	if player_position.is_empty():
		return
	var operation_id := "operation/v0-p3/domain/recovery-mine"
	var payload := {"resource_node_id": NODE_ID, "requested_units": 1}
	var mined: Dictionary = service.mine("a", operation_id, payload, player_position)
	_assert(bool(mined.get("success", false)), "recovery source mine succeeds")
	if not bool(mined.get("success", false)):
		return
	var output_item_id := String(mined.get("details", {}).get("output_item_id", ""))
	var graph_durable: Dictionary = graph.export_durable_state()
	var graph_replay: Dictionary = graph.export_replay_state()
	var resource_durable: Dictionary = service.export_durable_state()
	var resource_replay: Dictionary = service.export_replay_state()
	_assert(not graph_durable.is_empty() and not graph_replay.is_empty() and not resource_durable.is_empty() and not resource_replay.is_empty(), "resource and Item Graph durable/replay states export")

	var restored_graph = CanonicalItemGraph.new()
	_assert(bool(restored_graph.restore_durable_state(graph_durable).get("success", false)), "fresh Item Graph restores mined durable state")
	_assert(bool(restored_graph.restore_replay_state(graph_replay).get("success", false)), "fresh Item Graph restores trusted-output replay ledger")
	var restored_resolver = EarthResourceSpatialResolver.new()
	_assert(bool(restored_resolver.setup().get("success", false)), "fresh recovery resolver configures")
	var restored_service = ResourceMiningService.new()
	_assert(bool(restored_service.setup(AUTHORITY_ID, 1, restored_graph, restored_resolver).get("success", false)), "fresh ResourceMiningService configures before restore")
	_assert(bool(restored_service.restore_durable_state(resource_durable).get("success", false)), "fresh ResourceMiningService restores depleted state")
	_assert(bool(restored_service.restore_replay_state(resource_replay).get("success", false)), "fresh ResourceMiningService restores mining replay ledger")
	var resource_before_replay: Dictionary = restored_service.create_snapshot()
	var item_before_replay: Dictionary = restored_graph.create_snapshot()
	var restored_position := _target_position(restored_service, restored_resolver)
	var replay: Dictionary = restored_service.mine("a", operation_id, payload, restored_position)
	_assert(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "fresh recovery exact replay is idempotent")
	_assert(String(replay.get("details", {}).get("output_item_id", "")) == output_item_id, "fresh recovery replay preserves output identity")
	_assert(restored_service.create_snapshot() == resource_before_replay, "fresh recovery replay does not deplete resource again")
	_assert(restored_graph.create_snapshot() == item_before_replay, "fresh recovery replay does not duplicate ore")
	_assert(_count_inventory_definition(restored_graph.create_snapshot(), "a", "item/ore") == 1, "fresh recovery contains exactly one mined ore output in player inventory")


func _new_context() -> Dictionary:
	var graph = CanonicalItemGraph.new()
	var graph_setup: Dictionary = graph.setup(AUTHORITY_ID, 1, {"playable_sandbox": true})
	_assert(bool(graph_setup.get("success", false)), "canonical Item Graph configures for P3 domain test")
	if not bool(graph_setup.get("success", false)):
		return {}
	graph.ensure_player("a")
	var resolver = EarthResourceSpatialResolver.new()
	var resolver_setup: Dictionary = resolver.setup()
	_assert(bool(resolver_setup.get("success", false)), "Earth resource spatial resolver configures")
	if not bool(resolver_setup.get("success", false)):
		return {}
	var service = ResourceMiningService.new()
	var service_setup: Dictionary = service.setup(AUTHORITY_ID, 1, graph, resolver)
	_assert(bool(service_setup.get("success", false)), "ResourceMiningService configures against canonical Item Graph")
	if not bool(service_setup.get("success", false)):
		return {}
	return {"graph": graph, "resolver": resolver, "service": service}


func _target_position(service, resolver) -> Dictionary:
	var node: Dictionary = service.get_node(NODE_ID)
	var resolved: Dictionary = resolver.resolve_planar(Dictionary(node.get("spatial", {})))
	_assert(bool(resolved.get("success", false)), "resource target position resolves for test")
	return Dictionary(resolved.get("details", {}).get("planar_position", {})).duplicate(true) if bool(resolved.get("success", false)) else {}


func _assert_rejection_is_canonical_pure(
	service,
	graph,
	operation_id: String,
	payload: Dictionary,
	player_position: Dictionary,
	expected_error: String,
	label: String
) -> void:
	var resource_before: Dictionary = service.create_snapshot()
	var item_before: Dictionary = graph.create_snapshot()
	var result: Dictionary = service.mine("a", operation_id, payload, player_position)
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected_error, "%s rejection is precise" % label)
	_assert(service.create_snapshot() == resource_before, "%s rejection leaves resource canonical state unchanged" % label)
	_assert(graph.create_snapshot() == item_before, "%s rejection leaves Item Graph canonical state unchanged" % label)


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _count_inventory_definition(snapshot: Dictionary, player_id: String, definition_id: String) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var location: Dictionary = Dictionary(item.get("location", {}))
		if (
			String(item.get("definition_id", "")) == definition_id
			and String(location.get("kind", "")) == "INVENTORY"
			and String(location.get("player_id", "")) == player_id
		):
			count += 1
	return count


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V0-P3 resource/mining domain: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
