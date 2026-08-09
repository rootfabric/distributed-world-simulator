extends SceneTree

const T1A2BuilderScript = preload("res://scripts/labs/t1/t1_d0_authoritative_outpost_builder.gd")
const MaterializerScript = preload("res://scripts/labs/t1/t1_d0_item_graph_materializer.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ItemIdGeneratorScript = preload("res://scripts/items/services/item_id_generator.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const CONSTRUCT_ID := "construct/t1/lunar-outpost/d0"
const EXPECTED_PART_COUNT := 64
const EXPECTED_INTERACTIVE_COUNT := 6
const EXPECTED_TOTAL_ITEM_COUNT := 71
const EXPECTED_STATE_REVISION := 177

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	_test_deterministic_global_identity_resolution()
	_test_authoritative_item_graph_materialization()
	_test_p0_and_stage_boundaries()
	_finish()


func _test_deterministic_global_identity_resolution() -> void:
	var source: Dictionary = T1A2BuilderScript.build_d0()
	_assert_ok(source, "T1A.2 source snapshot failed")
	if not bool(source.get("success", false)):
		return
	var first: Dictionary = MaterializerScript.build_resolved_snapshot()
	var second: Dictionary = MaterializerScript.build_resolved_snapshot()
	_assert_ok(first, "First T1A.3 identity resolution failed")
	_assert_ok(second, "Repeated T1A.3 identity resolution failed")
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		return

	_assert(String(first.get("construct_id", "")) == CONSTRUCT_ID, "Construct identity changed during item resolution")
	_assert(String(first.get("fixture_checksum", "")) == String(source.get("fixture_checksum", "")), "Fixture checksum changed during item resolution")
	_assert(String(first.get("t1a2_snapshot_checksum", "")) == String(source.get("snapshot_checksum", "")), "T1A.2 provenance checksum changed")
	_assert(first.get("semantic_to_global_item_ids", {}) == second.get("semantic_to_global_item_ids", {}), "Global item resolution is not deterministic")
	_assert(first.get("snapshot", {}) == second.get("snapshot", {}), "Resolved ConstructSnapshot is not deterministic")
	_assert(String(first.get("resolved_snapshot_checksum", "")) == String(second.get("resolved_snapshot_checksum", "")), "Resolved snapshot checksum is not deterministic")
	_assert(String(first.get("resolved_snapshot_checksum", "")) != String(first.get("t1a2_snapshot_checksum", "")), "T1A.3 did not replace reserved item references")

	var snapshot: Dictionary = Dictionary(first["snapshot"])
	_assert_ok(SnapshotScript.validate(snapshot), "Resolved production ConstructSnapshot invalid")
	_assert(int(snapshot.get("state_revision", -1)) == EXPECTED_STATE_REVISION, "Item identity resolution changed Construction revision")
	_assert(Array(snapshot.get("parts", [])).size() == EXPECTED_PART_COUNT, "Resolved snapshot part count changed")
	_assert(Array(snapshot.get("bonds", [])).size() == 112, "Resolved snapshot bond count changed")
	_assert(ItemIdGeneratorScript.is_global_id(String(snapshot.get("root_item_instance_id", ""))), "Resolved root is not a global Item ID")

	var source_parts: Array = Array(Dictionary(source["snapshot"]).get("parts", []))
	var source_part_ids: Array = []
	for part_value in source_parts:
		source_part_ids.append(String(Dictionary(part_value).get("part_id", "")))
	source_part_ids.sort()
	var resolved_part_ids: Array = []
	var seen_global_ids: Dictionary = {}
	for part_value in snapshot.get("parts", []):
		var part: Dictionary = Dictionary(part_value)
		resolved_part_ids.append(String(part.get("part_id", "")))
		var global_item_id := String(part.get("item_instance_id", ""))
		_assert(ItemIdGeneratorScript.is_global_id(global_item_id), "Structural part is not backed by a global Item ID")
		_assert(not seen_global_ids.has(global_item_id), "Resolved structural global Item ID reused")
		seen_global_ids[global_item_id] = true
	resolved_part_ids.sort()
	_assert(resolved_part_ids == source_part_ids, "Part identity changed while resolving Item IDs")

	var mapping: Dictionary = Dictionary(first["semantic_to_global_item_ids"])
	_assert(mapping.size() == 1 + EXPECTED_PART_COUNT + EXPECTED_INTERACTIVE_COUNT, "Semantic/global Item mapping cardinality mismatch")
	for semantic_id in mapping.keys():
		_assert(String(semantic_id).begins_with("item/t1/d0/"), "Unexpected semantic reference escaped T1 namespace")
		_assert(ItemIdGeneratorScript.is_global_id(String(mapping[semantic_id])), "Semantic reference resolved to invalid global Item ID")


func _test_authoritative_item_graph_materialization() -> void:
	var root := "user://t1a3-acceptance-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var materialized: Dictionary = MaterializerScript.materialize(root)
	_assert_ok(materialized, "T1A.3 authoritative materialization failed")
	if not bool(materialized.get("success", false)):
		return
	var domain: Dictionary = Dictionary(materialized["domain"])
	var adapter = materialized["adapter"]
	var bridge = materialized["bridge"]
	var resolved: Dictionary = Dictionary(materialized["resolved"])
	var snapshot: Dictionary = Dictionary(resolved["snapshot"])
	var root_item_id := String(resolved["root_item_id"])

	_assert(domain.items.all_items().size() == EXPECTED_TOTAL_ITEM_COUNT, "Materialized Item Graph item count mismatch")
	_assert_ok(domain.validator.validate_graph(), "Materialized production Item Graph invalid")
	_assert_ok(SnapshotScript.validate(Dictionary(materialized["stored_snapshot"])), "Authoritative adapter stored invalid construct")
	_assert(UtilsScript.canonical_json(materialized["stored_snapshot"]) == UtilsScript.canonical_json(snapshot), "C2B stored construct differs from resolved T1A.3 snapshot")

	var root_item = domain.items.get_item(root_item_id)
	_assert(root_item != null, "Construct root Item was not created")
	if root_item != null:
		_assert(String(root_item.definition_id) == "construct_root", "Construct root has wrong definition")
		_assert(String(root_item.components.get("construction_root", {}).get("construct_id", "")) == CONSTRUCT_ID, "Construct root component lost D0 identity")
		_assert(RelationsScript.kind_of(root_item.relation) == RelationsScript.WORLD, "Construct root is not a WORLD Item")

	var attached_count := 0
	for part_value in snapshot.get("parts", []):
		var part: Dictionary = Dictionary(part_value)
		var item_id := String(part["item_instance_id"])
		var item = domain.items.get_item(item_id)
		_assert(item != null, "Structural Item missing after C2B assembly: %s" % item_id)
		if item == null:
			continue
		var relation: Dictionary = item.relation
		_assert(RelationsScript.kind_of(relation) == RelationsScript.ATTACHMENT, "Structural Item was not attached")
		_assert(String(relation.get("assembly_id", "")) == CONSTRUCT_ID, "Structural Item attachment construct mismatch")
		_assert(String(relation.get("parent_item_id", "")) == root_item_id, "Structural Item attachment root mismatch")
		_assert(String(relation.get("socket_id", "")) == String(part["part_id"]), "Structural Item attachment socket mismatch")
		_assert(int(item.revision) == 1, "Structural Item revision did not advance exactly once")
		var fixture_component: Dictionary = Dictionary(item.components.get("t1_fixture", {}))
		_assert(String(fixture_component.get("part_id", "")) == String(part["part_id"]), "Structural Item semantic part link lost")
		attached_count += 1
	_assert(attached_count == EXPECTED_PART_COUNT, "Wrong number of structural attachments")

	var inverse: Dictionary = Dictionary(resolved["global_to_semantic_item_ids"])
	var interactive_ids: Array = Array(resolved["interactive_item_ids"])
	_assert(interactive_ids.size() == EXPECTED_INTERACTIVE_COUNT, "Interactive Item count mismatch")
	for item_id_value in interactive_ids:
		var item_id := String(item_id_value)
		var item = domain.items.get_item(item_id)
		_assert(item != null, "Interactive fixture Item missing: %s" % item_id)
		if item == null:
			continue
		_assert(RelationsScript.kind_of(item.relation) == RelationsScript.WORLD, "T1A.3 prematurely attached interactive fixture")
		_assert(int(item.revision) == 0, "Interactive fixture revision changed without gameplay operation")
		var component: Dictionary = Dictionary(item.components.get("t1_fixture", {}))
		_assert(String(component.get("construct_id", "")) == CONSTRUCT_ID, "Interactive fixture lost construct semantic link")
		_assert(String(component.get("semantic_item_reference", "")) == String(inverse.get(item_id, "")), "Interactive semantic reference mismatch")
		_assert(not bool(component.get("gameplay_semantics_materialized", true)), "T1A.3 claimed future interactive gameplay semantics")

	var authority: Dictionary = Dictionary(materialized["authority_report"])
	_assert(int(authority.get("item_graph_revision", -1)) == 1, "Item Graph revision did not advance once")
	_assert(int(authority.get("ledger_revision", -1)) == 1, "Operation Ledger revision did not advance once")
	_assert(int(authority.get("server_tick", -1)) == 1, "Authority tick did not advance once")
	_assert(int(Dictionary(authority.get("construct_authority_revisions", {})).get(CONSTRUCT_ID, -1)) == 0, "Created construct authority revision must start at zero")
	var m0: Dictionary = bridge.get_state_report()
	_assert_ok(m0, "M0 state report failed")
	if bool(m0.get("success", false)):
		_assert(int(m0.get("details", {}).get("aggregate_count", -1)) == 3, "M0 did not commit Item Graph + ledger + construct")

	var before_replay := UtilsScript.canonical_json(adapter.export_state())
	var replay: Dictionary = adapter.apply_plan(Dictionary(materialized["plan"]))
	_assert(UtilsScript.canonical_json(replay) == UtilsScript.canonical_json(materialized["apply_result"]), "Exact T1A.3 replay changed result")
	_assert(UtilsScript.canonical_json(adapter.export_state()) == before_replay, "Exact T1A.3 replay mutated authoritative state")
	var replay_authority: Dictionary = adapter.get_authority_report()
	_assert(int(replay_authority.get("server_tick", -1)) == 1, "Exact replay advanced server tick")


func _test_p0_and_stage_boundaries() -> void:
	var resolved: Dictionary = MaterializerScript.build_resolved_snapshot()
	_assert_ok(resolved, "T1A.3 P0 fixture failed")
	if not bool(resolved.get("success", false)):
		return
	var snapshot_text := JSON.stringify(resolved["snapshot"])
	for forbidden in ["visual_profile_id", "representation_class", "detail_mode", "authority_route", "server_id", "material_definition_id"]:
		_assert(not snapshot_text.contains(forbidden), "T1A.3 leaked forbidden P0 field into ConstructSnapshot: %s" % forbidden)
	for part_value in Dictionary(resolved["snapshot"]).get("parts", []):
		_assert(not String(Dictionary(part_value).get("item_instance_id", "")).begins_with("item/t1/"), "Reserved T1 item reference survived canonical Item Graph boundary")
	_assert(not String(resolved.get("root_item_id", "")).begins_with("item/t1/"), "Reserved root item reference survived canonical Item Graph boundary")
	_assert(MaterializerScript.deterministic_global_item_id("item/t1/d0/door/main") == MaterializerScript.deterministic_global_item_id("item/t1/d0/door/main"), "Global Item ID mapping is unstable")
	_assert(MaterializerScript.deterministic_global_item_id("").is_empty(), "Empty semantic reference produced a global Item ID")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1A.3 Item Graph materialization: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1A.3 Item Graph materialization: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
