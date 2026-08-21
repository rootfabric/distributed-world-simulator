extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")

const SCHEMA := "planet_simulator.reference_frame_evidence.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"source_reference_frame_id",
	"target_reference_frame_id",
	"transform_revision",
	"world_graph_revision",
]


static func create(
		source_reference_frame_id: String,
		target_reference_frame_id: String,
		transform_revision: int,
		world_graph_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"source_reference_frame_id": source_reference_frame_id,
		"target_reference_frame_id": target_reference_frame_id,
		"transform_revision": transform_revision,
		"world_graph_revision": world_graph_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["source_reference_frame_id", "reference-frame"],
		["target_reference_frame_id", "reference-frame"],
	]:
		var id_check: Dictionary = CwipUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_positive_integer(value, "transform_revision"),
		CwipUtilsScript.require_positive_integer(value, "world_graph_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	return NetworkUtilsScript.validation_success()
