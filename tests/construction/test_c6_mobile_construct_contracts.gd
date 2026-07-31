extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DefinitionScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_definition.gd")
const StateScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_state.gd")
const ProfileScript = preload("res://scripts/construction/mobile/construction_mobile_profile.gd")
const CompilerScript = preload("res://scripts/construction/mobile/construction_mobile_compiler.gd")
const StoreScript = preload("res://scripts/construction/mobile/construction_mobile_profile_store.gd")
const PersistenceScript = preload("res://scripts/construction/mobile/construction_mobile_persistence.gd")
const CommandScript = preload("res://scripts/construction/mobile/construction_mobile_command.gd")
const AuthorizerScript = preload("res://scripts/construction/mobile/construction_mobile_command_authorizer.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c6_mobile_rover_fixture.gd")


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
	_test_subsystem_definition_contract()
	_test_subsystem_state_contract()
	_test_intact_profile_compilation()
	_test_degraded_and_immobile_compilation()
	_test_dependency_failures()
	_test_partial_suppression()
	_test_compiler_rejections()
	_test_command_contract_and_authorization()
	_test_profile_store_and_persistence()
	_finish()


func _test_subsystem_definition_contract() -> void:
	var definition: Dictionary = DefinitionScript.create(
		"mobile-subsystem/drive/main",
		"DRIVE",
		["part/mobile/rover/wheel-b", "part/mobile/rover/wheel-a"],
		["bond/mobile/rover/drive"],
		["mobile-subsystem/control/main", "mobile-subsystem/power/main"],
		1,
		{"max_speed_mps": 8.0}
	)
	_assert_ok(DefinitionScript.validate(definition), "Mobile subsystem definition rejected")
	_assert(definition.provider_part_ids == ["part/mobile/rover/wheel-a", "part/mobile/rover/wheel-b"], "Mobile providers not sorted")
	_assert(definition.dependency_subsystem_ids == ["mobile-subsystem/control/main", "mobile-subsystem/power/main"], "Mobile dependencies not sorted")
	_assert(String(definition.checksum).length() == 64, "Mobile subsystem checksum missing")
	var unexpected: Dictionary = definition.duplicate(true)
	unexpected["unexpected_field"] = true
	_assert_error(DefinitionScript.validate(unexpected), "UNEXPECTED_FIELD", "Mobile subsystem accepted unexpected field")
	var bad_minimum: Dictionary = definition.duplicate(true)
	bad_minimum.minimum_online_providers = 3
	bad_minimum.checksum = DefinitionScript.compute_checksum(bad_minimum)
	_assert_error(DefinitionScript.validate(bad_minimum), "INVALID_CONSTRUCTION_MOBILE_MINIMUM_ONLINE_PROVIDERS", "Mobile subsystem accepted impossible quorum")
	var self_dependency: Dictionary = definition.duplicate(true)
	self_dependency.dependency_subsystem_ids = [String(self_dependency.subsystem_id)]
	self_dependency.checksum = DefinitionScript.compute_checksum(self_dependency)
	_assert_error(DefinitionScript.validate(self_dependency), "CONSTRUCTION_MOBILE_SUBSYSTEM_SELF_DEPENDENCY", "Mobile subsystem accepted self dependency")
	var unsorted: Dictionary = definition.duplicate(true)
	unsorted.provider_part_ids = ["part/mobile/rover/wheel-b", "part/mobile/rover/wheel-a"]
	unsorted.checksum = DefinitionScript.compute_checksum(unsorted)
	_assert_error(DefinitionScript.validate(unsorted), "CONSTRUCTION_MOBILE_SUBSYSTEM_REFERENCES_NOT_SORTED", "Mobile subsystem accepted unsorted provider IDs")
	var drifted: Dictionary = definition.duplicate(true)
	drifted.properties.max_speed_mps = 9.0
	_assert_error(DefinitionScript.validate(drifted), "CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITION_CHECKSUM_MISMATCH", "Mobile subsystem accepted checksum drift")


