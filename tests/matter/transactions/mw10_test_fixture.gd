extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Participant = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_participant.gd")
const MassLedger = preload("res://scripts/simulation/matter/transactions/distributed/matter_distributed_mass_ledger.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")

const BODY_ID := "body/asteroid-mw10"
const CHECKPOINT_ID := "matter-cross-region-checkpoint/mw10"
const OWNER_A := "simulation-node/mw10-a"
const OWNER_B := "simulation-node/mw10-b"
const OWNER_C := "simulation-node/mw10-c"
const REGION_A := "matter-region/mw10-a"
const REGION_B := "matter-region/mw10-b"
const REGION_C := "matter-region/mw10-c"


class LeaseProvider extends RefCounted:
	var leases_by_region: Dictionary = {}

	func _init(leases: Array) -> void:
		for raw_lease in leases:
			var lease_value: Dictionary = raw_lease
			leases_by_region[String(lease_value["region_id"])] = lease_value.duplicate(true)

	func lease(region_id: String) -> Dictionary:
		return Dictionary(leases_by_region.get(region_id.strip_edges().to_lower(), {})).duplicate(true)


static func root_address(index: int) -> Dictionary:
	return CellAddress.create("universe", "mw10", "asteroid", "matter", 1, "asteroid-mw10", [index])


static func lease(region_id: String, owner_id: String, index: int, authority_epoch: int) -> Dictionary:
	return Lease.create_active(
		region_id, BODY_ID, root_address(index),
		MatterUtils.payload_hash([region_id, "region-state"]),
		MatterUtils.payload_hash([BODY_ID, "grid-profile"]),
		owner_id, authority_epoch, 5,
		"transition/mw10-initial-%d" % index, 10, 100, 1000
	)


static func leases() -> Array:
	return [
		lease(REGION_A, OWNER_A, 0, 3),
		lease(REGION_B, OWNER_B, 1, 4),
		lease(REGION_C, OWNER_C, 2, 5),
	]


static func lease_provider() -> LeaseProvider:
	return LeaseProvider.new(leases())


static func participant(region_id: String, owner_id: String, index: int, authority_epoch: int, source_revision: int = 20) -> Dictionary:
	var current_lease: Dictionary = lease(region_id, owner_id, index, authority_epoch)
	var source: Dictionary = SourceRevision.create(
		"MATTER", "matter-source/%s" % region_id.get_file(), authority_epoch, source_revision,
		MatterUtils.payload_hash([region_id, "source", source_revision]),
		MatterUtils.payload_hash([region_id, "dependency", source_revision])
	)
	return Participant.create({
		"region_id": region_id,
		"body_id": BODY_ID,
		"region_root_address": root_address(index),
		"owner_id": owner_id,
		"authority_epoch": authority_epoch,
		"lease_revision": int(current_lease["lease_revision"]),
		"fencing_token": current_lease["fencing_token"],
		"previous_source_revision": source,
		"mutation_payload": {
			"shape": "swept-sphere",
			"segment_id": "mutation-segment/%s" % region_id.get_file(),
			"sample_radius_m": 1.25,
		},
		"dirty_bounds_m": [float(index * 10), -2.0, -2.0, float(index * 10 + 8), 2.0, 2.0],
		"affected_scope_ids": [
			"matter-scope/%s" % region_id.get_file(),
			"matter-scope/%s-root" % region_id.get_file(),
		],
	})


static func plan_ab(
	transaction_id: String = "matter-transaction/mw10-ab",
	operation_id: String = "matter-operation/mw10-ab",
	created_tick: int = 30
) -> Dictionary:
	var a: Dictionary = participant(REGION_A, OWNER_A, 0, 3)
	var b: Dictionary = participant(REGION_B, OWNER_B, 1, 4)
	var ledger: Dictionary = MassLedger.create(transaction_id, [
		{"region_id": REGION_B, "removed": [{"material_id": "matter/basalt", "mass_kg": 3.0}], "added": []},
		{"region_id": REGION_A, "removed": [{"material_id": "matter/basalt", "mass_kg": 7.0}], "added": []},
	], [], [{"material_id": "matter/basalt", "mass_kg": 10.0}])
	return Plan.create({
		"transaction_id": transaction_id,
		"operation_id": operation_id,
		"body_id": BODY_ID,
		"created_tick": created_tick,
		"participants": [b, a],
		"mass_ledger": ledger,
	})


static func plan_bc(
	transaction_id: String = "matter-transaction/mw10-bc",
	operation_id: String = "matter-operation/mw10-bc",
	created_tick: int = 31
) -> Dictionary:
	var b: Dictionary = participant(REGION_B, OWNER_B, 1, 4)
	var c: Dictionary = participant(REGION_C, OWNER_C, 2, 5)
	var ledger: Dictionary = MassLedger.create(transaction_id, [
		{"region_id": REGION_C, "removed": [{"material_id": "matter/basalt", "mass_kg": 6.0}], "added": []},
		{"region_id": REGION_B, "removed": [{"material_id": "matter/basalt", "mass_kg": 4.0}], "added": []},
	], [], [{"material_id": "matter/basalt", "mass_kg": 10.0}])
	return Plan.create({
		"transaction_id": transaction_id,
		"operation_id": operation_id,
		"body_id": BODY_ID,
		"created_tick": created_tick,
		"participants": [c, b],
		"mass_ledger": ledger,
	})
