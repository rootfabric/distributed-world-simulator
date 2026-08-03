extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")

var _lease_provider = null


func configure(lease_provider) -> Dictionary:
	if lease_provider == null or not lease_provider.has_method("lease"):
		return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_LEASE_PROVIDER_REQUIRED")
	_lease_provider = lease_provider
	return MatterUtils.success()


func authorize_plan(plan: Dictionary, server_tick: int) -> Dictionary:
	if _lease_provider == null:
		return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_GATE_NOT_CONFIGURED")
	var checked: Dictionary = Plan.validate(plan)
	if not bool(checked.get("success", false)):
		return checked
	if server_tick < int(plan["created_tick"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_TICK_BEFORE_PLAN")
	var authorized_leases: Array = []
	for raw_participant in plan["participants"]:
		var participant: Dictionary = raw_participant
		var current = _lease_provider.call("lease", String(participant["region_id"]))
		if typeof(current) != TYPE_DICTIONARY or Dictionary(current).is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_REGION_NOT_FOUND", {
				"region_id": participant["region_id"],
			})
		var lease: Dictionary = current
		checked = Lease.validate(lease)
		if not bool(checked.get("success", false)):
			return checked
		if String(lease["status"]) != Lease.STATUS_ACTIVE:
			return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_HANDOFF_IN_PROGRESS", {
				"region_id": participant["region_id"],
			})
		if server_tick >= int(lease["expires_at_tick"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_LEASE_EXPIRED", {
				"region_id": participant["region_id"],
			})
		if String(lease["body_id"]) != String(participant["body_id"]) \
			or Dictionary(lease["region_root_address"]) != Dictionary(participant["region_root_address"]) \
			or String(lease["owner_id"]) != String(participant["owner_id"]) \
			or int(lease["authority_epoch"]) != int(participant["authority_epoch"]) \
			or int(lease["lease_revision"]) != int(participant["lease_revision"]) \
			or Dictionary(lease["fencing_token"]) != Dictionary(participant["fencing_token"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_FENCE_MISMATCH", {
				"region_id": participant["region_id"],
			})
		authorized_leases.append(lease.duplicate(true))
	return MatterUtils.success({"leases": authorized_leases})
