extends RefCounted

const SCHEMA: String = "planet_simulator.partition_address.v2"
const DEFAULT_UNIVERSE_ID: String = "main"
const DEFAULT_INSTANCE_ID: String = "persistent"
const DEFAULT_SPACE_ID: String = "moon"
const DEFAULT_SCHEME: String = "cube_sphere"
const DEFAULT_SCHEME_REVISION: int = 1


static func create_cube_sphere(
	face: int,
	zone_x: int,
	zone_y: int,
	chunk_x: int = -1,
	chunk_y: int = -1,
	universe_id: String = DEFAULT_UNIVERSE_ID,
	space_id: String = DEFAULT_SPACE_ID,
	partition_scheme: String = DEFAULT_SCHEME,
	instance_id: String = DEFAULT_INSTANCE_ID,
	partition_scheme_revision: int = DEFAULT_SCHEME_REVISION
) -> Dictionary:
	var normalized_universe_id: String = universe_id.strip_edges().to_lower()
	var normalized_instance_id: String = instance_id.strip_edges().to_lower()
	var normalized_space_id: String = space_id.strip_edges().to_lower()
	var scheme_info: Dictionary = _resolve_scheme(
		partition_scheme,
		partition_scheme_revision
	)
	if (
		not _is_canonical_identifier(normalized_universe_id)
		or not _is_canonical_identifier(normalized_instance_id)
		or not _is_canonical_identifier(normalized_space_id)
		or not _is_canonical_identifier(String(scheme_info.get("scheme_id", "")))
		or int(scheme_info.get("revision", 0)) <= 0
		or face < 0
		or face >= 6
		or zone_x < 0
		or zone_y < 0
		or chunk_x < -1
		or chunk_y < -1
		or ((chunk_x < 0) != (chunk_y < 0))
	):
		return {}
	var result: Dictionary = {
		"schema": SCHEMA,
		"universe_id": normalized_universe_id,
		"instance_id": normalized_instance_id,
		"space_id": normalized_space_id,
		"partition_scheme": String(scheme_info["scheme_id"]),
		"partition_scheme_revision": int(scheme_info["revision"]),
		"face": face,
		"zone_x": zone_x,
		"zone_y": zone_y,
	}
	if chunk_x >= 0 and chunk_y >= 0:
		result["chunk_x"] = chunk_x
		result["chunk_y"] = chunk_y
	result["zone_id"] = zone_key(result)
	result["chunk_id"] = chunk_key(result) if has_chunk(result) else ""
	return result


static func zone_key(address: Dictionary) -> String:
	var scheme_info: Dictionary = _resolve_scheme(
		String(address.get("partition_scheme", DEFAULT_SCHEME)),
		int(address.get("partition_scheme_revision", DEFAULT_SCHEME_REVISION))
	)
	return (
		"universe/%s/instance/%s/space/%s/partition/%s/revision/%d/zone/f%d/%02d/%02d"
		% [
			String(address.get("universe_id", DEFAULT_UNIVERSE_ID)).strip_edges().to_lower(),
			String(address.get("instance_id", DEFAULT_INSTANCE_ID)).strip_edges().to_lower(),
			String(address.get("space_id", DEFAULT_SPACE_ID)).strip_edges().to_lower(),
			String(scheme_info["scheme_id"]),
			int(scheme_info["revision"]),
			int(address.get("face", 0)),
			int(address.get("zone_x", 0)),
			int(address.get("zone_y", 0)),
		]
	)


static func chunk_key(address: Dictionary) -> String:
	if not has_chunk(address):
		return ""
	return "%s/chunk/%02d/%02d" % [
		zone_key(address),
		int(address.get("chunk_x", 0)),
		int(address.get("chunk_y", 0)),
	]


static func has_chunk(address: Dictionary) -> bool:
	return address.has("chunk_x") and address.has("chunk_y")


static func parse(value: String, defaults: Dictionary = {}) -> Dictionary:
	var parts: PackedStringArray = value.split("/", false)
	var parsed: Dictionary = {}
	if _matches_canonical_with_instance_and_revision(parts):
		parsed = _parse_canonical(parts, true, true, defaults)
	elif _matches_canonical_without_instance_with_revision(parts):
		parsed = _parse_canonical(parts, false, true, defaults)
		if not parsed.is_empty():
			parsed["legacy_source_id"] = value
	elif _matches_canonical_with_instance(parts):
		parsed = _parse_canonical(parts, true, false, defaults)
		if not parsed.is_empty():
			parsed["legacy_source_id"] = value
	elif _matches_canonical_without_instance(parts):
		parsed = _parse_canonical(parts, false, false, defaults)
		if not parsed.is_empty():
			parsed["legacy_source_id"] = value
	elif parts.size() in [4, 7] and parts[0] == "zone":
		parsed = _parse_legacy(parts, defaults)
		if not parsed.is_empty():
			parsed["legacy_source_id"] = value
	return parsed


