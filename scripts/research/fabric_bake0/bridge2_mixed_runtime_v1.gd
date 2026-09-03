extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const BakeExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")

const SESSION_SCHEMA := "planet_simulator.fabric_bridge2_mixed_session.v1"
const SESSION_FIELDS: Array[String] = [
	"schema", "registry_hash", "live_master_frontier", "live_master_authority",
	"state_values", "artifact_states", "invalidations_by_region",
	"event_ledger", "time_s", "step_index", "checksum",
]
const EVENT_FIELDS: Array[String] = ["event_id", "event_hash", "region_id", "from_kind", "to_kind"]

static func start(registry: Dictionary, initial_state_values: Dictionary) -> Dictionary:
	var checked := Registry.validate(registry)
	if not bool(checked.get("success", false)):
		return checked
	var values := {}
	var states := {}
	var invalidations := {}
	for region in registry["regions"]:
		var state_id := String(region["state_id"])
		if not initial_state_values.has(state_id) or not Utils.is_finite_number(initial_state_values[state_id]):
			return Utils.failure("BRIDGE2_INITIAL_STATE_MISSING", {"state_id": state_id})
		values[state_id] = float(initial_state_values[state_id])
		states[String(region["region_id"])] = "FULL" if String(region["representation_kind"]) == "FULL" else "READY"
		invalidations[String(region["region_id"])] = []
	var session: Dictionary = {
		"schema": SESSION_SCHEMA,
		"registry_hash": String(registry["registry_hash"]),
		"live_master_frontier": registry["master_frontier"].duplicate(true),
		"live_master_authority": registry["master_authority"].duplicate(true),
		"state_values": values,
		"artifact_states": states,
		"invalidations_by_region": invalidations,
		"event_ledger": [],
		"time_s": 0.0,
		"step_index": 0,
		"checksum": "",
	}
	session["checksum"] = Utils.compute_checksum(session)
	checked = validate_session(session, registry)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"session": session})

