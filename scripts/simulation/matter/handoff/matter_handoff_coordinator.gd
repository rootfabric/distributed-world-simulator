extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const PackageScript = preload("res://scripts/simulation/matter/handoff/matter_handoff_package.gd")
const TicketScript = preload("res://scripts/simulation/matter/handoff/matter_client_handoff_ticket.gd")

var _configured: bool = false
var _directory = null


func configure(directory) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("MATTER_HANDOFF_COORDINATOR_ALREADY_CONFIGURED")
	if directory == null or not directory.has_method("begin_handoff") \
			or not directory.has_method("mark_prepared") \
			or not directory.has_method("commit_handoff") \
			or not directory.has_method("abort_handoff"):
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_COORDINATOR_DIRECTORY")
	_directory = directory
	_configured = true
	return MatterUtilsScript.success()


func execute_handoff(
	transfer_id: String,
	region_id: String,
	source_endpoint,
	target_endpoint,
	target_authority_epoch: int,
	client_ids: Array = []
) -> Dictionary:
	if not _configured or source_endpoint == null or target_endpoint == null:
		return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_EXECUTION")
	var normalized_client_ids: Array = MatterUtilsScript.sorted_unique_ids(client_ids)
	for raw_client_id in normalized_client_ids:
		if not MatterUtilsScript.is_canonical_id(String(raw_client_id), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_CLIENT_ID")
	var source_owner_id: String = String(source_endpoint.owner_id())
	var source_epoch: int = int(source_endpoint.authority_epoch())
	var target_owner_id: String = String(target_endpoint.owner_id())
	if target_authority_epoch != int(target_endpoint.authority_epoch()):
		return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_ENDPOINT_EPOCH_MISMATCH")
	var begun: Dictionary = _directory.begin_handoff(
		transfer_id,
		region_id,
		source_owner_id,
		source_epoch,
		target_owner_id,
		target_authority_epoch
	)
	if not bool(begun.get("success", false)):
		return begun
	var package_result: Dictionary = source_endpoint.build_package(
		transfer_id, region_id, target_owner_id, target_authority_epoch
	)
	if not bool(package_result.get("success", false)):
		_directory.abort_handoff(transfer_id)
		return MatterUtilsScript.failure("MATTER_HANDOFF_PACKAGE_PREPARATION_FAILED", {
			"cause": package_result,
		})
	var package: Dictionary = package_result["details"]["package"]
	var target_prepared: Dictionary = target_endpoint.prepare_import(package)
	if not bool(target_prepared.get("success", false)):
		target_endpoint.abort_import(transfer_id)
		_directory.abort_handoff(transfer_id)
		return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_PREPARE_FAILED", {
			"cause": target_prepared,
		})
	var marked: Dictionary = _directory.mark_prepared(
		transfer_id,
		String(package["checksum"]),
		String(target_prepared["details"]["prepared_state_hash"])
	)
	if not bool(marked.get("success", false)):
		target_endpoint.abort_import(transfer_id)
		_directory.abort_handoff(transfer_id)
		return MatterUtilsScript.failure("MATTER_HANDOFF_DIRECTORY_PREPARE_FAILED", {"cause": marked})
	var committed: Dictionary = _directory.commit_handoff(transfer_id)
	if not bool(committed.get("success", false)):
		target_endpoint.abort_import(transfer_id)
		_directory.abort_handoff(transfer_id)
		return MatterUtilsScript.failure("MATTER_HANDOFF_DIRECTORY_COMMIT_FAILED", {"cause": committed})
	var imported: Dictionary = target_endpoint.commit_import(transfer_id, String(package["checksum"]))
	if not bool(imported.get("success", false)):
		return MatterUtilsScript.failure("MATTER_HANDOFF_TARGET_FINALIZE_FAILED", {"cause": imported})
	var relinquished: Dictionary = source_endpoint.mark_relinquished(region_id)
	if not bool(relinquished.get("success", false)):
		return MatterUtilsScript.failure("MATTER_HANDOFF_SOURCE_RELINQUISH_FAILED", {"cause": relinquished})
	var tickets: Array = []
	var region_transport: String = String(package["region_transport"])
	for raw_client_id in normalized_client_ids:
		var client_id: String = String(raw_client_id)
		var ticket: Dictionary = TicketScript.create({
			"ticket_id": "ticket/%s/%s" % [transfer_id.sha256_text(), client_id.sha256_text()],
			"transfer_id": transfer_id,
			"client_id": client_id,
			"body_id": package["body_id"],
			"region_transport": region_transport,
			"source_owner_id": source_owner_id,
			"source_authority_epoch": source_epoch,
			"target_owner_id": target_owner_id,
			"target_authority_epoch": target_authority_epoch,
			"target_endpoint_id": target_endpoint.endpoint_id(),
			"directory_revision": committed["details"]["directory_revision"],
			"package_checksum": package["checksum"],
		})
		if not bool(TicketScript.validate(ticket).get("success", false)):
			return MatterUtilsScript.failure("MATTER_HANDOFF_CLIENT_TICKET_BUILD_FAILED")
		tickets.append(ticket)
	return MatterUtilsScript.success({
		"package": package,
		"lease": committed["details"]["lease"],
		"tickets": tickets,
		"package_transport": PersistenceCodecScript.encode_persistence_json(package),
	})