static func normalize(address: Dictionary) -> Dictionary:
	var result: Dictionary = address.duplicate(true)
	if result.is_empty():
		return {}
	result["universe_id"] = String(
		result.get("universe_id", DEFAULT_UNIVERSE_ID)
	).strip_edges().to_lower()
	result["instance_id"] = String(
		result.get("instance_id", DEFAULT_INSTANCE_ID)
	).strip_edges().to_lower()
	result["space_id"] = String(
		result.get("space_id", DEFAULT_SPACE_ID)
	).strip_edges().to_lower()
	var scheme_info: Dictionary = _resolve_scheme(
		String(result.get("partition_scheme", DEFAULT_SCHEME)),
		int(result.get("partition_scheme_revision", DEFAULT_SCHEME_REVISION))
	)
	result["partition_scheme"] = String(scheme_info["scheme_id"])
	result["partition_scheme_revision"] = int(scheme_info["revision"])
	if not is_valid(result):
		return {}
	result["zone_id"] = zone_key(result)
	result["chunk_id"] = chunk_key(result) if has_chunk(result) else ""
	return result


static func is_valid(address: Dictionary) -> bool:
	var scheme_info: Dictionary = _resolve_scheme(
		String(address.get("partition_scheme", "")),
		int(address.get("partition_scheme_revision", DEFAULT_SCHEME_REVISION))
	)
	return (
		String(address.get("schema", "")) == SCHEMA
		and _is_canonical_identifier(String(address.get("universe_id", "")))
		and _is_canonical_identifier(String(address.get("instance_id", "")))
		and _is_canonical_identifier(String(address.get("space_id", "")))
		and _is_canonical_identifier(String(scheme_info.get("scheme_id", "")))
		and int(scheme_info.get("revision", 0)) > 0
		and int(address.get("face", -1)) >= 0
		and int(address.get("face", -1)) < 6
		and int(address.get("zone_x", -1)) >= 0
		and int(address.get("zone_y", -1)) >= 0
		and (
			not has_chunk(address)
			or (
				int(address.get("chunk_x", -1)) >= 0
				and int(address.get("chunk_y", -1)) >= 0
			)
		)
	)


static func file_components(address: Dictionary) -> PackedStringArray:
	var normalized: Dictionary = normalize(address)
	if normalized.is_empty():
		return PackedStringArray()
	var scheme_folder: String = "%s_r%d" % [
		String(normalized["partition_scheme"]),
		int(normalized["partition_scheme_revision"]),
	]
	var result := PackedStringArray([
		_sanitize(String(normalized.get("universe_id", DEFAULT_UNIVERSE_ID))),
		_sanitize(String(normalized.get("instance_id", DEFAULT_INSTANCE_ID))),
		_sanitize(String(normalized.get("space_id", DEFAULT_SPACE_ID))),
		_sanitize(scheme_folder),
		"face_%d" % int(normalized.get("face", 0)),
		"zone_%02d_%02d" % [
			int(normalized.get("zone_x", 0)),
			int(normalized.get("zone_y", 0)),
		],
	])
	if has_chunk(normalized):
		result.append("chunk_%02d_%02d.json" % [
			int(normalized.get("chunk_x", 0)),
			int(normalized.get("chunk_y", 0)),
		])
	return result


static func _matches_canonical_with_instance_and_revision(
	parts: PackedStringArray
) -> bool:
	return (
		parts.size() in [14, 17]
		and parts[0] == "universe"
		and parts[2] == "instance"
		and parts[4] == "space"
		and parts[6] == "partition"
		and parts[8] == "revision"
		and parts[10] == "zone"
		and (parts.size() == 14 or parts[14] == "chunk")
	)


static func _matches_canonical_without_instance_with_revision(
	parts: PackedStringArray
) -> bool:
	return (
		parts.size() in [12, 15]
		and parts[0] == "universe"
		and parts[2] == "space"
		and parts[4] == "partition"
		and parts[6] == "revision"
		and parts[8] == "zone"
		and (parts.size() == 12 or parts[12] == "chunk")
	)


static func _matches_canonical_with_instance(parts: PackedStringArray) -> bool:
	return (
		parts.size() in [12, 15]
		and parts[0] == "universe"
		and parts[2] == "instance"
		and parts[4] == "space"
		and parts[6] == "partition"
		and parts[8] == "zone"
		and (parts.size() == 12 or parts[12] == "chunk")
	)


static func _matches_canonical_without_instance(parts: PackedStringArray) -> bool:
	return (
		parts.size() in [10, 13]
		and parts[0] == "universe"
		and parts[2] == "space"
		and parts[4] == "partition"
		and parts[6] == "zone"
		and (parts.size() == 10 or parts[10] == "chunk")
	)


