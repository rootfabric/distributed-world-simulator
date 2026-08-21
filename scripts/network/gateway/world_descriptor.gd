extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.world_descriptor.v1"
const PROTOCOL_VERSION := 1

const SPATIAL_DOMAIN_FIELDS: Array[String] = ["kind", "partition", "index"]
const COVERAGE_FIELDS: Array[String] = ["kind", "radius"]
const PROJECTION_POLICY_FIELDS: Array[String] = ["read_only", "allows_mutation"]
const VISIBILITY_RULE_FIELDS: Array[String] = ["neighbor_depth"]
const INTEREST_RULE_FIELDS: Array[String] = ["max_projection_neighbors"]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"world_id",
	"world_kind",
	"reference_frame_id",
	"spatial_domain",
	"coverage",
	"authority_directory_key",
	"projection_capabilities",
	"projection_policy",
	"lod_classes",
	"visibility_rules",
	"interest_rules",
	"world_revision",
]


static func create(
		world_id: String,
		world_kind: String,
		reference_frame_id: String,
		spatial_domain: Dictionary,
		coverage: Dictionary,
		authority_directory_key: String,
		projection_capabilities: Array,
		projection_policy: Dictionary,
		lod_classes: Array,
		visibility_rules: Dictionary,
		interest_rules: Dictionary,
		world_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"world_id": world_id,
		"world_kind": world_kind,
		"reference_frame_id": reference_frame_id,
		"spatial_domain": spatial_domain.duplicate(true),
		"coverage": coverage.duplicate(true),
		"authority_directory_key": authority_directory_key,
		"projection_capabilities": projection_capabilities.duplicate(true),
		"projection_policy": projection_policy.duplicate(true),
		"lod_classes": lod_classes.duplicate(true),
		"visibility_rules": visibility_rules.duplicate(true),
		"interest_rules": interest_rules.duplicate(true),
		"world_revision": world_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["world_id", "world"],
		["reference_frame_id", "reference-frame"],
		["authority_directory_key", "authority-subject"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	if not BusUtilsScript.is_semantic_name(value.get("world_kind"), false):
		return NetworkUtilsScript.validation_failure("INVALID_WORLD_KIND", "world_kind must be a canonical semantic name")
	var revision_check: Dictionary = GatewayUtilsScript.require_positive_integer(value, "world_revision")
	if not bool(revision_check.get("success", false)):
		return revision_check
	for semantic_check in [
		_validate_spatial_domain(value.get("spatial_domain")),
		_validate_coverage(value.get("coverage")),
		_validate_projection_policy(value.get("projection_policy")),
		_validate_visibility_rules(value.get("visibility_rules")),
		_validate_interest_rules(value.get("interest_rules")),
	]:
		if not bool(semantic_check.get("success", false)):
			return semantic_check
	var projection_policy: Dictionary = Dictionary(value.get("projection_policy"))
	if bool(projection_policy.get("allows_mutation", false)):
		return NetworkUtilsScript.validation_failure(
			"PROJECTION_MUTATION_AUTHORITY_FORBIDDEN",
			"projection_policy cannot grant canonical mutation authority",
		)
	if projection_policy.has("read_only") and not bool(projection_policy.get("read_only")):
		return NetworkUtilsScript.validation_failure(
			"PROJECTION_NOT_READ_ONLY",
			"projection_policy.read_only cannot be false",
		)
	for field in ["projection_capabilities", "lod_classes"]:
		var list_check: Dictionary = _validate_semantic_list(value.get(String(field)), String(field))
		if not bool(list_check.get("success", false)):
			return list_check
	return GatewayUtilsScript.validate_schema(value, SCHEMA)


static func validate_newer(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_check: Dictionary = validate(candidate)
	if not bool(candidate_check.get("success", false)):
		return candidate_check
	var current_check: Dictionary = validate(current)
	if not bool(current_check.get("success", false)):
		return current_check
	if String(candidate.get("world_id")) != String(current.get("world_id")):
		return NetworkUtilsScript.validation_failure("WORLD_ID_MISMATCH", "Cannot compare revisions of different worlds")
	if int(candidate.get("world_revision")) <= int(current.get("world_revision")):
		return NetworkUtilsScript.validation_failure("STALE_WORLD_REVISION", "world_revision must advance")
	return NetworkUtilsScript.validation_success()


static func _validate_semantic_list(raw_value, field: String) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be an Array" % field)
	for item in raw_value:
		if not BusUtilsScript.is_semantic_name(item, false):
			return NetworkUtilsScript.validation_failure("INVALID_SEMANTIC_LIST", "%s contains invalid semantic value" % field)
	return NetworkUtilsScript.validation_success()


static func _validate_spatial_domain(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, SPATIAL_DOMAIN_FIELDS, "WorldDescriptor.spatial_domain")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	if not BusUtilsScript.is_semantic_name(value.get("kind"), false):
		return NetworkUtilsScript.validation_failure("INVALID_SPATIAL_DOMAIN", "spatial_domain.kind must be semantic")
	var has_partition: bool = value.has("partition")
	var has_index: bool = value.has("index")
	if not has_partition and not has_index:
		return NetworkUtilsScript.validation_failure("INVALID_SPATIAL_DOMAIN", "spatial_domain requires partition or index")
	if has_partition:
		var check: Dictionary = GatewayUtilsScript.require_nonnegative_integer(value, "partition")
		if not bool(check.get("success", false)):
			return check
	if has_index:
		var check: Dictionary = GatewayUtilsScript.require_nonnegative_integer(value, "index")
		if not bool(check.get("success", false)):
			return check
	return NetworkUtilsScript.validation_success()


static func _validate_coverage(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, COVERAGE_FIELDS, "WorldDescriptor.coverage")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	if not BusUtilsScript.is_semantic_name(value.get("kind"), false):
		return NetworkUtilsScript.validation_failure("INVALID_COVERAGE", "coverage.kind must be semantic")
	var radius = value.get("radius")
	if typeof(radius) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(radius)) or is_inf(float(radius)) or float(radius) < 0.0:
		return NetworkUtilsScript.validation_failure("INVALID_COVERAGE", "coverage.radius must be finite and non-negative")
	return NetworkUtilsScript.validation_success()


static func _validate_projection_policy(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, PROJECTION_POLICY_FIELDS, "WorldDescriptor.projection_policy")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	for field in PROJECTION_POLICY_FIELDS:
		if not value.has(field) or typeof(value.get(field)) != TYPE_BOOL:
			return NetworkUtilsScript.validation_failure("INVALID_PROJECTION_POLICY", "projection_policy fields must be Boolean")
	return NetworkUtilsScript.validation_success()


static func _validate_visibility_rules(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, VISIBILITY_RULE_FIELDS, "WorldDescriptor.visibility_rules")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	return GatewayUtilsScript.require_nonnegative_integer(value, "neighbor_depth")


static func _validate_interest_rules(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, INTEREST_RULE_FIELDS, "WorldDescriptor.interest_rules")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	return GatewayUtilsScript.require_nonnegative_integer(value, "max_projection_neighbors")
