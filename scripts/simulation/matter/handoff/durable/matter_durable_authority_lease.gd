extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const FencingToken = preload("res://scripts/simulation/matter/handoff/durable/matter_authority_fencing_token.gd")

const SCHEMA := "planet_simulator.matter_durable_authority_lease.v1"
const STATUS_ACTIVE := "ACTIVE"
const STATUS_PREPARING := "PREPARING"
const STATUSES: Array[String] = [STATUS_ACTIVE, STATUS_PREPARING]
const FIELDS: Array[String] = [
	"schema", "region_id", "body_id", "region_root_address", "region_checksum",
	"grid_profile_hash", "owner_id", "authority_epoch", "lease_revision", "status",
	"issued_tick", "renew_after_tick", "expires_at_tick", "fencing_token",
	"active_transfer_id", "source_owner_id", "target_owner_id", "last_transition_id", "checksum",
]


static func create_active(
	region_id: String,
	body_id: String,
	region_root_address: Dictionary,
	region_checksum: String,
	grid_profile_hash: String,
	owner_id: String,
	authority_epoch: int,
	lease_revision: int,
	transition_id: String,
	issued_tick: int,
	renew_after_tick: int,
	expires_at_tick: int
) -> Dictionary:
	var token: Dictionary = FencingToken.create(
		region_id, owner_id, authority_epoch, lease_revision, transition_id, issued_tick, expires_at_tick
	)
	if token.is_empty():
		return {}
	return _create({
		"region_id": region_id,
		"body_id": body_id,
		"region_root_address": region_root_address,
		"region_checksum": region_checksum,
		"grid_profile_hash": grid_profile_hash,
		"owner_id": owner_id,
		"authority_epoch": authority_epoch,
		"lease_revision": lease_revision,
		"status": STATUS_ACTIVE,
		"issued_tick": issued_tick,
		"renew_after_tick": renew_after_tick,
		"expires_at_tick": expires_at_tick,
		"fencing_token": token,
		"active_transfer_id": "",
		"source_owner_id": "",
		"target_owner_id": "",
		"last_transition_id": transition_id,
	})


static func create_preparing(
	previous: Dictionary,
	transfer_id: String,
	target_owner_id: String,
	transition_id: String,
	issued_tick: int,
	renew_after_tick: int,
	expires_at_tick: int
) -> Dictionary:
	if not bool(validate(previous).get("success", false)) or String(previous["status"]) != STATUS_ACTIVE:
		return {}
	var next_revision: int = int(previous["lease_revision"]) + 1
	var token: Dictionary = FencingToken.create(
		String(previous["region_id"]), String(previous["owner_id"]),
		int(previous["authority_epoch"]), next_revision, transition_id, issued_tick, expires_at_tick
	)
	if token.is_empty():
		return {}
	return _create({
		"region_id": previous["region_id"],
		"body_id": previous["body_id"],
		"region_root_address": previous["region_root_address"],
		"region_checksum": previous["region_checksum"],
		"grid_profile_hash": previous["grid_profile_hash"],
		"owner_id": previous["owner_id"],
		"authority_epoch": int(previous["authority_epoch"]),
		"lease_revision": next_revision,
		"status": STATUS_PREPARING,
		"issued_tick": issued_tick,
		"renew_after_tick": renew_after_tick,
		"expires_at_tick": expires_at_tick,
		"fencing_token": token,
		"active_transfer_id": transfer_id,
		"source_owner_id": previous["owner_id"],
		"target_owner_id": target_owner_id,
		"last_transition_id": transition_id,
	})


static func reactivate_source(
	preparing: Dictionary,
	transition_id: String,
	issued_tick: int,
	renew_after_tick: int,
	expires_at_tick: int
) -> Dictionary:
	if not bool(validate(preparing).get("success", false)) or String(preparing["status"]) != STATUS_PREPARING:
		return {}
	return create_active(
		String(preparing["region_id"]), String(preparing["body_id"]), preparing["region_root_address"],
		String(preparing["region_checksum"]), String(preparing["grid_profile_hash"]),
		String(preparing["source_owner_id"]), int(preparing["authority_epoch"]),
		int(preparing["lease_revision"]) + 1, transition_id, issued_tick, renew_after_tick, expires_at_tick
	)


static func activate_target(
	preparing: Dictionary,
	transition_id: String,
	issued_tick: int,
	renew_after_tick: int,
	expires_at_tick: int
) -> Dictionary:
	if not bool(validate(preparing).get("success", false)) or String(preparing["status"]) != STATUS_PREPARING:
		return {}
	return create_active(
		String(preparing["region_id"]), String(preparing["body_id"]), preparing["region_root_address"],
		String(preparing["region_checksum"]), String(preparing["grid_profile_hash"]),
		String(preparing["target_owner_id"]), int(preparing["authority_epoch"]) + 1,
		int(preparing["lease_revision"]) + 1, transition_id, issued_tick, renew_after_tick, expires_at_tick
	)


