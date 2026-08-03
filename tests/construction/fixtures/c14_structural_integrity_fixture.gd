extends RefCounted

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemPlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const LoadCaseScript = preload("res://scripts/construction/structural/construction_structural_load_case.gd")

static func snapshot(instance_key: String = "a", revision: int = 0, broken_bonds: Array = [], weak_payload: bool = false, buckling_column: bool = false) -> Dictionary:
	var p := "part/structural/%s/" % instance_key
	var payload_capacity := 1000.0 if weak_payload else 100000.0
	var column_structural := {"capacity_n": 100000.0, "buckling_capacity_n": 1100.0} if buckling_column else {"capacity_n": 100000.0}
	var parts := [
		PartScript.create(p + "foundation", "item/structural/%s/foundation" % instance_key, "FOUNDATION", "support", 100.0, [0.0, 0.0, 0.0], {"condition": "INTACT", "structural": {"capacity_n": 1000000.0, "support": true}}),
		PartScript.create(p + "column", "item/structural/%s/column" % instance_key, "COLUMN", "column", 20.0, [0.0, 1.0, 0.0], {"condition": "INTACT", "structural": column_structural}),
		PartScript.create(p + "brace", "item/structural/%s/brace" % instance_key, "BRACE", "brace", 10.0, [1.0, 1.0, 0.0], {"condition": "INTACT", "structural": {"capacity_n": 100000.0}}),
		PartScript.create(p + "payload", "item/structural/%s/payload" % instance_key, "PLATFORM", "payload", 80.0, [0.0, 2.0, 0.0], {"condition": "INTACT", "structural": {"capacity_n": payload_capacity}}),
		PartScript.create(p + "tool", "item/structural/%s/tool" % instance_key, "TOOL", "tool", 20.0, [0.0, 3.0, 0.0], {"condition": "INTACT", "structural": {"capacity_n": 100000.0}}),
	]
	var bonds := [
		BondScript.create("bond/structural/%s/foundation-column" % instance_key, p + "foundation", p + "column", "WELD", 10000.0, "BROKEN" if broken_bonds.has("foundation-column") else "INTACT"),
		BondScript.create("bond/structural/%s/column-payload-primary" % instance_key, p + "column", p + "payload", "BOLT", 1500.0, "BROKEN" if broken_bonds.has("primary") else "INTACT"),
		BondScript.create("bond/structural/%s/column-brace" % instance_key, p + "column", p + "brace", "WELD", 10000.0, "BROKEN" if broken_bonds.has("column-brace") else "INTACT"),
		BondScript.create("bond/structural/%s/brace-payload-secondary" % instance_key, p + "brace", p + "payload", "BOLT", 1600.0, "BROKEN" if broken_bonds.has("secondary") else "INTACT"),
		BondScript.create("bond/structural/%s/payload-tool" % instance_key, p + "payload", p + "tool", "WELD", 10000.0, "BROKEN" if broken_bonds.has("payload-tool") else "INTACT"),
	]
	return SnapshotScript.create(
		"construct/structural/%s" % instance_key,
		"item/structural/%s/root" % instance_key,
		revision,
		"OPERATIONAL" if broken_bonds.is_empty() else "DAMAGED",
		parts,
		bonds,
		{"operational": broken_bonds.is_empty(), "capabilities": [{"kind": "SUPPORT_STRUCTURE"}]}
	)

static func items(instance_key: String = "a", snapshot_value: Dictionary = {}) -> Array:
	var source := snapshot(instance_key) if snapshot_value.is_empty() else snapshot_value
	var output: Array = [ItemPlannerScript.create_root_projection(String(source["root_item_instance_id"]), String(source["construct_id"]), "Structural root")]
	for part in source["parts"]:
		output.append(ProjectionScript.create(
			String(part["item_instance_id"]), String(part["part_kind"]).to_lower(), String(part["role"]), 1,
			ProjectionScript.attachment_relation(String(source["construct_id"]), String(source["root_item_instance_id"]), String(part["part_id"])),
			{"condition": String(part["metadata"].get("condition", "INTACT")), "serial": String(part["part_id"])}, 0
		))
	return output

static func load_case(instance_key: String = "a", snapshot_value: Dictionary = {}, overloaded: bool = false, maximum_steps: int = 16, safety_factor: float = 1.0) -> Dictionary:
	var source := snapshot(instance_key) if snapshot_value.is_empty() else snapshot_value
	var loads := {}
	if overloaded: loads["part/structural/%s/payload" % instance_key] = 800.0
	return LoadCaseScript.create(
		"load-case/structural/%s/gravity" % instance_key,
		String(source["construct_id"]), String(source["checksum"]), 9.80665,
		["part/structural/%s/foundation" % instance_key], loads, safety_factor, 0.5, 1.5, maximum_steps, 2, ProjectionScript.world_relation()
	)
