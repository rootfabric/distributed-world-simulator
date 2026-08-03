extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const RegionScript = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")
const LeaseScript = preload("res://scripts/simulation/matter/handoff/matter_authority_lease.gd")
const PackageScript = preload("res://scripts/simulation/matter/handoff/matter_handoff_package.gd")

var _configured: bool = false
var _endpoint_id: String = ""
var _body: Dictionary = {}
var _grid_profile: Dictionary = {}
var _service = null
var _owner_id: String = ""
var _authority_epoch: int = 0
var _directory = null
var _authority = null
var _prepared_by_transfer_id: Dictionary = {}
var _relinquished_region_ids: Dictionary = {}


func configure(
	endpoint_id: String,
	body: Dictionary,
	grid_profile: Dictionary,
	service,
	owner_id: String,
	authority_epoch: int,
	directory,
	authority = null
) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("MATTER_HANDOFF_ENDPOINT_ALREADY_CONFIGURED")
	if not MatterUtilsScript.is_canonical_id(endpoint_id, 2) \
			or not MatterUtilsScript.is_canonical_id(owner_id, 2) or authority_epoch < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_ENDPOINT_IDENTITY")
	if not bool(BodyScript.validate(body).get("success", false)) \
			or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
			or String(body.get("body_id", "")) != String(grid_profile.get("body_id", "")) \
			or String(body.get("body_frame_id", "")) != String(grid_profile.get("body_frame_id", "")):
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_ENDPOINT_WORLD")
	if service == null or not service.has_method("snapshot_store") \
			or not service.has_method("material_receiver") \
			or not service.has_method("mutation_journal"):
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_ENDPOINT_SERVICE")
	if directory == null or not directory.has_method("resolve_region") \
			or not directory.has_method("lease_for_transfer"):
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_ENDPOINT_DIRECTORY")
	if authority != null and (not authority.has_method("stream_sequence") \
			or not authority.has_method("rebase_from_service_state")):
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_ENDPOINT_AUTHORITY")
	_endpoint_id = endpoint_id.strip_edges().to_lower()
	_body = body.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_service = service
	_owner_id = owner_id.strip_edges().to_lower()
	_authority_epoch = authority_epoch
	_directory = directory
	_authority = authority
	_prepared_by_transfer_id.clear()
	_relinquished_region_ids.clear()
	_configured = true
	return MatterUtilsScript.success()


