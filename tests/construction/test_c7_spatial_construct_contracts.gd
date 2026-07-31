extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c7_spatial_house_fixture.gd")
const SectionDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_section_definition.gd")
const OpeningDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_opening_definition.gd")
const SpaceDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_space_definition.gd")
const UtilityDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_utility_definition.gd")
const SectionStateScript = preload("res://scripts/construction/spatial/construction_spatial_section_state.gd")
const OpeningStateScript = preload("res://scripts/construction/spatial/construction_spatial_opening_state.gd")
const SpaceStateScript = preload("res://scripts/construction/spatial/construction_spatial_space_state.gd")
const UtilityStateScript = preload("res://scripts/construction/spatial/construction_spatial_utility_state.gd")
const ProfileScript = preload("res://scripts/construction/spatial/construction_spatial_profile.gd")
const CompilerScript = preload("res://scripts/construction/spatial/construction_spatial_compiler.gd")
const StoreScript = preload("res://scripts/construction/spatial/construction_spatial_profile_store.gd")
const CommandScript = preload("res://scripts/construction/spatial/construction_spatial_command.gd")

var assertions: int = 0
var failures: Array[String] = []

func _init() -> void:
	_test_definition_contracts()
	_test_compiled_state_contracts()
	_test_profile_store_and_command_contracts()
	_test_strict_schema_and_canonical_numeric_semantics()
	_finish()

func _test_definition_contracts() -> void:
	var snapshot := FixtureScript.house_snapshot("contracts")
	var facets: Dictionary = snapshot.compiled_facets
	_assert(Array(facets.spatial_sections).size() == 9, "Section definition count mismatch")
	_assert(Array(facets.spatial_openings).size() == 2, "Opening definition count mismatch")
	_assert(Array(facets.spatial_spaces).size() == 1, "Space definition count mismatch")
	_assert(Array(facets.spatial_utilities).size() == 2, "Utility definition count mismatch")
	for section in facets.spatial_sections:
		_assert_ok(SectionDefinitionScript.validate(section), "Section definition rejected")
		_assert(String(section.checksum).length() == 64, "Section checksum length mismatch")
	for opening in facets.spatial_openings:
		_assert_ok(OpeningDefinitionScript.validate(opening), "Opening definition rejected")
		_assert(String(opening.from_space_id) != String(opening.to_space_id), "Opening self-connects")
	for space in facets.spatial_spaces:
		_assert_ok(SpaceDefinitionScript.validate(space), "Space definition rejected")
		_assert(int(space.minimum_enclosure_sections) == 6, "Space enclosure quorum mismatch")
	for utility in facets.spatial_utilities:
		_assert_ok(UtilityDefinitionScript.validate(utility), "Utility definition rejected")
		_assert(Array(utility.provider_part_ids).size() == 1, "Utility provider count mismatch")
	var section_tamper: Dictionary = facets.spatial_sections[0].duplicate(true)
	section_tamper.properties["area_m2"] = 99.0
	_assert_error(SectionDefinitionScript.validate(section_tamper), "CONSTRUCTION_SPATIAL_SECTION_DEFINITION_CHECKSUM_MISMATCH", "Section checksum tamper accepted")
	var bad_section := SectionDefinitionScript.create("spatial-section/bad", "WALL", ["part/z", "part/a"])
	bad_section.provider_part_ids = ["part/z", "part/a"]
	bad_section.checksum = SectionDefinitionScript.compute_checksum(bad_section)
	_assert_error(SectionDefinitionScript.validate(bad_section), "CONSTRUCTION_SPATIAL_SECTION_REFERENCES_NOT_SORTED", "Unsorted section providers accepted")
	var self_opening := OpeningDefinitionScript.create("spatial-opening/self", "DOOR", "space/house/main", "space/house/main", "spatial-section/door-frame", "part/spatial/contracts/door")
	_assert_error(OpeningDefinitionScript.validate(self_opening), "CONSTRUCTION_SPATIAL_OPENING_SELF_CONNECTION", "Self opening accepted")
	var passage_with_door := OpeningDefinitionScript.create("spatial-opening/passage", "PASSAGE", "space/house/main", "space/exterior", "spatial-section/door-frame", "part/spatial/contracts/door")
	_assert_error(OpeningDefinitionScript.validate(passage_with_door), "CONSTRUCTION_SPATIAL_PASSAGE_CLOSURE_FORBIDDEN", "Passage closure accepted")
	var bad_space := SpaceDefinitionScript.create("space/house/bad", ["spatial-section/floor"], [], [], 2)
	_assert_error(SpaceDefinitionScript.validate(bad_space), "INVALID_CONSTRUCTION_SPATIAL_SPACE_MINIMUM_ENCLOSURE", "Impossible enclosure quorum accepted")
	var self_utility := UtilityDefinitionScript.create("spatial-utility/self", "DATA", ["part/spatial/contracts/data-router"], [], ["spatial-utility/self"])
	_assert_error(UtilityDefinitionScript.validate(self_utility), "CONSTRUCTION_SPATIAL_UTILITY_SELF_DEPENDENCY", "Utility self-dependency accepted")
	var wrong_kind := UtilityDefinitionScript.create("spatial-utility/bad-kind", "STEAM", ["part/spatial/contracts/power-panel"])
	_assert_error(UtilityDefinitionScript.validate(wrong_kind), "INVALID_CONSTRUCTION_SPATIAL_UTILITY_KIND", "Unknown utility kind accepted")

