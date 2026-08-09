extends RefCounted

const T1A2BuilderScript = preload("res://scripts/labs/t1/t1_d0_authoritative_outpost_builder.gd")
const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const FactoryScript = preload("res://scripts/items/services/item_domain_factory.gd")
const DefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemScript = preload("res://scripts/items/domain/item_instance.gd")
const ItemIdGeneratorScript = preload("res://scripts/items/services/item_id_generator.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const AdapterScript = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const BridgeScript = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")

const SCHEMA := "planet_simulator.t1a3_d0_item_graph_materializer.v1"
const PROFILE_ID := "D0"
const CONSTRUCT_ID := "construct/t1/lunar-outpost/d0"
const EXPECTED_PART_COUNT := 64
const EXPECTED_INTERACTIVE_COUNT := 6
const EXPECTED_TOTAL_ITEM_COUNT := 71
const PLAN_ID := "plan/t1a3/d0/materialize"
const OPERATION_ID := "operation/t1a3/d0/materialize"
const AUTHORITY_OWNER_ID := "authority/t1a3/d0"
const AUTHORITY_EPOCH := 1


static func build_resolved_snapshot() -> Dictionary:
	var source: Dictionary = T1A2BuilderScript.build_d0()
	if not bool(source.get("success", false)):
		return source
	var source_snapshot_value = source.get("snapshot", {})
	if not source_snapshot_value is Dictionary:
		return _failure("T1A3_SOURCE_SNAPSHOT_MISSING")
	var source_snapshot: Dictionary = Dictionary(source_snapshot_value)
	var source_validation: Dictionary = SnapshotScript.validate(source_snapshot)
	if not bool(source_validation.get("success", false)):
		return _failure("T1A3_SOURCE_SNAPSHOT_INVALID", {"cause": source_validation})

	var semantic_to_global: Dictionary = {}
	var global_to_semantic: Dictionary = {}
	var root_semantic := String(source_snapshot.get("root_item_instance_id", ""))
	var root_global := deterministic_global_item_id(root_semantic)
	if not ItemIdGeneratorScript.is_global_id(root_global):
		return _failure("T1A3_ROOT_GLOBAL_ITEM_ID_INVALID")
	semantic_to_global[root_semantic] = root_global
	global_to_semantic[root_global] = root_semantic

	var aggregate = AggregateScript.new()
	var setup: Dictionary = aggregate.setup(CONSTRUCT_ID, root_global)
	if not bool(setup.get("success", false)):
		return _failure("T1A3_AGGREGATE_SETUP_FAILED", {"cause": setup})

	var revision := 0
	var part_item_ids: Array = []
	for part_value in source_snapshot.get("parts", []):
		if not part_value is Dictionary:
			return _failure("T1A3_SOURCE_PART_INVALID")
		var source_part: Dictionary = Dictionary(part_value)
		var semantic_item_id := String(source_part.get("item_instance_id", ""))
		var global_item_id := deterministic_global_item_id(semantic_item_id)
		if not ItemIdGeneratorScript.is_global_id(global_item_id):
			return _failure("T1A3_PART_GLOBAL_ITEM_ID_INVALID", {"semantic_item_id": semantic_item_id})
		if global_to_semantic.has(global_item_id):
			return _failure("T1A3_GLOBAL_ITEM_ID_COLLISION", {"global_item_id": global_item_id})
		semantic_to_global[semantic_item_id] = global_item_id
		global_to_semantic[global_item_id] = semantic_item_id
		part_item_ids.append(global_item_id)
		var resolved_part := source_part.duplicate(true)
		resolved_part["item_instance_id"] = global_item_id
		var added: Dictionary = aggregate.add_part(
			"operation/t1a3/d0/resolve-part/%s" % String(source_part.get("part_id", "")).get_file(),
			revision,
			resolved_part
		)
		if not bool(added.get("success", false)):
			return _failure("T1A3_RESOLVED_PART_ADD_FAILED", {"cause": added})
		revision = int(added.get("state_revision", -1))

	if part_item_ids.size() != EXPECTED_PART_COUNT:
		return _failure("T1A3_RESOLVED_PART_COUNT_MISMATCH")

	for bond_value in source_snapshot.get("bonds", []):
		if not bond_value is Dictionary:
			return _failure("T1A3_SOURCE_BOND_INVALID")
		var bond: Dictionary = Dictionary(bond_value).duplicate(true)
		var added: Dictionary = aggregate.add_bond(
			"operation/t1a3/d0/resolve-bond/%s" % String(bond.get("bond_id", "")),
			revision,
			bond
		)
		if not bool(added.get("success", false)):
			return _failure("T1A3_RESOLVED_BOND_ADD_FAILED", {"cause": added})
		revision = int(added.get("state_revision", -1))

	var operational: Dictionary = aggregate.set_build_state(
		"operation/t1a3/d0/resolve-operational",
		revision,
		"OPERATIONAL"
	)
	if not bool(operational.get("success", false)):
		return _failure("T1A3_RESOLVED_OPERATIONAL_FAILED", {"cause": operational})

	var resolved_snapshot: Dictionary = aggregate.export_snapshot()
	var resolved_validation: Dictionary = SnapshotScript.validate(resolved_snapshot)
	if not bool(resolved_validation.get("success", false)):
		return _failure("T1A3_RESOLVED_SNAPSHOT_INVALID", {"cause": resolved_validation})
	if int(resolved_snapshot.get("state_revision", -1)) != int(source_snapshot.get("state_revision", -2)):
		return _failure("T1A3_RESOLUTION_CHANGED_STATE_REVISION")

	var interactive_item_ids: Array = []
	var deferred_ids: Array = Array(source.get("deferred_item_graph_ids", [])).duplicate(true)
	if deferred_ids.size() != EXPECTED_INTERACTIVE_COUNT:
		return _failure("T1A3_INTERACTIVE_SOURCE_COUNT_MISMATCH")
	for semantic_value in deferred_ids:
		var semantic_id := String(semantic_value)
		var global_id := deterministic_global_item_id(semantic_id)
		if not ItemIdGeneratorScript.is_global_id(global_id):
			return _failure("T1A3_INTERACTIVE_GLOBAL_ITEM_ID_INVALID", {"semantic_item_id": semantic_id})
		if global_to_semantic.has(global_id):
			return _failure("T1A3_GLOBAL_ITEM_ID_COLLISION", {"global_item_id": global_id})
		semantic_to_global[semantic_id] = global_id
		global_to_semantic[global_id] = semantic_id
		interactive_item_ids.append(global_id)

	return {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"profile_id": PROFILE_ID,
		"construct_id": CONSTRUCT_ID,
		"fixture_checksum": String(source.get("fixture_checksum", "")),
		"t1a2_snapshot_checksum": String(source_snapshot.get("checksum", "")),
		"resolved_snapshot_checksum": String(resolved_snapshot.get("checksum", "")),
		"root_item_id": root_global,
		"part_item_ids": part_item_ids,
		"interactive_item_ids": interactive_item_ids,
		"semantic_to_global_item_ids": semantic_to_global,
		"global_to_semantic_item_ids": global_to_semantic,
		"source_snapshot": source_snapshot.duplicate(true),
		"snapshot": resolved_snapshot,
	}


