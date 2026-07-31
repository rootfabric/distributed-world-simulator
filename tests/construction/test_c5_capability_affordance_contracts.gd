extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")
const ProfileScript = preload("res://scripts/construction/behavior/construction_behavior_profile.gd")
const CompilerScript = preload("res://scripts/construction/behavior/construction_behavior_compiler.gd")
const StoreScript = preload("res://scripts/construction/behavior/construction_behavior_profile_store.gd")
const PersistenceScript = preload("res://scripts/construction/behavior/construction_behavior_persistence.gd")
const QueryScript = preload("res://scripts/construction/behavior/construction_affordance_query.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c5_affordance_fixture.gd")


class MemoryStateStore:
	extends RefCounted
	var states: Dictionary = {}

	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true)
		return {"success": true, "error_code": "", "message": ""}

	func load_state(key: String) -> Dictionary:
		if not states.has(key):
			return {"success": false, "error_code": "STATE_NOT_FOUND", "message": "STATE_NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": Dictionary(states[key]).duplicate(true)}


var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_capability_descriptor()
	_test_affordance_descriptor()
	_test_table_behavior_compilation()
	_test_non_composite_fallback()
	_test_all_affordance_kinds()
	_test_non_operational_suppression()
	_test_compiler_rejections()
	_test_query_contract()
	_test_profile_store_and_persistence()
	_finish()


func _test_capability_descriptor() -> void:
	var capability: Dictionary = CapabilityScript.create(
		"capability/support-surface/port/work-surface",
		"SUPPORT_SURFACE",
		["part/table/top"],
		["port/work-surface"],
		{"load_rating_kg": 100.0}
	)
	_assert_ok(CapabilityScript.validate(capability), "Capability descriptor rejected")
	_assert(String(capability.checksum).length() == 64, "Capability checksum missing")
	_assert(capability.provider_part_ids == ["part/table/top"], "Capability provider canonicalization failed")
	var unexpected: Dictionary = capability.duplicate(true)
	unexpected["unexpected_field"] = true
	_assert_error(CapabilityScript.validate(unexpected), "UNEXPECTED_FIELD", "Capability accepted unexpected field")
	var unsorted: Dictionary = CapabilityScript.create(
		"capability/test/providers",
		"TEST",
		["part/z", "part/a"]
	)
	unsorted.provider_part_ids = ["part/z", "part/a"]
	unsorted.checksum = CapabilityScript.compute_checksum(unsorted)
	_assert_error(CapabilityScript.validate(unsorted), "CONSTRUCTION_CAPABILITY_REFERENCE_IDS_NOT_SORTED", "Capability accepted unsorted providers")
	var empty_provider: Dictionary = CapabilityScript.create("capability/test/empty", "TEST", [])
	_assert_error(CapabilityScript.validate(empty_provider), "CONSTRUCTION_CAPABILITY_PROVIDER_REQUIRED", "Capability accepted no provider")
	var bad_checksum: Dictionary = capability.duplicate(true)
	bad_checksum.properties.load_rating_kg = 200
	_assert_error(CapabilityScript.validate(bad_checksum), "CONSTRUCTION_CAPABILITY_DESCRIPTOR_CHECKSUM_MISMATCH", "Capability accepted checksum drift")
	var canonical_float: Dictionary = capability.duplicate(true)
	var canonical_int: Dictionary = capability.duplicate(true)
	canonical_int.properties.load_rating_kg = 100
	canonical_int.checksum = CapabilityScript.compute_checksum(canonical_int)
	_assert(UtilsScript.canonical_json(canonical_float.properties) == UtilsScript.canonical_json(canonical_int.properties), "Capability properties lost numeric semantic equivalence")


