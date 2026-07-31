extends RefCounted

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const PlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const MachineDefinitionScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_definition.gd")
const BehaviorCompilerScript = preload("res://scripts/construction/behavior/construction_behavior_compiler.gd")
const SpatialCompilerScript = preload("res://scripts/construction/spatial/construction_spatial_compiler.gd")
const HouseFixtureScript = preload("res://tests/construction/fixtures/c7_spatial_house_fixture.gd")

static func machine_snapshot(instance_key: String = "cell-a", revision: int = 0, conditions: Dictionary = {}, bond_states: Dictionary = {}, build_state: String = "OPERATIONAL") -> Dictionary:
	var prefix := "part/fabrication/%s/" % instance_key
	var parts := [
		PartScript.create(prefix + "controller", "item/fabrication/%s/controller" % instance_key, "CONTROL_UNIT", "control", 8.0, [0.0, 1.0, 0.0], {"condition": String(conditions.get("controller", "INTACT"))}),
		PartScript.create(prefix + "frame", "item/fabrication/%s/frame" % instance_key, "FRAME", "frame", 120.0, [0.0, 0.5, 0.0], {"condition": String(conditions.get("frame", "INTACT"))}),
		PartScript.create(prefix + "spindle", "item/fabrication/%s/spindle" % instance_key, "MACHINE_HEAD", "tool", 35.0, [0.0, 1.2, 0.0], {"condition": String(conditions.get("spindle", "INTACT"))}),
	]
	var bonds := [
		BondScript.create("bond/fabrication/%s/controller" % instance_key, prefix + "frame", prefix + "controller", "MECHANICAL", 9000.0, String(bond_states.get("controller", "INTACT"))),
		BondScript.create("bond/fabrication/%s/spindle" % instance_key, prefix + "frame", prefix + "spindle", "MECHANICAL", 15000.0, String(bond_states.get("spindle", "INTACT"))),
	]
	return SnapshotScript.create("construct/fabrication/%s" % instance_key, "item/fabrication/%s/root" % instance_key, revision, build_state, parts, bonds, {
		"operational": build_state == "OPERATIONAL",
		"capabilities": [],
		"composite_exposed_ports": [{"port_id": "port/fabrication/%s/operator" % instance_key, "part_id": prefix + "controller", "port_kind": "WORKSTATION", "local_position_m": [0.0, 1.0, -0.5], "metadata": {"station_kind": "FABRICATION"}}],
		"fabrication_runtime": {},
	})

static func behavior_profile(instance_key: String = "cell-a", snapshot: Dictionary = {}) -> Dictionary:
	var source := machine_snapshot(instance_key) if snapshot.is_empty() else snapshot
	return BehaviorCompilerScript.compile(source)["profile"]

static func powered_spatial_profile(instance_key: String = "power-a") -> Dictionary:
	return SpatialCompilerScript.compile(HouseFixtureScript.house_snapshot(instance_key))["profile"]
static func unpowered_spatial_profile(instance_key: String = "power-a", revision: int = 1) -> Dictionary:
	return SpatialCompilerScript.compile(HouseFixtureScript.power_lost(instance_key, revision))["profile"]

static func machine_definition(instance_key: String = "cell-a") -> Dictionary:
	var prefix := "part/fabrication/%s/" % instance_key
	return MachineDefinitionScript.create("fabrication-machine/cnc-router", [prefix + "controller", prefix + "spindle"], ["bond/fabrication/%s/controller" % instance_key, "bond/fabrication/%s/spindle" % instance_key], "container/fabrication/%s/input" % instance_key, "container/fabrication/%s/output" % instance_key, ["fabrication-recipe/structural-beam"], ["WORKSTATION"], ["spatial-utility/power"], 2, {"accuracy_mm": 0.2, "machine_kind": "CNC_ROUTER"})

static func recipe(version: int = 1) -> Dictionary:
	return RecipeScript.create("fabrication-recipe/structural-beam", version, "Structural beam", [RecipeScript.input_requirement("coolant", 1), RecipeScript.input_requirement("steel_ingot", 3, {"grade": "S355"})], [RecipeScript.output_product("beam", "beam", "Fabricated structural beam", 1, {"structural_grade": "S355", "length_m": 2.0})], ["FABRICATION_CELL"], ["POWER"], 10, {"process": "MILLING"})

static func material_projections(instance_key: String = "cell-a") -> Array:
	return [
		ProjectionScript.create("item/material/%s/coolant" % instance_key, "coolant", "Coolant", 1, ProjectionScript.container_relation("container/raw/%s" % instance_key), {"fluid": "coolant"}, 0),
		ProjectionScript.create("item/material/%s/steel" % instance_key, "steel_ingot", "Steel ingots", 6, ProjectionScript.container_relation("container/raw/%s" % instance_key), {"grade": "S355", "batch_temperature_c": 100.0}, 0),
	]

static func machine_item_graph(instance_key: String = "cell-a") -> Dictionary:
	var snapshot := machine_snapshot(instance_key)
	var root := PlannerScript.create_root_projection(String(snapshot["root_item_instance_id"]), String(snapshot["construct_id"]), "Fabrication cell root")
	var items: Array = [root]
	for part in snapshot["parts"]:
		items.append(ProjectionScript.create(String(part["item_instance_id"]), String(part["part_kind"]).to_lower(), String(part["role"]), 1, ProjectionScript.attachment_relation(String(snapshot["construct_id"]), String(snapshot["root_item_instance_id"]), String(part["part_id"])), {"condition": String(part["metadata"].get("condition", "INTACT"))}, 0))
	items.append_array(material_projections(instance_key))
	return {"snapshot": snapshot, "items": items}
