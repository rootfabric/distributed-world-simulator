extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")

const SCHEMA := "planet_simulator.effect_commit_result.v1"
const PROTOCOL_VERSION := 1
const RESULTS: Array[String] = ["COMMITTED", "DUPLICATE_REPLAY", "REJECTED", "STALE_OWNER"]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"interaction_id",
	"operation_id",
	"result",
	"canonical_effect_revision",
	"target_authority_epoch",
]


static func create(
		interaction_id: String,
		operation_id: String,
		result: String,
		canonical_effect_revision,
		target_authority_epoch: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"interaction_id": interaction_id,
		"operation_id": operation_id,
		"result": result,
		"canonical_effect_revision": canonical_effect_revision,
		"target_authority_epoch": target_authority_epoch,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_id(value, "interaction_id", "interaction"),
		CwipUtilsScript.require_id(value, "operation_id", "operation"),
		GatewayUtilsScript.require_enum(value, "result", RESULTS),
		CwipUtilsScript.require_positive_integer(value, "target_authority_epoch"),
	]:
		if not bool(check.get("success", false)):
			return check
	var result := String(value.get("result"))
	if result == "COMMITTED" or result == "DUPLICATE_REPLAY":
		var revision_holder := {"revision": value.get("canonical_effect_revision")}
		var revision_check: Dictionary = CwipUtilsScript.require_positive_integer(revision_holder, "revision")
		if not bool(revision_check.get("success", false)):
			return NetworkUtilsScript.validation_failure(
				"INVALID_CANONICAL_EFFECT_REVISION",
				"Committed/replayed effect requires canonical_effect_revision >= 1",
			)
	elif value.get("canonical_effect_revision") != null:
		return NetworkUtilsScript.validation_failure(
			"UNEXPECTED_CANONICAL_EFFECT_REVISION",
			"Rejected/stale effect result cannot claim a canonical effect revision",
		)
	return NetworkUtilsScript.validation_success()
