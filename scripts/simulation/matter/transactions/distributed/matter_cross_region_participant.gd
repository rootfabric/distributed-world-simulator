extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const FencingToken = preload("res://scripts/simulation/matter/handoff/durable/matter_authority_fencing_token.gd")

const SCHEMA := "planet_simulator.matter_cross_region_participant.v1"
const FIELDS: Array[String] = [
	"schema", "region_id", "body_id", "region_root_address", "owner_id",
	"authority_epoch", "lease_revision", "fencing_token", "previous_source_revision",
	"mutation_payload", "mutation_hash", "dirty_bounds_m", "affected_scope_ids", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var scopes: Array = MatterUtils.sorted_unique_ids(Array(data.get("affected_scope_ids", [])))
	var mutation_payload: Dictionary = Dictionary(data.get("mutation_payload", {})).duplicate(true)
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_id": String(data.get("region_id", "")).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"region_root_address": Dictionary(data.get("region_root_address", {})).duplicate(true),
		"owner_id": String(data.get("owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"lease_revision": int(data.get("lease_revision", 0)),
		"fencing_token": Dictionary(data.get("fencing_token", {})).duplicate(true),
		"previous_source_revision": Dictionary(data.get("previous_source_revision", {})).duplicate(true),
		"mutation_payload": mutation_payload,
		"mutation_hash": MatterUtils.payload_hash(mutation_payload),
		"dirty_bounds_m": Array(data.get("dirty_bounds_m", [])).duplicate(true),
		"affected_scope_ids": scopes,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_PARTICIPANT_SCHEMA")
	for field in ["region_id", "body_id", "owner_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PARTICIPANT_ID", {"field": field})
	if typeof(value.get("region_root_address")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_ROOT_ADDRESS")
	checked = CellAddress.validate(value["region_root_address"])
	if not bool(checked.get("success", false)):
		return checked
	for field in ["authority_epoch", "lease_revision"]:
		if not MatterUtils.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PARTICIPANT_FRONTIER", {"field": field})
	if typeof(value.get("fencing_token")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_FENCING_TOKEN")
	checked = FencingToken.validate(value["fencing_token"])
	if not bool(checked.get("success", false)):
		return checked
	var token: Dictionary = value["fencing_token"]
	if String(token["region_id"]) != String(value["region_id"]) \
		or String(token["owner_id"]) != String(value["owner_id"]) \
		or int(token["authority_epoch"]) != int(value["authority_epoch"]) \
		or int(token["lease_revision"]) != int(value["lease_revision"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_FENCING_TOKEN_BINDING_MISMATCH")
	if typeof(value.get("previous_source_revision")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PREVIOUS_SOURCE")
	checked = SourceRevision.validate(value["previous_source_revision"])
	if not bool(checked.get("success", false)):
		return checked
	var source: Dictionary = value["previous_source_revision"]
	if String(source["source_domain"]) != "MATTER" \
		or int(source["authority_epoch"]) != int(value["authority_epoch"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_SOURCE_BINDING_MISMATCH")
	if typeof(value.get("mutation_payload")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_MUTATION_PAYLOAD")
	checked = MatterUtils.validate_json_safe(value["mutation_payload"], "$.matter_cross_region_participant.mutation_payload")
	if not bool(checked.get("success", false)):
		return checked
	if not MatterUtils.is_lower_hex_64(value.get("mutation_hash")) \
		or String(value["mutation_hash"]) != MatterUtils.payload_hash(value["mutation_payload"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_MUTATION_HASH_MISMATCH")
	checked = _validate_bounds(value.get("dirty_bounds_m"))
	if not bool(checked.get("success", false)):
		return checked
	checked = MatterUtils.validate_sorted_unique_ids(value.get("affected_scope_ids"), false)
	if not bool(checked.get("success", false)):
		return checked
	return MatterUtils.validate_checksum(value)


static func _validate_bounds(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 6:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_DIRTY_BOUNDS")
	for item in value:
		if not MatterUtils.is_finite_number(item):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_DIRTY_BOUNDS")
	if float(value[0]) > float(value[3]) \
		or float(value[1]) > float(value[4]) \
		or float(value[2]) > float(value[5]):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_DIRTY_BOUNDS_ORDER")
	return MatterUtils.success()
