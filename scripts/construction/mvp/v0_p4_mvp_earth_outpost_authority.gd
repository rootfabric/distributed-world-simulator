extends RefCounted

const FactoryScript = preload("res://scripts/items/services/item_domain_factory.gd")
const DefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemScript = preload("res://scripts/items/domain/item_instance.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const BuildStoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const BuildProcessScript = preload("res://scripts/construction/mvp/v0_p4_live_m4_construction_build_process.gd")
const GeometryProcessScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_process.gd")
const DamageProcessScript = preload("res://scripts/construction/damage/construction_damage_process.gd")
const ExecutorScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command_executor.gd")
const PermissionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_store.gd")
const SessionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_session_store.gd")
const GatewayScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_gateway.gd")
const AuthoritativeAdapterScript = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const M0BridgeScript = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const LivePortScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_live_m4_construction_transaction_port.gd")

const CONSTRUCT_ID := "construct/mvp/earth-outpost"
const BUILD_PLAN_ID := "build-plan/mvp/earth-outpost"
const ROOT_ITEM_ID := "item/00000000-0000-4000-8000-00000000c000"
const FOUNDATION_ITEM_ID := "item/00000000-0000-4000-8000-00000000c001"
const WALL_N_ITEM_ID := "item/00000000-0000-4000-8000-00000000c002"
const WALL_S_ITEM_ID := "item/00000000-0000-4000-8000-00000000c003"
const WALL_E_ITEM_ID := "item/00000000-0000-4000-8000-00000000c004"
const WALL_W_ITEM_ID := "item/00000000-0000-4000-8000-00000000c005"
const ROOF_ITEM_ID := "item/00000000-0000-4000-8000-00000000c006"
const ORE_QUANTITY_BY_STAGE := {0: 2, 1: 4, 2: 2}


static func create_gateway(
	canonical_item_graph,
	authority_owner_id: String,
	authority_epoch: int,
	repository_root: String
) -> Dictionary:
	if canonical_item_graph == null:
		return _failure("V0_P4_CANONICAL_ITEM_GRAPH_REQUIRED")
	if (
		not canonical_item_graph.has_method("preflight_server_construction_consume")
		or not canonical_item_graph.has_method("apply_server_construction_consume")
	):
		return _failure("V0_P4_CANONICAL_ITEM_GRAPH_NOT_CONSTRUCTION_CAPABLE")
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1:
		return _failure("V0_P4_CONSTRUCTION_AUTHORITY_INVALID")
	if repository_root.strip_edges().is_empty():
		return _failure("V0_P4_CONSTRUCTION_REPOSITORY_ROOT_REQUIRED")

	var domain: Dictionary = FactoryScript.create()
	for definition in [
		{"id": "construct_root", "display_name": "Construction root", "max_stack": 1, "unit_mass_kg": 0.1, "external_volume_l": 0.1, "tags": ["construction"]},
		{"id": "mvp_outpost_module", "display_name": "Earth Outpost Module", "max_stack": 1, "unit_mass_kg": 50.0, "external_volume_l": 100.0, "tags": ["construction_part"]},
	]:
		domain.items.register_definition(DefinitionScript.new(definition))
	for row in _structural_item_rows():
		var item = ItemScript.new({
			"instance_id": String(row[0]),
			"definition_id": "mvp_outpost_module",
			"display_name": String(row[1]),
			"quantity": 1,
			"relation": RelationsScript.world(),
			"components": {},
			"revision": 0,
		})
		if not domain.items.add_item(item):
			return _failure("V0_P4_CONSTRUCTION_STRUCTURAL_ITEM_SETUP_FAILED", {"item_id": String(row[0])})
	var graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		return _failure("V0_P4_CONSTRUCTION_STRUCTURAL_GRAPH_INVALID", {"cause": graph_validation})

	var m0_bridge = M0BridgeScript.new()
	var result: Dictionary = m0_bridge.setup(repository_root)
	if not bool(result.get("success", false)):
		return result
	var adapter = AuthoritativeAdapterScript.new()
	result = adapter.setup(
		domain.items,
		domain.containers,
		domain.validator,
		domain.mass,
		domain.operations,
		ConstructStoreScript.new(),
		m0_bridge,
		"%s/construction" % authority_owner_id.strip_edges(),
		authority_epoch,
		0,
		0,
		0,
		{}
	)
	if not bool(result.get("success", false)):
		return result

	var live_port = LivePortScript.new()
	result = live_port.setup(canonical_item_graph, adapter)
	if not bool(result.get("success", false)):
		return result
	var store = BuildStoreScript.new()
	result = store.setup()
	if not bool(result.get("success", false)):
		return result
	var build = BuildProcessScript.new()
	result = build.setup_live(live_port, canonical_item_graph, store, ORE_QUANTITY_BY_STAGE)
	if not bool(result.get("success", false)):
		return result
	var plan: Dictionary = _build_plan(domain.items)
	var plan_validation: Dictionary = BuildPlanScript.validate(plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	result = build.register_plan(plan)
	if not bool(result.get("success", false)):
		return result

	var executor = ExecutorScript.new()
	result = executor.setup(live_port, build, GeometryProcessScript.new(), DamageProcessScript.new())
	if not bool(result.get("success", false)):
		return result
	var permissions = PermissionStoreScript.new()
	result = permissions.setup(1)
	if not bool(result.get("success", false)):
		return result
	var gateway = GatewayScript.new()
	result = gateway.setup(executor, permissions, SessionStoreScript.new())
	if not bool(result.get("success", false)):
		return result
	return {
		"success": true,
		"error_code": "",
		"details": {
			"gateway": gateway,
			"construct_id": CONSTRUCT_ID,
			"build_plan_id": BUILD_PLAN_ID,
			"live_port": live_port,
			"authoritative_adapter": adapter,
			"m0_bridge": m0_bridge,
			"single_item_graph_identity": live_port.is_bound_to_item_graph(canonical_item_graph),
			"fixture_material_truth_present": false,
			"recipe_ore_quantity_by_stage": ORE_QUANTITY_BY_STAGE.duplicate(true),
		},
	}


static func _structural_item_rows() -> Array:
	return [
		[FOUNDATION_ITEM_ID, "Outpost foundation"],
		[WALL_N_ITEM_ID, "Outpost wall north"],
		[WALL_S_ITEM_ID, "Outpost wall south"],
		[WALL_E_ITEM_ID, "Outpost wall east"],
		[WALL_W_ITEM_ID, "Outpost wall west"],
		[ROOF_ITEM_ID, "Outpost roof"],
	]


static func _parts() -> Array:
	return [
		PartScript.create("part/mvp/outpost/foundation", FOUNDATION_ITEM_ID, "FOUNDATION", "base", 80.0, [0.0, 0.0, 0.0], {"geometry":{"bounding_box_m":[6.0,0.5,6.0]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-n", WALL_N_ITEM_ID, "WALL", "shell", 30.0, [0.0, 1.5, -2.5], {"geometry":{"bounding_box_m":[6.0,3.0,0.3]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-s", WALL_S_ITEM_ID, "WALL", "shell", 30.0, [0.0, 1.5, 2.5], {"geometry":{"bounding_box_m":[6.0,3.0,0.3]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-e", WALL_E_ITEM_ID, "WALL", "shell", 30.0, [2.5, 1.5, 0.0], {"geometry":{"bounding_box_m":[0.3,3.0,6.0]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-w", WALL_W_ITEM_ID, "WALL", "shell", 30.0, [-2.5, 1.5, 0.0], {"geometry":{"bounding_box_m":[0.3,3.0,6.0]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/roof", ROOF_ITEM_ID, "ROOF", "shell", 50.0, [0.0, 3.2, 0.0], {"geometry":{"bounding_box_m":[6.0,0.3,6.0]},"proxy_material_key":"hull"}),
	]


static func _target_snapshot() -> Dictionary:
	var bonds: Array = []
	var index := 0
	for part in _parts().slice(1):
		bonds.append(BondScript.create("bond/mvp/outpost/%d" % index, "part/mvp/outpost/foundation", String(part["part_id"]), "BOLT", 4000.0))
		index += 1
	return SnapshotScript.create(CONSTRUCT_ID, ROOT_ITEM_ID, 0, "OPERATIONAL", _parts(), bonds, {"mvp":"earth-c22-outpost","v0_p4":"real-ore"})


static func _source_projections(item_registry) -> Array:
	var result: Array = []
	for row in _structural_item_rows():
		var item = item_registry.get_item(String(row[0]))
		if item == null:
			continue
		var projected: Dictionary = ProjectionScript.from_item_instance_dict(item.to_dict())
		if bool(projected.get("success", false)):
			result.append(Dictionary(projected.get("projection", {})).duplicate(true))
	return result


static func _build_plan(item_registry) -> Dictionary:
	var snapshot: Dictionary = _target_snapshot()
	var stages := [
		StageScript.create("stage/mvp/outpost/foundation", 0, "Outpost foundation", StageScript.SEMANTIC_FOUNDATION, ["part/mvp/outpost/foundation"], [], [], ["FASTEN"]),
		StageScript.create("stage/mvp/outpost/shell", 1, "Outpost shell", StageScript.SEMANTIC_FRAME, ["part/mvp/outpost/foundation","part/mvp/outpost/wall-n","part/mvp/outpost/wall-s","part/mvp/outpost/wall-e","part/mvp/outpost/wall-w"], [], [], ["FASTEN"]),
		StageScript.create("stage/mvp/outpost/roof", 2, "Outpost commissioning", StageScript.SEMANTIC_OPERATIONAL, Array(snapshot.get("parts", [])).map(func(part): return String(part["part_id"])), Array(snapshot.get("bonds", [])).map(func(bond): return String(bond["bond_id"])), [], ["INSPECT"]),
	]
	return BuildPlanScript.create(BUILD_PLAN_ID, "MVP Earth Outpost", ProjectionScript.world_relation(), snapshot, _source_projections(item_registry), stages)


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
