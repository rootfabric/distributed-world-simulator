extends RefCounted

const FixtureBuilderScript = preload("res://scripts/labs/t1/t1_complex_construct_fixture_builder.gd")
const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const BUILDER_SCHEMA := "planet_simulator.t1a2_d0_authoritative_outpost_builder.v1"
const PROFILE_ID := "D0"
const EXPECTED_PART_COUNT := 64
const GRID_SIZE := 8
const EXPECTED_BOND_COUNT := 112
const ROOT_ITEM_INSTANCE_ID := "item/t1/d0/construct-root"
const OPERATION_PREFIX := "operation/t1a2/d0"


static func build_d0() -> Dictionary:
	var fixture_result: Dictionary = FixtureBuilderScript.build_profile(PROFILE_ID)
	if not bool(fixture_result.get("success", false)):
		return fixture_result
	return build_from_fixture(Dictionary(fixture_result["fixture"]))


static func build_from_fixture(fixture: Dictionary) -> Dictionary:
	var fixture_validation: Dictionary = FixtureBuilderScript.validate_fixture(fixture)
	if not bool(fixture_validation.get("success", false)):
		return fixture_validation
	if String(fixture.get("profile_id", "")) != PROFILE_ID:
		return _failure("T1A2_ONLY_D0_SUPPORTED")
	if int(fixture.get("part_count", -1)) != EXPECTED_PART_COUNT:
		return _failure("T1A2_D0_PART_COUNT_MISMATCH")
	var fixture_part_ids: Array = Array(fixture.get("part_ids", [])).duplicate(true)
	if fixture_part_ids.size() != EXPECTED_PART_COUNT:
		return _failure("T1A2_D0_PART_ID_COUNT_MISMATCH")

	var aggregate = AggregateScript.new()
	var setup_result: Dictionary = aggregate.setup(
		String(fixture["construct_id"]),
		ROOT_ITEM_INSTANCE_ID
	)
	if not bool(setup_result.get("success", false)):
		return setup_result

	var parts: Array = _build_parts(fixture_part_ids)
	var revision := 0
	for part_value in parts:
		var part: Dictionary = part_value
		var part_id := String(part["part_id"])
		var add_result: Dictionary = aggregate.add_part(
			"%s/add-part/%s" % [OPERATION_PREFIX, part_id.get_file()],
			revision,
			part
		)
		if not bool(add_result.get("success", false)):
			return _failure("T1A2_ADD_PART_FAILED", {
				"part_id": part_id,
				"cause": add_result,
			})
		revision = int(add_result.get("state_revision", -1))

	var bonds: Array = _build_grid_bonds(fixture_part_ids)
	if bonds.size() != EXPECTED_BOND_COUNT:
		return _failure("T1A2_D0_BOND_COUNT_MISMATCH", {"bond_count": bonds.size()})
	for bond_value in bonds:
		var bond: Dictionary = bond_value
		var bond_id := String(bond["bond_id"])
		var add_result: Dictionary = aggregate.add_bond(
			"%s/add-bond/%s" % [OPERATION_PREFIX, bond_id],
			revision,
			bond
		)
		if not bool(add_result.get("success", false)):
			return _failure("T1A2_ADD_BOND_FAILED", {
				"bond_id": bond_id,
				"cause": add_result,
			})
		revision = int(add_result.get("state_revision", -1))

	var operational: Dictionary = aggregate.set_build_state(
		"%s/set-operational" % OPERATION_PREFIX,
		revision,
		"OPERATIONAL"
	)
	if not bool(operational.get("success", false)):
		return _failure("T1A2_OPERATIONAL_TRANSITION_FAILED", {"cause": operational})

	var snapshot: Dictionary = aggregate.export_snapshot()
	var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return _failure("T1A2_EXPORTED_SNAPSHOT_INVALID", {"cause": snapshot_validation})
	if Array(snapshot.get("parts", [])).size() != EXPECTED_PART_COUNT:
		return _failure("T1A2_EXPORTED_PART_COUNT_MISMATCH")
	if Array(snapshot.get("bonds", [])).size() != EXPECTED_BOND_COUNT:
		return _failure("T1A2_EXPORTED_BOND_COUNT_MISMATCH")
	var facets: Dictionary = Dictionary(snapshot.get("compiled_facets", {}))
	if not bool(facets.get("connected", false)) or not bool(facets.get("stable", false)):
		return _failure("T1A2_D0_NOT_STABLE_CONNECTED", {"compiled_facets": facets})
	if int(facets.get("rigid_island_count", -1)) != 1:
		return _failure("T1A2_D0_NOT_SINGLE_RIGID_ISLAND")

	return {
		"success": true,
		"error_code": "",
		"schema": BUILDER_SCHEMA,
		"profile_id": PROFILE_ID,
		"fixture_checksum": String(fixture["fixture_checksum"]),
		"construct_id": String(snapshot["construct_id"]),
		"root_item_instance_id": ROOT_ITEM_INSTANCE_ID,
		"part_count": EXPECTED_PART_COUNT,
		"bond_count": EXPECTED_BOND_COUNT,
		"state_revision": int(snapshot["state_revision"]),
		"snapshot_checksum": String(snapshot["checksum"]),
		"snapshot": snapshot,
		"source_room_ids": Array(fixture.get("room_ids", [])).duplicate(true),
		"source_utility_ids": Array(fixture.get("utility_ids", [])).duplicate(true),
		"deferred_item_graph_ids": Array(fixture.get("item_ids", [])).duplicate(true),
	}


