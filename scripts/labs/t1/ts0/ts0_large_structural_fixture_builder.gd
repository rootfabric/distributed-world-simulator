extends RefCounted

const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")

const CONFIG_PATH := "res://config/construction/ts0-large-structural-visual-lab.v1.json"
const FIXTURE_SEED_VERSION := "ts0-large-structural-fixtures-v1"
const GRID_FAST_PATH := "C22_UNIT_AXIS_GRID"
const FORWARD := "FORWARD"
const REVERSE := "REVERSE"
const RESEARCH_PROFILE := "CUBE_1M_RESEARCH"

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return _failure("TS0_CONFIG_NOT_FOUND")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("TS0_CONFIG_INVALID_JSON")
	var config: Dictionary = parsed
	if String(config.get("schema", "")) != "distributed_world_simulator.ts0_large_structural_visual_lab.v1":
		return _failure("TS0_CONFIG_UNSUPPORTED_SCHEMA")
	var grid: Dictionary = config.get("structural_grid", {})
	if float(grid.get("cell_size_m", 0.0)) != 1.0:
		return _failure("TS0_GRID_CELL_SIZE_MUST_MATCH_C22_UNIT_FAST_PATH")
	if float(grid.get("section_size_m", 0.0)) <= 0.0:
		return _failure("TS0_INVALID_SECTION_SIZE")
	if String(grid.get("representation_fast_path", "")) != GRID_FAST_PATH:
		return _failure("TS0_INVALID_REPRESENTATION_FAST_PATH")
	if String(config.get("fixture_seed_version", "")) != FIXTURE_SEED_VERSION:
		return _failure("TS0_FIXTURE_SEED_VERSION_MISMATCH")
	return _success({"config": config})

static func describe_profile(profile_id: String) -> Dictionary:
	var loaded := load_config()
	if not bool(loaded.get("success", false)):
		return loaded
	var config: Dictionary = loaded["config"]
	var profiles: Dictionary = config.get("profiles", {})
	if not profiles.has(profile_id):
		return _failure("TS0_UNKNOWN_PROFILE")
	var profile: Dictionary = Dictionary(profiles[profile_id]).duplicate(true)
	var computed_count := _computed_part_count(profile)
	if computed_count < 0:
		return _failure("TS0_UNSUPPORTED_SHAPE")
	if computed_count != int(profile.get("expected_part_count", -1)):
		return _failure("TS0_PROFILE_COUNT_CONTRACT_MISMATCH")
	if float(profile.get("block_size_m", 0.0)) != float(config["structural_grid"]["cell_size_m"]):
		return _failure("TS0_PROFILE_CELL_SIZE_MISMATCH")
	var expected_checksum := String(profile.get("expected_canonical_checksum", ""))
	if expected_checksum.length() != 64:
		return _failure("TS0_PROFILE_CHECKSUM_NOT_PINNED")
	return _success({
		"profile_id": profile_id,
		"profile": profile,
		"computed_part_count": computed_count,
		"construct_id": _construct_id(profile_id),
		"root_item_instance_id": _root_item_id(profile_id),
		"expected_canonical_checksum": expected_checksum,
	})

static func build_profile(profile_id: String, traversal_order: String = FORWARD, allow_research: bool = false) -> Dictionary:
	if traversal_order not in [FORWARD, REVERSE]:
		return _failure("TS0_INVALID_TRAVERSAL_ORDER")
	var described := describe_profile(profile_id)
	if not bool(described.get("success", false)):
		return described
	if profile_id == RESEARCH_PROFILE and not allow_research:
		return _failure("TS0_RESEARCH_PROFILE_REQUIRES_EXPLICIT_OPT_IN")
	var loaded := load_config()
	if not bool(loaded.get("success", false)):
		return loaded
	var config: Dictionary = loaded["config"]
	var profile: Dictionary = described["profile"]
	var grid: Dictionary = config["structural_grid"]
	var parts := _build_parts(profile_id, profile, grid)
	if traversal_order == REVERSE:
		parts.reverse()
	var compiled_facets := {
		"ts0_fixture": {
			"profile_id": profile_id,
			"shape": String(profile["shape"]),
			"seed_version": FIXTURE_SEED_VERSION,
			"part_identity_policy": "COORDINATE_STABLE",
			"section_size_m": float(grid["section_size_m"]),
			"representation_fast_path": GRID_FAST_PATH,
		},
	}
	var snapshot := Snapshot.create(
		String(described["construct_id"]),
		String(described["root_item_instance_id"]),
		1,
		"OPERATIONAL",
		parts,
		[],
		compiled_facets
	)
	var validation := Snapshot.validate(snapshot)
	if not bool(validation.get("success", false)):
		return _failure("TS0_CANONICAL_SNAPSHOT_INVALID", validation)
	if Array(snapshot["parts"]).size() != int(described["computed_part_count"]):
		return _failure("TS0_CANONICAL_PART_COUNT_MISMATCH")
	if String(snapshot["checksum"]) != String(described["expected_canonical_checksum"]):
		return _failure("TS0_CANONICAL_CHECKSUM_MISMATCH", {
			"expected": String(described["expected_canonical_checksum"]),
			"actual": String(snapshot["checksum"]),
		})
	return _success({
		"profile_id": profile_id,
		"snapshot": snapshot,
		"canonical_part_count": Array(snapshot["parts"]).size(),
		"canonical_revision": int(snapshot["state_revision"]),
		"canonical_checksum": String(snapshot["checksum"]),
		"traversal_order": traversal_order,
	})

