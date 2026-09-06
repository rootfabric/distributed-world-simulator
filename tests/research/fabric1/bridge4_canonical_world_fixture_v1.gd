extends RefCounted

const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ConstructMutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const ConstructStore = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const MatterComposition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const CONSTRUCT_ID := "construct/bridge4/canonical-truss"
const ROOT_ITEM_ID := "item/bridge4-canonical-truss-root"
const PART_COUNT := 104
const TARGET_BOND_ID := "bond/bridge4/link-051-052"
const AUTHORITY_OWNER := "server/bridge4-authority"
const AUTHORITY_EPOCH := 7

static func initial_snapshot() -> Dictionary:
	var parts: Array = []
	for index in range(PART_COUNT):
		parts.append(Part.create(
			part_id(index),
			"item/bridge4-part-%03d" % index,
			"BEAM",
			"fabric_boundary" if index in [0, PART_COUNT - 1] else "member",
			1.0,
			[float(index), 0.0, 0.0],
			{"bridge4_fixture": true}
		))
	var bonds: Array = []
	for index in range(PART_COUNT - 1):
		bonds.append(Bond.create(
			"bond/bridge4/link-%03d-%03d" % [index, index + 1],
			part_id(index), part_id(index + 1), "GENERIC_COUPLING", 100.0, "INTACT",
			{"bridge4_fixture": true}
		))
	bonds.append(Bond.create(
		"bond/bridge4/bypass-050-053", part_id(50), part_id(53), "GENERIC_COUPLING", 20.0, "INTACT",
		{"bridge4_fixture": true}
	))
	return Snapshot.create(CONSTRUCT_ID, ROOT_ITEM_ID, 0, "OPERATIONAL", parts, bonds, {"bridge4": "canonical-world-r1"})

static func damaged_snapshot(before: Dictionary) -> Dictionary:
	var bonds: Array = []
	for raw in before["bonds"]:
		var bond: Dictionary = raw
		bonds.append(Bond.create(
			String(bond["bond_id"]), String(bond["part_a_id"]), String(bond["part_b_id"]), String(bond["bond_kind"]),
			float(bond["strength_n"]), "BROKEN" if String(bond["bond_id"]) == TARGET_BOND_ID else String(bond["state"]),
			Dictionary(bond["metadata"])
		))
	return Snapshot.create(CONSTRUCT_ID, ROOT_ITEM_ID, int(before["state_revision"]) + 1, "DAMAGED", before["parts"], bonds, before["compiled_facets"])

static func matter_batch() -> Dictionary:
	var composition := MatterComposition.create([{"material_id": "material/bridge4-steel", "mass_fraction": 1.0}])
	return MatterBatch.create({
		"batch_id": "batch/bridge4/canonical-truss",
		"container_id": "container/bridge4/material",
		"source_body_id": "body/bridge4/source",
		"source_operation_id": "operation/bridge4/materialize",
		"total_mass_kg": float(PART_COUNT),
		"bulk_volume_m3": 0.013,
		"composition": composition,
		"temperature_k": 293.15,
	})

static func create_store(snapshot: Dictionary) -> Dictionary:
	var store := ConstructStore.new()
	var mutation := ConstructMutation.create(ConstructMutation.OP_CREATE, CONSTRUCT_ID, {}, snapshot)
	return {"store": store, "mutation": mutation, "result": store.apply_mutation(mutation)}

static func apply_damage(store, before: Dictionary, after: Dictionary) -> Dictionary:
	var mutation := ConstructMutation.create(ConstructMutation.OP_UPDATE, CONSTRUCT_ID, before, after)
	return {"mutation": mutation, "result": store.apply_mutation(mutation)}

static func part_id(index: int) -> String:
	return "part/bridge4/%03d" % index