func _test_subsystem_state_contract() -> void:
	var definition: Dictionary = DefinitionScript.create(
		"mobile-subsystem/drive/main",
		"DRIVE",
		["part/mobile/rover/wheel-a", "part/mobile/rover/wheel-b"],
		[],
		[],
		1,
		{"max_speed_mps": 8.0}
	)
	var state: Dictionary = StateScript.create(
		definition,
		"DEGRADED",
		["part/mobile/rover/wheel-a"],
		[],
		["part/mobile/rover/wheel-b"],
		{"health_ratio": 0.5},
		{"reason": "provider-loss"}
	)
	_assert_ok(StateScript.validate(state), "Mobile subsystem state rejected")
	_assert(String(state.status) == "DEGRADED", "Mobile subsystem state changed status")
	_assert(state.online_provider_part_ids == ["part/mobile/rover/wheel-a"], "Mobile subsystem online provider changed")
	var overlap: Dictionary = state.duplicate(true)
	overlap.degraded_provider_part_ids = ["part/mobile/rover/wheel-a"]
	overlap.checksum = StateScript.compute_checksum(overlap)
	_assert_error(StateScript.validate(overlap), "CONSTRUCTION_MOBILE_SUBSYSTEM_PROVIDER_PARTITION_MISMATCH", "Mobile subsystem accepted overlapping provider partition")
	var missing: Dictionary = state.duplicate(true)
	missing.offline_provider_part_ids = []
	missing.checksum = StateScript.compute_checksum(missing)
	_assert_error(StateScript.validate(missing), "CONSTRUCTION_MOBILE_SUBSYSTEM_PROVIDER_PARTITION_MISMATCH", "Mobile subsystem accepted incomplete provider partition")
	var bad_status: Dictionary = state.duplicate(true)
	bad_status.status = "FAILED"
	bad_status.checksum = StateScript.compute_checksum(bad_status)
	_assert_error(StateScript.validate(bad_status), "INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATUS", "Mobile subsystem accepted unknown status")


func _test_intact_profile_compilation() -> void:
	var snapshot: Dictionary = FixtureScript.rover_snapshot("contracts-intact")
	var compiled: Dictionary = CompilerScript.compile(snapshot)
	_assert_ok(compiled, "Intact rover compilation failed")
	var profile: Dictionary = compiled.profile
	_assert_ok(ProfileScript.validate(profile), "Intact mobile profile invalid")
	_assert(String(profile.mobility_state) == "MOBILE", "Intact rover not mobile")
	_assert(String(profile.construct_id) == String(snapshot.construct_id), "Mobile profile changed construct ID")
	_assert(String(profile.construct_checksum) == String(snapshot.checksum), "Mobile profile lost source checksum")
	_assert(int(profile.construct_revision) == 0, "Mobile profile changed construct revision")
	_assert(profile.subsystem_states.size() == 4, "Intact rover subsystem count mismatch")
	_assert(_all_subsystem_statuses(profile) == ["ONLINE", "ONLINE", "ONLINE", "ONLINE"], "Intact rover subsystem status mismatch")
	_assert(_capability_kinds(profile) == ["LOCOMOTION_GROUND", "MOBILE_CONTROL", "PERCEPTION", "POWERED", "STEERING"], "Intact rover capability kinds mismatch")
	_assert(_action_kinds(profile) == ["DRIVE_TO", "ROTATE", "SCAN_ENVIRONMENT", "STOP"], "Intact rover affordance kinds mismatch")
	_assert(profile.capabilities.size() == 5, "Intact rover capability count mismatch")
	_assert(profile.affordances.size() == 4, "Intact rover affordance count mismatch")
	var drive: Dictionary = _affordance_by_action(profile, "DRIVE_TO")
	_assert(float(drive.parameters.effective_max_speed_mps) == 8.0, "Intact rover effective speed mismatch")
	_assert(drive.actor_requirements == ["OPERATE_MOBILE_CONSTRUCT"], "Drive actor requirement mismatch")
	var scan: Dictionary = _affordance_by_action(profile, "SCAN_ENVIRONMENT")
	_assert(float(scan.parameters.range_m) == 60.0, "Sensor range missing from affordance")
	_assert(int(profile.diagnostics.online_subsystem_count) == 4, "Intact rover diagnostics mismatch")
	var json_roundtrip = JSON.parse_string(JSON.stringify(profile, "", true, true))
	_assert(json_roundtrip is Dictionary, "Mobile profile did not survive JSON")
	_assert_ok(ProfileScript.validate(Dictionary(json_roundtrip)), "JSON mobile profile invalid")
	_assert(UtilsScript.canonical_json(profile) == UtilsScript.canonical_json(json_roundtrip), "Mobile profile JSON roundtrip changed semantics")