static func materialize(m0_root: String) -> Dictionary:
	var resolved: Dictionary = build_resolved_snapshot()
	if not bool(resolved.get("success", false)):
		return resolved
	if m0_root.strip_edges().is_empty():
		return _failure("T1A3_M0_ROOT_REQUIRED")

	var domain: Dictionary = FactoryScript.create()
	_register_definitions(domain)
	var source_items_result: Dictionary = _add_source_items(domain, resolved)
	if not bool(source_items_result.get("success", false)):
		return source_items_result
	var initial_graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(initial_graph_validation.get("success", false)):
		return _failure("T1A3_INITIAL_ITEM_GRAPH_INVALID", {"cause": initial_graph_validation})

	var constructs = ConstructStoreScript.new()
	var bridge = BridgeScript.new()
	var bridge_setup: Dictionary = bridge.setup(m0_root)
	if not bool(bridge_setup.get("success", false)):
		return _failure("T1A3_M0_BRIDGE_SETUP_FAILED", {"cause": bridge_setup})
	var adapter = AdapterScript.new()
	var adapter_setup: Dictionary = adapter.setup(
		domain.items,
		domain.containers,
		domain.validator,
		domain.mass,
		domain.operations,
		constructs,
		bridge,
		AUTHORITY_OWNER_ID,
		AUTHORITY_EPOCH,
		0,
		0,
		0,
		{}
	)
	if not bool(adapter_setup.get("success", false)):
		return _failure("T1A3_AUTHORITATIVE_ADAPTER_SETUP_FAILED", {"cause": adapter_setup})

	var snapshot: Dictionary = Dictionary(resolved["snapshot"])
	var root_projection: Dictionary = PlannerScript.create_root_projection(
		String(resolved["root_item_id"]),
		CONSTRUCT_ID,
		"T1 D0 Lunar Outpost",
		RelationsScript.world()
	)
	var part_sources: Array = []
	for part_value in snapshot.get("parts", []):
		var part: Dictionary = Dictionary(part_value)
		var projection: Dictionary = adapter.get_item_projection(String(part["item_instance_id"]))
		if projection.is_empty():
			return _failure("T1A3_PART_SOURCE_PROJECTION_MISSING", {"part_id": String(part["part_id"])})
		part_sources.append(projection)

	var plan_result: Dictionary = PlannerScript.build_assembly_plan(
		PLAN_ID,
		OPERATION_ID,
		snapshot,
		root_projection,
		part_sources,
		{}
	)
	if not bool(plan_result.get("success", false)):
		return _failure("T1A3_ASSEMBLY_PLAN_FAILED", {"cause": plan_result})
	var plan: Dictionary = Dictionary(plan_result["plan"])
	var applied: Dictionary = adapter.apply_plan(plan)
	if not bool(applied.get("success", false)):
		return _failure("T1A3_AUTHORITATIVE_MATERIALIZATION_FAILED", {"cause": applied})

	var final_graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(final_graph_validation.get("success", false)):
		return _failure("T1A3_FINAL_ITEM_GRAPH_INVALID", {"cause": final_graph_validation})
	var stored_snapshot: Dictionary = adapter.get_construct_snapshot(CONSTRUCT_ID)
	var stored_validation: Dictionary = SnapshotScript.validate(stored_snapshot)
	if not bool(stored_validation.get("success", false)):
		return _failure("T1A3_STORED_CONSTRUCT_INVALID", {"cause": stored_validation})

	return {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"resolved": resolved,
		"plan": plan,
		"apply_result": applied,
		"domain": domain,
		"constructs": constructs,
		"bridge": bridge,
		"adapter": adapter,
		"stored_snapshot": stored_snapshot,
		"authority_report": adapter.get_authority_report(),
	}


