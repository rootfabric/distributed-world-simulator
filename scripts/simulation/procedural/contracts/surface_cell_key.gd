extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.surface_cell_key.v1"
const FACES: Array[String] = ["PX", "NX", "PY", "NY", "PZ", "NZ"]
const MAX_LOD: int = 30
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"face",
	"lod",
	"x",
	"y",
	"checksum",
]


static func create(body_id: String, face: String, lod: int, x: int, y: int) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"face": face.to_upper(),
		"lod": lod,
		"x": x,
		"y": y,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SURFACE_CELL_KEY_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_BODY_ID")
	if typeof(value.get("face")) != TYPE_STRING or not FACES.has(String(value["face"])):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_FACE")
	for field in ["lod", "x", "y"]:
		if not GeoUtilsScript.is_json_integer(value.get(field)):
			return GeoUtilsScript.failure("INVALID_SURFACE_CELL_INDEX", {"field": field})
	var lod: int = int(value["lod"])
	if lod < 0 or lod > MAX_LOD:
		return GeoUtilsScript.failure("SURFACE_CELL_LOD_OUT_OF_RANGE")
	var side: int = 1 << lod
	var x: int = int(value["x"])
	var y: int = int(value["y"])
	if x < 0 or y < 0 or x >= side or y >= side:
		return GeoUtilsScript.failure("SURFACE_CELL_COORDINATE_OUT_OF_RANGE")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.surface_cell_key")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func token(value: Dictionary) -> String:
	if not bool(validate(value).get("success", false)):
		return ""
	return identity_token(value)


# Fast identity form for callers that already validated the cell or created it
# through SurfaceCellKey.create(). It deliberately excludes checksum because the
# address identity is body/face/lod/x/y; checksum protects DTO transport.
static func identity_token(value: Dictionary) -> String:
	return "%s#%s#%d#%d#%d" % [
		String(value["body_id"]),
		String(value["face"]),
		int(value["lod"]),
		int(value["x"]),
		int(value["y"]),
	]
