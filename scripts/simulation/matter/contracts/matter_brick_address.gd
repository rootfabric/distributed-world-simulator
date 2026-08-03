extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")

const SCHEMA: String = "planet_simulator.matter_brick_address.v1"
const FIELDS: Array[String] = [
	"schema",
	"cell_address",
	"storage_level",
	"brick_x",
	"brick_y",
	"brick_z",
	"address_id",
]


static func create(
	cell_address: Dictionary,
	storage_level: int,
	brick_x: int,
	brick_y: int,
	brick_z: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"cell_address": cell_address.duplicate(true),
		"storage_level": storage_level,
		"brick_x": brick_x,
		"brick_y": brick_y,
		"brick_z": brick_z,
		"address_id": "",
	}
	value["address_id"] = compute_address_id(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_BRICK_ADDRESS_SCHEMA")
	if typeof(value.get("cell_address")) != TYPE_DICTIONARY \
		or not bool(CellAddressScript.validate(value["cell_address"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_CELL_ADDRESS")
	for field in ["storage_level", "brick_x", "brick_y", "brick_z"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_BRICK_INTEGER", {"field": field})
	var storage_level: int = int(value["storage_level"])
	if storage_level < 0 or storage_level > MatterUtilsScript.MAX_STORAGE_LEVEL:
		return MatterUtilsScript.failure("INVALID_MATTER_STORAGE_LEVEL")
	for field in ["brick_x", "brick_y", "brick_z"]:
		if absi(int(value[field])) > MatterUtilsScript.MAX_BRICK_COORDINATE:
			return MatterUtilsScript.failure("MATTER_BRICK_COORDINATE_OUT_OF_RANGE", {"field": field})
	if typeof(value.get("address_id")) != TYPE_STRING \
		or String(value["address_id"]) != compute_address_id(value):
		return MatterUtilsScript.failure("MATTER_BRICK_ADDRESS_ID_MISMATCH")
	return MatterUtilsScript.success()


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func compute_address_id(value: Dictionary) -> String:
	var cell_id: String = String(value.get("cell_address", {}).get("cell_id", ""))
	if cell_id.is_empty():
		return ""
	return "%s/matter/storage/%d/brick/%d/%d/%d" % [
		cell_id,
		int(value.get("storage_level", -1)),
		int(value.get("brick_x", 0)),
		int(value.get("brick_y", 0)),
		int(value.get("brick_z", 0)),
	]