static func materialize_into_store(store, build_result: Dictionary = {}) -> Dictionary:
	if store == null or not store.has_method("apply_mutation") or not store.has_method("get_snapshot"):
		return _failure("T1A2_INVALID_CONSTRUCT_STORE")
	var candidate: Dictionary = build_result
	if candidate.is_empty():
		candidate = build_d0()
	if not bool(candidate.get("success", false)):
		return candidate
	if typeof(candidate.get("snapshot")) != TYPE_DICTIONARY:
		return _failure("T1A2_BUILD_RESULT_SNAPSHOT_MISSING")
	var snapshot: Dictionary = Dictionary(candidate["snapshot"]).duplicate(true)
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return _failure("T1A2_BUILD_RESULT_SNAPSHOT_INVALID", {"cause": validation})
	var construct_id := String(snapshot["construct_id"])
	if store.has_method("has_construct") and bool(store.has_construct(construct_id)):
		return _failure("T1A2_CONSTRUCT_ALREADY_MATERIALIZED")
	var mutation: Dictionary = ConstructMutationScript.create(
		ConstructMutationScript.OP_CREATE,
		construct_id,
		{},
		snapshot
	)
	var applied: Dictionary = store.apply_mutation(mutation)
	if not bool(applied.get("success", false)):
		return _failure("T1A2_CONSTRUCT_STORE_CREATE_FAILED", {"cause": applied})
	var stored: Dictionary = store.get_snapshot(construct_id)
	var stored_validation: Dictionary = SnapshotScript.validate(stored)
	if not bool(stored_validation.get("success", false)):
		return _failure("T1A2_CONSTRUCT_STORE_RETURNED_INVALID_SNAPSHOT", {"cause": stored_validation})
	var source_canonical := UtilsScript.canonical_json(snapshot)
	var stored_canonical := UtilsScript.canonical_json(stored)
	if source_canonical.is_empty() or stored_canonical.is_empty() or stored_canonical != source_canonical:
		return _failure("T1A2_CONSTRUCT_STORE_ROUNDTRIP_MISMATCH", {
			"source_checksum": String(snapshot.get("checksum", "")),
			"stored_checksum": String(stored.get("checksum", "")),
		})
	return {
		"success": true,
		"error_code": "",
		"construct_id": construct_id,
		"snapshot_checksum": String(stored["checksum"]),
		"snapshot": stored,
	}


static func _build_parts(part_ids: Array) -> Array:
	var parts: Array = []
	for index in range(part_ids.size()):
		var x := index % GRID_SIZE
		var z := int(index / GRID_SIZE)
		var support := _is_corner(x, z)
		var role := "support" if support else "surface"
		var part_kind := "FOUNDATION" if support else "PANEL"
		var mass_kg := 250.0 if support else 80.0
		parts.append(PartScript.create(
			String(part_ids[index]),
			"item/t1/d0/structural/p%04d" % index,
			part_kind,
			role,
			mass_kg,
			[float(x) - 3.5, 0.0, float(z) - 3.5],
			{
				"source": "T1A2_D0_FIXTURE",
				"profile_id": PROFILE_ID,
				"semantic_index": index,
			}
		))
	return parts


static func _build_grid_bonds(part_ids: Array) -> Array:
	var bonds: Array = []
	for z in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var index := z * GRID_SIZE + x
			if x + 1 < GRID_SIZE:
				bonds.append(_create_grid_bond(
					"bond/t1/d0/grid/x%02d-z%02d/east" % [x, z],
					String(part_ids[index]),
					String(part_ids[index + 1])
				))
			if z + 1 < GRID_SIZE:
				bonds.append(_create_grid_bond(
					"bond/t1/d0/grid/x%02d-z%02d/south" % [x, z],
					String(part_ids[index]),
					String(part_ids[index + GRID_SIZE])
				))
	return bonds


static func _create_grid_bond(bond_id: String, part_a_id: String, part_b_id: String) -> Dictionary:
	return BondScript.create(
		bond_id,
		part_a_id,
		part_b_id,
		"STRUCTURAL_WELD",
		1_000_000.0,
		"INTACT",
		{
			"source": "T1A2_D0_FIXTURE",
			"profile_id": PROFILE_ID,
		}
	)


static func _is_corner(x: int, z: int) -> bool:
	return (x == 0 or x == GRID_SIZE - 1) and (z == 0 or z == GRID_SIZE - 1)


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code}
	for key in details:
		result[key] = details[key]
	return result
