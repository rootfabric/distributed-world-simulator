extends RefCounted

const DomainFactory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const Item = preload("res://scripts/items/domain/item_instance.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const ItemProjection = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Stage = preload("res://scripts/construction/build/construction_build_stage.gd")
const BuildPlan = preload("res://scripts/construction/build/construction_build_plan.gd")
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
const AuthorityRecord = preload("res://scripts/construction/distributed/construction_authority_record.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const CONSTRUCT_ID := "construct/mvp6/seam-bridge"
const BUILD_PLAN_ID := "build-plan/mvp6/seam-bridge"
const ROOT_ITEM_ID := "item/00000000-0000-4000-8000-00000002d000"
const SERVER_A := "server/mvp6/authority-a"
const SERVER_B := "server/mvp6/authority-b"
const CELL_A := "cell/mvp6/seam-west"
const CELL_B := "cell/mvp6/seam-east"
const BASE_PART_COUNT := 100
const FINAL_PART_COUNT := 101
const SEAM_LEFT_INDEX := 49
const SEAM_RIGHT_INDEX := 50
const ADD_PART_INDEX := 100
const ORE_QUANTITY_BY_STAGE := {0: 100, 1: 1}


class TransferBackend extends RefCounted:
	var adapter
	var gateway

	func setup(authoritative_adapter, multiplayer_gateway) -> Dictionary:
		if authoritative_adapter == null or not authoritative_adapter.has_method("export_state") or not authoritative_adapter.has_method("load_state") or not authoritative_adapter.has_method("get_construct_snapshot"):
			return ParametricUtils.failure("MVP6_CONSTRUCTION_TRANSFER_ADAPTER_REQUIRED")
		if multiplayer_gateway == null or not multiplayer_gateway.has_method("export_state") or not multiplayer_gateway.has_method("load_state"):
			return ParametricUtils.failure("MVP6_CONSTRUCTION_TRANSFER_GATEWAY_REQUIRED")
		adapter = authoritative_adapter
		gateway = multiplayer_gateway
		return ParametricUtils.success()

	func export_construct_state(construct_id: String) -> Dictionary:
		var snapshot: Dictionary = adapter.get_construct_snapshot(construct_id)
		if snapshot.is_empty():
			return ParametricUtils.failure("MVP6_CONSTRUCTION_TRANSFER_STATE_NOT_FOUND")
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
			return ParametricUtils.failure("MVP6_CONSTRUCTION_TRANSFER_PAYLOAD_REQUIRED")
		var payload: Dictionary = state.get("payload", {})
		if not payload.get("authoritative_adapter", {}) is Dictionary or not payload.get("multiplayer_gateway", {}) is Dictionary:
			return ParametricUtils.failure("MVP6_CONSTRUCTION_TRANSFER_PAYLOAD_INVALID")
		var loaded: Dictionary = adapter.load_state(Dictionary(payload["authoritative_adapter"]))
		if not bool(loaded.get("success", false)):
			return loaded
		loaded = gateway.load_state(Dictionary(payload["multiplayer_gateway"]))
		if not bool(loaded.get("success", false)):
			return loaded
		var current: Dictionary = adapter.get_construct_snapshot(String(state.get("construct_id", "")))
		if current.is_empty() or String(current.get("checksum", "")) != String(state.get("checksum", "")):
			return ParametricUtils.failure("MVP6_CONSTRUCTION_TRANSFER_IMPORT_CHECKSUM_MISMATCH")
		return ParametricUtils.success()

	func get_construct_checksum(construct_id: String) -> String:
		return String(adapter.get_construct_snapshot(construct_id).get("checksum", ""))

	func has_terminal_command(command_id: String, command_checksum: String) -> bool:
		for row in gateway.export_state().get("terminal_commands", []):
			if String(row.get("command_id", "")) == command_id:
				return String(row.get("command_checksum", "")) == command_checksum
		return false


static func create(canonical_item_graph, authority_owner_id: String, authority_epoch: int, repository_root: String) -> Dictionary:
	if canonical_item_graph == null or not canonical_item_graph.has_method("preflight_server_construction_consume") or not canonical_item_graph.has_method("apply_server_construction_consume"):
		return _failure("MVP6_CANONICAL_ITEM_GRAPH_REQUIRED")
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1 or repository_root.strip_edges().is_empty():
		return _failure("MVP6_CONSTRUCTION_FACTORY_ARGUMENT_INVALID")

	var domain: Dictionary = DomainFactory.create()
	for row in [
		{"id":"construct_root","display_name":"Construction root","max_stack":1,"unit_mass_kg":0.1,"external_volume_l":0.1,"tags":["construction"]},
		{"id":"mvp6_seam_module","display_name":"MVP6 Seam Module","max_stack":1,"unit_mass_kg":10.0,"external_volume_l":2.0,"tags":["construction_part","seam"]},
	]:
		domain.items.register_definition(Definition.new(row))
	for index in range(FINAL_PART_COUNT):
		var item_id := part_item_id(index)
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
			return _failure("MVP6_SEAM_STRUCTURAL_ITEM_SETUP_FAILED", {"item_id": item_id})
	var graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		return _failure("MVP6_SEAM_STRUCTURAL_GRAPH_INVALID", {"cause": graph_validation})

	var m0_bridge = M0Bridge.new()
	var result: Dictionary = m0_bridge.setup(repository_root)
	if not bool(result.get("success", false)): return result
	var adapter = AuthoritativeAdapter.new()
	result = adapter.setup(
		domain.items, domain.containers, domain.validator, domain.mass, domain.operations,
		ConstructStore.new(), m0_bridge, "%s/construction" % authority_owner_id.strip_edges(),
		authority_epoch, 0, 0, 0, {}
	)
	if not bool(result.get("success", false)): return result

	var live_port = LivePort.new()
	result = live_port.setup(canonical_item_graph, adapter)
	if not bool(result.get("success", false)): return result
	var store = BuildStore.new()
	result = store.setup()
	if not bool(result.get("success", false)): return result
	var build = BuildProcess.new()
	result = build.setup_live(live_port, canonical_item_graph, store, ORE_QUANTITY_BY_STAGE)
	if not bool(result.get("success", false)): return result
	var plan := build_plan(domain.items)
	var checked: Dictionary = BuildPlan.validate(plan)
	if not bool(checked.get("success", false)): return checked
	result = build.register_plan(plan)
	if not bool(result.get("success", false)): return result

	var damage = DamageProcess.new()
	result = damage.setup(adapter)
	if not bool(result.get("success", false)): return result
	var executor = Executor.new()
	result = executor.setup(live_port, build, GeometryProcess.new(), damage)
	if not bool(result.get("success", false)): return result
	var permissions = PermissionStore.new()
	result = permissions.setup(1)
	if not bool(result.get("success", false)): return result
	var gateway = Gateway.new()
	result = gateway.setup(executor, permissions, SessionStore.new())
	if not bool(result.get("success", false)): return result

	var transfer = TransferBackend.new()
	result = transfer.setup(adapter, gateway)
	if not bool(result.get("success", false)): return result
	var endpoint_a = AuthenticatedEndpoint.new()
	result = endpoint_a.setup(SERVER_A, CELL_A, gateway, transfer)
	if not bool(result.get("success", false)): return result
	var endpoint_b = AuthenticatedEndpoint.new()
	result = endpoint_b.setup(SERVER_B, CELL_B, gateway, transfer)
	if not bool(result.get("success", false)): return result
	var cluster = DistributedCluster.new()
	result = cluster.setup(AuthorityRegistry.new())
	if not bool(result.get("success", false)): return result
	result = cluster.register_server(SERVER_A, CELL_A, endpoint_a)
	if not bool(result.get("success", false)): return result
	result = cluster.register_server(SERVER_B, CELL_B, endpoint_b)
	if not bool(result.get("success", false)): return result
	cluster.set_tick(1)

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
			"build_plan": plan,
			"transfer_backend": transfer,
			"endpoint_a": endpoint_a,
			"endpoint_b": endpoint_b,
			"cluster": cluster,
			"construct_id": CONSTRUCT_ID,
			"build_plan_id": BUILD_PLAN_ID,
			"base_part_count": BASE_PART_COUNT,
			"final_part_count": FINAL_PART_COUNT,
			"single_item_graph_identity": live_port.is_bound_to_item_graph(canonical_item_graph),
			"fixture_material_truth_present": false,
			"damage_process_configured": true,
		},
	}


