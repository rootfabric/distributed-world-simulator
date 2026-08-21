extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")

const SCHEMA := "planet_simulator.interaction_time.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"simulation_epoch",
	"canonical_time",
	"source_local_tick",
	"time_mapping_revision",
]


static func create(
		simulation_epoch: int,
		canonical_time: float,
		source_local_tick: int,
		time_mapping_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"simulation_epoch": simulation_epoch,
		"canonical_time": canonical_time,
		"source_local_tick": source_local_tick,
		"time_mapping_revision": time_mapping_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_positive_integer(value, "simulation_epoch"),
		CwipUtilsScript.require_nonnegative_number(value, "canonical_time"),
		CwipUtilsScript.require_nonnegative_integer(value, "source_local_tick"),
		CwipUtilsScript.require_positive_integer(value, "time_mapping_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	return NetworkUtilsScript.validation_success()