func _test_degraded_and_immobile_compilation() -> void:
	var degraded_result: Dictionary = CompilerScript.compile(FixtureScript.one_wheel_lost("contracts-degraded"))
	_assert_ok(degraded_result, "One-wheel-loss compilation failed")
	var degraded: Dictionary = degraded_result.profile
	_assert(String(degraded.mobility_state) == "DEGRADED", "One-wheel-loss rover not degraded")
	_assert(String(_subsystem_by_kind(degraded, "DRIVE").status) == "DEGRADED", "Drive subsystem did not degrade")
	_assert(float(_subsystem_by_kind(degraded, "DRIVE").properties.health_ratio) == 0.75, "Drive health ratio mismatch")
	_assert(float(_affordance_by_action(degraded, "DRIVE_TO").parameters.effective_max_speed_mps) == 6.0, "Degraded speed not scaled")
	_assert(_action_kinds(degraded).has("SCAN_ENVIRONMENT"), "Wheel damage removed healthy sensor affordance")
	var immobile_result: Dictionary = CompilerScript.compile(FixtureScript.three_wheels_lost("contracts-immobile"))
	_assert_ok(immobile_result, "Three-wheel-loss compilation failed")
	var immobile: Dictionary = immobile_result.profile
	_assert(String(immobile.mobility_state) == "IMMOBILE", "Three-wheel-loss rover remained mobile")
	_assert(String(_subsystem_by_kind(immobile, "DRIVE").status) == "OFFLINE", "Drive subsystem did not go offline")
	_assert(not _capability_kinds(immobile).has("LOCOMOTION_GROUND"), "Immobile rover retained locomotion capability")
	_assert(not _action_kinds(immobile).has("DRIVE_TO"), "Immobile rover retained drive affordance")
	_assert(_action_kinds(immobile).has("SCAN_ENVIRONMENT"), "Immobile rover lost independent sensor affordance")


func _test_dependency_failures() -> void:
	var sensor_result: Dictionary = CompilerScript.compile(FixtureScript.sensor_lost("contracts-sensor"))
	_assert_ok(sensor_result, "Sensor-loss compilation failed")
	var sensor_profile: Dictionary = sensor_result.profile
	_assert(String(sensor_profile.mobility_state) == "MOBILE", "Sensor loss changed mobility")
	_assert(String(_subsystem_by_kind(sensor_profile, "SENSOR").status) == "OFFLINE", "Sensor subsystem remained online")
	_assert(not _capability_kinds(sensor_profile).has("PERCEPTION"), "Sensor loss retained perception")
	_assert(not _action_kinds(sensor_profile).has("SCAN_ENVIRONMENT"), "Sensor loss retained scan affordance")
	_assert(_action_kinds(sensor_profile).has("DRIVE_TO"), "Sensor loss removed drive affordance")
	var control_result: Dictionary = CompilerScript.compile(FixtureScript.controller_lost("contracts-control"))
	_assert_ok(control_result, "Control-loss compilation failed")
	var control_profile: Dictionary = control_result.profile
	_assert(String(control_profile.mobility_state) == "IMMOBILE", "Control loss did not immobilize rover")
	_assert(String(_subsystem_by_kind(control_profile, "POWER").status) == "ONLINE", "Control loss damaged power subsystem")
	_assert(String(_subsystem_by_kind(control_profile, "DRIVE").status) == "OFFLINE", "Drive ignored control dependency")
	_assert(String(_subsystem_by_kind(control_profile, "SENSOR").status) == "OFFLINE", "Sensor ignored control dependency")
	var power_result: Dictionary = CompilerScript.compile(FixtureScript.power_lost("contracts-power"))
	_assert_ok(power_result, "Power-loss compilation failed")
	var power_profile: Dictionary = power_result.profile
	_assert(String(power_profile.mobility_state) == "IMMOBILE", "Power loss did not immobilize rover")
	_assert(_capability_kinds(power_profile).is_empty(), "Power loss retained dependent capabilities")
	_assert(_action_kinds(power_profile).is_empty(), "Power loss retained actions")