func _test_compiled_state_contracts() -> void:
	var compiled := CompilerScript.compile(FixtureScript.house_snapshot("compiled"))
	_assert_ok(compiled, "Intact house did not compile")
	var profile: Dictionary = compiled.profile
	_assert_ok(ProfileScript.validate(profile), "Compiled profile rejected")
	_assert(String(profile.building_state) == "ACTIVE", "Intact building not active")
	_assert(String(profile.activation_level) == "FUNCTIONAL", "Active building not functional")
	_assert(Array(profile.section_states).size() == 9, "Compiled section count mismatch")
	_assert(Array(profile.opening_states).size() == 2, "Compiled opening count mismatch")
	_assert(Array(profile.space_states).size() == 1, "Compiled space count mismatch")
	_assert(Array(profile.utility_states).size() == 2, "Compiled utility count mismatch")
	for state in profile.section_states:
		_assert_ok(SectionStateScript.validate(state), "Section state rejected")
		_assert(String(state.status) == "ONLINE", "Intact section not online")
	for state in profile.opening_states:
		_assert_ok(OpeningStateScript.validate(state), "Opening state rejected")
		_assert(String(state.status) in ["CLOSED", "SEALED"], "Intact opening status mismatch")
	for state in profile.space_states:
		_assert_ok(SpaceStateScript.validate(state), "Space state rejected")
		_assert(String(state.status) == "HABITABLE", "Intact space not habitable")
	for state in profile.utility_states:
		_assert_ok(UtilityStateScript.validate(state), "Utility state rejected")
		_assert(String(state.status) == "ONLINE", "Intact utility not online")
	_assert(_capability_kinds(profile).has("ENCLOSED_SPACE"), "Enclosed-space capability missing")
	_assert(_capability_kinds(profile).has("SHELTER"), "Shelter capability missing")
	_assert(_capability_kinds(profile).has("POWER_DISTRIBUTION"), "Power capability missing")
	_assert(_capability_kinds(profile).has("DATA_DISTRIBUTION"), "Data capability missing")
	_assert(_action_kinds(profile).has("OPEN_DOOR"), "Open-door action missing")
	_assert(_action_kinds(profile).has("TRAVERSE_OPENING"), "Traverse action missing")
	_assert(_action_kinds(profile).has("TOGGLE_LIGHTING"), "Lighting action missing")
	var tampered: Dictionary = profile.duplicate(true)
	tampered.space_states[0].status = "EXPOSED"
	_assert_error(ProfileScript.validate(tampered), "CONSTRUCTION_SPATIAL_SPACE_STATE_CHECKSUM_MISMATCH", "Tampered nested space accepted")
	var unsorted: Dictionary = profile.duplicate(true)
	unsorted.section_states.reverse()
	unsorted.checksum = ProfileScript.compute_checksum(unsorted)
	_assert_error(ProfileScript.validate(unsorted), "CONSTRUCTION_SPATIAL_PROFILE_SECTION_STATES_NOT_SORTED", "Unsorted section states accepted")
	var inactive_with_behavior: Dictionary = profile.duplicate(true)
	inactive_with_behavior.building_state = "INACTIVE"
	inactive_with_behavior.activation_level = "SUMMARY"
	inactive_with_behavior.checksum = ProfileScript.compute_checksum(inactive_with_behavior)
	_assert_error(ProfileScript.validate(inactive_with_behavior), "INACTIVE_CONSTRUCTION_SPATIAL_PROFILE_EXPOSES_BEHAVIOR", "Inactive profile exposed behavior")

