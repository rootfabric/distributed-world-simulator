extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")

const BINDING_SCHEMA := "planet_simulator.fabric_bridge4_canonical_binding.v2"
const DEPENDENCY_CONTRACT := "FABRIC-BRIDGE4/CANONICAL-WORLD-R1"
const BOUNDARY_ROLE := "fabric_boundary"
const MASS_ABS_TOL := 1.0e-9
const MASS_REL_TOL := 1.0e-12

static func compile(snapshot: Dictionary, matter_batch: Dictionary, execution_owner: String, authority_epoch: int, applied_event_ids: Array = []) -> Dictionary:
	return compile_authoritative(snapshot, matter_batch, authority_for(snapshot, matter_batch, execution_owner, authority_epoch), applied_event_ids)

static func authority_for(snapshot: Dictionary, matter_batch: Dictionary, execution_owner: String, authority_epoch: int) -> Dictionary:
	# Convenience for a trusted caller. Never derive these values from a cache/artifact.
	return AuthorityEnvelope.create(execution_owner, [
		{"source_domain": "CONSTRUCTION", "source_id": snapshot.get("construct_id", ""), "authority_epoch": authority_epoch, "owner_id": execution_owner},
		{"source_domain": "MATTER", "source_id": matter_batch.get("batch_id", ""), "authority_epoch": authority_epoch, "owner_id": execution_owner},
	], [Utils.source_key("CONSTRUCTION", str(snapshot.get("construct_id", "")))],
		[Utils.source_key("MATTER", str(matter_batch.get("batch_id", "")))])

static func compile_authoritative(snapshot: Dictionary, matter_batch: Dictionary, authority: Dictionary, applied_event_ids: Array = []) -> Dictionary:
	var checked := Snapshot.validate(snapshot)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE4_CONSTRUCTION_SNAPSHOT_INVALID", {"cause": checked.get("error_code", "")})
	checked = MatterBatch.validate(matter_batch)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE4_MATTER_BATCH_INVALID", {"cause": checked.get("error_code", "")})
	checked = AuthorityEnvelope.validate_b0_safety(authority)
	if not checked.success:
		return Utils.failure("BRIDGE4_AUTHORITY_INVALID", {"cause": checked.get("error_code", "")})
	var construction_key := Utils.source_key("CONSTRUCTION", snapshot["construct_id"])
	var matter_key := Utils.source_key("MATTER", matter_batch["batch_id"])
	if authority.mutable_source_ids != [construction_key] or authority.readonly_source_ids != [matter_key]:
		return Utils.failure("BRIDGE4_SOURCE_AUTHORITY_COVERAGE_INVALID")
	var execution_owner: String = authority.execution_owner
	var authority_epoch := AuthorityEnvelope.authority_epoch_for(authority, "CONSTRUCTION", snapshot["construct_id"])
	var matter_epoch := AuthorityEnvelope.authority_epoch_for(authority, "MATTER", matter_batch["batch_id"])
	if not ["OPERATIONAL", "DAMAGED"].has(String(snapshot["build_state"])):
		return Utils.failure("BRIDGE4_CONSTRUCTION_NOT_EXECUTABLE")
	checked = Utils.validate_sorted_unique_strings(applied_event_ids, true)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE4_EVENT_LEDGER_INVALID")
	for event_id in applied_event_ids:
		if not Utils.is_canonical_id(event_id, 2):
			return Utils.failure("BRIDGE4_EVENT_ID_INVALID")

	var mass_total := 0.0
	var node_ids := {}
	var boundaries: Array = []
	var internals: Array = []
	for raw_part in snapshot["parts"]:
		var part: Dictionary = raw_part
		var part_id := String(part["part_id"])
		node_ids[part_id] = true
		mass_total += float(part["mass_kg"])
		if String(part["role"]) == BOUNDARY_ROLE:
			boundaries.append(part_id)
		else:
			internals.append(part_id)
	if not _near(mass_total, float(matter_batch["total_mass_kg"])):
		return Utils.failure("BRIDGE4_CONSTRUCTION_MATTER_MASS_MISMATCH", {"construct_mass_kg": mass_total, "matter_mass_kg": matter_batch["total_mass_kg"]})
	if boundaries.size() < 2:
		return Utils.failure("BRIDGE4_REDUCTION_BOUNDARY_OUT_OF_SCOPE", {"boundaries": boundaries.size(), "internals": internals.size()})

	var edges: Array = []
	for raw_bond in snapshot["bonds"]:
		var bond: Dictionary = raw_bond
		if not node_ids.has(String(bond["part_a_id"])) or not node_ids.has(String(bond["part_b_id"])):
			return Utils.failure("BRIDGE4_BOND_ENDPOINT_UNKNOWN")
		edges.append({
			"edge_id": String(bond["bond_id"]),
			"node_a": String(bond["part_a_id"]),
			"node_b": String(bond["part_b_id"]),
			"conductance": float(bond["strength_n"]),
			"active": String(bond["state"]) != "BROKEN",
		})
	var spec := Graph.create(String(snapshot["construct_id"]), int(snapshot["state_revision"]) + 1, boundaries, internals, edges, applied_event_ids)
	if spec.is_empty():
		return Utils.failure("BRIDGE4_FABRIC1_GRAPH_INVALID")

	var dependency_hash := Utils.canonical_hash({
		"bridge": DEPENDENCY_CONTRACT,
		"construction_schema": Snapshot.SCHEMA,
		"matter_schema": MatterBatch.SCHEMA,
		"fabric1_graph_schema": Graph.SCHEMA,
	})
	var construction := SourceRevision.create(
		"CONSTRUCTION", String(snapshot["construct_id"]), authority_epoch, int(snapshot["state_revision"]),
		String(snapshot["checksum"]), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", String(matter_batch["batch_id"]), matter_epoch, 0,
		String(matter_batch["checksum"]), dependency_hash
	)
	if construction.is_empty() or matter.is_empty():
		return Utils.failure("BRIDGE4_SOURCE_REVISION_INVALID")
	var frontier := Frontier.create([construction, matter])
	if frontier.is_empty():
		return Utils.failure("BRIDGE4_FRONTIER_INVALID")
	var binding := {
		"schema": BINDING_SCHEMA,
		"construct_id": snapshot["construct_id"],
		"construct_revision": snapshot["state_revision"],
		"construct_checksum": snapshot["checksum"],
		"matter_batch_id": matter_batch["batch_id"],
		"matter_checksum": matter_batch["checksum"],
		"authority_epoch": authority_epoch,
		"execution_owner": execution_owner,
		"authority_checksum": authority["checksum"],
		"frontier_hash": frontier["frontier_hash"],
		"graph_hash": spec["graph_hash"],
		"checksum": "",
	}
	binding["checksum"] = Utils.compute_checksum(binding)
	return Utils.success({
		"spec": spec,
		"binding": binding,
		"frontier": frontier,
		"authority": authority,
		"source_context": {"frontier": frontier, "authority": authority, "graph_hash": spec["graph_hash"]},
		"construct_mass_kg": mass_total,
		"matter_mass_kg": float(matter_batch["total_mass_kg"]),
	})

