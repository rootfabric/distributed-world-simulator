extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const SCHEMA := "planet_simulator.matter_summary_node.v1"
const MATERIAL_FIELDS: Array[String] = ["material_id", "occupancy_weight"]
const FIELDS: Array[String] = [
	"schema",
	"summary_id",
	"body_id",
	"cell_address",
	"scope_id",
	"bounds_m",
	"authority_epoch",
	"summary_revision",
	"build_generation",
	"child_count",
	"leaf_count",
	"sample_count",
	"occupied_sample_count",
	"surface_sample_count",
	"minimum_signed_distance_m",
	"maximum_signed_distance_m",
	"minimum_occupancy_ratio",
	"maximum_occupancy_ratio",
	"contains_matter",
	"contains_vacuum",
	"contains_surface",
	"material_occupancy_weights",
	"total_occupancy_weight",
	"minimum_descendant_revision",
	"maximum_descendant_revision",
	"dependency_hash",
	"descendant_revision_hash",
	"checksum",
]
const SURFACE_EPSILON_M: float = 0.000000001
const WEIGHT_TOLERANCE: float = 0.000000001


static func create(data: Dictionary) -> Dictionary:
	var cell_address: Dictionary = Dictionary(data.get("cell_address", {})).duplicate(true)
	var body_id: String = String(data.get("body_id", "")).strip_edges().to_lower()
	var materials: Array = _sorted_materials(Array(data.get("material_occupancy_weights", [])))
	var value: Dictionary = {
		"schema": SCHEMA,
		"summary_id": summary_id_for(body_id, cell_address),
		"body_id": body_id,
		"cell_address": cell_address,
		"scope_id": scope_id_for(body_id, cell_address),
		"bounds_m": Array(data.get("bounds_m", [])).duplicate(true),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"summary_revision": int(data.get("summary_revision", -1)),
		"build_generation": int(data.get("build_generation", 0)),
		"child_count": int(data.get("child_count", -1)),
		"leaf_count": int(data.get("leaf_count", 0)),
		"sample_count": int(data.get("sample_count", 0)),
		"occupied_sample_count": int(data.get("occupied_sample_count", -1)),
		"surface_sample_count": int(data.get("surface_sample_count", -1)),
		"minimum_signed_distance_m": float(data.get("minimum_signed_distance_m", INF)),
		"maximum_signed_distance_m": float(data.get("maximum_signed_distance_m", -INF)),
		"minimum_occupancy_ratio": float(data.get("minimum_occupancy_ratio", INF)),
		"maximum_occupancy_ratio": float(data.get("maximum_occupancy_ratio", -INF)),
		"contains_matter": bool(data.get("contains_matter", false)),
		"contains_vacuum": bool(data.get("contains_vacuum", false)),
		"contains_surface": bool(data.get("contains_surface", false)),
		"material_occupancy_weights": materials,
		"total_occupancy_weight": float(data.get("total_occupancy_weight", 0.0)),
		"minimum_descendant_revision": int(data.get("minimum_descendant_revision", -1)),
		"maximum_descendant_revision": int(data.get("maximum_descendant_revision", -1)),
		"dependency_hash": String(data.get("dependency_hash", "")).strip_edges().to_lower(),
		"descendant_revision_hash": String(data.get("descendant_revision_hash", "")).strip_edges().to_lower(),
		"checksum": "",
	}
	value["checksum"] = RepresentationUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = RepresentationUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return RepresentationUtils.failure("UNSUPPORTED_MATTER_SUMMARY_NODE_SCHEMA")
	if not MatterUtils.is_canonical_id(value.get("body_id"), 2):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_BODY_ID")
	if typeof(value.get("cell_address")) != TYPE_DICTIONARY:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_CELL_ADDRESS")
	var cell_address: Dictionary = value["cell_address"]
	if not bool(CellAddress.validate(cell_address).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_CELL_ADDRESS")
	if String(value.get("summary_id", "")) != summary_id_for(String(value["body_id"]), cell_address):
		return RepresentationUtils.failure("MATTER_SUMMARY_ID_MISMATCH")
	if String(value.get("scope_id", "")) != scope_id_for(String(value["body_id"]), cell_address):
		return RepresentationUtils.failure("MATTER_SUMMARY_SCOPE_ID_MISMATCH")
	checked = RepresentationUtils.validate_bounds_m(value.get("bounds_m"))
	if not bool(checked.get("success", false)):
		return checked
	for field in [
		"authority_epoch",
		"summary_revision",
		"build_generation",
		"child_count",
		"leaf_count",
		"sample_count",
		"occupied_sample_count",
		"surface_sample_count",
		"minimum_descendant_revision",
		"maximum_descendant_revision",
	]:
		if not RepresentationUtils.is_json_integer(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_AUTHORITY_EPOCH")
	if int(value["summary_revision"]) < 0 or int(value["build_generation"]) < 1:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REVISION")
	var child_count: int = int(value["child_count"])
	var leaf_count: int = int(value["leaf_count"])
	var sample_count: int = int(value["sample_count"])
	var occupied_count: int = int(value["occupied_sample_count"])
	var surface_count: int = int(value["surface_sample_count"])
	if child_count < 0 or child_count > 8:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_CHILD_COUNT")
	if leaf_count < 1 or sample_count < leaf_count:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_COUNTS")
	if child_count == 0 and leaf_count != 1:
		return RepresentationUtils.failure("MATTER_SUMMARY_LEAF_COUNT_MISMATCH")
	if child_count > 0 and leaf_count < child_count:
		return RepresentationUtils.failure("MATTER_SUMMARY_PARENT_LEAF_COUNT_MISMATCH")
	if occupied_count < 0 or occupied_count > sample_count \
		or surface_count < 0 or surface_count > sample_count:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_SAMPLE_COUNTS")
	for field in [
		"minimum_signed_distance_m",
		"maximum_signed_distance_m",
		"minimum_occupancy_ratio",
		"maximum_occupancy_ratio",
		"total_occupancy_weight",
	]:
		if not RepresentationUtils.is_finite_number(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_NUMBER", {"field": field})
	if float(value["minimum_signed_distance_m"]) > float(value["maximum_signed_distance_m"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_DISTANCE_RANGE_REVERSED")
	var minimum_occupancy: float = float(value["minimum_occupancy_ratio"])
	var maximum_occupancy: float = float(value["maximum_occupancy_ratio"])
	if minimum_occupancy < 0.0 or maximum_occupancy > 1.0 or minimum_occupancy > maximum_occupancy:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_OCCUPANCY_RANGE")
	for field in ["contains_matter", "contains_vacuum", "contains_surface"]:
		if typeof(value.get(field)) != TYPE_BOOL:
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_FLAG", {"field": field})
	var expected_matter: bool = maximum_occupancy > 0.0
	var expected_vacuum: bool = minimum_occupancy < 1.0
	var expected_surface: bool = surface_count > 0 \
		or (float(value["minimum_signed_distance_m"]) <= SURFACE_EPSILON_M \
		and float(value["maximum_signed_distance_m"]) >= -SURFACE_EPSILON_M)
	if bool(value["contains_matter"]) != expected_matter \
		or bool(value["contains_vacuum"]) != expected_vacuum \
		or bool(value["contains_surface"]) != expected_surface:
		return RepresentationUtils.failure("MATTER_SUMMARY_FLAG_MISMATCH")
	if expected_matter != (occupied_count > 0):
		return RepresentationUtils.failure("MATTER_SUMMARY_OCCUPIED_COUNT_MISMATCH")
	if not RepresentationUtils.is_non_negative_number(value.get("total_occupancy_weight")):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_TOTAL_WEIGHT")
	checked = _validate_materials(value.get("material_occupancy_weights"), float(value["total_occupancy_weight"]))
	if not bool(checked.get("success", false)):
		return checked
	if expected_matter != (float(value["total_occupancy_weight"]) > 0.0):
		return RepresentationUtils.failure("MATTER_SUMMARY_MATERIAL_PRESENCE_MISMATCH")
	var minimum_descendant: int = int(value["minimum_descendant_revision"])
	var maximum_descendant: int = int(value["maximum_descendant_revision"])
	if minimum_descendant < 0 or maximum_descendant < minimum_descendant:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_DESCENDANT_REVISION_RANGE")
	if int(value["summary_revision"]) < maximum_descendant:
		return RepresentationUtils.failure("MATTER_SUMMARY_REVISION_BEHIND_DESCENDANTS")
	if not RepresentationUtils.is_lower_hex_64(value.get("dependency_hash")):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_DEPENDENCY_HASH")
	if not RepresentationUtils.is_lower_hex_64(value.get("descendant_revision_hash")):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_DESCENDANT_HASH")
	return RepresentationUtils.validate_checksum(value)


static func to_source_revision(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return SourceRevision.create(
		"MATTER",
		String(value["body_id"]),
		int(value["authority_epoch"]),
		int(value["summary_revision"]),
		String(value["checksum"]),
		String(value["dependency_hash"])
	)


static func summary_id_for(body_id: String, cell_address: Dictionary) -> String:
	var cell_id: String = String(cell_address.get("cell_id", ""))
	if not MatterUtils.is_canonical_id(body_id, 2) or not MatterUtils.is_canonical_id(cell_id, 2):
		return ""
	return "matter-summary/%s/%s" % [body_id, cell_id]


static func scope_id_for(body_id: String, cell_address: Dictionary) -> String:
	var cell_id: String = String(cell_address.get("cell_id", ""))
	if not MatterUtils.is_canonical_id(body_id, 2) or not MatterUtils.is_canonical_id(cell_id, 2):
		return ""
	return "representation-scope/matter-summary/%s/%s" % [body_id, cell_id]


static func content_hash(value: Dictionary) -> String:
	return String(value.get("checksum", "")) if bool(validate(value).get("success", false)) else ""


static func _validate_materials(value, expected_total: float) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MATERIALS")
	var previous_id: String = ""
	var total: float = 0.0
	for index in range(value.size()):
		var raw_entry = value[index]
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MATERIAL", {"index": index})
		var entry: Dictionary = raw_entry
		var checked: Dictionary = RepresentationUtils.validate_exact_fields(entry, MATERIAL_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var material_id: String = String(entry.get("material_id", ""))
		if not MatterUtils.is_canonical_id(material_id, 2):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MATERIAL_ID", {"index": index})
		if index > 0 and material_id <= previous_id:
			return RepresentationUtils.failure("MATTER_SUMMARY_MATERIALS_NOT_SORTED_UNIQUE", {"index": index})
		if not RepresentationUtils.is_positive_number(entry.get("occupancy_weight")):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MATERIAL_WEIGHT", {"index": index})
		total += float(entry["occupancy_weight"])
		previous_id = material_id
	if absf(total - expected_total) > WEIGHT_TOLERANCE * maxf(1.0, absf(expected_total)):
		return RepresentationUtils.failure("MATTER_SUMMARY_MATERIAL_WEIGHT_MISMATCH")
	return RepresentationUtils.success()


static func _sorted_materials(values: Array) -> Array:
	var by_id: Dictionary = {}
	for raw_value in values:
		if typeof(raw_value) != TYPE_DICTIONARY:
			continue
		var material_id: String = String(raw_value.get("material_id", "")).strip_edges().to_lower()
		var weight: float = float(raw_value.get("occupancy_weight", 0.0))
		if by_id.has(material_id):
			by_id[material_id] = float(by_id[material_id]) + weight
		else:
			by_id[material_id] = weight
	var ids: Array = by_id.keys()
	ids.sort()
	var output: Array = []
	for material_id in ids:
		output.append({
			"material_id": String(material_id),
			"occupancy_weight": float(by_id[material_id]),
		})
	return output
