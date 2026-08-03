extends RefCounted

const C4FixtureScript = preload("res://tests/construction/fixtures/c4_reusable_table_fixture.gd")
const CompositeCompilerScript = preload("res://scripts/construction/composites/construction_composite_build_plan_compiler.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SnapshotBuilderScript = preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/compilation/construction_capability_compiler.gd")


static func compiled_table(instance_key: String, parameter_values: Dictionary = {}) -> Dictionary:
	var ids: Dictionary = C4FixtureScript.compile_ids(instance_key)
	var result: Dictionary = CompositeCompilerScript.compile(
		C4FixtureScript.definition(),
		ids["instantiation_id"],
		ids["build_plan_id"],
		ids["construct_id"],
		ids["root_item_instance_id"],
		ProjectionScript.world_relation(),
		C4FixtureScript.source_projections(instance_key),
		parameter_values
	)
	assert(bool(result.get("success", false)))
	return result


static func table_snapshot(instance_key: String, parameter_values: Dictionary = {}) -> Dictionary:
	var compiled: Dictionary = compiled_table(instance_key, parameter_values)
	var built: Dictionary = SnapshotBuilderScript.build_for_stage(compiled["build_plan"], 2)
	assert(bool(built.get("success", false)))
	return built["snapshot"]


static func partial_table_snapshot(instance_key: String) -> Dictionary:
	var compiled: Dictionary = compiled_table(instance_key)
	var built: Dictionary = SnapshotBuilderScript.build_for_stage(compiled["build_plan"], 0)
	assert(bool(built.get("success", false)))
	return built["snapshot"]


static func all_affordance_snapshot(instance_key: String = "all-affordances") -> Dictionary:
	var source: Dictionary = table_snapshot(instance_key)
	var facets: Dictionary = source["compiled_facets"].duplicate(true)
	var top_id: String = ""
	var leg_a_id: String = ""
	for part in source["parts"]:
		if String(part["role"]) == "surface":
			top_id = String(part["part_id"])
		elif leg_a_id.is_empty():
			leg_a_id = String(part["part_id"])
	var ports: Array = Array(facets.get("composite_exposed_ports", [])).duplicate(true)
	ports.append({"port_id": "port/climb-rung", "part_id": leg_a_id, "port_kind": "CLIMB_POINT", "local_position_m": [0.0, 0.5, 0.0], "metadata": {"label": "Climb rung"}})
	ports.append({"port_id": "port/container-access", "part_id": top_id, "port_kind": "CONTAINER_ACCESS", "local_position_m": [0.0, 0.0, 0.0], "metadata": {"label": "Storage access"}})
	ports.append({"port_id": "port/seat", "part_id": top_id, "port_kind": "SEAT", "local_position_m": [0.0, 0.0, 0.0], "metadata": {"label": "Seat"}})
	ports.append({"port_id": "port/workstation", "part_id": top_id, "port_kind": "WORKSTATION", "local_position_m": [0.0, 0.0, 0.0], "metadata": {"label": "Control station"}})
	ports.sort_custom(func(left, right): return String(left["port_id"]) < String(right["port_id"]))
	facets["composite_exposed_ports"] = ports
	return SnapshotScript.create(
		String(source["construct_id"]),
		String(source["root_item_instance_id"]),
		int(source["state_revision"]),
		String(source["build_state"]),
		Array(source["parts"]),
		Array(source["bonds"]),
		facets
	)


static func damaged_table_snapshot(instance_key: String = "damaged") -> Dictionary:
	var source: Dictionary = table_snapshot(instance_key)
	var bonds: Array = Array(source["bonds"]).duplicate(true)
	bonds[0]["state"] = "BROKEN"
	var compiled_result: Dictionary = CapabilityCompilerScript.compile(Array(source["parts"]), bonds)
	assert(bool(compiled_result.get("success", false)))
	var facets: Dictionary = Dictionary(compiled_result["compiled"]).duplicate(true)
	for field in [
		"composite_definition_id",
		"composite_definition_version",
		"composite_definition_checksum",
		"composite_instantiation_id",
		"composite_parameters",
		"composite_exposed_ports",
	]:
		if source["compiled_facets"].has(field):
			facets[field] = source["compiled_facets"][field]
	facets["operational"] = false
	return SnapshotScript.create(
		String(source["construct_id"]),
		String(source["root_item_instance_id"]),
		int(source["state_revision"]) + 1,
		"DAMAGED",
		Array(source["parts"]),
		bonds,
		facets
	)