static func binding_matches(binding: Dictionary, snapshot: Dictionary, matter_batch: Dictionary, execution_owner: String, authority_epoch: int, applied_event_ids: Array = []) -> Dictionary:
	var current := compile(snapshot, matter_batch, execution_owner, authority_epoch, applied_event_ids)
	if not bool(current.get("success", false)):
		return current
	var actual: Dictionary = current["details"]["binding"]
	if not Utils.validate_checksum(binding).success or Utils.canonical_hash(binding) != Utils.canonical_hash(actual):
		return Utils.failure("BRIDGE4_CANONICAL_BINDING_STALE", {"expected": binding.get("checksum", ""), "actual": actual.get("checksum", "")})
	return Utils.success({"context": current["details"]})

static func validate_successor(previous: Dictionary, successor: Dictionary, matter_before: Dictionary, matter_after: Dictionary, failed_bond_id: String) -> Dictionary:
	var checked := Snapshot.validate(previous)
	if not bool(checked.get("success", false)):
		return checked
	checked = Snapshot.validate(successor)
	if not bool(checked.get("success", false)):
		return checked
	if not MatterBatch.validate(matter_before).success or not MatterBatch.validate(matter_after).success:
		return Utils.failure("BRIDGE4_MATTER_BATCH_INVALID")
	if String(previous["construct_id"]) != String(successor["construct_id"]) or int(successor["state_revision"]) != int(previous["state_revision"]) + 1:
		return Utils.failure("BRIDGE4_CONSTRUCTION_SUCCESSOR_REVISION_INVALID")
	if previous["root_item_instance_id"] != successor["root_item_instance_id"] or Utils.canonical_hash(previous["parts"]) != Utils.canonical_hash(successor["parts"]) or Utils.canonical_hash(previous["compiled_facets"]) != Utils.canonical_hash(successor["compiled_facets"]):
		return Utils.failure("BRIDGE4_CONSTRUCTION_SUCCESSOR_SHAPE_CHANGED")
	if String(matter_before.get("checksum", "")) != String(matter_after.get("checksum", "")):
		return Utils.failure("BRIDGE4_MATTER_CHANGED_DURING_CONSTRUCTION_FAILURE")
	if previous["bonds"].size() != successor["bonds"].size():
		return Utils.failure("BRIDGE4_CONSTRUCTION_BOND_SET_CHANGED")
	var actual_failed: Array = []
	for index in range(previous["bonds"].size()):
		var before: Dictionary = previous["bonds"][index]
		var after: Dictionary = successor["bonds"][index]
		for field in ["schema", "bond_id", "part_a_id", "part_b_id", "bond_kind", "strength_n", "metadata"]:
			if Utils.canonical_hash(before[field]) != Utils.canonical_hash(after[field]):
				return Utils.failure("BRIDGE4_CONSTRUCTION_BOND_METADATA_CHANGED", {"bond_id": before["bond_id"], "field": field})
		if String(before["state"]) != String(after["state"]):
			if String(before["state"]) == "BROKEN" or String(after["state"]) != "BROKEN":
				return Utils.failure("BRIDGE4_CONSTRUCTION_BOND_STATE_TRANSITION_INVALID", {"bond_id": before["bond_id"]})
			actual_failed.append(String(before["bond_id"]))
	actual_failed.sort()
	if actual_failed != [failed_bond_id]:
		return Utils.failure("BRIDGE4_CANONICAL_FAILURE_SET_MISMATCH", {"expected": [failed_bond_id], "actual": actual_failed})
	if String(successor["build_state"]) != "DAMAGED":
		return Utils.failure("BRIDGE4_DAMAGED_SUCCESSOR_STATE_REQUIRED")
	return Utils.success({"failed_bond_ids": actual_failed})

static func bond_by_id(snapshot: Dictionary, bond_id: String) -> Dictionary:
	for raw in snapshot.get("bonds", []):
		if String(raw.get("bond_id", "")) == bond_id:
			return Dictionary(raw).duplicate(true)
	return {}

static func _near(left: float, right: float) -> bool:
	if not is_finite(left) or not is_finite(right): return false
	var scale := maxf(1.0, maxf(absf(left), absf(right)))
	return absf(left - right) <= MASS_ABS_TOL + MASS_REL_TOL * scale