func _test_partial_suppression() -> void:
	var result: Dictionary = CompilerScript.compile(FixtureScript.partial("contracts-partial"))
	_assert_ok(result, "Partial rover compilation failed")
	var profile: Dictionary = result.profile
	_assert(String(profile.build_state) == "PARTIAL", "Partial rover build state changed")
	_assert(String(profile.mobility_state) == "IMMOBILE", "Partial rover became mobile")
	_assert(profile.capabilities.is_empty(), "Partial rover published capabilities")
	_assert(profile.affordances.is_empty(), "Partial rover published affordances")
	_assert(not bool(profile.diagnostics.active_build_state), "Partial rover diagnostics marked active")


func _test_compiler_rejections() -> void:
	var missing_facets: Dictionary = FixtureScript.rover_snapshot("reject-no-facets")
	missing_facets.compiled_facets.erase("mobile_subsystems")
	missing_facets.checksum = preload("res://scripts/construction/contracts/construct_snapshot.gd").compute_checksum(missing_facets)
	_assert_error(CompilerScript.compile(missing_facets), "CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITIONS_REQUIRED", "Compiler accepted missing subsystem definitions")
	var missing_part: Dictionary = FixtureScript.rover_snapshot("reject-missing-part")
	missing_part.compiled_facets.mobile_subsystems[0].provider_part_ids = ["part/mobile/reject-missing-part/missing"]
	missing_part.compiled_facets.mobile_subsystems[0].checksum = DefinitionScript.compute_checksum(missing_part.compiled_facets.mobile_subsystems[0])
	missing_part.checksum = preload("res://scripts/construction/contracts/construct_snapshot.gd").compute_checksum(missing_part)
	_assert_error(CompilerScript.compile(missing_part), "CONSTRUCTION_MOBILE_SUBSYSTEM_PROVIDER_PART_MISSING", "Compiler accepted missing subsystem provider")
	var cycle: Dictionary = FixtureScript.rover_snapshot("reject-cycle")
	cycle.compiled_facets.mobile_subsystems[2].dependency_subsystem_ids = ["mobile-subsystem/control/main"]
	cycle.compiled_facets.mobile_subsystems[2].checksum = DefinitionScript.compute_checksum(cycle.compiled_facets.mobile_subsystems[2])
	cycle.checksum = preload("res://scripts/construction/contracts/construct_snapshot.gd").compute_checksum(cycle)
	_assert_error(CompilerScript.compile(cycle), "CONSTRUCTION_MOBILE_SUBSYSTEM_DEPENDENCY_CYCLE", "Compiler accepted dependency cycle")
	var invalid_condition: Dictionary = FixtureScript.rover_snapshot("reject-condition")
	invalid_condition.parts[0].metadata.condition = "MISSING"
	invalid_condition.checksum = preload("res://scripts/construction/contracts/construct_snapshot.gd").compute_checksum(invalid_condition)
	_assert_error(CompilerScript.compile(invalid_condition), "INVALID_CONSTRUCTION_MOBILE_PROVIDER_CONDITION", "Compiler accepted invalid part condition")


