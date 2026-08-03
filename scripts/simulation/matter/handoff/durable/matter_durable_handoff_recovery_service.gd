extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Checkpoint = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_checkpoint.gd")
const Record = preload("res://scripts/simulation/matter/handoff/durable/matter_handoff_journal_record.gd")
const Projector = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_runtime_projector.gd")

var _coordinator
var _adapter
var _projector := Projector.new()


func configure(coordinator, adapter) -> Dictionary:
	if coordinator == null or not coordinator.has_method("recover_incomplete") \
		or not coordinator.has_method("checkpoint"):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECOVERY_COORDINATOR_REQUIRED")
	if adapter == null or not adapter.has_method("synchronize_lease") \
		or not adapter.has_method("commit_handoff") or not adapter.has_method("abort_handoff"):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECOVERY_ADAPTER_REQUIRED")
	_coordinator = coordinator
	_adapter = adapter
	return MatterUtils.success()


func recover_and_reconcile(recovery_id: String, server_tick: int) -> Dictionary:
	if _coordinator == null or _adapter == null:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECOVERY_SERVICE_NOT_CONFIGURED")
	var recovered: Dictionary = _coordinator.recover_incomplete(recovery_id, server_tick)
	if not bool(recovered.get("success", false)):
		return recovered
	var reconciled: Dictionary = reconcile_runtime()
	if not bool(reconciled.get("success", false)):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RUNTIME_RECONCILIATION_PENDING", {
			"cause": reconciled,
			"durable_recovery": recovered.get("details", {}),
		})
	return MatterUtils.success({
		"durable_recovery": recovered["details"],
		"runtime_reconciliation": reconciled["details"],
	})


func reconcile_runtime() -> Dictionary:
	if _coordinator == null or _adapter == null:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECOVERY_SERVICE_NOT_CONFIGURED")
	var checkpoint: Dictionary = _coordinator.checkpoint()
	var checked: Dictionary = Checkpoint.validate(checkpoint)
	if not bool(checked.get("success", false)):
		return checked
	var latest: Dictionary = {}
	for raw_record in checkpoint["handoff_records"]:
		var record: Dictionary = raw_record
		latest[String(record["transfer_id"])] = record
	var transfer_ids: Array = latest.keys()
	transfer_ids.sort()
	var terminal_count := 0
	for transfer_id in transfer_ids:
		var record: Dictionary = latest[transfer_id]
		if not String(record["phase"]) in [Record.PHASE_COMMITTED, Record.PHASE_ABORTED]:
			continue
		var projected: Dictionary = _projector.project(_adapter, record)
		if not bool(projected.get("success", false)):
			return projected
		terminal_count += 1
	var lease_count := 0
	for raw_lease in checkpoint["leases"]:
		var synchronized = _adapter.synchronize_lease(Dictionary(raw_lease).duplicate(true))
		if typeof(synchronized) != TYPE_DICTIONARY or not bool(synchronized.get("success", false)):
			return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LEASE_RECONCILIATION_FAILED", {
				"region_id": String(raw_lease.get("region_id", "")),
			})
		lease_count += 1
	return MatterUtils.success({
		"lease_count": lease_count,
		"terminal_transfer_count": terminal_count,
		"checkpoint_generation": int(checkpoint["generation"]),
	})
