extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture = preload("res://tests/construction/fixtures/c13_runtime_projection_fixture.gd")
const RequestScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const CompilerScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_compiler.gd")
const PartDescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_part_descriptor.gd")
const OpeningDescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_opening_descriptor.gd")
const DescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_descriptor.gd")
const StoreScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_store.gd")
const PersistenceScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_persistence.gd")

class MemoryStore:
	extends RefCounted
	var values := {}
	func put(key: String, value: Dictionary) -> Dictionary: values[key] = value.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func get_value(key: String) -> Dictionary:
		if not values.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "value": Dictionary(values[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_request_and_compiler_contracts()
	_test_part_opening_and_construct_contracts()
	_test_store_and_persistence()
	_finish()

func _test_request_and_compiler_contracts() -> void:
	var request := Fixture.beam_request("contracts", 0, 4.0, [10.0, 2.0, -4.0])
	_assert_ok(RequestScript.validate(request), "Valid runtime request rejected")
	var compiled := CompilerScript.compile(request); _assert_ok(compiled, "Runtime beam compilation failed")
	var descriptor: Dictionary = compiled["descriptor"]
	_assert_ok(DescriptorScript.validate(descriptor), "Runtime construct descriptor rejected")
	_assert(String(descriptor["body_kind"]) == "STATIC" and bool(descriptor["frozen"]), "Beam did not compile to frozen static body")
	_assert(Array(descriptor["world_origin_m"]) == [10.0, 2.0, -4.0], "World origin mismatch")
	_assert(descriptor["part_descriptors"].size() == 1, "Beam part descriptor count mismatch")
	var part: Dictionary = {}
	for candidate in descriptor["part_descriptors"]:
		if bool(candidate["collision_enabled"]): part = candidate; break
	_assert(String(part["geometry_kind"]) == "BOX", "Straight beam did not compile to box")
	_assert(absf(float(part["dimensions_m"][0]) - 4.0) < 0.000001, "Beam runtime length mismatch")
	_assert(bool(part["visible"]) and bool(part["collision_enabled"]), "Operational beam presentation flags mismatch")
	_assert(String(part["source_checksum"]).length() == 64, "Part source checksum missing")
	_assert(String(descriptor["diagnostics"]["request_checksum"]) == String(request["checksum"]), "Descriptor did not pin request checksum")
	var repeated := CompilerScript.compile(request); _assert_ok(repeated, "Repeated compilation failed")
	_assert(String(repeated["descriptor"]["checksum"]) == String(descriptor["checksum"]), "Compilation was not deterministic")
	var unknown := request.duplicate(true); unknown["unexpected_field"] = true
	_assert_error(RequestScript.validate(unknown), "UNEXPECTED_FIELD", "Runtime request accepted unknown field")
	var bad_rotation := request.duplicate(true); bad_rotation["world_rotation_quaternion"] = [0.0, 0.0, 0.0, 2.0]; bad_rotation["checksum"] = RequestScript.compute_checksum(bad_rotation)
	_assert_error(RequestScript.validate(bad_rotation), "CONSTRUCTION_RUNTIME_REQUEST_ROTATION_NOT_NORMALIZED", "Runtime request accepted non-normalized rotation")
	var profile_mismatch := Fixture.rover_request("profile-mismatch")
	profile_mismatch["construct_snapshot"] = Fixture.beam_request("other")["construct_snapshot"]
	profile_mismatch["checksum"] = RequestScript.compute_checksum(profile_mismatch)
	_assert_error(RequestScript.validate(profile_mismatch), "CONSTRUCTION_RUNTIME_PROFILE_SNAPSHOT_MISMATCH", "Runtime request accepted profile from another construct")
	var edited := CompilerScript.compile(Fixture.edited_beam_request("path-contracts")); _assert_ok(edited, "Edited path compilation failed")
	var edited_part: Dictionary = edited["descriptor"]["part_descriptors"][0]
	_assert(String(edited_part["geometry_kind"]) == "PATH_BOXES", "C11 path did not compile to path geometry")
	_assert(edited_part["path_points_m"].size() == 3, "C11 control points were not projected")
	_assert(absf(float(edited["descriptor"]["total_mass_kg"]) - float(edited_part["mass_kg"])) < 0.000001, "Runtime total mass mismatch")
	_assert(UtilsScript.canonical_json(request).contains("construct_snapshot"), "Request was not JSON-safe")
	_assert(not UtilsScript.canonical_json(descriptor).is_empty(), "Descriptor was not JSON-safe")

func _test_part_opening_and_construct_contracts() -> void:
	var descriptor: Dictionary = CompilerScript.compile(Fixture.house_request("contracts-house", true))["descriptor"]
	_assert(String(descriptor["body_kind"]) == "STATIC", "House did not compile to static body")
	_assert(descriptor["opening_descriptors"].size() == 2, "House opening descriptor count mismatch")
	var door: Dictionary = {}
	for opening in descriptor["opening_descriptors"]:
		_assert_ok(OpeningDescriptorScript.validate(opening), "Opening descriptor rejected")
		if String(opening["status"]) == "OPEN": door = opening
	_assert(not door.is_empty(), "Open door descriptor missing")
	_assert(absf(float(door["target_angle_rad"]) - PI * 0.5) < 0.000001, "Door target angle mismatch")
	_assert(bool(door["collision_enabled"]), "Open but intact door collision was disabled")
	var bad_opening := door.duplicate(true); bad_opening["status"] = "BREACHED"; bad_opening["checksum"] = OpeningDescriptorScript.compute_checksum(bad_opening)
	_assert_error(OpeningDescriptorScript.validate(bad_opening), "INACTIVE_CONSTRUCTION_RUNTIME_OPENING_COLLIDES", "Breached opening retained collision")
	var part: Dictionary = {}
	for candidate in descriptor["part_descriptors"]:
		if bool(candidate["collision_enabled"]): part = candidate; break
	_assert(not part.is_empty(), "House fixture has no colliding part")
	var destroyed := part.duplicate(true); destroyed["condition"] = "DESTROYED"; destroyed["checksum"] = PartDescriptorScript.compute_checksum(destroyed)
	_assert_error(PartDescriptorScript.validate(destroyed), "DESTROYED_CONSTRUCTION_RUNTIME_PART_ACTIVE", "Destroyed runtime part remained active")
	var hidden_collision := part.duplicate(true); hidden_collision["visible"] = false; hidden_collision["checksum"] = PartDescriptorScript.compute_checksum(hidden_collision)
	_assert_error(PartDescriptorScript.validate(hidden_collision), "HIDDEN_CONSTRUCTION_RUNTIME_PART_COLLIDES", "Hidden runtime part retained collision")
	var bad_path := part.duplicate(true); bad_path["geometry_kind"] = "PATH_BOXES"; bad_path["path_points_m"] = [[0, 0, 0]]; bad_path["checksum"] = PartDescriptorScript.compute_checksum(bad_path)
	_assert_error(PartDescriptorScript.validate(bad_path), "CONSTRUCTION_RUNTIME_PATH_REQUIRES_TWO_POINTS", "Path descriptor accepted one point")
	var rover: Dictionary = CompilerScript.compile(Fixture.rover_request("contract-rover"))["descriptor"]
	_assert(String(rover["body_kind"]) == "RIGID" and String(rover["mobility_state"]) == "MOBILE", "Healthy rover runtime body mismatch")
	_assert(not bool(rover["frozen"]), "Healthy rover compiled frozen")
	var immobile: Dictionary = CompilerScript.compile(Fixture.rover_request("contract-rover", "immobile"))["descriptor"]
	_assert(String(immobile["mobility_state"]) == "IMMOBILE" and bool(immobile["frozen"]), "Immobile rover was not frozen")
	var static_mobile := descriptor.duplicate(true); static_mobile["mobility_state"] = "MOBILE"; static_mobile["checksum"] = DescriptorScript.compute_checksum(static_mobile)
	_assert_error(DescriptorScript.validate(static_mobile), "STATIC_CONSTRUCTION_RUNTIME_HAS_MOBILITY_STATE", "Static body accepted mobility state")
	var mass_tamper := rover.duplicate(true); mass_tamper["total_mass_kg"] = float(mass_tamper["total_mass_kg"]) + 1.0; mass_tamper["checksum"] = DescriptorScript.compute_checksum(mass_tamper)
	_assert_error(DescriptorScript.validate(mass_tamper), "CONSTRUCTION_RUNTIME_TOTAL_MASS_MISMATCH", "Runtime descriptor accepted mass mismatch")

func _test_store_and_persistence() -> void:
	var base: Dictionary = CompilerScript.compile(Fixture.beam_request("store", 0, 4.0))["descriptor"]
	var next: Dictionary = CompilerScript.compile(Fixture.beam_request("store", 1, 5.0))["descriptor"]
	var same_revision_other: Dictionary = CompilerScript.compile(Fixture.beam_request("store", 1, 6.0))["descriptor"]
	var store = StoreScript.new(); _assert_ok(store.publish(base), "Runtime descriptor publish failed")
	_assert(store.get_generation() == 1, "Runtime store generation mismatch")
	var replay := store.publish(base); _assert_ok(replay, "Runtime descriptor replay failed"); _assert(bool(replay["details"]["replay"]), "Runtime descriptor replay not marked")
	_assert(store.get_generation() == 1, "Runtime replay changed generation")
	_assert_ok(store.publish(next), "Runtime descriptor update failed")
	_assert(store.get_generation() == 2, "Runtime update generation mismatch")
	_assert_error(store.publish(base), "STALE_CONSTRUCTION_RUNTIME_PROJECTION", "Runtime store accepted stale descriptor")
	_assert_error(store.publish(same_revision_other), "CONSTRUCTION_RUNTIME_SAME_REVISION_MUTATION", "Runtime store accepted same-revision mutation")
	var state := store.export_state(); _assert_ok(StoreScript.validate_state(state), "Runtime store state rejected")
	var restored = StoreScript.new(); _assert_ok(restored.load_state(state), "Runtime store load failed")
	_assert(UtilsScript.canonical_json(restored.export_state()) == UtilsScript.canonical_json(state), "Runtime store roundtrip changed")
	var storage = MemoryStore.new(); _assert_ok(PersistenceScript.save(storage, store), "Runtime persistence save failed")
	var loaded = StoreScript.new(); _assert_ok(PersistenceScript.load(storage, loaded), "Runtime persistence load failed")
	_assert(String(loaded.get_descriptor(String(next["construct_id"]))["checksum"]) == String(next["checksum"]), "Runtime persistence lost descriptor")
	var tampered := state.duplicate(true); tampered["generation"] = 99
	_assert_error(restored.load_state(tampered), "CONSTRUCTION_RUNTIME_STORE_CHECKSUM_MISMATCH", "Runtime store accepted tamper")
	_assert_error(store.remove(String(next["construct_id"]), String(base["checksum"])), "CONSTRUCTION_RUNTIME_REMOVE_PRECONDITION_MISMATCH", "Runtime store removed with stale checksum")
	_assert_ok(store.remove(String(next["construct_id"]), String(next["checksum"])), "Runtime descriptor removal failed")
	_assert(store.get_all().is_empty(), "Runtime descriptor remained after removal")

func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, expected: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C13 runtime projection contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C13 runtime projection contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