static func validate_session(session: Dictionary, registry: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(session, SESSION_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if session.get("schema") != SESSION_SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_SESSION_SCHEMA")
	checked = Registry.validate(registry)
	if not bool(checked.get("success", false)):
		return checked
	if String(session.get("registry_hash", "")) != String(registry["registry_hash"]):
		return Utils.failure("BRIDGE2_SESSION_REGISTRY_HASH_MISMATCH")
	checked = Frontier.validate(session["live_master_frontier"])
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(session["live_master_authority"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(session.get("state_values")) != TYPE_DICTIONARY or typeof(session.get("artifact_states")) != TYPE_DICTIONARY or typeof(session.get("invalidations_by_region")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BRIDGE2_SESSION_STATE")
	for region in registry["regions"]:
		var state_id := String(region["state_id"])
		var region_id := String(region["region_id"])
		if not session["state_values"].has(state_id) or not Utils.is_finite_number(session["state_values"][state_id]):
			return Utils.failure("INVALID_BRIDGE2_STATE_VALUE", {"state_id": state_id})
		if not session["artifact_states"].has(region_id):
			return Utils.failure("BRIDGE2_ARTIFACT_STATE_MISSING", {"region_id": region_id})
		if not session["invalidations_by_region"].has(region_id) or typeof(session["invalidations_by_region"][region_id]) != TYPE_ARRAY:
			return Utils.failure("BRIDGE2_INVALIDATION_BUCKET_MISSING", {"region_id": region_id})
		for invalidation in session["invalidations_by_region"][region_id]:
			checked = BakeInvalidation.validate(invalidation)
			if not bool(checked.get("success", false)):
				return checked
	if typeof(session.get("event_ledger")) != TYPE_ARRAY:
		return Utils.failure("INVALID_BRIDGE2_EVENT_LEDGER")
	var seen := {}
	for raw in session["event_ledger"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BRIDGE2_EVENT_LEDGER_ENTRY")
		checked = Utils.validate_exact_fields(raw, EVENT_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var event_id := String(raw["event_id"])
		if event_id.is_empty() or seen.has(event_id):
			return Utils.failure("DUPLICATE_BRIDGE2_EVENT_ID")
		seen[event_id] = true
		for field in ["event_hash"]:
			if not Utils.is_lower_hex_64(raw[field]):
				return Utils.failure("INVALID_BRIDGE2_EVENT_HASH")
	if not Utils.is_non_negative_number(session.get("time_s")):
		return Utils.failure("INVALID_BRIDGE2_SESSION_TIME")
	if not Utils.is_json_integer(session.get("step_index")) or int(session["step_index"]) < 0:
		return Utils.failure("INVALID_BRIDGE2_STEP_INDEX")
	return Utils.validate_checksum(session)

static func can_execute_region(session: Dictionary, registry: Dictionary, region_id: String) -> Dictionary:
	var checked := validate_session(session, registry)
	if not bool(checked.get("success", false)):
		return checked
	var region := Registry.region_by_id(registry, region_id)
	if region.is_empty():
		return Utils.failure("BRIDGE2_REGION_NOT_FOUND")
	var adapter: Dictionary = region["adapter"]
	checked = Slice.validate_against_master(
		adapter["source_slice"],
		session["live_master_frontier"],
		session["live_master_authority"]
	)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE2_REGION_SOURCE_SLICE_STALE", {
			"region_id": region_id,
			"cause": checked.get("error_code", "SLICE_STALE"),
		})
	if String(region["representation_kind"]) == "FULL":
		return Utils.success({
			"region_id": region_id,
			"representation_kind": "FULL",
			"minimum_safe_fidelity": "FULL",
		})
	if String(session["artifact_states"][region_id]) == "STALE":
		return Utils.failure("BRIDGE2_REGION_STALE_EXECUTION_FORBIDDEN", {"region_id": region_id})
	var artifact: Dictionary = adapter["artifact"]
	var live := {
		"artifact_state": "READY",
		"canonical_source_frontier": adapter["source_slice"]["frontier"],
		"authority_envelope": adapter["source_slice"]["authority_envelope"],
		"dependency_set": artifact["source_binding"]["dependency_set"],
		"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
		"fabric_compiler_version": artifact["source_binding"]["fabric_compiler_version"],
		"boundary_contract_hash": artifact["boundary_contract"]["contract_hash"],
		"bake_policy_hash": artifact["source_binding"]["bake_policy_hash"],
		"runtime_domain": {
			"source_frontier_hash": adapter["source_slice"]["frontier"]["frontier_hash"],
			"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
			"elapsed_s": float(session["time_s"]),
			"mode": String(region["representation_kind"]),
			"quantities": {},
		},
		"runtime_error_estimator": {},
		"guard_values": {},
		"invalidations": session["invalidations_by_region"][region_id].duplicate(true),
	}
	return BakeExecutionGate.can_execute(artifact, live)

static func step(
	session: Dictionary,
	registry: Dictionary,
	external_flows: Dictionary,
	delta_s: float
) -> Dictionary:
	var checked := validate_session(session, registry)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_positive_number(delta_s):
		return Utils.failure("INVALID_BRIDGE2_STEP_DELTA")
	var gate_results := {}
	for region in registry["regions"]:
		var region_id := String(region["region_id"])
		var gate := can_execute_region(session, registry, region_id)
		if not bool(gate.get("success", false)):
			return Utils.failure("BRIDGE2_MIXED_STEP_BLOCKED", {
				"region_id": region_id,
				"cause": gate.get("error_code", "REGION_GATE_FAILED"),
			})
		gate_results[region_id] = gate["details"]
	var solved := _solve(registry, session["state_values"], external_flows, delta_s)
	if not bool(solved.get("success", false)):
		return solved
	var next := session.duplicate(true)
	next["state_values"] = solved["details"]["state_values"]
	next["time_s"] = float(next["time_s"]) + delta_s
	next["step_index"] = int(next["step_index"]) + 1
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate_session(next, registry)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"session": next,
		"gate_results": gate_results,
		"interface_flows": solved["details"]["interface_flows"],
		"energy_before": solved["details"]["energy_before"],
		"energy_after": solved["details"]["energy_after"],
		"status": "BRIDGE2_MIXED_FLOW_ACCEPTED",
	})

static func full_reference_step(
	registry: Dictionary,
	state_values: Dictionary,
	external_flows: Dictionary,
	delta_s: float
) -> Dictionary:
	var checked := Registry.validate(registry)
	if not bool(checked.get("success", false)):
		return checked
	return _solve(registry, state_values, external_flows, delta_s)

static func consume_representation_event(
	session: Dictionary,
	registry: Dictionary,
	fabric_event: Dictionary,
	region_id: String,
	replacement_adapter: Dictionary
) -> Dictionary:
	var checked := validate_session(session, registry)
	if not bool(checked.get("success", false)):
		return checked
	var event_id := String(fabric_event.get("event_id", ""))
	if event_id.is_empty():
		return Utils.failure("BRIDGE2_FABRIC_EVENT_ID_REQUIRED")
	for record in session["event_ledger"]:
		if String(record["event_id"]) == event_id:
			return Utils.failure("BRIDGE2_DUPLICATE_FABRIC_EVENT")
	var region := Registry.region_by_id(registry, region_id)
	if region.is_empty():
		return Utils.failure("BRIDGE2_EVENT_REGION_NOT_FOUND")
	checked = Adapter.validate(replacement_adapter)
	if not bool(checked.get("success", false)):
		return checked
	if String(replacement_adapter["region_id"]) != region_id or String(replacement_adapter["state_id"]) != String(region["state_id"]):
		return Utils.failure("BRIDGE2_EVENT_REPLACEMENT_BINDING_MISMATCH")
	if String(replacement_adapter["source_slice"]["frontier"]["frontier_hash"]) != String(region["adapter"]["source_slice"]["frontier"]["frontier_hash"]):
		return Utils.failure("BRIDGE2_EVENT_REPLACEMENT_SOURCE_MISMATCH")
	var replacement := {
		"region_id": region_id,
		"representation_kind": String(replacement_adapter["representation_kind"]),
		"state_id": String(region["state_id"]),
		"adapter": replacement_adapter,
	}
	var next_registry := Registry.replace_region(registry, replacement)
	if next_registry.is_empty():
		return Utils.failure("BRIDGE2_EVENT_REGISTRY_REBUILD_FAILED")
	var next := session.duplicate(true)
	next["registry_hash"] = String(next_registry["registry_hash"])
	next["artifact_states"][region_id] = "FULL" if String(replacement_adapter["representation_kind"]) == "FULL" else "READY"
	next["invalidations_by_region"][region_id] = []
	var event_hash := Utils.canonical_hash(fabric_event)
	next["event_ledger"].append({
		"event_id": event_id,
		"event_hash": event_hash,
		"region_id": region_id,
		"from_kind": String(region["representation_kind"]),
		"to_kind": String(replacement_adapter["representation_kind"]),
	})
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate_session(next, next_registry)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"session": next,
		"registry": next_registry,
		"handoff": {
			"reconstruction_required": String(region["representation_kind"]) != "FULL",
			"full_state_value": float(session["state_values"][String(region["state_id"])]),
			"projection_required": String(replacement_adapter["representation_kind"]) != "FULL",
			"state_error": 0.0,
		},
		"event_hash": event_hash,
		"status": "BRIDGE2_REPRESENTATION_EVENT_ACCEPTED",
	})

static func apply_master_update(
	session: Dictionary,
	registry: Dictionary,
	new_master_frontier: Dictionary,
	new_master_authority: Dictionary,
	created_tick: int
) -> Dictionary:
	var checked := validate_session(session, registry)
	if not bool(checked.get("success", false)):
		return checked
	checked = Frontier.validate(new_master_frontier)
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(new_master_authority)
	if not bool(checked.get("success", false)):
		return checked
	var next := session.duplicate(true)
	next["live_master_frontier"] = new_master_frontier.duplicate(true)
	next["live_master_authority"] = new_master_authority.duplicate(true)
	var affected: Array = []
	var unaffected: Array = []
	for region in registry["regions"]:
		var region_id := String(region["region_id"])
		var adapter: Dictionary = region["adapter"]
		var live_slice := Slice.refreshed(adapter["source_slice"], new_master_frontier, new_master_authority)
		if live_slice.is_empty():
			return Utils.failure("BRIDGE2_MASTER_UPDATE_SLICE_REFRESH_FAILED", {"region_id": region_id})
		if String(live_slice["frontier"]["frontier_hash"]) == String(adapter["source_slice"]["frontier"]["frontier_hash"]):
			unaffected.append(region_id)
			continue
		affected.append(region_id)
		if String(region["representation_kind"]) == "FULL":
			next["artifact_states"][region_id] = "FULL"
			continue
		var invalidation := BakeInvalidation.create(
			"invalidation/bridge2-%s-%06d" % [region_id.replace("/", "-"), created_tick],
			String(adapter["artifact"]["artifact_id"]),
			"SOURCE_REVISION",
			String(adapter["source_slice"]["frontier"]["frontier_hash"]),
			String(live_slice["frontier"]["frontier_hash"]),
			created_tick
		)
		if invalidation.is_empty():
			return Utils.failure("BRIDGE2_BAKE_INVALIDATION_CREATE_FAILED", {"region_id": region_id})
		next["invalidations_by_region"][region_id].append(invalidation)
		next["artifact_states"][region_id] = "STALE"
	next["checksum"] = Utils.compute_checksum(next)
	return Utils.success({
		"session": next,
		"affected_regions": affected,
		"unaffected_regions": unaffected,
	})

static func rebuild_region(
	session: Dictionary,
	registry: Dictionary,
	replacement_adapter: Dictionary
) -> Dictionary:
	var region_id := String(replacement_adapter.get("region_id", ""))
	var old_region := Registry.region_by_id(registry, region_id)
	if old_region.is_empty():
		return Utils.failure("BRIDGE2_REBUILD_REGION_NOT_FOUND")
	var checked := Adapter.validate(replacement_adapter)
	if not bool(checked.get("success", false)):
		return checked
	checked = Slice.validate_against_master(
		replacement_adapter["source_slice"],
		session["live_master_frontier"],
		session["live_master_authority"]
	)
	if not bool(checked.get("success", false)):
		return checked
	var replacement := {
		"region_id": region_id,
		"representation_kind": String(replacement_adapter["representation_kind"]),
		"state_id": String(replacement_adapter["state_id"]),
		"adapter": replacement_adapter,
	}
	var regions: Array = []
	for region in registry["regions"]:
		if String(region["region_id"]) == region_id:
			regions.append(replacement)
		else:
			regions.append(Dictionary(region).duplicate(true))
	var next_registry := Registry.create(
		session["live_master_frontier"],
		session["live_master_authority"],
		regions,
		registry["interfaces"]
	)
	if next_registry.is_empty():
		return Utils.failure("BRIDGE2_REBUILD_REGISTRY_FAILED")
	var next := session.duplicate(true)
	next["registry_hash"] = String(next_registry["registry_hash"])
	next["artifact_states"][region_id] = "FULL" if String(replacement_adapter["representation_kind"]) == "FULL" else "READY"
	next["invalidations_by_region"][region_id] = []
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate_session(next, next_registry)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"session": next,
		"registry": next_registry,
		"state_handoff_error": 0.0,
		"status": "BRIDGE2_REGION_REBUILT",
	})

