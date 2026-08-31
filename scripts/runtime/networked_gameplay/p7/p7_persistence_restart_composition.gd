extends RefCounted

const RequestScript = preload(
	"res://scripts/simulation/matter/contracts/matter_mutation_request.gd"
)
const ResultScript = preload(
	"res://scripts/simulation/matter/contracts/matter_mutation_result.gd"
)
const DeliveryCoordinatorScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd"
)
const AuthoritativeItemGraphPortScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_authoritative_item_graph_output_port.gd"
)

var _configured := false
var _matter_recovery = null
var _matter_service = null
var _gameplay_recovery = null
var _gameplay_service = null


func configure(
	matter_recovery,
	matter_service,
	gameplay_recovery,
	gameplay_service
) -> Dictionary:
	if _configured:
		return _failure("P7_PERSISTENCE_RESTART_ALREADY_CONFIGURED")
	if matter_recovery == null or not matter_recovery.has_method("restore_latest"):
		return _failure("P7_MW5_RECOVERY_REQUIRED")
	if matter_service == null \
		or not matter_service.has_method("execute") \
		or not matter_service.has_method("material_receiver") \
		or not matter_service.has_method("mutation_journal"):
		return _failure("P7_MW4_MATTER_SERVICE_REQUIRED")
	var receiver = matter_service.material_receiver()
	var journal = matter_service.mutation_journal()
	if receiver == null \
		or not receiver.has_method("content_hash") \
		or not receiver.has_method("batch_count") \
		or journal == null \
		or not journal.has_method("result_for") \
		or not journal.has_method("content_hash"):
		return _failure("P7_MW5_RESTORABLE_MATTER_STATE_REQUIRED")
	if gameplay_recovery == null or not gameplay_recovery.has_method("recover_latest"):
		return _failure("P7_EXISTING_GAMEPLAY_RECOVERY_REQUIRED")
	if gameplay_service == null \
		or not gameplay_service.has_method("get_canonical_item_graph_port") \
		or not gameplay_service.has_method("get_report") \
		or not gameplay_service.has_method("preflight_canonical_server_output") \
		or not gameplay_service.has_method("apply_canonical_server_output"):
		return _failure("P7_EXISTING_V0_GAMEPLAY_SERVICE_REQUIRED")
	_matter_recovery = matter_recovery
	_matter_service = matter_service
	_gameplay_recovery = gameplay_recovery
	_gameplay_service = gameplay_service
	_configured = true
	return _success(contract_report())


