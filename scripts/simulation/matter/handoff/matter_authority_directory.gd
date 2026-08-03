extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const RegionScript = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")
const LeaseScript = preload("res://scripts/simulation/matter/handoff/matter_authority_lease.gd")

var _configured: bool = false
var _body_id: String = ""
var _grid_profile: Dictionary = {}
var _leases_by_region_id: Dictionary = {}
var _region_id_by_transfer_id: Dictionary = {}
var _directory_revision: int = 0


func configure(body_id: String, grid_profile: Dictionary) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("MATTER_AUTHORITY_DIRECTORY_ALREADY_CONFIGURED")
	if not MatterUtilsScript.is_canonical_id(body_id, 2) \
			or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
			or String(grid_profile.get("body_id", "")) != body_id.strip_edges().to_lower():
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_DIRECTORY_WORLD")
	_body_id = body_id.strip_edges().to_lower()
	_grid_profile = grid_profile.duplicate(true)
	_leases_by_region_id.clear()
	_region_id_by_transfer_id.clear()
	_directory_revision = 0
	_configured = true
	return MatterUtilsScript.success()


func register_region(region: Dictionary, owner_id: String, authority_epoch: int) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_AUTHORITY_DIRECTORY_NOT_CONFIGURED")
	var validation: Dictionary = RegionScript.validate_for_grid(_grid_profile, region)
	if not bool(validation.get("success", false)):
		return validation
	if String(region["body_id"]) != _body_id \
			or not MatterUtilsScript.is_canonical_id(owner_id, 2) or authority_epoch < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_REGION_REGISTRATION")
	var region_id: String = String(region["region_id"])
	if _leases_by_region_id.has(region_id):
		var existing: Dictionary = _leases_by_region_id[region_id]
		var existing_region: Dictionary = LeaseScript.decode_region(existing)
		if existing_region == region \
				and String(existing["owner_id"]) == owner_id.strip_edges().to_lower() \
				and int(existing["authority_epoch"]) == authority_epoch:
			return MatterUtilsScript.success({"replay": true, "lease": existing.duplicate(true)})
		return MatterUtilsScript.failure("MATTER_AUTHORITY_REGION_ALREADY_REGISTERED")
	for existing_value in _leases_by_region_id.values():
		var existing_region: Dictionary = LeaseScript.decode_region(Dictionary(existing_value))
		if int(existing_region.get("cell_level", -1)) != int(region["cell_level"]):
			return MatterUtilsScript.failure("MIXED_LEVEL_MATTER_AUTHORITY_REGIONS_UNSUPPORTED")
		if RegionScript.overlaps(_grid_profile, region, existing_region):
			return MatterUtilsScript.failure("OVERLAPPING_MATTER_AUTHORITY_REGIONS")
	_directory_revision += 1
	var lease: Dictionary = LeaseScript.create({
		"region_transport": PersistenceCodecScript.encode_persistence_json(region),
		"owner_id": owner_id,
		"authority_epoch": authority_epoch,
		"lease_revision": _directory_revision,
		"status": "ACTIVE",
	})
	if not bool(LeaseScript.validate(lease).get("success", false)):
		return MatterUtilsScript.failure("MATTER_AUTHORITY_LEASE_BUILD_FAILED")
	_leases_by_region_id[region_id] = lease
	return MatterUtilsScript.success({"replay": false, "lease": lease.duplicate(true)})


func begin_handoff(
	transfer_id: String,
	region_id: String,
	source_owner_id: String,
	source_authority_epoch: int,
	target_owner_id: String,
	target_authority_epoch: int
) -> Dictionary:
	if not _configured or not _leases_by_region_id.has(region_id):
		return MatterUtilsScript.failure("UNKNOWN_MATTER_AUTHORITY_REGION")
	for value in [transfer_id, region_id, source_owner_id, target_owner_id]:
		if not MatterUtilsScript.is_canonical_id(value, 2):
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_ID")
	var lease: Dictionary = _leases_by_region_id[region_id]
	if String(lease["status"]) == "PREPARING":
		if String(lease["transfer_id"]) == transfer_id:
			if String(lease["owner_id"]) == source_owner_id.strip_edges().to_lower() \
					and int(lease["authority_epoch"]) == source_authority_epoch \
					and String(lease["target_owner_id"]) == target_owner_id.strip_edges().to_lower() \
					and int(lease["target_authority_epoch"]) == target_authority_epoch:
				return MatterUtilsScript.success({"replay": true, "lease": lease.duplicate(true)})
			return MatterUtilsScript.failure("MATTER_HANDOFF_TRANSFER_FINGERPRINT_CONFLICT")
		return MatterUtilsScript.failure("MATTER_AUTHORITY_REGION_HANDOFF_ALREADY_ACTIVE")
	if String(lease["owner_id"]) != source_owner_id.strip_edges().to_lower() \
			or int(lease["authority_epoch"]) != source_authority_epoch:
		return MatterUtilsScript.failure("STALE_MATTER_HANDOFF_SOURCE_LEASE")
	if source_owner_id.strip_edges().to_lower() == target_owner_id.strip_edges().to_lower() \
			or target_authority_epoch <= source_authority_epoch:
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_TARGET_LEASE")
	if _region_id_by_transfer_id.has(transfer_id):
		return MatterUtilsScript.failure("MATTER_HANDOFF_TRANSFER_ID_CONFLICT")
	_directory_revision += 1
	var preparing: Dictionary = LeaseScript.create({
		"region_transport": lease["region_transport"],
		"owner_id": lease["owner_id"],
		"authority_epoch": lease["authority_epoch"],
		"lease_revision": _directory_revision,
		"status": "PREPARING",
		"transfer_id": transfer_id,
		"target_owner_id": target_owner_id,
		"target_authority_epoch": target_authority_epoch,
	})
	_leases_by_region_id[region_id] = preparing
	_region_id_by_transfer_id[transfer_id] = region_id
	return MatterUtilsScript.success({"replay": false, "lease": preparing.duplicate(true)})