static func _parse_canonical(
	parts: PackedStringArray,
	has_instance: bool,
	has_revision: bool,
	defaults: Dictionary
) -> Dictionary:
	var universe_id: String = parts[1]
	var instance_id: String = (
		parts[3]
		if has_instance
		else String(defaults.get("instance_id", DEFAULT_INSTANCE_ID))
	)
	var space_offset: int = 4 if has_instance else 2
	var partition_offset: int = 6 if has_instance else 4
	var revision_offset: int = partition_offset + 2
	var zone_offset: int = partition_offset + (4 if has_revision else 2)
	var face: int = _parse_face(parts[zone_offset + 1])
	var zone_x: int = _parse_non_negative_int(parts[zone_offset + 2])
	var zone_y: int = _parse_non_negative_int(parts[zone_offset + 3])
	var raw_scheme: String = parts[partition_offset + 1]
	var revision: int = (
		_parse_positive_int(parts[revision_offset + 1])
		if has_revision
		else int(defaults.get(
			"partition_scheme_revision",
			_infer_scheme_revision(raw_scheme)
		))
	)
	if (
		universe_id.is_empty()
		or instance_id.is_empty()
		or parts[space_offset + 1].is_empty()
		or raw_scheme.is_empty()
		or revision <= 0
		or face < 0
		or zone_x < 0
		or zone_y < 0
	):
		return {}
	var result := create_cube_sphere(
		face,
		zone_x,
		zone_y,
		-1,
		-1,
		universe_id,
		parts[space_offset + 1],
		raw_scheme,
		instance_id,
		revision
	)
	var chunk_offset: int = zone_offset + 4
	if parts.size() > chunk_offset:
		var chunk_x: int = _parse_non_negative_int(parts[chunk_offset + 1])
		var chunk_y: int = _parse_non_negative_int(parts[chunk_offset + 2])
		if chunk_x < 0 or chunk_y < 0:
			return {}
		result["chunk_x"] = chunk_x
		result["chunk_y"] = chunk_y
		result["chunk_id"] = chunk_key(result)
	return normalize(result)


static func _parse_legacy(
	parts: PackedStringArray,
	defaults: Dictionary
) -> Dictionary:
	var face: int = _parse_face(parts[1])
	var zone_x: int = _parse_non_negative_int(parts[2])
	var zone_y: int = _parse_non_negative_int(parts[3])
	if face < 0 or zone_x < 0 or zone_y < 0:
		return {}
	var partition_scheme: String = String(defaults.get(
		"partition_scheme",
		DEFAULT_SCHEME
	))
	var result := create_cube_sphere(
		face,
		zone_x,
		zone_y,
		-1,
		-1,
		String(defaults.get("universe_id", DEFAULT_UNIVERSE_ID)),
		String(defaults.get("space_id", DEFAULT_SPACE_ID)),
		partition_scheme,
		String(defaults.get("instance_id", DEFAULT_INSTANCE_ID)),
		int(defaults.get(
			"partition_scheme_revision",
			_infer_scheme_revision(partition_scheme)
		))
	)
	if parts.size() == 7:
		if parts[4] != "chunk":
			return {}
		var chunk_x: int = _parse_non_negative_int(parts[5])
		var chunk_y: int = _parse_non_negative_int(parts[6])
		if chunk_x < 0 or chunk_y < 0:
			return {}
		result["chunk_x"] = chunk_x
		result["chunk_y"] = chunk_y
		result["chunk_id"] = chunk_key(result)
	return normalize(result)


static func _resolve_scheme(
	partition_scheme: String,
	partition_scheme_revision: int
) -> Dictionary:
	var scheme_id: String = partition_scheme.strip_edges().to_lower()
	var inferred_revision: int = _infer_scheme_revision(scheme_id)
	var marker_index: int = scheme_id.rfind("_v")
	if marker_index >= 0:
		var suffix: String = scheme_id.substr(marker_index + 2)
		if suffix.is_valid_int():
			scheme_id = scheme_id.substr(0, marker_index)
	var revision: int = partition_scheme_revision
	if revision <= 0:
		revision = inferred_revision
	elif revision == DEFAULT_SCHEME_REVISION and inferred_revision != DEFAULT_SCHEME_REVISION:
		revision = inferred_revision
	return {
		"scheme_id": scheme_id,
		"revision": revision,
	}


static func _infer_scheme_revision(partition_scheme: String) -> int:
	var marker_index: int = partition_scheme.rfind("_v")
	if marker_index < 0:
		return DEFAULT_SCHEME_REVISION
	var revision_text: String = partition_scheme.substr(marker_index + 2)
	if not revision_text.is_valid_int():
		return DEFAULT_SCHEME_REVISION
	return maxi(int(revision_text), DEFAULT_SCHEME_REVISION)


static func _parse_face(value: String) -> int:
	if not value.begins_with("f"):
		return -1
	var face_text: String = value.trim_prefix("f")
	if not face_text.is_valid_int():
		return -1
	var face: int = int(face_text)
	return face if face >= 0 and face < 6 else -1


static func _parse_non_negative_int(value: String) -> int:
	if not value.is_valid_int():
		return -1
	var parsed: int = int(value)
	return parsed if parsed >= 0 else -1


static func _parse_positive_int(value: String) -> int:
	var parsed: int = _parse_non_negative_int(value)
	return parsed if parsed > 0 else -1


static func _is_canonical_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for forbidden in ["/", "\\", ":", " ", ".."]:
		if value.contains(forbidden):
			return false
	return true


static func _sanitize(value: String) -> String:
	var result: String = value.strip_edges().to_lower()
	for character in ["/", "\\", ":", " ", ".."]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "unknown"