static func deterministic_global_item_id(semantic_reference: String) -> String:
	var semantic := semantic_reference.strip_edges().to_lower()
	if semantic.is_empty():
		return ""
	var digest := semantic.sha256_text()
	if digest.length() < 32:
		return ""
	return "item/%s-%s-4%s-8%s-%s" % [
		digest.substr(0, 8),
		digest.substr(8, 4),
		digest.substr(13, 3),
		digest.substr(17, 3),
		digest.substr(20, 12),
	]


static func _register_definitions(domain: Dictionary) -> void:
	for row in [
		{"id": "construct_root", "display_name": "Construct root", "max_stack": 1, "unit_mass_kg": 0.1, "external_volume_l": 0.1, "tags": ["construction"]},
		{"id": "t1_d0_foundation", "display_name": "D0 foundation", "max_stack": 1, "unit_mass_kg": 250.0, "external_volume_l": 120.0, "tags": ["construction_part", "t1_d0"]},
		{"id": "t1_d0_panel", "display_name": "D0 structural panel", "max_stack": 1, "unit_mass_kg": 80.0, "external_volume_l": 80.0, "tags": ["construction_part", "t1_d0"]},
		{"id": "t1_d0_door", "display_name": "D0 door fixture", "max_stack": 1, "unit_mass_kg": 45.0, "external_volume_l": 35.0, "tags": ["interactive_fixture", "door", "t1_d0"]},
		{"id": "t1_d0_storage", "display_name": "D0 storage fixture", "max_stack": 1, "unit_mass_kg": 65.0, "external_volume_l": 90.0, "tags": ["interactive_fixture", "storage", "t1_d0"]},
		{"id": "t1_d0_generator", "display_name": "D0 generator fixture", "max_stack": 1, "unit_mass_kg": 120.0, "external_volume_l": 110.0, "tags": ["interactive_fixture", "generator", "t1_d0"]},
		{"id": "t1_d0_battery", "display_name": "D0 battery fixture", "max_stack": 1, "unit_mass_kg": 75.0, "external_volume_l": 55.0, "tags": ["interactive_fixture", "battery", "t1_d0"]},
		{"id": "t1_d0_lamp", "display_name": "D0 lamp fixture", "max_stack": 1, "unit_mass_kg": 6.0, "external_volume_l": 8.0, "tags": ["interactive_fixture", "lamp", "t1_d0"]},
		{"id": "t1_d0_console", "display_name": "D0 console fixture", "max_stack": 1, "unit_mass_kg": 25.0, "external_volume_l": 20.0, "tags": ["interactive_fixture", "console", "t1_d0"]},
	]:
		domain.items.register_definition(DefinitionScript.new(row))