static func _solve(
	registry: Dictionary,
	state_values: Dictionary,
	external_flows: Dictionary,
	delta_s: float
) -> Dictionary:
	if not Utils.is_positive_number(delta_s):
		return Utils.failure("INVALID_BRIDGE2_SOLVE_DELTA")
	var regions: Array = registry["regions"]
	var n := regions.size()
	var index_by_region := {}
	var matrix: Array = []
	var rhs: Array = []
	var energy_before := 0.0
	for i in range(n):
		var region: Dictionary = regions[i]
		index_by_region[String(region["region_id"])] = i
		var row: Array = []
		row.resize(n)
		row.fill(0.0)
		matrix.append(row)
		var state_id := String(region["state_id"])
		var x_old := float(state_values[state_id])
		var storage := float(region["adapter"]["storage"])
		var damping := float(region["adapter"]["damping"])
		matrix[i][i] = storage / delta_s + damping
		var input := float(external_flows.get(String(region["region_id"]), 0.0))
		rhs.append(storage / delta_s * x_old + input)
		energy_before += 0.5 * storage * x_old * x_old
	for interface in registry["interfaces"]:
		var ia := int(index_by_region[String(interface["region_a"])])
		var ib := int(index_by_region[String(interface["region_b"])])
		var g := float(interface["conductance"])
		matrix[ia][ia] = float(matrix[ia][ia]) + g
		matrix[ib][ib] = float(matrix[ib][ib]) + g
		matrix[ia][ib] = float(matrix[ia][ib]) - g
		matrix[ib][ia] = float(matrix[ib][ia]) - g
	var solved := _gaussian_solve(matrix, rhs)
	if not bool(solved.get("success", false)):
		return solved
	var values: Array = solved["details"]["values"]
	var next_state := {}
	var energy_after := 0.0
	for i in range(n):
		var region: Dictionary = regions[i]
		var state_id := String(region["state_id"])
		var value := float(values[i])
		next_state[state_id] = value
		energy_after += 0.5 * float(region["adapter"]["storage"]) * value * value
	var interface_flows: Array = []
	for interface in registry["interfaces"]:
		var ia := int(index_by_region[String(interface["region_a"])])
		var ib := int(index_by_region[String(interface["region_b"])])
		var flow := float(interface["conductance"]) * (float(values[ia]) - float(values[ib]))
		interface_flows.append({
			"interface_id": String(interface["interface_id"]),
			"region_a": String(interface["region_a"]),
			"region_b": String(interface["region_b"]),
			"flow_a_to_b": flow,
			"power_dissipation": flow * (float(values[ia]) - float(values[ib])),
		})
	return Utils.success({
		"state_values": next_state,
		"interface_flows": interface_flows,
		"energy_before": energy_before,
		"energy_after": energy_after,
	})

