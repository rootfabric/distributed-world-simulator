extends RefCounted

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemPlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const PolicyScript = preload("res://scripts/construction/damage/construction_salvage_policy.gd")
const RequestScript = preload("res://scripts/construction/damage/construction_damage_request.gd")

static func snapshot(instance_key: String = "a", revision: int = 0) -> Dictionary:
	var prefix := "part/bridge/%s/" % instance_key
	var parts := [
		PartScript.create(prefix + "anchor", "item/bridge/%s/anchor" % instance_key, "FRAME", "anchor", 50.0, [0.0, 0.0, 0.0], {"condition": "INTACT"}),
		PartScript.create(prefix + "core", "item/bridge/%s/core" % instance_key, "FRAME", "core", 40.0, [1.0, 0.0, 0.0], {"condition": "INTACT"}),
		PartScript.create(prefix + "joint", "item/bridge/%s/joint" % instance_key, "FRAME", "joint", 20.0, [2.0, 0.0, 0.0], {"condition": "INTACT"}),
		PartScript.create(prefix + "arm", "item/bridge/%s/arm" % instance_key, "BEAM", "arm", 18.0, [3.0, 0.0, 0.0], {"condition": "INTACT"}),
		PartScript.create(prefix + "tool", "item/bridge/%s/tool" % instance_key, "TOOL", "tool", 12.0, [4.0, 0.0, 0.0], {"condition": "INTACT"}),
		PartScript.create(prefix + "sensor", "item/bridge/%s/sensor" % instance_key, "SENSOR", "sensor", 4.0, [1.0, 1.0, 0.0], {"condition": "INTACT"}),
	]
	var bonds := [
		BondScript.create("bond/bridge/%s/anchor-core" % instance_key, prefix + "anchor", prefix + "core", "WELD", 20000.0),
		BondScript.create("bond/bridge/%s/core-joint" % instance_key, prefix + "core", prefix + "joint", "WELD", 18000.0),
		BondScript.create("bond/bridge/%s/joint-arm" % instance_key, prefix + "joint", prefix + "arm", "BOLT", 9000.0),
		BondScript.create("bond/bridge/%s/arm-tool" % instance_key, prefix + "arm", prefix + "tool", "BOLT", 7000.0),
		BondScript.create("bond/bridge/%s/core-sensor" % instance_key, prefix + "core", prefix + "sensor", "MOUNT", 1200.0),
	]
	return SnapshotScript.create(
		"construct/bridge/%s" % instance_key,
		"item/bridge/%s/root" % instance_key,
		revision,
		"OPERATIONAL",
		parts,
		bonds,
		{"operational": true, "capabilities": [{"kind": "SUPPORT_STRUCTURE"}]}
	)

static func items(instance_key: String = "a") -> Array:
	var source := snapshot(instance_key)
	var output: Array = [ItemPlannerScript.create_root_projection(String(source["root_item_instance_id"]), String(source["construct_id"]), "Bridge root")]
	for part in source["parts"]:
		output.append(ProjectionScript.create(
			String(part["item_instance_id"]),
			String(part["part_kind"]).to_lower(),
			String(part["role"]),
			1,
			ProjectionScript.attachment_relation(String(source["construct_id"]), String(source["root_item_instance_id"]), String(part["part_id"])),
			{"condition": "INTACT", "serial": String(part["part_id"])},
			0
		))
	return output

static func request(instance_key: String = "a", snapshot_value: Dictionary = {}) -> Dictionary:
	var source := snapshot(instance_key) if snapshot_value.is_empty() else snapshot_value
	return RequestScript.create(
		"damage/bridge/%s/impact-1" % instance_key,
		String(source["construct_id"]),
		String(source["checksum"]),
		"part/bridge/%s/anchor" % instance_key,
		["bond/bridge/%s/core-sensor" % instance_key, "bond/bridge/%s/joint-arm" % instance_key],
		[],
		{
			"part/bridge/%s/joint" % instance_key: "DEGRADED",
			"part/bridge/%s/sensor" % instance_key: "DEGRADED",
		},
		[RequestScript.split_target("construct/bridge/%s/split-arm" % instance_key, "item/bridge/%s/split-root" % instance_key)],
		PolicyScript.create(2, ProjectionScript.world_relation(), false)
	)
