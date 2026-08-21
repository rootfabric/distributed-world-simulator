extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")

const SCHEMA := "planet_simulator.effect_commit_request.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"interaction_id",
	"operation_id",
	"resolution_digest",
	"target_entity_id",
	"target_authority",
	"target_authority_epoch_observed",
	"effect_kind",
	"effect_definition_id",
	"effect_payload",
]


static func create(
		interaction_id: String,
		operation_id: String,
		resolution_digest: String,
		target_entity_id: String,
		target_authority: String,
		target_authority_epoch_observed: int,
		effect_kind: String,
		effect_definition_id: String,
		effect_payload: Dictionary,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"interaction_id": interaction_id,
		"operation_id": operation_id,
		"resolution_digest": resolution_digest,
		"target_entity_id": target_entity_id,
		"target_authority": target_authority,
		"target_authority_epoch_observed": target_authority_epoch_observed,
		"effect_kind": effect_kind,
		"effect_definition_id": effect_definition_id,
		"effect_payload": effect_payload.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["interaction_id", "interaction"],
		["operation_id", "operation"],
		["target_entity_id", "entity"],
		["target_authority", "authority"],
		["effect_definition_id", "effect-definition"],
	]:
		var id_check: Dictionary = CwipUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_sha256(value, "resolution_digest"),
		CwipUtilsScript.require_positive_integer(value, "target_authority_epoch_observed"),
		CwipUtilsScript.require_nonempty_string(value, "effect_kind"),
		CwipUtilsScript.require_payload(value, "effect_payload"),
	]:
		if not bool(check.get("success", false)):
			return check
	return NetworkUtilsScript.validation_success()
