extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_proxy_section_topology.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "source_revision", "source_checksum", "section_size_m", "sections", "part_section_index", "checksum"]

static func compile(snapshot: Dictionary, section_size_m: float) -> Dictionary:
	var buckets: Dictionary = {}
	var part_section_index: Dictionary = {}
	for part in snapshot["parts"]:
		var part_id := String(part["part_id"])
		var position: Array = part["local_position_m"]
		var coord := [int(floor(float(position[0]) / section_size_m)), int(floor(float(position[1]) / section_size_m)), int(floor(float(position[2]) / section_size_m))]
		var key := _coord_key(coord)
		if not buckets.has(key): buckets[key] = {"coord": coord, "parts": []}
		buckets[key]["parts"].append(part)
		part_section_index[part_id] = _section_id(String(snapshot["construct_id"]), coord)
	var sections: Array = []
	var keys: Array = buckets.keys(); keys.sort()
	for key in keys:
		var bucket: Dictionary = buckets[key]
		var coord: Array = bucket["coord"]
		var part_ids: Array = []
		var interactive_part_ids: Array = []
		var cell_ids: Dictionary = {}
		var min_v: Array = [INF, INF, INF]
		var max_v: Array = [-INF, -INF, -INF]
		for part in bucket["parts"]:
			var part_id := String(part["part_id"]); part_ids.append(part_id)
			var metadata: Dictionary = part["metadata"]
			if bool(metadata.get("proxy_interactive", false)): interactive_part_ids.append(part_id)
			var cell_id := String(metadata.get("proxy_interior_cell_id", ""))
			if not cell_id.is_empty(): cell_ids[cell_id] = true
			var dimensions: Array = part_dimensions(part)
			var position: Array = part["local_position_m"]
			for axis in range(3):
				min_v[axis] = minf(float(min_v[axis]), float(position[axis]) - float(dimensions[axis]) * 0.5)
				max_v[axis] = maxf(float(max_v[axis]), float(position[axis]) + float(dimensions[axis]) * 0.5)
		part_ids.sort(); interactive_part_ids.sort()
		var cells: Array = cell_ids.keys(); cells.sort()
		var section := {"section_id": _section_id(String(snapshot["construct_id"]), coord), "grid_coord": coord, "bounds_min_m": min_v, "bounds_max_m": max_v, "part_ids": part_ids, "interactive_part_ids": interactive_part_ids, "interior_cell_ids": cells, "part_count": part_ids.size(), "checksum": ""}
		section["checksum"] = _section_checksum(section)
		sections.append(section)
	sections.sort_custom(func(a, b): return String(a["section_id"]) < String(b["section_id"]))
	var value := {"schema": SCHEMA, "construct_id": String(snapshot["construct_id"]), "source_revision": int(snapshot["state_revision"]), "source_checksum": String(snapshot["checksum"]), "section_size_m": section_size_m, "sections": sections, "part_section_index": part_section_index, "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return C.success({"topology": value})

static func part_dimensions(part: Dictionary) -> Array:
	var metadata: Dictionary = part["metadata"]
	var geometry = metadata.get("geometry", {})
	if typeof(geometry) == TYPE_DICTIONARY:
		var bounds = Dictionary(geometry).get("bounding_box_m", [])
		if typeof(bounds) == TYPE_ARRAY and Array(bounds).size() == 3:
			return [maxf(absf(float(bounds[0])), 0.02), maxf(absf(float(bounds[1])), 0.02), maxf(absf(float(bounds[2])), 0.02)]
	match String(part["part_kind"]):
		"WHEEL": return [0.22, 0.55, 0.55]
		"WALL_PANEL": return [0.18, 2.5, 4.0]
		"ROOF_PANEL", "FLOOR_PANEL": return [4.0, 0.18, 4.0]
		"FOUNDATION": return [4.2, 0.6, 4.2]
		_: return [0.5, 0.5, 0.5]

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("construct_id", "")), "construct/"): return C.failure("INVALID_CONSTRUCTION_PROXY_TOPOLOGY_IDENTITY")
	if not Utils.is_json_integer(value.get("source_revision")) or int(value["source_revision"]) < 0 or not C.hash64(String(value.get("source_checksum", ""))): return C.failure("INVALID_CONSTRUCTION_PROXY_TOPOLOGY_SOURCE")
	if not C.finite_number(value.get("section_size_m")) or float(value["section_size_m"]) <= 0.0: return C.failure("INVALID_CONSTRUCTION_PROXY_SECTION_SIZE")
	if typeof(value.get("sections")) != TYPE_ARRAY or typeof(value.get("part_section_index")) != TYPE_DICTIONARY: return C.failure("INVALID_CONSTRUCTION_PROXY_TOPOLOGY_COLLECTIONS")
	var section_ids := {}; var part_ids := {}; var previous := ""
	for section in value["sections"]:
		if typeof(section) != TYPE_DICTIONARY or not C.path_id(String(section.get("section_id", "")), "section/"): return C.failure("INVALID_CONSTRUCTION_PROXY_SECTION")
		var section_id := String(section["section_id"])
		if section_ids.has(section_id) or (not previous.is_empty() and section_id < previous): return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_SECTIONS")
		if not C.finite_vector(section.get("grid_coord"), 3) or not C.finite_vector(section.get("bounds_min_m"), 3) or not C.finite_vector(section.get("bounds_max_m"), 3): return C.failure("INVALID_CONSTRUCTION_PROXY_SECTION_BOUNDS")
		if not C.sorted_unique_strings(section.get("part_ids"), "part/") or not C.sorted_unique_strings(section.get("interactive_part_ids"), "part/") or not C.sorted_unique_strings(section.get("interior_cell_ids"), "interior-cell/"): return C.failure("INVALID_CONSTRUCTION_PROXY_SECTION_INDEX")
		if int(section.get("part_count", -1)) != Array(section["part_ids"]).size() or String(section.get("checksum", "")) != _section_checksum(section): return C.failure("CONSTRUCTION_PROXY_SECTION_CHECKSUM_MISMATCH")
		for part_id in section["part_ids"]:
			if part_ids.has(part_id): return C.failure("DUPLICATE_CONSTRUCTION_PROXY_PART")
			part_ids[part_id] = section_id
		section_ids[section_id] = true; previous = section_id
	if Dictionary(value["part_section_index"]).size() != part_ids.size(): return C.failure("CONSTRUCTION_PROXY_PART_INDEX_SIZE_MISMATCH")
	for part_id in part_ids:
		if String(value["part_section_index"].get(part_id, "")) != String(part_ids[part_id]): return C.failure("CONSTRUCTION_PROXY_PART_INDEX_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_TOPOLOGY_CHECKSUM_MISMATCH")
	return C.success()

static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
static func _section_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _coord_key(coord: Array) -> String: return "%s/%s/%s" % [_coord_token(int(coord[0])), _coord_token(int(coord[1])), _coord_token(int(coord[2]))]
static func _section_id(construct_id: String, coord: Array) -> String: return "section/%s/%s" % [construct_id.trim_prefix("construct/"), _coord_key(coord).replace("/", "_")]
static func _coord_token(value: int) -> String: return "n%06d" % abs(value) if value < 0 else "p%06d" % value
