extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA := "planet_simulator.matter_cross_region_reservation.v1"
const FIELDS: Array[String] = [
	"schema", "region_id", "transaction_id", "participant_checksum", "acquired_tick", "checksum",
]


static func create(
	region_id: String,
	transaction_id: String,
	participant_checksum: String,
	acquired_tick: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_id": region_id.strip_edges().to_lower(),
		"transaction_id": transaction_id.strip_edges().to_lower(),
		"participant_checksum": participant_checksum.strip_edges().to_lower(),
		"acquired_tick": acquired_tick,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_RESERVATION_SCHEMA")
	for field in ["region_id", "transaction_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RESERVATION_ID", {"field": field})
	if not MatterUtils.is_lower_hex_64(value.get("participant_checksum")):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RESERVATION_PARTICIPANT")
	if not MatterUtils.is_json_integer(value.get("acquired_tick")) or int(value["acquired_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RESERVATION_TICK")
	return MatterUtils.validate_checksum(value)