func _test_affordance_descriptor() -> void:
	var affordance: Dictionary = AffordanceScript.create(
		"affordance/place-item/port/work-surface",
		"PLACE_ITEM",
		"capability/place-items/port/work-surface",
		"part/table/top",
		"port/work-surface",
		["MANIPULATE_ITEM"],
		{"load_rating_kg": 100.0},
		240
	)
	_assert_ok(AffordanceScript.validate(affordance), "Affordance descriptor rejected")
	_assert(affordance.actor_requirements == ["MANIPULATE_ITEM"], "Affordance requirements changed")
	var unsorted: Dictionary = AffordanceScript.create(
		"affordance/test/requirements",
		"TEST_ACTION",
		"capability/test/target",
		"part/test/target",
		"",
		["ZETA", "ALPHA"]
	)
	unsorted.actor_requirements = ["ZETA", "ALPHA"]
	unsorted.checksum = AffordanceScript.compute_checksum(unsorted)
	_assert_error(AffordanceScript.validate(unsorted), "CONSTRUCTION_AFFORDANCE_ACTOR_REQUIREMENTS_NOT_SORTED", "Affordance accepted unsorted actor requirements")
	var bad_capability: Dictionary = affordance.duplicate(true)
	bad_capability.capability_id = "invalid"
	bad_capability.checksum = AffordanceScript.compute_checksum(bad_capability)
	_assert_error(AffordanceScript.validate(bad_capability), "INVALID_CONSTRUCTION_AFFORDANCE_CAPABILITY_ID", "Affordance accepted invalid capability reference")
	var bad_priority: Dictionary = affordance.duplicate(true)
	bad_priority.priority = 1001
	bad_priority.checksum = AffordanceScript.compute_checksum(bad_priority)
	_assert_error(AffordanceScript.validate(bad_priority), "INVALID_CONSTRUCTION_AFFORDANCE_PRIORITY", "Affordance accepted invalid priority")
	var bad_checksum: Dictionary = affordance.duplicate(true)
	bad_checksum.action_kind = "STORE_ITEM"
	_assert_error(AffordanceScript.validate(bad_checksum), "CONSTRUCTION_AFFORDANCE_DESCRIPTOR_CHECKSUM_MISMATCH", "Affordance accepted checksum drift")