static func register_active_construct(details: Dictionary) -> Dictionary:
	var transfer = details.get("transfer_backend")
	var cluster = details.get("cluster")
	if transfer == null or cluster == null:
		return _failure("MVP6_DISTRIBUTED_CONSTRUCTION_DETAILS_REQUIRED")
	var exported: Dictionary = transfer.export_construct_state(CONSTRUCT_ID)
	if not bool(exported.get("success", false)): return exported
	var state: Dictionary = exported.get("state", {})
	var record := AuthorityRecord.create(
		CONSTRUCT_ID, SERVER_A, CELL_A, 1, String(state.get("checksum", "")), [SERVER_B], 100,
		SERVER_A, {"boundary_cells":[CELL_A, CELL_B], "seam_x_m":0.0, "single_writer":true}
	)
	var result: Dictionary = cluster.register_construct(record, state)
	if not bool(result.get("success", false)): return result
	result = cluster.register_replica(CONSTRUCT_ID, SERVER_B)
	if not bool(result.get("success", false)): return result
	return ParametricUtils.success({"record": cluster.get_registry().get_record(CONSTRUCT_ID), "replica": cluster.get_replica(CONSTRUCT_ID, SERVER_B).get_state()})


static func part_item_id(index: int) -> String:
	return "item/00000000-0000-4000-8000-00000001%04d" % index