static func is_c22_unit_grid_compatible_part(part: Dictionary) -> bool:
	var metadata: Dictionary = part.get("metadata", {})
	var geometry = metadata.get("geometry", {})
	if typeof(geometry) != TYPE_DICTIONARY:
		return false
	var bounds = Dictionary(geometry).get("bounding_box_m", [])
	if typeof(bounds) != TYPE_ARRAY or Array(bounds).size() != 3:
		return false
	for value in bounds:
		if absf(float(value) - 1.0) > 0.000001:
			return false
	var position = part.get("local_position_m", [])
	if typeof(position) != TYPE_ARRAY or Array(position).size() != 3:
		return false
	for value in position:
		if absf(float(value) - round(float(value))) > 0.000001:
			return false
	var rotation = metadata.get("local_rotation_quaternion", [0.0, 0.0, 0.0, 1.0])
	if typeof(rotation) != TYPE_ARRAY or Array(rotation).size() != 4:
		return false
	return absf(float(rotation[0])) <= 0.000001 \
		and absf(float(rotation[1])) <= 0.000001 \
		and absf(float(rotation[2])) <= 0.000001 \
		and absf(float(rotation[3]) - 1.0) <= 0.000001

static func _build_parts(profile_id: String, profile: Dictionary, grid: Dictionary) -> Array:
	var shape := String(profile["shape"])
	if shape == "CUBE":
		return _build_cube_parts(profile_id, profile, grid)
	if shape == "STEPPED_SQUARE_PYRAMID":
		return _build_pyramid_parts(profile_id, profile, grid)
	return []

static func _build_cube_parts(profile_id: String, profile: Dictionary, grid: Dictionary) -> Array:
	var dimensions: Array = profile["dimensions"]
	var parts: Array = []
	for z in range(int(dimensions[2])):
		for y in range(int(dimensions[1])):
			for x in range(int(dimensions[0])):
				parts.append(_make_part(profile_id, x, y, z, grid))
	return parts

static func _build_pyramid_parts(profile_id: String, profile: Dictionary, grid: Dictionary) -> Array:
	var levels := int(profile["levels"])
	var parts: Array = []
	for y in range(levels):
		var side := levels - y
		var start := int((levels - side) / 2)
		for local_z in range(side):
			for local_x in range(side):
				parts.append(_make_part(profile_id, start + local_x, y, start + local_z, grid))
	return parts

static func _make_part(profile_id: String, x: int, y: int, z: int, grid: Dictionary) -> Dictionary:
	var token := _profile_token(profile_id)
	var suffix := "x%04d-y%04d-z%04d" % [x, y, z]
	var cell_size := float(grid["cell_size_m"])
	return Part.create(
		"part/ts0/%s/%s" % [token, suffix],
		"item/ts0/%s/%s" % [token, suffix],
		"STRUCTURAL_CELL",
		"structure",
		float(grid["part_mass_kg"]),
		[float(x) * cell_size, float(y) * cell_size, float(z) * cell_size],
		{
			"geometry": {"bounding_box_m": [cell_size, cell_size, cell_size]},
			"condition": "INTACT",
			"proxy_material_key": "structure",
		}
	)

static func _computed_part_count(profile: Dictionary) -> int:
	match String(profile.get("shape", "")):
		"CUBE":
			var dimensions = profile.get("dimensions", [])
			if typeof(dimensions) != TYPE_ARRAY or Array(dimensions).size() != 3:
				return -1
			return int(dimensions[0]) * int(dimensions[1]) * int(dimensions[2])
		"STEPPED_SQUARE_PYRAMID":
			var levels := int(profile.get("levels", 0))
			if levels <= 0:
				return -1
			return levels * (levels + 1) * (2 * levels + 1) / 6
	return -1

static func _construct_id(profile_id: String) -> String:
	return "construct/ts0/%s" % _profile_token(profile_id)

static func _root_item_id(profile_id: String) -> String:
	return "item/ts0/%s/root" % _profile_token(profile_id)

static func _profile_token(profile_id: String) -> String:
	return profile_id.to_lower().replace("_", "-")

static func _success(extra: Dictionary = {}) -> Dictionary:
	var value := {"success": true, "error_code": "", "message": ""}
	for key in extra:
		value[key] = extra[key]
	return value

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"message": code,
		"details": details.duplicate(true),
	}
