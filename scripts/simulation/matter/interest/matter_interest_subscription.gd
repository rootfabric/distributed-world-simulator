extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")

const SCHEMA: String = "planet_simulator.matter_interest_subscription.v1"
const MAX_RADIUS_CELLS: int = 8
const FIELDS: Array[String] = [
	"schema", "subscription_id", "client_id", "authority_epoch",
	"interest_revision", "cell_level", "center_cell_address",
	"radius_cells", "checksum",
]


static func create(
	subscription_id: String,
	client_id: String,
	authority_epoch: int,
	interest_revision: int,
	cell_level: int,
	center_cell_address: Dictionary,
	radius_cells: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"subscription_id": subscription_id.strip_edges().to_lower(),
		"client_id": client_id.strip_edges().to_lower(),
		"authority_epoch": authority_epoch,
		"interest_revision": interest_revision,
		"cell_level": cell_level,
		"center_cell_address": center_cell_address.duplicate(true),
		"radius_cells": radius_cells,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_INTEREST_SUBSCRIPTION_SCHEMA")
	for field in ["subscription_id", "client_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SUBSCRIPTION_ID", {"field": field})
	for field in ["authority_epoch", "interest_revision", "cell_level", "radius_cells"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SUBSCRIPTION_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["interest_revision"]) < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SUBSCRIPTION_REVISION")
	if int(value["cell_level"]) < 0 or int(value["radius_cells"]) < 0 \
			or int(value["radius_cells"]) > MAX_RADIUS_CELLS:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SUBSCRIPTION_BOUNDS")
	if typeof(value.get("center_cell_address")) != TYPE_DICTIONARY \
			or not bool(CellAddressScript.validate(value["center_cell_address"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_CENTER_ADDRESS")
	if int(value["center_cell_address"]["level"]) != int(value["cell_level"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_CENTER_LEVEL_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_interest_subscription")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)