func mark_prepared(
	transfer_id: String,
	package_checksum: String,
	prepared_state_hash: String
) -> Dictionary:
	var lease: Dictionary = lease_for_transfer(transfer_id)
	if lease.is_empty() or String(lease["status"]) != "PREPARING":
		return MatterUtilsScript.failure("UNKNOWN_ACTIVE_MATTER_HANDOFF")
	if not MatterUtilsScript.is_lower_hex_64(package_checksum) \
			or not MatterUtilsScript.is_lower_hex_64(prepared_state_hash):
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_PREPARED_PROOF")
	if not String(lease["prepared_package_checksum"]).is_empty():
		if String(lease["prepared_package_checksum"]) == package_checksum \
				and String(lease["prepared_state_hash"]) == prepared_state_hash:
			return MatterUtilsScript.success({"replay": true, "lease": lease.duplicate(true)})
		return MatterUtilsScript.failure("MATTER_HANDOFF_PREPARED_PROOF_CONFLICT")
	_directory_revision += 1
	var prepared: Dictionary = LeaseScript.create({
		"region_transport": lease["region_transport"],
		"owner_id": lease["owner_id"],
		"authority_epoch": lease["authority_epoch"],
		"lease_revision": _directory_revision,
		"status": "PREPARING",
		"transfer_id": lease["transfer_id"],
		"target_owner_id": lease["target_owner_id"],
		"target_authority_epoch": lease["target_authority_epoch"],
		"prepared_package_checksum": package_checksum,
		"prepared_state_hash": prepared_state_hash,
	})
	var region: Dictionary = LeaseScript.decode_region(lease)
	_leases_by_region_id[String(region["region_id"])] = prepared
	return MatterUtilsScript.success({"replay": false, "lease": prepared.duplicate(true)})


func commit_handoff(transfer_id: String) -> Dictionary:
	var lease: Dictionary = lease_for_transfer(transfer_id)
	if lease.is_empty() or String(lease["status"]) != "PREPARING":
		return MatterUtilsScript.failure("UNKNOWN_ACTIVE_MATTER_HANDOFF")
	if String(lease["prepared_package_checksum"]).is_empty() \
			or String(lease["prepared_state_hash"]).is_empty():
		return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_NOT_PREPARED")
	var region: Dictionary = LeaseScript.decode_region(lease)
	_directory_revision += 1
	var active: Dictionary = LeaseScript.create({
		"region_transport": lease["region_transport"],
		"owner_id": lease["target_owner_id"],
		"authority_epoch": lease["target_authority_epoch"],
		"lease_revision": _directory_revision,
		"status": "ACTIVE",
	})
	_leases_by_region_id[String(region["region_id"])] = active
	_region_id_by_transfer_id.erase(transfer_id)
	return MatterUtilsScript.success({
		"lease": active.duplicate(true),
		"region": region,
		"package_checksum": lease["prepared_package_checksum"],
		"prepared_state_hash": lease["prepared_state_hash"],
		"directory_revision": _directory_revision,
	})


func abort_handoff(transfer_id: String) -> Dictionary:
	var lease: Dictionary = lease_for_transfer(transfer_id)
	if lease.is_empty():
		return MatterUtilsScript.success({"replay": true})
	var region: Dictionary = LeaseScript.decode_region(lease)
	_directory_revision += 1
	var active: Dictionary = LeaseScript.create({
		"region_transport": lease["region_transport"],
		"owner_id": lease["owner_id"],
		"authority_epoch": lease["authority_epoch"],
		"lease_revision": _directory_revision,
		"status": "ACTIVE",
	})
	_leases_by_region_id[String(region["region_id"])] = active
	_region_id_by_transfer_id.erase(transfer_id)
	return MatterUtilsScript.success({"replay": false, "lease": active.duplicate(true)})


func resolve_region(region_id: String) -> Dictionary:
	return Dictionary(_leases_by_region_id.get(region_id, {})).duplicate(true)


func resolve_brick_address(brick_address: Dictionary) -> Dictionary:
	var region_ids: Array = _leases_by_region_id.keys()
	region_ids.sort()
	for raw_region_id in region_ids:
		var lease: Dictionary = _leases_by_region_id[raw_region_id]
		var region: Dictionary = LeaseScript.decode_region(lease)
		if RegionScript.contains_brick_address(_grid_profile, region, brick_address):
			return lease.duplicate(true)
	return {}


func lease_for_transfer(transfer_id: String) -> Dictionary:
	if not _region_id_by_transfer_id.has(transfer_id):
		return {}
	return resolve_region(String(_region_id_by_transfer_id[transfer_id]))


func directory_revision() -> int:
	return _directory_revision


func content_hash() -> String:
	var region_ids: Array = _leases_by_region_id.keys()
	region_ids.sort()
	var entries: Array = []
	for region_id in region_ids:
		entries.append({
			"region_id": String(region_id),
			"lease_checksum": String(_leases_by_region_id[region_id]["checksum"]),
		})
	return MatterUtilsScript.payload_hash({
		"body_id": _body_id,
		"directory_revision": _directory_revision,
		"entries": entries,
	})
