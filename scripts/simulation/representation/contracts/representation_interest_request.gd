extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const SCHEMA := "planet_simulator.representation_interest_request.v1"
const FIELDS: Array[String] = [
	"schema",
	"request_id",
	"observer_id",
	"required_source_revision",
	"distance_m",
	"projection_scale_px",
	"maximum_screen_error_px",
	"maximum_geometric_error_m",
	"collision_required",
	"interior_required",
	"bandwidth_budget_bytes",
	"preferred_artifact_kinds",
	"request_revision",
	"checksum",
]


static func create(
	request_id: String,
	observer_id: String,
	required_source_revision: Dictionary,
	distance_m: float,
	projection_scale_px: float,
	maximum_screen_error_px: float,
	maximum_geometric_error_m: float,
	collision_required: bool,
	interior_required: bool,
	bandwidth_budget_bytes: int,
	preferred_artifact_kinds: Array,
	request_revision: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"request_id": request_id,
		"observer_id": observer_id,
		"required_source_revision": required_source_revision.duplicate(true),
		"distance_m": distance_m,
		"projection_scale_px": projection_scale_px,
		"maximum_screen_error_px": maximum_screen_error_px,
		"maximum_geometric_error_m": maximum_geometric_error_m,
		"collision_required": collision_required,
		"interior_required": interior_required,
		"bandwidth_budget_bytes": bandwidth_budget_bytes,
		"preferred_artifact_kinds": preferred_artifact_kinds.duplicate(true),
		"request_revision": request_revision,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_INTEREST_REQUEST_SCHEMA")
	if not Utils.is_canonical_id(value.get("request_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_REQUEST_ID")
	if not Utils.is_canonical_id(value.get("observer_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_OBSERVER_ID")
	if typeof(value.get("required_source_revision")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_REQUIRED_SOURCE")
	checked = SourceRevision.validate(value["required_source_revision"])
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_positive_number(value.get("distance_m")):
		return Utils.failure("INVALID_REPRESENTATION_DISTANCE")
	if not Utils.is_positive_number(value.get("projection_scale_px")):
		return Utils.failure("INVALID_REPRESENTATION_PROJECTION_SCALE")
	if not Utils.is_positive_number(value.get("maximum_screen_error_px")):
		return Utils.failure("INVALID_REPRESENTATION_SCREEN_ERROR_BUDGET")
	if not Utils.is_non_negative_number(value.get("maximum_geometric_error_m")):
		return Utils.failure("INVALID_REPRESENTATION_GEOMETRIC_ERROR_BUDGET")
	if typeof(value.get("collision_required")) != TYPE_BOOL or typeof(value.get("interior_required")) != TYPE_BOOL:
		return Utils.failure("INVALID_REPRESENTATION_INTEREST_CAPABILITIES")
	if not Utils.is_json_integer(value.get("bandwidth_budget_bytes")) or int(value["bandwidth_budget_bytes"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_BANDWIDTH_BUDGET")
	checked = Utils.validate_sorted_unique_kinds(value.get("preferred_artifact_kinds"), true)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_json_integer(value.get("request_revision")) or int(value["request_revision"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_REQUEST_REVISION")
	return Utils.validate_checksum(value)
