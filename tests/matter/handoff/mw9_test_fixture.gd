extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")
const SummaryManifest = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_persistence_manifest.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const REGION_ID := "matter-region/mw9-alpha"
const BODY_ID := "body/asteroid-mw9"
const SOURCE_OWNER := "simulation-node/source-mw9"
const TARGET_OWNER := "simulation-node/target-mw9"
const CLAIM_OWNER := "simulation-node/recovery-mw9"
const CHECKPOINT_ID := "matter-handoff-checkpoint/mw9"
const GRID_PROFILE_HASH := "a9a94df8f969e8e1903a9b8de409e67b805b41b8f140d08f0bc0c1a927366f71"
const REGION_CHECKSUM := "c5b8ef751dcdcf90aac8dbca707edcfef632f30652169d89c2290b09f16ccad2"


static func root_address() -> Dictionary:
	return CellAddress.create(
		"universe", "mw9", "asteroid", "matter", 1, "asteroid-mw9", [2, 1]
	)


static func initial_lease(issued_tick: int = 10) -> Dictionary:
	return Lease.create_active(
		REGION_ID, BODY_ID, root_address(), REGION_CHECKSUM, GRID_PROFILE_HASH,
		SOURCE_OWNER, 4, 7, "transition/mw9-initial", issued_tick,
		issued_tick + 40, issued_tick + 120
	)


static func package_value(label: String = "primary") -> Dictionary:
	var value: Dictionary = {
		"schema": "planet_simulator.matter_handoff_package.v1",
		"body_id": BODY_ID,
		"region_id": REGION_ID,
		"label": label,
		"payload_hash": MatterUtils.payload_hash([REGION_ID, label]),
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value


static func package_transport(label: String = "primary") -> String:
	return MatterUtils.canonical_json(package_value(label))


static func package_checksum(label: String = "primary") -> String:
	return String(package_value(label)["checksum"])


static func target_state_hash(label: String = "primary") -> String:
	return MatterUtils.payload_hash({"target_state": label, "region_id": REGION_ID})


static func summary_manifest(authority_epoch: int = 4, summary_revision: int = 12) -> Dictionary:
	var dependency_hash: String = MatterUtils.payload_hash([REGION_ID, "dependency"])
	var descendant_hash: String = MatterUtils.payload_hash([REGION_ID, summary_revision])
	var summary: Dictionary = SummaryNode.create({
		"body_id": BODY_ID,
		"cell_address": root_address(),
		"bounds_m": [-64.0, -64.0, -64.0, 64.0, 64.0, 64.0],
		"authority_epoch": authority_epoch,
		"summary_revision": summary_revision,
		"build_generation": 3,
		"child_count": 0,
		"leaf_count": 1,
		"sample_count": 8,
		"occupied_sample_count": 4,
		"surface_sample_count": 2,
		"minimum_signed_distance_m": -2.0,
		"maximum_signed_distance_m": 3.0,
		"minimum_occupancy_ratio": 0.0,
		"maximum_occupancy_ratio": 1.0,
		"contains_matter": true,
		"contains_vacuum": true,
		"contains_surface": true,
		"material_occupancy_weights": [{
			"material_id": "matter/basalt",
			"occupancy_weight": 4.0,
		}],
		"total_occupancy_weight": 4.0,
		"minimum_descendant_revision": summary_revision,
		"maximum_descendant_revision": summary_revision,
		"dependency_hash": dependency_hash,
		"descendant_revision_hash": descendant_hash,
	})
	if summary.is_empty():
		return {}
	var source: Dictionary = SourceRevision.create(
		"MATTER", BODY_ID, authority_epoch, summary_revision,
		String(summary["checksum"]), dependency_hash
	)
	if source.is_empty():
		return {}
	return SummaryManifest.create(
		"matter-summary-manifest/mw9-alpha", BODY_ID, root_address(),
		GRID_PROFILE_HASH, source, 2, [summary]
	)