func _test_table_behavior_compilation() -> void:
	var snapshot: Dictionary = FixtureScript.table_snapshot("contracts-table", {
		"parameter/finish": "painted",
		"parameter/load-rating-kg": 125.0,
	})
	var result: Dictionary = CompilerScript.compile(snapshot)
	_assert_ok(result, "Reusable table behavior compilation failed")
	var profile: Dictionary = result.profile
	_assert_ok(ProfileScript.validate(profile), "Compiled table behavior profile invalid")
	_assert(bool(profile.operational), "Operational table profile not operational")
	_assert(String(profile.construct_id) == String(snapshot.construct_id), "Behavior profile construct identity changed")
	_assert(String(profile.construct_checksum) == String(snapshot.checksum), "Behavior profile source checksum changed")
	_assert(int(profile.construct_revision) == int(snapshot.state_revision), "Behavior profile revision changed")
	_assert(String(profile.composite_definition_id) == "composite-definition/furniture/reusable-table", "Behavior profile lost definition provenance")
	_assert(int(profile.composite_definition_version) == 1, "Behavior profile lost definition version")
	_assert(profile.capabilities.size() == 4, "Reusable table capability count mismatch")
	_assert(profile.affordances.size() == 3, "Reusable table affordance count mismatch")
	_assert(_capability_kinds(profile) == ["MOUNTING_SURFACE", "PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Reusable table capability kinds mismatch")
	_assert(_action_kinds(profile) == ["MOUNT_ITEM", "PLACE_ITEM", "USE_WORK_SURFACE"], "Reusable table affordance kinds mismatch")
	var place: Dictionary = _affordance_by_action(profile, "PLACE_ITEM")
	_assert(not place.is_empty(), "PLACE_ITEM affordance missing")
	_assert(String(place.target_port_id) == "port/work-surface", "PLACE_ITEM did not bind exposed work surface")
	_assert(float(place.parameters.load_rating_kg) == 125.0, "PLACE_ITEM lost load rating parameter")
	_assert(String(place.parameters.finish) == "painted", "PLACE_ITEM lost finish parameter")
	_assert(place.actor_requirements == ["MANIPULATE_ITEM"], "PLACE_ITEM actor requirement mismatch")
	var mount: Dictionary = _affordance_by_action(profile, "MOUNT_ITEM")
	_assert(String(mount.target_port_id) == "port/service-anchor", "MOUNT_ITEM did not bind service anchor")
	_assert(mount.actor_requirements == ["INSTALL_COMPONENT"], "MOUNT_ITEM actor requirement mismatch")
	_assert(int(profile.diagnostics.compiled_capability_count) == 4, "Profile diagnostics capability count mismatch")
	_assert(int(profile.diagnostics.compiled_affordance_count) == 3, "Profile diagnostics affordance count mismatch")
	var json_roundtrip = JSON.parse_string(JSON.stringify(profile, "", true, true))
	_assert(json_roundtrip is Dictionary, "Behavior profile did not survive JSON")
	_assert_ok(ProfileScript.validate(Dictionary(json_roundtrip)), "JSON behavior profile invalid")
	_assert(UtilsScript.canonical_json(profile) == UtilsScript.canonical_json(json_roundtrip), "Behavior profile JSON roundtrip changed semantics")
	var mismatched_provider: Dictionary = profile.duplicate(true)
	mismatched_provider.affordances[0].target_part_id = "part/missing/provider"
	mismatched_provider.affordances[0].checksum = AffordanceScript.compute_checksum(mismatched_provider.affordances[0])
	mismatched_provider.checksum = ProfileScript.compute_checksum(mismatched_provider)
	_assert_error(ProfileScript.validate(mismatched_provider), "CONSTRUCTION_BEHAVIOR_AFFORDANCE_PROVIDER_MISMATCH", "Profile accepted affordance outside capability provider")
	var mismatched_port: Dictionary = profile.duplicate(true)
	mismatched_port.affordances[0].target_port_id = "port/missing"
	mismatched_port.affordances[0].checksum = AffordanceScript.compute_checksum(mismatched_port.affordances[0])
	mismatched_port.checksum = ProfileScript.compute_checksum(mismatched_port)
	_assert_error(ProfileScript.validate(mismatched_port), "CONSTRUCTION_BEHAVIOR_AFFORDANCE_PORT_MISMATCH", "Profile accepted affordance outside capability port")


func _test_non_composite_fallback() -> void:
	var source: Dictionary = FixtureScript.table_snapshot("fallback-table")
	var facets: Dictionary = source.compiled_facets.duplicate(true)
	facets.erase("composite_exposed_ports")
	facets.erase("composite_definition_id")
	facets.erase("composite_definition_version")
	facets.erase("composite_definition_checksum")
	facets.erase("composite_instantiation_id")
	facets.erase("composite_parameters")
	var snapshot: Dictionary = SnapshotScript.create(
		String(source.construct_id),
		String(source.root_item_instance_id),
		int(source.state_revision),
		String(source.build_state),
		Array(source.parts),
		Array(source.bonds),
		facets
	)
	var result: Dictionary = CompilerScript.compile(snapshot)
	_assert_ok(result, "Non-composite fallback compilation failed")
	_assert(result.profile.capabilities.size() == 3, "Non-composite fallback capability count mismatch")
	_assert(result.profile.affordances.size() == 2, "Non-composite fallback affordance count mismatch")
	_assert(_capability_kinds(result.profile) == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Non-composite fallback capability kinds mismatch")
	_assert(_action_kinds(result.profile) == ["PLACE_ITEM", "USE_WORK_SURFACE"], "Non-composite fallback action kinds mismatch")
	_assert(String(_affordance_by_action(result.profile, "PLACE_ITEM").target_port_id).is_empty(), "Non-composite fallback invented a port")
	_assert(String(_affordance_by_action(result.profile, "PLACE_ITEM").target_part_id).begins_with("part/"), "Non-composite fallback lost provider part")
	_assert(String(result.profile.composite_definition_id).is_empty(), "Non-composite fallback invented definition provenance")
	_assert(int(result.profile.composite_definition_version) == 0, "Non-composite fallback invented definition version")


func _test_all_affordance_kinds() -> void:
	var result: Dictionary = CompilerScript.compile(FixtureScript.all_affordance_snapshot())
	_assert_ok(result, "All-affordance fixture compilation failed")
	var profile: Dictionary = result.profile
	_assert(profile.capabilities.size() == 8, "All-affordance capability count mismatch")
	_assert(profile.affordances.size() == 9, "All-affordance action count mismatch")
	_assert(_capability_kinds(profile) == [
		"CLIMBABLE",
		"CONTAINER",
		"MOUNTING_SURFACE",
		"PLACE_ITEMS",
		"SEAT",
		"SUPPORT_SURFACE",
		"WORKSTATION",
		"WORK_SURFACE",
	], "All-affordance capability kinds mismatch")
	_assert(_action_kinds(profile) == [
		"CLIMB",
		"MOUNT_ITEM",
		"OPEN_CONTAINER",
		"PLACE_ITEM",
		"SIT",
		"STORE_ITEM",
		"TAKE_ITEM",
		"USE_WORKSTATION",
		"USE_WORK_SURFACE",
	], "All-affordance action kinds mismatch")
	_assert(String(_affordance_by_action(profile, "CLIMB").target_port_id) == "port/climb-rung", "CLIMB target mismatch")
	_assert(String(_affordance_by_action(profile, "OPEN_CONTAINER").target_port_id) == "port/container-access", "OPEN_CONTAINER target mismatch")
	_assert(String(_affordance_by_action(profile, "SIT").target_port_id) == "port/seat", "SIT target mismatch")
	_assert(String(_affordance_by_action(profile, "USE_WORKSTATION").target_port_id) == "port/workstation", "USE_WORKSTATION target mismatch")


func _test_non_operational_suppression() -> void:
	var partial_result: Dictionary = CompilerScript.compile(FixtureScript.partial_table_snapshot("partial-profile"))
	_assert_ok(partial_result, "Partial table behavior compilation failed")
	_assert(not bool(partial_result.profile.operational), "Partial table profile marked operational")
	_assert(partial_result.profile.capabilities.is_empty(), "Partial table exposed capabilities")
	_assert(partial_result.profile.affordances.is_empty(), "Partial table exposed affordances")
	var damaged_result: Dictionary = CompilerScript.compile(FixtureScript.damaged_table_snapshot("damaged-profile"))
	_assert_ok(damaged_result, "Damaged table behavior compilation failed")
	_assert(String(damaged_result.profile.build_state) == "DAMAGED", "Damaged profile lost build state")
	_assert(damaged_result.profile.capabilities.is_empty(), "Damaged table retained capabilities")
	_assert(damaged_result.profile.affordances.is_empty(), "Damaged table retained affordances")


func _test_compiler_rejections() -> void:
	var source: Dictionary = FixtureScript.table_snapshot("compiler-rejection")
	var bad_capabilities: Dictionary = source.duplicate(true)
	bad_capabilities.compiled_facets.capabilities = "PLACE_ITEMS"
	bad_capabilities.checksum = SnapshotScript.compute_checksum(bad_capabilities)
	_assert_error(CompilerScript.compile(bad_capabilities), "INVALID_CONSTRUCTION_SOURCE_CAPABILITIES", "Compiler accepted non-array source capabilities")
	var missing_part: Dictionary = source.duplicate(true)
	missing_part.compiled_facets.composite_exposed_ports[0].part_id = "part/missing/provider"
	missing_part.checksum = SnapshotScript.compute_checksum(missing_part)
	_assert_error(CompilerScript.compile(missing_part), "CONSTRUCTION_COMPILED_EXPOSED_PORT_PART_MISSING", "Compiler accepted port referencing missing part")
	var duplicate_port: Dictionary = source.duplicate(true)
	duplicate_port.compiled_facets.composite_exposed_ports.append(Dictionary(duplicate_port.compiled_facets.composite_exposed_ports[0]).duplicate(true))
	duplicate_port.checksum = SnapshotScript.compute_checksum(duplicate_port)
	_assert_error(CompilerScript.compile(duplicate_port), "INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT_ID", "Compiler accepted duplicate port")
	var unsafe_port: Dictionary = source.duplicate(true)
	unsafe_port.compiled_facets.composite_exposed_ports[0].metadata.node = Node.new()
	unsafe_port.checksum = SnapshotScript.compute_checksum(unsafe_port)
	_assert(not bool(SnapshotScript.validate(unsafe_port).get("success", false)), "Unsafe source snapshot unexpectedly remained valid")
	unsafe_port.compiled_facets.composite_exposed_ports[0].metadata.node.free()


func _test_query_contract() -> void:
	var query: Dictionary = QueryScript.create(
		"affordance-query/contracts/table",
		["USE_WORK_SURFACE", "PLACE_ITEM"],
		["MANIPULATE_ITEM", "INSTALL_COMPONENT"],
		["construct/z", "construct/a"],
		{"load_rating_kg": 120.0},
		{"finish": "painted"},
		true,
		5
	)
	_assert_ok(QueryScript.validate(query), "Affordance query rejected")
	_assert(query.action_kinds == ["PLACE_ITEM", "USE_WORK_SURFACE"], "Query action canonicalization failed")
	_assert(query.actor_capabilities == ["INSTALL_COMPONENT", "MANIPULATE_ITEM"], "Query actor capability canonicalization failed")
	_assert(query.construct_ids == ["construct/a", "construct/z"], "Query construct canonicalization failed")
	var no_action: Dictionary = QueryScript.create("affordance-query/contracts/empty", [], [])
	_assert_error(QueryScript.validate(no_action), "CONSTRUCTION_AFFORDANCE_QUERY_UPPER_COLLECTION_REQUIRED", "Query accepted no action")
	var bad_minimum: Dictionary = query.duplicate(true)
	bad_minimum.minimum_properties.load_rating_kg = "heavy"
	bad_minimum.checksum = QueryScript.compute_checksum(bad_minimum)
	_assert_error(QueryScript.validate(bad_minimum), "INVALID_CONSTRUCTION_AFFORDANCE_MINIMUM_PROPERTY", "Query accepted nonnumeric minimum")
	var bad_checksum: Dictionary = query.duplicate(true)
	bad_checksum.limit = 6
	_assert_error(QueryScript.validate(bad_checksum), "CONSTRUCTION_AFFORDANCE_QUERY_CHECKSUM_MISMATCH", "Query accepted checksum drift")


func _test_profile_store_and_persistence() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Behavior store setup failed")
	var source: Dictionary = FixtureScript.table_snapshot("store")
	var first: Dictionary = store.compile_snapshot(source)
	_assert_ok(first, "Behavior store compile failed")
	_assert(not bool(first.replay), "First behavior publish marked replay")
	_assert(store.get_generation() == 1, "Behavior store generation did not advance")
	var replay: Dictionary = store.compile_snapshot(source)
	_assert_ok(replay, "Behavior store exact replay failed")
	_assert(bool(replay.replay) and store.get_generation() == 1, "Behavior replay mutated generation")
	var same_revision_source: Dictionary = source.duplicate(true)
	same_revision_source.compiled_facets.composite_parameters["parameter/finish"] = "painted"
	same_revision_source.checksum = SnapshotScript.compute_checksum(same_revision_source)
	var same_revision_profile: Dictionary = CompilerScript.compile(same_revision_source).profile
	_assert_error(store.publish_profile(same_revision_profile), "CONSTRUCTION_BEHAVIOR_SAME_REVISION_CONFLICT", "Behavior store accepted same-revision mutation")
	_assert(String(store.get_profile(String(source.construct_id)).construct_checksum) == String(source.checksum), "Rejected same-revision profile changed store")
	var damaged: Dictionary = FixtureScript.damaged_table_snapshot("store")
	var damaged_publish: Dictionary = store.compile_snapshot(damaged)
	_assert_ok(damaged_publish, "Damaged behavior profile publish failed")
	_assert(store.get_generation() == 2, "Damaged behavior publish generation mismatch")
	_assert(store.get_profile(String(source.construct_id)).affordances.is_empty(), "Damaged behavior store retained affordances")
	var stale_profile: Dictionary = CompilerScript.compile(source).profile
	_assert_error(store.publish_profile(stale_profile), "STALE_CONSTRUCTION_BEHAVIOR_PROFILE", "Behavior store accepted stale profile")
	var state: Dictionary = store.to_dict()
	_assert_ok(StoreScript.validate_state(state), "Behavior store state invalid")
	var restored = StoreScript.new()
	_assert_ok(restored.setup(), "Restored behavior store setup failed")
	_assert_ok(restored.load_dict(state), "Behavior store state load failed")
	_assert(UtilsScript.canonical_json(restored.to_dict()) == UtilsScript.canonical_json(state), "Behavior store roundtrip changed state")
	var stable_before: String = UtilsScript.canonical_json(restored.to_dict())
	var tampered: Dictionary = state.duplicate(true)
	tampered.profiles[0].diagnostics.compiled_affordance_count = 99
	_assert(not bool(restored.load_dict(tampered).get("success", false)), "Behavior store accepted tampered state")
	_assert(UtilsScript.canonical_json(restored.to_dict()) == stable_before, "Rejected behavior state mutated restored store")
	var memory = MemoryStateStore.new()
	var persistence = PersistenceScript.new()
	_assert_ok(persistence.setup(store, memory, "c5-behavior"), "Behavior persistence setup failed")
	_assert_ok(persistence.save(), "Behavior persistence save failed")
	var persisted_store = StoreScript.new()
	_assert_ok(persisted_store.setup(), "Persisted behavior store setup failed")
	var loader = PersistenceScript.new()
	_assert_ok(loader.setup(persisted_store, memory, "c5-behavior"), "Behavior persistence loader setup failed")
	_assert_ok(loader.load(), "Behavior persistence load failed")
	_assert(UtilsScript.canonical_json(persisted_store.to_dict()) == UtilsScript.canonical_json(store.to_dict()), "Behavior persistence changed state")
	var removed: Dictionary = persisted_store.remove_profile(String(source.construct_id), String(damaged.checksum))
	_assert_ok(removed, "Behavior profile removal failed")
	_assert(bool(removed.removed), "Behavior profile removal not reported")
	_assert(persisted_store.get_profile(String(source.construct_id)).is_empty(), "Behavior profile remained after removal")
	_assert_ok(persisted_store.remove_profile(String(source.construct_id), String(damaged.checksum)), "Behavior profile removal replay failed")


func _capability_kinds(profile: Dictionary) -> Array:
	var result: Array = []
	for capability in profile.capabilities:
		result.append(String(capability.capability_kind))
	result.sort()
	return result


func _action_kinds(profile: Dictionary) -> Array:
	var result: Array = []
	for affordance in profile.affordances:
		result.append(String(affordance.action_kind))
	result.sort()
	return result


func _affordance_by_action(profile: Dictionary, action_kind: String) -> Dictionary:
	for affordance in profile.affordances:
		if String(affordance.action_kind) == action_kind:
			return Dictionary(affordance).duplicate(true)
	return {}


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("C5 capability/affordance contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C5 capability/affordance contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