func recover_replay_and_deliver(request: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("P7_PERSISTENCE_RESTART_NOT_CONFIGURED")
	if not bool(RequestScript.validate(request).get("success", false)):
		return _failure("P7_INVALID_MATTER_REQUEST")

	var matter_recovered: Dictionary = _matter_recovery.restore_latest()
	if not bool(matter_recovered.get("success", false)):
		return _failure("P7_MW5_RECOVERY_FAILED", {"cause": matter_recovered})
	var gameplay_recovered: Dictionary = _gameplay_recovery.recover_latest()
	if not bool(gameplay_recovered.get("success", false)):
		return _failure("P7_GAMEPLAY_RECOVERY_FAILED", {"cause": gameplay_recovered})

	var operation_id := String(request["operation_id"])
	var journal = _matter_service.mutation_journal()
	var persisted_result: Dictionary = journal.result_for(operation_id)
	if not bool(ResultScript.validate(persisted_result).get("success", false)) \
		or String(persisted_result.get("status", "")) != "COMMITTED":
		return _failure("P7_COMMITTED_MATTER_REPLAY_NOT_RECOVERED", {
			"operation_id": operation_id,
		})

	var receiver = _matter_service.material_receiver()
	var receiver_hash_before := String(receiver.content_hash())
	var journal_hash_before := String(journal.content_hash())
	var batch_count_before := int(receiver.batch_count())
	var replayed_result: Dictionary = _matter_service.execute(request)
	if not bool(ResultScript.validate(replayed_result).get("success", false)):
		return _failure("P7_MATTER_REPLAY_EXECUTION_FAILED")
	if replayed_result != persisted_result:
		return _failure("P7_MATTER_REPLAY_RESULT_CHANGED", {
			"operation_id": operation_id,
			"persisted_checksum": String(persisted_result.get("checksum", "")),
			"replayed_checksum": String(replayed_result.get("checksum", "")),
		})
	if String(receiver.content_hash()) != receiver_hash_before \
		or int(receiver.batch_count()) != batch_count_before \
		or String(journal.content_hash()) != journal_hash_before:
		return _failure("P7_MATTER_REPLAY_MUTATED_RECOVERED_STATE")

	var item_graph = _gameplay_service.get_canonical_item_graph_port()
	if item_graph == null or not item_graph.has_method("create_snapshot"):
		return _failure("P7_RECOVERED_CANONICAL_ITEM_GRAPH_REQUIRED")
	var item_before: Dictionary = item_graph.create_snapshot()
	var gameplay_report_before: Dictionary = _gameplay_service.get_report()
	var authoritative_item_port = AuthoritativeItemGraphPortScript.new()
	var port_setup: Dictionary = authoritative_item_port.configure(_gameplay_service)
	if not bool(port_setup.get("success", false)):
		return port_setup
	var delivery = DeliveryCoordinatorScript.new()
	var delivery_setup: Dictionary = delivery.configure(
		_matter_service, authoritative_item_port
	)
	if not bool(delivery_setup.get("success", false)):
		return delivery_setup
	var delivered: Dictionary = delivery.deliver_committed(request, replayed_result)
	if not bool(delivered.get("success", false)):
		return delivered
	var item_after: Dictionary = item_graph.create_snapshot()
	var gameplay_report_after: Dictionary = _gameplay_service.get_report()

	if String(receiver.content_hash()) != receiver_hash_before \
		or int(receiver.batch_count()) != batch_count_before \
		or String(journal.content_hash()) != journal_hash_before:
		return _failure("P7_RESTART_DELIVERY_MUTATED_MATTER_PROVENANCE")

	var matter_details: Dictionary = Dictionary(
		matter_recovered.get("details", {})
	).duplicate(true)
	var gameplay_details: Dictionary = Dictionary(
		gameplay_recovered.get("details", {})
	).duplicate(true)
	var coordinator_details: Dictionary = Dictionary(
		delivered.get("details", {})
	).duplicate(true)
	var delivery_details: Dictionary = Dictionary(
		coordinator_details.get("delivery", {})
	).duplicate(true)
	return _success({
		"matter_operation_id": operation_id,
		"matter_recovery_source": String(matter_details.get("source", "")),
		"matter_checkpoint_generation": int(
			Dictionary(matter_details.get("checkpoint", {})).get("generation", 0)
		),
		"matter_checkpoint_checksum": String(
			Dictionary(matter_details.get("checkpoint", {})).get("checksum", "")
		),
		"gameplay_recovery_source": String(gameplay_details.get("source", "")),
		"gameplay_checkpoint_generation": int(
			Dictionary(gameplay_details.get("checkpoint", {})).get("generation", 0)
		),
		"matter_replay_exact": true,
		"matter_result_checksum": String(replayed_result.get("checksum", "")),
		"matter_receiver_hash": receiver_hash_before,
		"matter_journal_hash": journal_hash_before,
		"matter_batch_count": batch_count_before,
		"item_graph_checksum_before_delivery": String(item_before.get("checksum", "")),
		"item_graph_checksum_after_delivery": String(item_after.get("checksum", "")),
		"gameplay_revision_before_delivery": int(gameplay_report_before.get("revision", -1)),
		"gameplay_revision_after_delivery": int(gameplay_report_after.get("revision", -1)),
		"gameplay_tick_before_delivery": int(gameplay_report_before.get("server_tick", -1)),
		"gameplay_tick_after_delivery": int(gameplay_report_after.get("server_tick", -1)),
		"batch_id": String(coordinator_details.get("batch_id", "")),
		"logical_player_id": String(coordinator_details.get("logical_player_id", "")),
		"delivery": delivery_details,
	})


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"matter_persistence_owner": "MW5_MATTER_STATE_COORDINATOR",
		"gameplay_persistence_owner": "M6_AUTHORITATIVE_RECOVERY_COORDINATOR",
		"matter_owner": "MW4_MATERIAL_RECEIVER_AND_JOURNAL",
		"item_owner": "CANONICAL_ITEM_GRAPH",
		"aggregate_revision_owner": "NETWORKED_GAMEPLAY_SERVICE",
		"exactly_once_owner": "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER",
		"canonical_state_owned": false,
		"private_filesystem": false,
		"private_save_format": false,
		"delivery_receipt_store": false,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
