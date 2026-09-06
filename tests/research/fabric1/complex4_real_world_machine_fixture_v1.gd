extends RefCounted

const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ConstructMutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const ConstructStore = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const MatterComposition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const CONSTRUCT_ID := "construct/complex4/physical-outpost"
const ROOT_ITEM_ID := "item/complex4-physical-outpost-root"
const PART_COUNT := 164
const SUPPORT_A := "bond/complex4/frame-054-055"
const SUPPORT_B := "bond/complex4/frame-108-109"
const POWER_A := "bond/complex4/power-path-a"
const POWER_B := "bond/complex4/power-path-b"
const AUTHORITY_OWNER := "server/complex4-authority"
const AUTHORITY_EPOCH := 9

static func initial_snapshot() -> Dictionary:
	var parts: Array = []
	for index in range(PART_COUNT):
		var metadata := {"complex4_section": "frame"}
		if index == 0:
			metadata = {"complex4_section": "source", "functional_role": "power_source", "source_common": 12.0}
		elif index == PART_COUNT - 1:
			metadata = {"complex4_section": "load", "functional_role": "power_load", "load_gain": 0.25, "on_power_threshold_w": 1.0}
		parts.append(Part.create(
			part_id(index),
			"item/complex4-part-%03d" % index,
			"MACHINE_MEMBER",
			"fabric_boundary" if index in [0, PART_COUNT - 1] else "member",
			1.0,
			[float(index), 0.0, 0.0],
			metadata
		))
	var bonds: Array = []
	for index in range(PART_COUNT - 1):
		bonds.append(Bond.create(
			"bond/complex4/frame-%03d-%03d" % [index, index + 1],
			part_id(index), part_id(index + 1), "STRUCTURAL_MEMBER", 100.0, "INTACT",
			{"complex4_section": "frame"}
		))
	bonds.append(Bond.create("bond/complex4/bypass-a", part_id(53), part_id(56), "STRUCTURAL_MEMBER", 20.0, "INTACT", {"complex4_section": "redundant_support"}))
	bonds.append(Bond.create("bond/complex4/bypass-b", part_id(107), part_id(110), "STRUCTURAL_MEMBER", 20.0, "INTACT", {"complex4_section": "redundant_support"}))
	bonds.append(Bond.create(POWER_A, part_id(0), part_id(PART_COUNT - 1), "POWER_LINK", 1.0, "INTACT", {"support_bond_ids": [SUPPORT_A], "path": "primary"}))
	bonds.append(Bond.create(POWER_B, part_id(0), part_id(PART_COUNT - 1), "POWER_LINK", 1.0, "INTACT", {"support_bond_ids": [SUPPORT_B], "path": "backup"}))
	return Snapshot.create(CONSTRUCT_ID, ROOT_ITEM_ID, 0, "OPERATIONAL", parts, bonds, {
		"lab": "COMPLEX4_REAL_WORLD_MACHINE",
		"functional_contract": "redundant_power_paths_supported_by_structure",
	})

static func successor_with_broken_support(before: Dictionary, support_bond_id: String) -> Dictionary:
	var bonds: Array = []
	var found := false
	for raw in before["bonds"]:
		var bond: Dictionary = raw
		var state := String(bond["state"])
		if String(bond["bond_id"]) == support_bond_id:
			state = "BROKEN"
			found = true
		bonds.append(Bond.create(
			String(bond["bond_id"]), String(bond["part_a_id"]), String(bond["part_b_id"]), String(bond["bond_kind"]),
			float(bond["strength_n"]), state, Dictionary(bond["metadata"])
		))
	if not found:
		return {}
	return Snapshot.create(CONSTRUCT_ID, ROOT_ITEM_ID, int(before["state_revision"]) + 1, "DAMAGED", before["parts"], bonds, before["compiled_facets"])

static func matter_batch() -> Dictionary:
	var composition := MatterComposition.create([
		{"material_id": "material/complex4-ceramic", "mass_fraction": 0.10},
		{"material_id": "material/complex4-copper", "mass_fraction": 0.18},
		{"material_id": "material/complex4-steel", "mass_fraction": 0.72},
	])
	return MatterBatch.create({
		"batch_id": "batch/complex4/physical-outpost",
		"container_id": "container/complex4/material",
		"source_body_id": "body/complex4/source",
		"source_operation_id": "operation/complex4/materialize",
		"total_mass_kg": float(PART_COUNT),
		"bulk_volume_m3": 0.021,
		"composition": composition,
		"temperature_k": 293.15,
	})

static func create_store(snapshot: Dictionary) -> Dictionary:
	var store := ConstructStore.new()
	var mutation := ConstructMutation.create(ConstructMutation.OP_CREATE, CONSTRUCT_ID, {}, snapshot)
	return {"store": store, "mutation": mutation, "result": store.apply_mutation(mutation)}

static func apply_successor(store, before: Dictionary, after: Dictionary) -> Dictionary:
	var mutation := ConstructMutation.create(ConstructMutation.OP_UPDATE, CONSTRUCT_ID, before, after)
	return {"mutation": mutation, "result": store.apply_mutation(mutation)}

static func bond(snapshot: Dictionary, bond_id: String) -> Dictionary:
	for raw in snapshot.get("bonds", []):
		if String(raw.get("bond_id", "")) == bond_id:
			return Dictionary(raw).duplicate(true)
	return {}

static func part_id(index: int) -> String:
	return "part/complex4/%03d" % index
