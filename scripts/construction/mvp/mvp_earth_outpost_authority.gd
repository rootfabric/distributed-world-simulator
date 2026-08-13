extends RefCounted

# Fixed first-MVP outpost. This bootstraps existing canonical Construction
# services; it is not a second Construction authority or persistence layer.
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const BuildStoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const BuildProcessScript = preload("res://scripts/construction/build/construction_build_process.gd")
const GeometryProcessScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_process.gd")
const GeometryHistoryScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_history_store.gd")
const DamageProcessScript = preload("res://scripts/construction/damage/construction_damage_process.gd")
const ExecutorScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command_executor.gd")
const PermissionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_store.gd")
const SessionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_session_store.gd")
const GatewayScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_gateway.gd")

const CONSTRUCT_ID := "construct/mvp/earth-outpost"
const BUILD_PLAN_ID := "build-plan/mvp/earth-outpost"
const ROOT_ITEM_ID := "item/mvp/earth-outpost/root"

static func create_gateway() -> Dictionary:
	var adapter = AdapterScript.new()
	var adapter_setup: Dictionary = adapter.setup(_source_projections(), [])
	if not bool(adapter_setup.get("success", false)): return adapter_setup
	var store = BuildStoreScript.new()
	var setup: Dictionary = store.setup()
	if not bool(setup.get("success", false)): return setup
	var build = BuildProcessScript.new()
	setup = build.setup(adapter, store)
	if not bool(setup.get("success", false)): return setup
	setup = build.register_plan(_build_plan())
	if not bool(setup.get("success", false)): return setup
	# MVP accepts BUILD_STAGE only; edit/damage services remain unconfigured but
	# are supplied to the shared executor to preserve its canonical boundary.
	var geometry = GeometryProcessScript.new()
	var damage = DamageProcessScript.new()
	var executor = ExecutorScript.new()
	setup = executor.setup(adapter, build, geometry, damage)
	if not bool(setup.get("success", false)): return setup
	var permissions = PermissionStoreScript.new()
	setup = permissions.setup(1)
	if not bool(setup.get("success", false)): return setup
	var gateway = GatewayScript.new()
	setup = gateway.setup(executor, permissions, SessionStoreScript.new())
	if not bool(setup.get("success", false)): return setup
	return {"success": true, "error_code": "", "gateway": gateway, "construct_id": CONSTRUCT_ID, "build_plan_id": BUILD_PLAN_ID}

static func _source_projections() -> Array:
	var result: Array = []
	for part in _parts():
		result.append(ProjectionScript.create(String(part["item_instance_id"]), "mvp_outpost_module", "Earth Outpost Module", 1, ProjectionScript.container_relation("container/mvp/outpost"), {}, 0))
	result.append(ProjectionScript.create("item/mvp/earth-outpost/fasteners", "fastener", "Outpost fasteners", 12, ProjectionScript.container_relation("container/mvp/outpost"), {}, 0))
	return result

static func _parts() -> Array:
	return [
		PartScript.create("part/mvp/outpost/foundation", "item/mvp/earth-outpost/foundation", "FOUNDATION", "base", 80.0, [0.0, 0.0, 0.0], {"geometry":{"bounding_box_m":[6.0,0.5,6.0]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-n", "item/mvp/earth-outpost/wall-n", "WALL", "shell", 30.0, [0.0, 1.5, -2.5], {"geometry":{"bounding_box_m":[6.0,3.0,0.3]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-s", "item/mvp/earth-outpost/wall-s", "WALL", "shell", 30.0, [0.0, 1.5, 2.5], {"geometry":{"bounding_box_m":[6.0,3.0,0.3]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-e", "item/mvp/earth-outpost/wall-e", "WALL", "shell", 30.0, [2.5, 1.5, 0.0], {"geometry":{"bounding_box_m":[0.3,3.0,6.0]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/wall-w", "item/mvp/earth-outpost/wall-w", "WALL", "shell", 30.0, [-2.5, 1.5, 0.0], {"geometry":{"bounding_box_m":[0.3,3.0,6.0]},"proxy_material_key":"hull"}),
		PartScript.create("part/mvp/outpost/roof", "item/mvp/earth-outpost/roof", "ROOF", "shell", 50.0, [0.0, 3.2, 0.0], {"geometry":{"bounding_box_m":[6.0,0.3,6.0]},"proxy_material_key":"hull"}),
	]

static func _target_snapshot() -> Dictionary:
	var bonds: Array = []
	var index := 0
	for part in _parts().slice(1):
		bonds.append(BondScript.create("bond/mvp/outpost/%d" % index, "part/mvp/outpost/foundation", String(part["part_id"]), "BOLT", 4000.0))
		index += 1
	return SnapshotScript.create(CONSTRUCT_ID, ROOT_ITEM_ID, 0, "OPERATIONAL", _parts(), bonds, {"mvp":"earth-c22-outpost"})

static func _build_plan() -> Dictionary:
	var snapshot: Dictionary = _target_snapshot()
	var stages := [
		StageScript.create("stage/mvp/outpost/foundation", 0, "Outpost foundation", StageScript.SEMANTIC_FOUNDATION, ["part/mvp/outpost/foundation"], [], [{"item_instance_id":"item/mvp/earth-outpost/fasteners","definition_id":"fastener","quantity":2}], ["FASTEN"]),
		StageScript.create("stage/mvp/outpost/shell", 1, "Outpost shell", StageScript.SEMANTIC_FRAME, ["part/mvp/outpost/foundation","part/mvp/outpost/wall-n","part/mvp/outpost/wall-s","part/mvp/outpost/wall-e","part/mvp/outpost/wall-w"], [], [{"item_instance_id":"item/mvp/earth-outpost/fasteners","definition_id":"fastener","quantity":6}], ["FASTEN"]),
		StageScript.create("stage/mvp/outpost/roof", 2, "Outpost commissioning", StageScript.SEMANTIC_OPERATIONAL, Array(snapshot.get("parts", [])).map(func(part): return String(part["part_id"])), Array(snapshot.get("bonds", [])).map(func(bond): return String(bond["bond_id"])), [{"item_instance_id":"item/mvp/earth-outpost/fasteners","definition_id":"fastener","quantity":2}], ["INSPECT"]),
	]
	return BuildPlanScript.create(BUILD_PLAN_ID, "MVP Earth Outpost", ProjectionScript.world_relation(), snapshot, _source_projections(), stages)