static func part_id(index: int) -> String:
	return "part/mvp6/seam/p%03d" % index

static func bond_id(index: int) -> String:
	return "bond/mvp6/seam/b%03d" % index

static func parts() -> Array:
	var result: Array = []
	for index in range(FINAL_PART_COUNT):
		var x := float(index) - 49.5
		result.append(Part.create(
			part_id(index), part_item_id(index), "BEAM", "seam", 10.0, [x, 0.5, 0.0],
			{"geometry":{"bounding_box_m":[1.05,1.0,2.0]}, "proxy_material_key":"hull", "region":"a" if x < 0.0 else "b", "seam_witness":index in [SEAM_LEFT_INDEX, SEAM_RIGHT_INDEX]}
		))
	return result

static func bonds() -> Array:
	var result: Array = []
	for index in range(FINAL_PART_COUNT - 1):
		result.append(Bond.create(bond_id(index), part_id(index), part_id(index + 1), "BOLT", 4000.0))
	return result

static func target_snapshot() -> Dictionary:
	return Snapshot.create(CONSTRUCT_ID, ROOT_ITEM_ID, 0, "OPERATIONAL", parts(), bonds(), {
		"mvp6":"cross-authority-seam", "seam_x_m":0.0, "base_part_count":BASE_PART_COUNT,
		"authority_cells":[CELL_A,CELL_B], "single_writer":SERVER_A
	})

static func source_projections(item_registry) -> Array:
	var result: Array = []
	for index in range(FINAL_PART_COUNT):
		var projected: Dictionary = ItemProjection.from_item_instance_dict(item_registry.get_item(part_item_id(index)).to_dict())
		if bool(projected.get("success", false)):
			result.append(Dictionary(projected.get("projection", {})).duplicate(true))
	return result

static func build_plan(item_registry) -> Dictionary:
	var snapshot := target_snapshot()
	var base_parts: Array = []
	for index in range(BASE_PART_COUNT): base_parts.append(part_id(index))
	var base_bonds: Array = []
	for index in range(BASE_PART_COUNT - 1): base_bonds.append(bond_id(index))
	var final_parts: Array = []
	for index in range(FINAL_PART_COUNT): final_parts.append(part_id(index))
	var final_bonds: Array = []
	for index in range(FINAL_PART_COUNT - 1): final_bonds.append(bond_id(index))
	var stages := [
		Stage.create("stage/mvp6/seam/base", 0, "Seam bridge base 100", Stage.SEMANTIC_STRUCTURE, base_parts, base_bonds, [], ["FASTEN"]),
		Stage.create("stage/mvp6/seam/add-east", 1, "Seam bridge ADD east leaf", Stage.SEMANTIC_OPERATIONAL, final_parts, final_bonds, [], ["FASTEN"]),
	]
	return BuildPlan.create(BUILD_PLAN_ID, "MVP6 Cross Authority Seam Bridge", ItemProjection.world_relation(), snapshot, source_projections(item_registry), stages)

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success":false, "error_code":code, "details":details.duplicate(true)}
