extends RefCounted

# Reopens an existing MVP6 Construction through its canonical M0 repository.
# This is composition wiring only: it does not register a build plan, create a
# second Construction store, or insert a snapshot directly.
const Factory = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_cross_authority_construction_factory.gd")
const DomainFactory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const Item = preload("res://scripts/items/domain/item_instance.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const BuildStore = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const BuildProcess = preload("res://scripts/construction/mvp/v0_p4_live_m4_construction_build_process.gd")
const GeometryProcess = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_process.gd")
const DamageProcess = preload("res://scripts/construction/damage/construction_damage_process.gd")
const Executor = preload("res://scripts/construction/multiplayer/construction_multiplayer_command_executor.gd")
const PermissionStore = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_store.gd")
const SessionStore = preload("res://scripts/construction/multiplayer/construction_multiplayer_session_store.gd")
const Gateway = preload("res://scripts/construction/multiplayer/construction_multiplayer_gateway.gd")
const AuthoritativeAdapter = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const ConstructStore = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const M0Bridge = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const LivePort = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_live_m4_construction_transaction_port.gd")
const AuthenticatedEndpoint = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_authenticated_construction_authority_endpoint.gd")
const DistributedCluster = preload("res://scripts/construction/distributed/construction_distributed_authority_cluster.gd")
const AuthorityRegistry = preload("res://scripts/construction/distributed/construction_authority_registry.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")


class TransferBackend extends RefCounted:
	var adapter
	var gateway

	func setup(authoritative_adapter, multiplayer_gateway) -> Dictionary:
		if authoritative_adapter == null or not authoritative_adapter.has_method("export_state") or not authoritative_adapter.has_method("load_state") or not authoritative_adapter.has_method("get_construct_snapshot"):
			return ParametricUtils.failure("MVP6_RESTORE_ADAPTER_REQUIRED")
		if multiplayer_gateway == null or not multiplayer_gateway.has_method("export_state") or not multiplayer_gateway.has_method("load_state"):
			return ParametricUtils.failure("MVP6_RESTORE_GATEWAY_REQUIRED")
		adapter = authoritative_adapter
		gateway = multiplayer_gateway
		return ParametricUtils.success()

	func export_construct_state(construct_id: String) -> Dictionary:
		var snapshot: Dictionary = adapter.get_construct_snapshot(construct_id)
		if snapshot.is_empty():
			return ParametricUtils.failure("MVP6_RESTORE_CONSTRUCT_NOT_FOUND")
		return ParametricUtils.success({
			"state": {
				"construct_id": construct_id,
				"revision": int(snapshot.get("state_revision", 0)),
				"payload": {
					"authoritative_adapter": adapter.export_state(),
					"multiplayer_gateway": gateway.export_state(),
				},
				"checksum": String(snapshot.get("checksum", "")),
			},
			"terminal_operations": [],
		})

	func import_construct_state(state: Dictionary, _terminal_operations: Array = []) -> Dictionary:
		if not state.get("payload", {}) is Dictionary:
			return ParametricUtils.failure("MVP6_RESTORE_TRANSFER_PAYLOAD_REQUIRED")
		var payload: Dictionary = state.get("payload", {})
		if not payload.get("authoritative_adapter", {}) is Dictionary or not payload.get("multiplayer_gateway", {}) is Dictionary:
			return ParametricUtils.failure("MVP6_RESTORE_TRANSFER_PAYLOAD_INVALID")
		var loaded: Dictionary = adapter.load_state(Dictionary(payload["authoritative_adapter"]))
		if not bool(loaded.get("success", false)):
			return loaded
		loaded = gateway.load_state(Dictionary(payload["multiplayer_gateway"]))
		if not bool(loaded.get("success", false)):
			return loaded
		var current: Dictionary = adapter.get_construct_snapshot(String(state.get("construct_id", "")))
		if current.is_empty() or String(current.get("checksum", "")) != String(state.get("checksum", "")):
			return ParametricUtils.failure("MVP6_RESTORE_TRANSFER_CHECKSUM_MISMATCH")
		return ParametricUtils.success()

	func get_construct_checksum(construct_id: String) -> String:
		return String(adapter.get_construct_snapshot(construct_id).get("checksum", ""))

	func has_terminal_command(command_id: String, command_checksum: String) -> bool:
		for row in gateway.export_state().get("terminal_commands", []):
			if String(row.get("command_id", "")) == command_id:
				return String(row.get("command_checksum", "")) == command_checksum
		return false


static func restore(canonical_item_graph, authority_owner_id: String, authority_epoch: int, repository_root: String) -> Dictionary:
	if canonical_item_graph == null or not canonical_item_graph.has_method("preflight_server_construction_consume") or not canonical_item_graph.has_method("apply_server_construction_consume"):
		return _failure("MVP6_RESTORE_CANONICAL_ITEM_GRAPH_REQUIRED")
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1 or repository_root.strip_edges().is_empty():
		return _failure("MVP6_RESTORE_ARGUMENT_INVALID")

	var domain: Dictionary = DomainFactory.create()
	for row in [
		{"id":"construct_root","display_name":"Construction root","max_stack":1,"unit_mass_kg":0.1,"external_volume_l":0.1,"tags":["construction"]},
		{"id":"mvp6_seam_module","display_name":"MVP6 Seam Module","max_stack":1,"unit_mass_kg":10.0,"external_volume_l":2.0,"tags":["construction_part","seam"]},
	]:
		domain.items.register_definition(Definition.new(row))
	for index in range(Factory.FINAL_PART_COUNT):
		var item_id := Factory.part_item_id(index)
		var item = Item.new({
			"instance_id": item_id,
			"definition_id": "mvp6_seam_module",
			"display_name": "MVP6 Seam Module %03d" % index,
			"quantity": 1,
			"relation": Relations.world(),
			"components": {},
			"revision": 0,
		})
		if not domain.items.add_item(item):
			return _failure("MVP6_RESTORE_STRUCTURAL_ITEM_SETUP_FAILED", {"item_id": item_id})
	var graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		return _failure("MVP6_RESTORE_STRUCTURAL_GRAPH_INVALID", {"cause": graph_validation})

	var m0_bridge = M0Bridge.new()
	var result: Dictionary = m0_bridge.setup(repository_root)
	if not bool(result.get("success", false)):
		return result
	var adapter = AuthoritativeAdapter.new()
	result = adapter.setup(
		domain.items, domain.containers, domain.validator, domain.mass, domain.operations,
		ConstructStore.new(), m0_bridge, "%s/construction" % authority_owner_id.strip_edges(),
		authority_epoch, 0, 0, 0, {}
	)
	if not bool(result.get("success", false)):
		return result
	var recovered: Dictionary = adapter.get_construct_snapshot(Factory.CONSTRUCT_ID)
	if recovered.is_empty():
		return _failure("MVP6_RESTORE_CANONICAL_CONSTRUCT_REQUIRED")

	var live_port = LivePort.new()
	result = live_port.setup(canonical_item_graph, adapter)
	if not bool(result.get("success", false)):
		return result
	var store = BuildStore.new()
	result = store.setup()
	if not bool(result.get("success", false)):
		return result
	var build = BuildProcess.new()
	result = build.setup_live(live_port, canonical_item_graph, store, Factory.ORE_QUANTITY_BY_STAGE)
	if not bool(result.get("success", false)):
		return result
	# Deliberately no build.register_plan(): persisted part sources are already
	# attached to the recovered Construction and must not be made transferable.
	var damage = DamageProcess.new()
	result = damage.setup(adapter)
	if not bool(result.get("success", false)):
		return result
	var executor = Executor.new()
	result = executor.setup(live_port, build, GeometryProcess.new(), damage)
	if not bool(result.get("success", false)):
		return result
	var permissions = PermissionStore.new()
	result = permissions.setup(1)
	if not bool(result.get("success", false)):
		return result
	var gateway = Gateway.new()
	result = gateway.setup(executor, permissions, SessionStore.new())
	if not bool(result.get("success", false)):
		return result

	var transfer = TransferBackend.new()
	result = transfer.setup(adapter, gateway)
	if not bool(result.get("success", false)):
		return result
	var endpoint_a = AuthenticatedEndpoint.new()
	result = endpoint_a.setup(Factory.SERVER_A, Factory.CELL_A, gateway, transfer)
	if not bool(result.get("success", false)):
		return result
	var endpoint_b = AuthenticatedEndpoint.new()
	result = endpoint_b.setup(Factory.SERVER_B, Factory.CELL_B, gateway, transfer)
	if not bool(result.get("success", false)):
		return result
	var cluster = DistributedCluster.new()
	result = cluster.setup(AuthorityRegistry.new())
	if not bool(result.get("success", false)):
		return result
	result = cluster.register_server(Factory.SERVER_A, Factory.CELL_A, endpoint_a)
	if not bool(result.get("success", false)):
		return result
	result = cluster.register_server(Factory.SERVER_B, Factory.CELL_B, endpoint_b)
	if not bool(result.get("success", false)):
		return result

	return {
		"success": true,
		"error_code": "",
		"details": {
			"gateway": gateway,
			"permissions": permissions,
			"live_port": live_port,
			"authoritative_adapter": adapter,
			"damage_process": damage,
			"build_process": build,
			"build_store": store,
			"transfer_backend": transfer,
			"endpoint_a": endpoint_a,
			"endpoint_b": endpoint_b,
			"cluster": cluster,
			"construct_id": Factory.CONSTRUCT_ID,
			"build_plan_id": Factory.BUILD_PLAN_ID,
			"single_item_graph_identity": live_port.is_bound_to_item_graph(canonical_item_graph),
			"fixture_material_truth_present": false,
			"damage_process_configured": true,
			"build_plan_registered": false,
			"recovered_from_existing_m0": true,
			"recovered_construct_checksum": String(recovered.get("checksum", "")),
		},
	}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