func build_package(
	transfer_id: String,
	region_id: String,
	target_owner_id: String,
	target_authority_epoch: int
) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_HANDOFF_ENDPOINT_NOT_CONFIGURED")
	var lease: Dictionary = _directory.resolve_region(region_id)
	if lease.is_empty() or String(lease.get("status", "")) != "PREPARING" \
			or String(lease.get("transfer_id", "")) != transfer_id:
		return MatterUtilsScript.failure("MATTER_HANDOFF_SOURCE_LEASE_NOT_FROZEN")
	if String(lease["owner_id"]) != _owner_id \
			or int(lease["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("MATTER_HANDOFF_ENDPOINT_NOT_SOURCE_OWNER")
	if String(lease["target_owner_id"]) != target_owner_id.strip_edges().to_lower() \
			or int(lease["target_authority_epoch"]) != target_authority_epoch:
		return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_BINDING_MISMATCH")
	var region: Dictionary = LeaseScript.decode_region(lease)
	var snapshot_transports: Array = []
	var snapshot_entries: Array = []
	var store = _service.snapshot_store()
	for raw_address_id in store.address_ids():
		var snapshot: Dictionary = store.get_snapshot_by_address_id(String(raw_address_id))
		if int(snapshot.get("state_revision", 0)) < 1 \
				or not RegionScript.contains_snapshot(_grid_profile, region, snapshot):
			continue
		var encoded_snapshot: String = PersistenceCodecScript.encode_persistence_json(snapshot)
		if encoded_snapshot.is_empty():
			return MatterUtilsScript.failure("MATTER_HANDOFF_SNAPSHOT_ENCODING_FAILED")
		snapshot_transports.append(encoded_snapshot)
		snapshot_entries.append({
			"address_id": String(snapshot["address"]["address_id"]),
			"state_revision": int(snapshot["state_revision"]),
			"snapshot_checksum": String(snapshot["checksum"]),
		})
	var journal_records: Array = []
	var journal_entries: Array = []
	var required_batch_ids: Dictionary = {}
	var journal_state: Dictionary = _service.mutation_journal().export_persistence_state()
	for record_value in journal_state.get("records", []):
		var record: Dictionary = record_value
		var request: Dictionary = record["request"]
		var inside_count: int = 0
		for address_value in request["target_bricks"]:
			var address: Dictionary = address_value
			if RegionScript.contains_brick_address(_grid_profile, region, address):
				inside_count += 1
		if inside_count == 0:
			continue
		if inside_count != request["target_bricks"].size():
			return MatterUtilsScript.failure("MATTER_HANDOFF_CROSS_REGION_JOURNAL_RECORD", {
				"operation_id": record["operation_id"],
			})
		var result: Dictionary = record["result"]
		var request_transport: String = PersistenceCodecScript.encode_persistence_json(request)
		var result_transport: String = PersistenceCodecScript.encode_persistence_json(result)
		if request_transport.is_empty() or result_transport.is_empty():
			return MatterUtilsScript.failure("MATTER_HANDOFF_JOURNAL_ENCODING_FAILED")
		journal_records.append({
			"operation_id": String(record["operation_id"]),
			"request_transport": request_transport,
			"result_transport": result_transport,
		})
		journal_entries.append({
			"operation_id": String(record["operation_id"]),
			"request_checksum": String(request["checksum"]),
			"result_checksum": String(result["checksum"]),
		})
		for batch_id in result["created_aggregate_ids"]:
			required_batch_ids[String(batch_id)] = true
	var batch_transports: Array = []
	var batch_entries: Array = []
	var sorted_batch_ids: Array = required_batch_ids.keys()
	sorted_batch_ids.sort()
	for raw_batch_id in sorted_batch_ids:
		var batch_id: String = String(raw_batch_id)
		var batch: Dictionary = _service.material_receiver().get_batch(batch_id)
		if batch.is_empty():
			return MatterUtilsScript.failure("MATTER_HANDOFF_SOURCE_BATCH_MISSING", {"batch_id": batch_id})
		var batch_transport: String = PersistenceCodecScript.encode_persistence_json(batch)
		if batch_transport.is_empty():
			return MatterUtilsScript.failure("MATTER_HANDOFF_BATCH_ENCODING_FAILED")
		batch_transports.append(batch_transport)
		batch_entries.append({"batch_id": batch_id, "batch_checksum": String(batch["checksum"])})
	var regional_state_hash: String = PackageScript.compute_regional_state_hash(
		region, snapshot_entries, journal_entries, batch_entries
	)
	var source_sequence: int = int(_authority.stream_sequence()) if _authority != null \
		else int(_service.mutation_journal().size())
	var package: Dictionary = PackageScript.create({
		"transfer_id": transfer_id,
		"body_id": _body["body_id"],
		"body_definition_hash": _body["checksum"],
		"grid_profile_hash": GridProfileScript.content_hash(_grid_profile),
		"region_transport": lease["region_transport"],
		"source_owner_id": _owner_id,
		"source_authority_epoch": _authority_epoch,
		"target_owner_id": target_owner_id,
		"target_authority_epoch": target_authority_epoch,
		"directory_revision": int(lease["lease_revision"]),
		"source_stream_sequence": source_sequence,
		"snapshot_transports": snapshot_transports,
		"journal_records": journal_records,
		"batch_transports": batch_transports,
		"regional_state_hash": regional_state_hash,
	})
	var package_validation: Dictionary = PackageScript.validate_for_grid(package, _grid_profile)
	if not bool(package_validation.get("success", false)):
		return MatterUtilsScript.failure("MATTER_HANDOFF_PACKAGE_BUILD_FAILED", {"cause": package_validation})
	return MatterUtilsScript.success({"package": package})


func prepare_import(package: Dictionary) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_HANDOFF_ENDPOINT_NOT_CONFIGURED")
	var validation: Dictionary = PackageScript.validate_for_grid(package, _grid_profile)
	if not bool(validation.get("success", false)):
		return validation
	var transfer_id: String = String(package["transfer_id"])
	if String(package["body_definition_hash"]) != String(_body["checksum"]) \
			or String(package["grid_profile_hash"]) != GridProfileScript.content_hash(_grid_profile):
		return MatterUtilsScript.failure("MATTER_HANDOFF_PACKAGE_WORLD_MISMATCH")
	if String(package["target_owner_id"]) != _owner_id \
			or int(package["target_authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("MATTER_HANDOFF_PACKAGE_TARGET_MISMATCH")
	var lease: Dictionary = _directory.lease_for_transfer(transfer_id)
	if lease.is_empty() or String(lease.get("status", "")) != "PREPARING" \
			or String(lease.get("target_owner_id", "")) != _owner_id \
			or int(lease.get("target_authority_epoch", 0)) != _authority_epoch:
		return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_LEASE_NOT_PREPARING")
	if String(package["source_owner_id"]) != String(lease["owner_id"]) \
			or int(package["source_authority_epoch"]) != int(lease["authority_epoch"]) \
			or int(package["directory_revision"]) != int(lease["lease_revision"]) \
			or String(package["region_transport"]) != String(lease["region_transport"]):
		return MatterUtilsScript.failure("MATTER_HANDOFF_PACKAGE_LEASE_BINDING_MISMATCH")
	if _prepared_by_transfer_id.has(transfer_id):
		var existing: Dictionary = _prepared_by_transfer_id[transfer_id]
		if String(existing["package_checksum"]) == String(package["checksum"]):
			return MatterUtilsScript.success({
				"replay": true,
				"prepared_state_hash": existing["prepared_state_hash"],
			})
		return MatterUtilsScript.failure("MATTER_HANDOFF_PREPARE_PACKAGE_CONFLICT")
	var store = _service.snapshot_store()
	var receiver = _service.material_receiver()
	var journal = _service.mutation_journal()
	var backups: Dictionary = {
		"store_state": store.export_persistence_state(),
		"receiver_state": receiver.export_persistence_state(),
		"journal_state": journal.export_persistence_state(),
	}
	for transport_value in package["snapshot_transports"]:
		var snapshot: Dictionary = PackageScript.decode_snapshot(String(transport_value))
		var stored: Dictionary = store.put(snapshot)
		if not bool(stored.get("success", false)):
			_restore_backups(backups)
			return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_SNAPSHOT_IMPORT_FAILED", {"cause": stored})
	for transport_value in package["batch_transports"]:
		var batch: Dictionary = PackageScript.decode_batch(String(transport_value))
		var reserved: Dictionary = receiver.reserve(
			String(batch["source_operation_id"]),
			float(batch["total_mass_kg"]),
			float(batch["bulk_volume_m3"])
		)
		if not bool(reserved.get("success", false)):
			_restore_backups(backups)
			return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_BATCH_RESERVATION_FAILED", {"cause": reserved})
		var committed: Dictionary = receiver.commit_reserved(batch)
		if not bool(committed.get("success", false)):
			_restore_backups(backups)
			return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_BATCH_IMPORT_FAILED", {"cause": committed})
	for record_value in package["journal_records"]:
		var record: Dictionary = record_value
		var request: Dictionary = PackageScript.decode_request(String(record["request_transport"]))
		var result: Dictionary = PackageScript.decode_result(String(record["result_transport"]))
		var recorded: Dictionary = journal.record(request, result)
		if not bool(recorded.get("success", false)):
			_restore_backups(backups)
			return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_JOURNAL_IMPORT_FAILED", {"cause": recorded})
	var verified: Dictionary = _verify_imported_package(package)
	if not bool(verified.get("success", false)):
		_restore_backups(backups)
		return verified
	if _authority != null:
		var rebased: Dictionary = _authority.rebase_from_service_state()
		if not bool(rebased.get("success", false)):
			_restore_backups(backups)
			_authority.rebase_from_service_state()
			return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_AUTHORITY_REBASE_FAILED", {"cause": rebased})
	_prepared_by_transfer_id[transfer_id] = {
		"package_checksum": String(package["checksum"]),
		"prepared_state_hash": String(package["regional_state_hash"]),
		"backups": backups,
		"region_id": String(PackageScript.decode_region(package)["region_id"]),
	}
	return MatterUtilsScript.success({
		"replay": false,
		"prepared_state_hash": package["regional_state_hash"],
	})


func commit_import(transfer_id: String, package_checksum: String) -> Dictionary:
	if not _prepared_by_transfer_id.has(transfer_id):
		return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_NOT_PREPARED")
	var prepared: Dictionary = _prepared_by_transfer_id[transfer_id]
	if String(prepared["package_checksum"]) != package_checksum:
		return MatterUtilsScript.failure("MATTER_HANDOFF_COMMIT_PACKAGE_MISMATCH")
	_prepared_by_transfer_id.erase(transfer_id)
	return MatterUtilsScript.success({
		"region_id": prepared["region_id"],
		"prepared_state_hash": prepared["prepared_state_hash"],
	})


func abort_import(transfer_id: String) -> Dictionary:
	if not _prepared_by_transfer_id.has(transfer_id):
		return MatterUtilsScript.success({"replay": true})
	var prepared: Dictionary = _prepared_by_transfer_id[transfer_id]
	var restored: Dictionary = _restore_backups(prepared["backups"])
	if not bool(restored.get("success", false)):
		return restored
	_prepared_by_transfer_id.erase(transfer_id)
	if _authority != null:
		_authority.rebase_from_service_state()
	return MatterUtilsScript.success({"replay": false})


func mark_relinquished(region_id: String) -> Dictionary:
	if not MatterUtilsScript.is_canonical_id(region_id, 2):
		return MatterUtilsScript.failure("INVALID_RELINQUISHED_MATTER_REGION")
	_relinquished_region_ids[region_id] = true
	return MatterUtilsScript.success()


func endpoint_id() -> String:
	return _endpoint_id


func owner_id() -> String:
	return _owner_id


func authority_epoch() -> int:
	return _authority_epoch


func prepared_count() -> int:
	return _prepared_by_transfer_id.size()


func has_relinquished(region_id: String) -> bool:
	return _relinquished_region_ids.has(region_id)


func _verify_imported_package(package: Dictionary) -> Dictionary:
	for transport_value in package["snapshot_transports"]:
		var snapshot: Dictionary = PackageScript.decode_snapshot(String(transport_value))
		var stored: Dictionary = _service.snapshot_store().get_snapshot_by_address_id(
			String(snapshot["address"]["address_id"])
		)
		if String(stored.get("checksum", "")) != String(snapshot["checksum"]):
			return MatterUtilsScript.failure("MATTER_HANDOFF_IMPORTED_SNAPSHOT_MISMATCH")
	for record_value in package["journal_records"]:
		var record: Dictionary = record_value
		var result: Dictionary = PackageScript.decode_result(String(record["result_transport"]))
		var stored_result: Dictionary = _service.mutation_journal().result_for(String(record["operation_id"]))
		if String(stored_result.get("checksum", "")) != String(result["checksum"]):
			return MatterUtilsScript.failure("MATTER_HANDOFF_IMPORTED_JOURNAL_MISMATCH")
	for transport_value in package["batch_transports"]:
		var batch: Dictionary = PackageScript.decode_batch(String(transport_value))
		var stored_batch: Dictionary = _service.material_receiver().get_batch(String(batch["batch_id"]))
		if String(stored_batch.get("checksum", "")) != String(batch["checksum"]):
			return MatterUtilsScript.failure("MATTER_HANDOFF_IMPORTED_BATCH_MISMATCH")
	return MatterUtilsScript.success()


func _restore_backups(backups: Dictionary) -> Dictionary:
	var store_restored: Dictionary = _service.snapshot_store().restore_persistence_state(
		backups["store_state"]
	)
	var receiver_restored: Dictionary = _service.material_receiver().restore_persistence_state(
		backups["receiver_state"]
	)
	var journal_restored: Dictionary = _service.mutation_journal().restore_persistence_state(
		backups["journal_state"]
	)
	if not bool(store_restored.get("success", false)) \
			or not bool(receiver_restored.get("success", false)) \
			or not bool(journal_restored.get("success", false)):
		return MatterUtilsScript.failure("MATTER_HANDOFF_COMPENSATION_FAILED", {
			"store": store_restored,
			"receiver": receiver_restored,
			"journal": journal_restored,
		})
	return MatterUtilsScript.success()