static func _add_source_items(domain: Dictionary, resolved: Dictionary) -> Dictionary:
	var snapshot: Dictionary = Dictionary(resolved["snapshot"])
	var inverse_map: Dictionary = Dictionary(resolved["global_to_semantic_item_ids"])
	for part_value in snapshot.get("parts", []):
		var part: Dictionary = Dictionary(part_value)
		var item_id := String(part["item_instance_id"])
		var position: Array = Array(part.get("local_position_m", [0.0, 0.0, 0.0]))
		var transform := Transform3D(Basis.IDENTITY, Vector3(float(position[0]), float(position[1]), float(position[2])))
		var definition_id := "t1_d0_foundation" if String(part.get("part_kind", "")) == "FOUNDATION" else "t1_d0_panel"
		var item = ItemScript.new({
			"instance_id": item_id,
			"definition_id": definition_id,
			"display_name": "D0 structural part %s" % String(part.get("part_id", "")).get_file(),
			"quantity": 1,
			"relation": RelationsScript.world(transform),
			"components": {
				"t1_fixture": {
					"schema": "planet_simulator.t1_fixture_item_component.v1",
					"construct_id": CONSTRUCT_ID,
					"semantic_item_reference": String(inverse_map.get(item_id, "")),
					"part_id": String(part.get("part_id", "")),
					"kind": "STRUCTURAL_PART",
				}
			},
			"revision": 0,
		})
		if not domain.items.add_item(item):
			return _failure("T1A3_STRUCTURAL_SOURCE_ITEM_ADD_FAILED", {"item_id": item_id})

	var interactive_ids: Array = Array(resolved["interactive_item_ids"])
	for index in range(interactive_ids.size()):
		var item_id := String(interactive_ids[index])
		var semantic := String(inverse_map.get(item_id, ""))
		var kind := _interactive_kind(semantic)
		var definition_id := _interactive_definition_id(kind)
		var transform := Transform3D(Basis.IDENTITY, Vector3(-2.5 + float(index), 1.0, 0.0))
		var item = ItemScript.new({
			"instance_id": item_id,
			"definition_id": definition_id,
			"display_name": "D0 %s fixture" % kind.to_lower(),
			"quantity": 1,
			"relation": RelationsScript.world(transform),
			"components": {
				"t1_fixture": {
					"schema": "planet_simulator.t1_fixture_item_component.v1",
					"construct_id": CONSTRUCT_ID,
					"semantic_item_reference": semantic,
					"kind": kind,
					"gameplay_semantics_materialized": false,
				}
			},
			"revision": 0,
		})
		if not domain.items.add_item(item):
			return _failure("T1A3_INTERACTIVE_SOURCE_ITEM_ADD_FAILED", {"item_id": item_id, "semantic_item_id": semantic})
	return {"success": true, "error_code": ""}


static func _interactive_kind(semantic_id: String) -> String:
	for kind in ["door", "container", "generator", "battery", "lamp", "console"]:
		if semantic_id.contains("/%s/" % kind):
			return kind.to_upper()
	return "FIXTURE"


static func _interactive_definition_id(kind: String) -> String:
	match kind:
		"DOOR": return "t1_d0_door"
		"CONTAINER": return "t1_d0_storage"
		"GENERATOR": return "t1_d0_generator"
		"BATTERY": return "t1_d0_battery"
		"LAMP": return "t1_d0_lamp"
		"CONSOLE": return "t1_d0_console"
	return "t1_d0_panel"


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code}
	for key in details:
		result[key] = details[key]
	return result
