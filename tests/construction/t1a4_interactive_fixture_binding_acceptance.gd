extends SceneTree

const BinderScript = preload("res://scripts/labs/t1/t1_d0_interactive_fixture_binder.gd")
const T1A3Script = preload("res://scripts/labs/t1/t1_d0_item_graph_materializer.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const ItemIdGeneratorScript = preload("res://scripts/items/services/item_id_generator.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")
const NetworkScript = preload("res://scripts/construction/utilities/construction_utility_network_definition.gd")
const DemandScript = preload("res://scripts/construction/utilities/construction_utility_demand.gd")
const StorageScript = preload("res://scripts/construction/utilities/construction_utility_storage_state.gd")
const ExecutionProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const CONSTRUCT_ID := "construct/t1/lunar-outpost/d0"
const STORAGE_CONTAINER_ID := "container/t1/d0/storage-main"
const EXPECTED_ITEM_COUNT := 71
const EXPECTED_PART_COUNT := 64
const EXPECTED_BINDING_COUNT := 6

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_bound_authoritative_composition()
	_test_binding_contracts_and_utilities()
	_test_replay_and_p0_boundaries()
	_finish()

func _fixture() -> Dictionary:
	var root := "user://t1a4-acceptance-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	return BinderScript.materialize_bound(root)

func _test_bound_authoritative_composition() -> void:
	var result := _fixture()
	_assert_ok(result, "T1A.4 bound composition failed")
	if not bool(result.get("success", false)): return
	var domain: Dictionary = result["domain"]
	var resolved: Dictionary = result["resolved"]
	var snapshot: Dictionary = resolved["snapshot"]
	var profile: Dictionary = result["binding_profile"]

	_assert_ok(BinderScript.validate_binding_profile(profile), "T1A.4 binding profile invalid")
	_assert_ok(SnapshotScript.validate(snapshot), "T1A.4 source ConstructSnapshot invalid")
	_assert(String(snapshot.get("construct_id", "")) == CONSTRUCT_ID, "Construct identity changed")
	_assert(Array(snapshot.get("parts", [])).size() == EXPECTED_PART_COUNT, "Part count changed")
	_assert(int(snapshot.get("state_revision", -1)) == 177, "Construction revision changed")
	_assert(domain.items.all_items().size() == EXPECTED_ITEM_COUNT, "Item count changed after fixture binding")
	_assert_ok(domain.validator.validate_graph(), "Bound production Item Graph invalid")

	var binding_rows: Array = profile["bindings"]
	_assert(binding_rows.size() == EXPECTED_BINDING_COUNT, "Binding count mismatch")
	var snapshot_parts := {}
	for part_value in snapshot.get("parts", []):
		snapshot_parts[String(Dictionary(part_value)["part_id"])] = true
	var seen_kinds := {}
	for binding_value in binding_rows:
		var binding: Dictionary = binding_value
		var kind := String(binding["kind"])
		var item_id := String(binding["item_id"])
		seen_kinds[kind] = true
		_assert(ItemIdGeneratorScript.is_global_id(item_id), "Binding does not point to global Item: %s" % kind)
		_assert(snapshot_parts.has(String(binding["host_part_id"])), "Binding host part missing from D0: %s" % kind)
		var item = domain.items.get_item(item_id)
		_assert(item != null, "Bound Item missing: %s" % kind)
		if item == null: continue
		_assert(RelationsScript.kind_of(item.relation) == RelationsScript.WORLD, "Interactive fixture relation changed: %s" % kind)
		_assert(int(item.revision) == 0, "Binding bootstrap changed Item revision: %s" % kind)
		var fixture: Dictionary = Dictionary(item.components.get("t1_fixture", {}))
		_assert(bool(fixture.get("gameplay_semantics_materialized", false)), "Fixture binding not marked materialized: %s" % kind)
		var component: Dictionary = Dictionary(item.components.get("fixture_binding", {}))
		_assert(String(component.get("construct_id", "")) == CONSTRUCT_ID, "Binding component lost construct identity: %s" % kind)
		_assert(String(component.get("host_part_id", "")) == String(binding["host_part_id"]), "Binding host mismatch: %s" % kind)
		_assert(String(component.get("capability_id", "")) == String(binding["capability_id"]), "Binding capability mismatch: %s" % kind)
	_assert(seen_kinds.keys().size() == 6, "Not all six fixture kinds were bound")
	for expected in ["BATTERY", "CONSOLE", "CONTAINER", "DOOR", "GENERATOR", "LAMP"]:
		_assert(seen_kinds.has(expected), "Missing fixture binding: %s" % expected)

	var storage_binding := _binding(profile, "CONTAINER")
	var storage_item = domain.items.get_item(String(storage_binding.get("item_id", "")))
	_assert(storage_item != null, "Storage fixture Item missing")
	if storage_item != null:
		_assert(storage_item.owns_container(), "Storage fixture does not own a production container")
		_assert(storage_item.get_owned_container_id() == STORAGE_CONTAINER_ID, "Storage fixture container component mismatch")
	var storage = domain.containers.get_container(STORAGE_CONTAINER_ID)
	_assert(storage != null, "Production storage container missing")
	if storage != null:
		_assert(storage.owner_kind == "ITEM_INSTANCE", "Storage owner kind is not ITEM_INSTANCE")
		_assert(storage.owner_id == String(storage_binding.get("item_id", "")), "Storage owner back-reference mismatch")
		_assert(storage.is_slot_container() and int(storage.slot_count) == 24, "Storage must expose 24 slots")
		_assert(storage.item_ids.is_empty(), "Fresh D0 storage is not empty")

	var authority: Dictionary = result["authority_report"]
	_assert(int(authority.get("item_graph_revision", -1)) == 1, "Item Graph authority revision mismatch")
	_assert(int(authority.get("ledger_revision", -1)) == 1, "Ledger authority revision mismatch")
	_assert(int(authority.get("server_tick", -1)) == 1, "Authority tick mismatch")
	_assert(int(Dictionary(authority.get("construct_authority_revisions", {})).get(CONSTRUCT_ID, -1)) == 0, "Construct authority revision mismatch")
	var exported: Dictionary = result["adapter"].export_state()
	_assert(Array(Dictionary(exported.get("container_registry", {})).get("containers", [])).size() == 1, "Bound container was not included in authoritative Item Graph state")
	var m0 := result["bridge"].get_state_report()
	_assert_ok(m0, "M0 state report unavailable")
	if bool(m0.get("success", false)):
		_assert(int(m0.get("details", {}).get("aggregate_count", -1)) == 3, "M0 aggregate composition changed")

func _test_binding_contracts_and_utilities() -> void:
	var result := _fixture()
	_assert_ok(result, "T1A.4 fixture failed for contract checks")
	if not bool(result.get("success", false)): return
	var profile: Dictionary = result["binding_profile"]
	var capabilities: Array = profile["behavior_capabilities"]
	var affordances: Array = profile["behavior_affordances"]
	_assert(capabilities.size() == 6, "Expected six capabilities")
	_assert(affordances.size() == 10, "Expected ten affordances")
	var capability_kinds: Array = []
	for capability_value in capabilities:
		var capability: Dictionary = capability_value
		_assert_ok(CapabilityScript.validate(capability), "Capability rejected")
		capability_kinds.append(String(capability["capability_kind"]))
	capability_kinds.sort()
	_assert(capability_kinds == ["CONTAINER", "DOOR_CONTROL", "LIGHTING", "POWER_SOURCE", "POWER_STORAGE", "WORKSTATION"], "Capability vocabulary mismatch")
	var actions: Array = []
	for affordance_value in affordances:
		var affordance: Dictionary = affordance_value
		_assert_ok(AffordanceScript.validate(affordance), "Affordance rejected")
		actions.append(String(affordance["action_kind"]))
	actions.sort()
	_assert(actions == ["CLOSE_DOOR", "INSPECT_BATTERY", "OPEN_CONTAINER", "OPEN_DOOR", "START_GENERATOR", "STOP_GENERATOR", "STORE_ITEM", "TAKE_ITEM", "TOGGLE_LIGHT", "USE_WORKSTATION"], "Affordance vocabulary mismatch")

	var power: Dictionary = profile["power_network"]
	var data: Dictionary = profile["data_network"]
	_assert_ok(NetworkScript.validate(power), "Power network rejected")
	_assert_ok(NetworkScript.validate(data), "Data network rejected")
	_assert(String(power["construct_id"]) == CONSTRUCT_ID and String(data["construct_id"]) == CONSTRUCT_ID, "Utility construct identity mismatch")
	_assert(int(power["construct_revision"]) == 177 and int(data["construct_revision"]) == 177, "Utility construct revision pin mismatch")
	_assert(String(power["construct_checksum"]) == String(profile["construct_checksum"]), "Power construct checksum pin mismatch")
	_assert(String(data["construct_checksum"]) == String(profile["construct_checksum"]), "Data construct checksum pin mismatch")
	_assert(Array(power["nodes"]).size() == 6, "Power node count mismatch")
	_assert(Array(data["nodes"]).size() == 3, "Data node count mismatch")

	for demand_value in profile["power_demands"]:
		_assert_ok(DemandScript.validate(Dictionary(demand_value)), "Power demand rejected")
	for demand_value in profile["data_demands"]:
		_assert_ok(DemandScript.validate(Dictionary(demand_value)), "Data demand rejected")
	_assert_ok(StorageScript.validate(Dictionary(profile["power_storage"])), "Battery storage state rejected")
	var power_exec: Dictionary = profile["power_execution_profile"]
	var data_exec: Dictionary = profile["data_execution_profile"]
	_assert_ok(ExecutionProfileScript.validate(power_exec), "Power execution profile rejected")
	_assert_ok(ExecutionProfileScript.validate(data_exec), "Data execution profile rejected")
	_assert(String(power_exec["status"]) == "BALANCED", "D0 power network is not balanced")
	_assert(String(data_exec["status"]) == "BALANCED", "D0 data network is not balanced")
	for allocation in power_exec["allocations"]:
		_assert(String(allocation["status"]) == "FULL", "Power demand not fully served")
	for allocation in data_exec["allocations"]:
		_assert(String(allocation["status"]) == "FULL", "Data demand not fully served")

	var bindings: Array = profile["bindings"]
	var by_kind := {}
	for binding_value in bindings: by_kind[String(Dictionary(binding_value)["kind"])] = binding_value
	_assert(Array(Dictionary(by_kind["GENERATOR"])["utility_node_ids"]).size() == 1, "Generator utility binding missing")
	_assert(Array(Dictionary(by_kind["BATTERY"])["utility_node_ids"]).size() == 1, "Battery utility binding missing")
	_assert(Array(Dictionary(by_kind["LAMP"])["utility_node_ids"]).size() == 1, "Lamp utility binding missing")
	_assert(Array(Dictionary(by_kind["DOOR"])["utility_node_ids"]).size() == 2, "Door power+data binding missing")
	_assert(Array(Dictionary(by_kind["CONSOLE"])["utility_node_ids"]).size() == 2, "Console power+data binding missing")
	_assert(String(Dictionary(by_kind["CONTAINER"])["container_id"]) == STORAGE_CONTAINER_ID, "Storage container binding missing")

func _test_replay_and_p0_boundaries() -> void:
	var result := _fixture()
	_assert_ok(result, "T1A.4 fixture failed for replay/P0 checks")
	if not bool(result.get("success", false)): return
	var adapter = result["adapter"]
	var before := UtilsScript.canonical_json(adapter.export_state())
	var replay: Dictionary = adapter.apply_plan(Dictionary(result["plan"]))
	_assert(UtilsScript.canonical_json(replay) == UtilsScript.canonical_json(result["apply_result"]), "Exact bound assembly replay changed result")
	_assert(UtilsScript.canonical_json(adapter.export_state()) == before, "Exact bound assembly replay mutated state")
	_assert(int(adapter.get_authority_report().get("server_tick", -1)) == 1, "Replay advanced authority tick")

	var t1a3: Dictionary = T1A3Script.build_resolved_snapshot()
	_assert_ok(t1a3, "T1A.3 baseline unavailable")
	if bool(t1a3.get("success", false)):
		_assert(UtilsScript.canonical_json(result["resolved"]["snapshot"]) == UtilsScript.canonical_json(t1a3["snapshot"]), "T1A.4 changed canonical ConstructSnapshot")
	var snapshot_text := JSON.stringify(result["resolved"]["snapshot"])
	for forbidden in ["fixture_binding", "container/t1/d0", "utility-node/", "utility-network/", "affordance/t1a4", "capability/t1a4", "authority/t1a4", "visual_profile_id", "detail_mode"]:
		_assert(not snapshot_text.contains(forbidden), "T1A.4 leaked binding/runtime data into canonical ConstructSnapshot: %s" % forbidden)
	var profile_text := JSON.stringify(result["binding_profile"])
	_assert(not profile_text.contains("server_id"), "Binding profile encoded server routing identity")
	_assert(not profile_text.contains("visual_profile_id"), "Binding profile encoded presentation identity")
	_assert(not profile_text.contains("material_definition_id"), "Binding profile invented material ontology")

func _binding(profile: Dictionary, kind: String) -> Dictionary:
	for value in profile.get("bindings", []):
		if String(Dictionary(value).get("kind", "")) == kind: return Dictionary(value)
	return {}

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("T1A.4 interactive fixture binding: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("T1A.4 interactive fixture binding: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
