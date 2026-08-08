extends RefCounted

const MANIFEST_PATH := "res://config/construction/t1-complex-construct-demo.v1.json"
const FIXTURE_SCHEMA := "planet_simulator.t1_complex_construct_fixture.v1"

static func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _failure("T1A0_MANIFEST_NOT_FOUND")
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return _failure("T1A0_MANIFEST_OPEN_FAILED")
	var decoded = JSON.parse_string(file.get_as_text())
	if typeof(decoded) != TYPE_DICTIONARY:
		return _failure("T1A0_MANIFEST_INVALID_JSON")
	var manifest: Dictionary = decoded
	if String(manifest.get("schema", "")) != "planet_simulator.t1_complex_construct_demo_manifest.v1":
		return _failure("T1A0_MANIFEST_SCHEMA_MISMATCH")
	if typeof(manifest.get("profiles")) != TYPE_DICTIONARY:
		return _failure("T1A0_MANIFEST_PROFILES_MISSING")
	return {"success": true, "manifest": manifest}

static func build_profile(profile_id: String) -> Dictionary:
	var loaded: Dictionary = load_manifest()
	if not bool(loaded.get("success", false)):
		return loaded
	var manifest: Dictionary = loaded["manifest"]
	var profiles: Dictionary = manifest["profiles"]
	if not profiles.has(profile_id):
		return _failure("T1A0_UNKNOWN_PROFILE")
	var contract: Dictionary = profiles[profile_id]
	var expected_count := int(contract.get("expected_part_count", -1))
	if expected_count < 1:
		return _failure("T1A0_INVALID_PART_COUNT")
	var part_ids: Array = []
	for index in range(expected_count):
		part_ids.append("part/t1/%s/p%04d" % [profile_id.to_lower(), index])
	var fixture := {
		"schema": FIXTURE_SCHEMA,
		"profile_id": profile_id,
		"fixture_seed": String(manifest["fixture_seed"]),
		"construct_id": String(contract["construct_id"]),
		"part_count": expected_count,
		"part_ids": part_ids,
		"room_ids": Array(contract["expected_room_ids"]).duplicate(true),
		"utility_ids": Array(contract["expected_utility_ids"]).duplicate(true),
		"item_ids": Array(contract["expected_item_ids"]).duplicate(true),
		"fixture_checksum": "",
	}
	fixture["fixture_checksum"] = compute_fixture_checksum(fixture)
	if String(fixture["fixture_checksum"]) != String(contract.get("initial_fixture_checksum", "")):
		return _failure("T1A0_FIXTURE_CHECKSUM_MISMATCH")
	return {"success": true, "fixture": fixture}

static func compute_fixture_checksum(fixture: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(String(fixture.get("schema", "")))
	lines.append(String(fixture.get("profile_id", "")))
	lines.append(String(fixture.get("fixture_seed", "")))
	lines.append(String(fixture.get("construct_id", "")))
	lines.append(str(int(fixture.get("part_count", -1))))
	lines.append(_joined(Array(fixture.get("part_ids", []))))
	lines.append(_joined(Array(fixture.get("room_ids", []))))
	lines.append(_joined(Array(fixture.get("utility_ids", []))))
	lines.append(_joined(Array(fixture.get("item_ids", []))))
	return "\n".join(lines).sha256_text()

static func validate_fixture(fixture: Dictionary) -> Dictionary:
	if String(fixture.get("schema", "")) != FIXTURE_SCHEMA:
		return _failure("T1A0_FIXTURE_SCHEMA_MISMATCH")
	for field in ["profile_id", "fixture_seed", "construct_id", "fixture_checksum"]:
		if typeof(fixture.get(field)) != TYPE_STRING or String(fixture[field]).is_empty():
			return _failure("T1A0_FIXTURE_INVALID_%s" % String(field).to_upper())
	if typeof(fixture.get("part_count")) != TYPE_INT or int(fixture["part_count"]) < 1:
		return _failure("T1A0_FIXTURE_INVALID_PART_COUNT")
	for field in ["part_ids", "room_ids", "utility_ids", "item_ids"]:
		if typeof(fixture.get(field)) != TYPE_ARRAY:
			return _failure("T1A0_FIXTURE_INVALID_%s" % String(field).to_upper())
	if Array(fixture["part_ids"]).size() != int(fixture["part_count"]):
		return _failure("T1A0_FIXTURE_PART_COUNT_MISMATCH")
	for field in ["part_ids", "room_ids", "utility_ids", "item_ids"]:
		if not _unique_strings(Array(fixture[field])):
			return _failure("T1A0_FIXTURE_DUPLICATE_%s" % String(field).to_upper())
	if String(fixture["fixture_checksum"]) != compute_fixture_checksum(fixture):
		return _failure("T1A0_FIXTURE_CHECKSUM_INVALID")
	return {"success": true}

static func _joined(values: Array) -> String:
	var strings := PackedStringArray()
	for value in values:
		strings.append(String(value))
	return ",".join(strings)

static func _unique_strings(values: Array) -> bool:
	var seen := {}
	for value in values:
		if typeof(value) != TYPE_STRING or String(value).is_empty():
			return false
		var key := String(value)
		if seen.has(key):
			return false
		seen[key] = true
	return true

static func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code}