func _test_command_contract_and_authorization() -> void:
	var profile: Dictionary = CompilerScript.compile(FixtureScript.rover_snapshot("command-rover")).profile
	var command: Dictionary = CommandScript.create(
		"mobile-command/c6/drive",
		String(profile.construct_id),
		"DRIVE_TO",
		["OPERATE_MOBILE_CONSTRUCT"],
		{"target_position_m": [10.0, 0.0, 5.0]},
		String(profile.checksum)
	)
	_assert_ok(CommandScript.validate(command), "Mobile command rejected")
	_assert_ok(AuthorizerScript.authorize(command, profile), "Valid mobile command not authorized")
	var unexpected: Dictionary = command.duplicate(true)
	unexpected["unexpected_field"] = true
	_assert_error(CommandScript.validate(unexpected), "UNEXPECTED_FIELD", "Mobile command accepted unexpected field")
	var unskilled: Dictionary = CommandScript.create(
		"mobile-command/c6/unskilled",
		String(profile.construct_id),
		"DRIVE_TO",
		[],
		{},
		String(profile.checksum)
	)
	_assert_error(AuthorizerScript.authorize(unskilled, profile), "CONSTRUCTION_MOBILE_COMMAND_NOT_AUTHORIZED", "Unskilled actor received drive command")
	var stale: Dictionary = command.duplicate(true)
	stale.expected_profile_checksum = "0".repeat(64)
	stale.checksum = CommandScript.compute_checksum(stale)
	_assert_error(AuthorizerScript.authorize(stale, profile), "CONSTRUCTION_MOBILE_COMMAND_PROFILE_PRECONDITION_MISMATCH", "Command accepted stale profile checksum")
	var drifted: Dictionary = command.duplicate(true)
	drifted.parameters.target_position_m = [20, 0, 0]
	_assert_error(CommandScript.validate(drifted), "CONSTRUCTION_MOBILE_COMMAND_CHECKSUM_MISMATCH", "Mobile command accepted checksum drift")


func _test_profile_store_and_persistence() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Mobile profile store setup failed")
	var snapshot: Dictionary = FixtureScript.rover_snapshot("store-rover")
	var published: Dictionary = store.compile_snapshot(snapshot)
	_assert_ok(published, "Mobile profile publish failed")
	_assert(not bool(published.replay), "First mobile profile publish marked replay")
	_assert(int(store.get_generation()) == 1, "Mobile profile generation mismatch")
	var replay: Dictionary = store.compile_snapshot(snapshot)
	_assert_ok(replay, "Mobile profile replay failed")
	_assert(bool(replay.replay), "Mobile profile replay not detected")
	_assert(int(store.get_generation()) == 1, "Mobile profile replay advanced generation")
	var state: Dictionary = store.to_dict()
	_assert_ok(StoreScript.validate_state(state), "Mobile profile store state invalid")
	var memory = MemoryStateStore.new()
	var persistence = PersistenceScript.new()
	_assert_ok(persistence.setup(store, memory, "c6-mobile"), "Mobile persistence setup failed")
	_assert_ok(persistence.save(), "Mobile persistence save failed")
	var restored = StoreScript.new()
	_assert_ok(restored.setup(), "Restored mobile store setup failed")
	var restored_persistence = PersistenceScript.new()
	_assert_ok(restored_persistence.setup(restored, memory, "c6-mobile"), "Restored mobile persistence setup failed")
	_assert_ok(restored_persistence.load(), "Mobile persistence load failed")
	_assert(UtilsScript.canonical_json(restored.to_dict()) == UtilsScript.canonical_json(state), "Mobile persistence roundtrip changed state")
	var tampered: Dictionary = state.duplicate(true)
	tampered.generation = 9
	_assert_error(StoreScript.validate_state(tampered), "CONSTRUCTION_MOBILE_PROFILE_STORE_CHECKSUM_MISMATCH", "Mobile store accepted checksum drift")


func _subsystem_by_kind(profile: Dictionary, kind: String) -> Dictionary:
	for state in profile.subsystem_states:
		if String(state.subsystem_kind) == kind:
			return state
	return {}


func _affordance_by_action(profile: Dictionary, action_kind: String) -> Dictionary:
	for affordance in profile.affordances:
		if String(affordance.action_kind) == action_kind:
			return affordance
	return {}


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


func _all_subsystem_statuses(profile: Dictionary) -> Array:
	var result: Array = []
	for state in profile.subsystem_states:
		result.append(String(state.status))
	return result


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
		print("C6 mobile construct contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C6 mobile construct contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