static func _gaussian_solve(matrix: Array, rhs: Array) -> Dictionary:
	var n := rhs.size()
	var a: Array = []
	for i in range(n):
		var row: Array = matrix[i].duplicate()
		row.append(float(rhs[i]))
		a.append(row)
	for pivot in range(n):
		var best := pivot
		var best_abs := absf(float(a[pivot][pivot]))
		for row in range(pivot + 1, n):
			var candidate := absf(float(a[row][pivot]))
			if candidate > best_abs:
				best = row
				best_abs = candidate
		if best_abs <= 1.0e-14:
			return Utils.failure("BRIDGE2_SINGULAR_MIXED_OPERATOR")
		if best != pivot:
			var tmp = a[pivot]
			a[pivot] = a[best]
			a[best] = tmp
		var diag := float(a[pivot][pivot])
		for col in range(pivot, n + 1):
			a[pivot][col] = float(a[pivot][col]) / diag
		for row in range(n):
			if row == pivot:
				continue
			var factor := float(a[row][pivot])
			if absf(factor) <= 1.0e-18:
				continue
			for col in range(pivot, n + 1):
				a[row][col] = float(a[row][col]) - factor * float(a[pivot][col])
	var values: Array = []
	for i in range(n):
		values.append(float(a[i][n]))
	return Utils.success({"values": values})