func _test_profile_store_and_command_contracts() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Spatial store setup failed")
	var snapshot := FixtureScript.house_snapshot("store")
	var first := store.compile_snapshot(snapshot)
	_assert_ok(first, "Spatial store compile failed")
	_assert(not bool(first.replay), "First publish marked replay")
	_assert(int(store.get_generation()) == 1, "First publish generation mismatch")
	var replay := store.compile_snapshot(snapshot)
	_assert_ok(replay, "Spatial exact replay failed")
	_assert(bool(replay.replay), "Spatial exact replay not detected")
	_assert(int(store.get_generation()) == 1, "Replay advanced generation")
	var stale := FixtureScript.house_snapshot("store", {}, {}, {}, 0, "OPERATIONAL")
	var changed := FixtureScript.door_open("store", 1)
	_assert_ok(store.compile_snapshot(changed), "Spatial changed revision failed")
	_assert_error(store.compile_snapshot(stale), "STALE_CONSTRUCTION_SPATIAL_PROFILE", "Stale spatial profile accepted")
	var same_revision := FixtureScript.roof_degraded("store", 1)
	_assert_error(store.compile_snapshot(same_revision), "CONSTRUCTION_SPATIAL_PROFILE_SAME_REVISION_CONFLICT", "Same-revision spatial mutation accepted")
	var profile: Dictionary = store.get_profile(String(snapshot.construct_id))
	var command := CommandScript.create("spatial-command/contracts/open", String(profile.construct_id), "CLOSE_DOOR", ["OPERATE_DOOR"], {}, String(profile.checksum))
	_assert_ok(CommandScript.validate(command), "Valid spatial command rejected")
	var command_tamper: Dictionary = command.duplicate(true)
	command_tamper.action_kind = "OPEN_DOOR"
	_assert_error(CommandScript.validate(command_tamper), "CONSTRUCTION_SPATIAL_COMMAND_CHECKSUM_MISMATCH", "Tampered spatial command accepted")
	var bad_caps := CommandScript.create("spatial-command/contracts/bad-caps", String(profile.construct_id), "CLOSE_DOOR", ["Z_SKILL", "A_SKILL"], {}, String(profile.checksum))
	bad_caps.actor_capabilities = ["Z_SKILL", "A_SKILL"]
	bad_caps.checksum = CommandScript.compute_checksum(bad_caps)
	_assert_error(CommandScript.validate(bad_caps), "CONSTRUCTION_SPATIAL_COMMAND_ACTOR_CAPABILITIES_NOT_SORTED", "Unsorted command capabilities accepted")
	var state := store.to_dict()
	_assert_ok(StoreScript.validate_state(state), "Spatial store state rejected")
	var state_tamper: Dictionary = state.duplicate(true)
	state_tamper.generation = 999
	_assert_error(StoreScript.validate_state(state_tamper), "CONSTRUCTION_SPATIAL_PROFILE_STORE_CHECKSUM_MISMATCH", "Tampered store generation accepted")

func _test_strict_schema_and_canonical_numeric_semantics() -> void:
	var section: Dictionary = FixtureScript.house_snapshot("strict").compiled_facets.spatial_sections[0]
	var unexpected: Dictionary = section.duplicate(true)
	unexpected["unexpected_field"] = true
	_assert_error(SectionDefinitionScript.validate(unexpected), "UNEXPECTED_FIELD", "Section accepted unexpected field")
	var float_dto: Dictionary = {"load_kg": 100.0, "origin": [0.0, 1.0, 0.0]}
	var integer_dto: Dictionary = {"load_kg": 100, "origin": [0, 1, 0]}
	_assert(float_dto != integer_dto, "Raw numeric DTO unexpectedly equal")
	_assert(UtilsScript.canonical_json(float_dto) == UtilsScript.canonical_json(integer_dto), "Canonical numeric DTO mismatch")
	var roundtrip = JSON.parse_string(JSON.stringify(FixtureScript.house_snapshot("roundtrip"), "", true, true))
	_assert(roundtrip is Dictionary, "Spatial snapshot JSON roundtrip failed")
	_assert_ok(CompilerScript.compile(Dictionary(roundtrip)), "Canonicalized spatial snapshot did not compile")

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
func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty():
		print("C7 spatial construct contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("C7 spatial construct contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