static func renew(
	active: Dictionary,
	transition_id: String,
	issued_tick: int,
	renew_after_tick: int,
	expires_at_tick: int
) -> Dictionary:
	if not bool(validate(active).get("success", false)) or String(active["status"]) != STATUS_ACTIVE:
		return {}
	return create_active(
		String(active["region_id"]), String(active["body_id"]), active["region_root_address"],
		String(active["region_checksum"]), String(active["grid_profile_hash"]), String(active["owner_id"]),
		int(active["authority_epoch"]), int(active["lease_revision"]) + 1,
		transition_id, issued_tick, renew_after_tick, expires_at_tick
	)


static func claim_expired(
	active: Dictionary,
	claimant_owner_id: String,
	transition_id: String,
	issued_tick: int,
	renew_after_tick: int,
	expires_at_tick: int
) -> Dictionary:
	if not bool(validate(active).get("success", false)) or String(active["status"]) != STATUS_ACTIVE:
		return {}
	return create_active(
		String(active["region_id"]), String(active["body_id"]), active["region_root_address"],
		String(active["region_checksum"]), String(active["grid_profile_hash"]), claimant_owner_id,
		int(active["authority_epoch"]) + 1, int(active["lease_revision"]) + 1,
		transition_id, issued_tick, renew_after_tick, expires_at_tick
	)


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_DURABLE_AUTHORITY_LEASE_SCHEMA")
	for field in ["region_id", "body_id", "owner_id", "last_transition_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_LEASE_ID", {"field": field})
	if typeof(value.get("region_root_address")) != TYPE_DICTIONARY \
		or not bool(CellAddress.validate(value["region_root_address"]).get("success", false)):
		return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_REGION_ROOT")
	for field in ["region_checksum", "grid_profile_hash"]:
		if not MatterUtils.is_lower_hex_64(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_HASH", {"field": field})
	for field in ["authority_epoch", "lease_revision", "issued_tick", "renew_after_tick", "expires_at_tick"]:
		if not MatterUtils.is_json_integer(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["lease_revision"]) < 1 \
		or int(value["issued_tick"]) < 0 \
		or int(value["renew_after_tick"]) <= int(value["issued_tick"]) \
		or int(value["expires_at_tick"]) <= int(value["renew_after_tick"]):
		return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_LEASE_WINDOW")
	if not String(value.get("status", "")) in STATUSES:
		return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_STATUS")
	if typeof(value.get("fencing_token")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_FENCING_TOKEN")
	checked = FencingToken.validate(value["fencing_token"])
	if not bool(checked.get("success", false)):
		return checked
	var token: Dictionary = value["fencing_token"]
	if String(token["region_id"]) != String(value["region_id"]) \
		or String(token["owner_id"]) != String(value["owner_id"]) \
		or int(token["authority_epoch"]) != int(value["authority_epoch"]) \
		or int(token["lease_revision"]) != int(value["lease_revision"]) \
		or int(token["issued_tick"]) != int(value["issued_tick"]) \
		or int(token["expires_at_tick"]) != int(value["expires_at_tick"]):
		return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_FENCING_TOKEN_BINDING_MISMATCH")
	var status: String = String(value["status"])
	if status == STATUS_ACTIVE:
		if not String(value["active_transfer_id"]).is_empty() \
			or not String(value["source_owner_id"]).is_empty() \
			or not String(value["target_owner_id"]).is_empty():
			return MatterUtils.failure("ACTIVE_MATTER_DURABLE_LEASE_HAS_TRANSFER")
	else:
		for field in ["active_transfer_id", "source_owner_id", "target_owner_id"]:
			if not MatterUtils.is_canonical_id(value.get(field), 2):
				return MatterUtils.failure("INVALID_MATTER_DURABLE_TRANSFER_IDENTITY", {"field": field})
		if String(value["source_owner_id"]) != String(value["owner_id"]) \
			or String(value["target_owner_id"]) == String(value["owner_id"]):
			return MatterUtils.failure("INVALID_MATTER_DURABLE_PREPARING_OWNERS")
	return MatterUtils.validate_checksum(value)


static func _create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_id": String(data.get("region_id", "")).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"region_root_address": Dictionary(data.get("region_root_address", {})).duplicate(true),
		"region_checksum": String(data.get("region_checksum", "")).strip_edges().to_lower(),
		"grid_profile_hash": String(data.get("grid_profile_hash", "")).strip_edges().to_lower(),
		"owner_id": String(data.get("owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"lease_revision": int(data.get("lease_revision", 0)),
		"status": String(data.get("status", "")).strip_edges().to_upper(),
		"issued_tick": int(data.get("issued_tick", 0)),
		"renew_after_tick": int(data.get("renew_after_tick", 0)),
		"expires_at_tick": int(data.get("expires_at_tick", 0)),
		"fencing_token": Dictionary(data.get("fencing_token", {})).duplicate(true),
		"active_transfer_id": String(data.get("active_transfer_id", "")).strip_edges().to_lower(),
		"source_owner_id": String(data.get("source_owner_id", "")).strip_edges().to_lower(),
		"target_owner_id": String(data.get("target_owner_id", "")).strip_edges().to_lower(),
		"last_transition_id": String(data.get("last_transition_id", "")).strip_edges().to_lower(),
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}
