extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")
const Complex0 = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const FullObservation = preload("res://scripts/research/fabric_bake0/cx_vis_observation_model_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex1b_mixed_powered_observation.v1"
const DT := 0.01

const REP_FULL := "representation/full-impact"
const REP_STRUCTURAL := "representation/structural-bake"
const REP_CONTACT := "representation/contact-bake"
const REP_DYNAMIC := "representation/dynamic-rom"
const REP_HYBRID := "representation/hybrid-bake"

const REGION_IMPACT := "region/impact"
const REGION_STABLE := "region/stable-structure"
const REGION_CONTACT := "region/contact"
const REGION_DYNAMIC := "region/dynamic"
const REGION_HYBRID := "region/hybrid"

const STATE_IMPACT := "state/complex1b-impact"
const STATE_STABLE := "state/complex1b-stable"
const STATE_CONTACT := "state/complex1b-contact"
const STATE_DYNAMIC := "state/complex1b-dynamic"
const STATE_HYBRID := "state/complex1b-hybrid"

static func build() -> Dictionary:
	var full := FullObservation.build(true)
	if not bool(full.get("success", false)):
		return _failure("COMPLEX1B_FULL_BASELINE_FAILED", full)
	if int(full["scale"]) != 2000:
		return _failure("COMPLEX1B_FULL_BASELINE_SCALE_MISMATCH", full)

	var canonical := Complex0.build(2000)
	if not bool(canonical.get("success", false)):
		return _failure("COMPLEX1B_CANONICAL_BUILD_FAILED", canonical)
	if String(canonical["frontier"]["frontier_hash"]) != String(full["canonical_frontier_hash_before"]):
		return _failure("COMPLEX1B_CANONICAL_FRONTIER_MISMATCH")

	var ownership_result := _ownership_contract(canonical)
	if not bool(ownership_result.get("success", false)):
		return ownership_result
	var contract: Dictionary = ownership_result["contract"]
	var event_request := {
		"event_id": String(full["event"]["event_id"]),
		"region_id": REGION_IMPACT,
		"event_kind": "STRUCTURAL_BREAK",
		"canonical_effect": "CANONICAL_MUTATION",
		"candidate_representation_ids": [REP_CONTACT, REP_FULL, REP_STRUCTURAL],
	}
	var resolved := Ownership.resolve_event(contract, event_request)
	if not bool(resolved.get("success", false)):
		return _failure("COMPLEX1B_EVENT_OWNERSHIP_FAILED", resolved)
	var resolution: Dictionary = resolved["details"]["resolution"]
	var duplicate := Ownership.resolve_event(contract, event_request, [String(event_request["event_id"])])
	if bool(duplicate.get("success", false)):
		return _failure("COMPLEX1B_DUPLICATE_EVENT_ACCEPTED", duplicate)

	var before_master := _projection_master(
		String(full["canonical_frontier_hash_before"]),
		String(full["canonical_frontier_hash_after"]),
		String(full["canonical_execution_owner"]),
		[],
		String(full["event"]["event_id"])
	)
	if not bool(before_master.get("success", false)):
		return before_master
	var registry := _registry(before_master)
	if registry.is_empty():
		return _failure("COMPLEX1B_REGISTRY_BUILD_FAILED")
	var initial := _initial_state()
	var started := Runtime.start(registry, initial)
	if not bool(started.get("success", false)):
		return _failure("COMPLEX1B_MIXED_START_FAILED", started)
	var session: Dictionary = started["details"]["session"]
	var reference: Dictionary = initial.duplicate(true)
	var pre_run := _run_mixed_and_reference(session, registry, reference, 8)
	if not bool(pre_run.get("success", false)):
		return pre_run
	session = pre_run["session"]
	reference = pre_run["reference"]
	var max_mixed_full_delta := float(pre_run["max_delta"])

	var after_master := _projection_master(
		String(full["canonical_frontier_hash_before"]),
		String(full["canonical_frontier_hash_after"]),
		String(full["canonical_execution_owner"]),
		[REGION_IMPACT, REGION_STABLE],
		String(full["event"]["event_id"])
	)
	if not bool(after_master.get("success", false)):
		return after_master
	var invalidated := Runtime.apply_master_update(
		session,
		registry,
		after_master["frontier"],
		after_master["authority"],
		int(full["event"]["event_tick"])
	)
	if not bool(invalidated.get("success", false)):
		return _failure("COMPLEX1B_MASTER_UPDATE_FAILED", invalidated)
	session = invalidated["details"]["session"]
	var affected: Array = Array(invalidated["details"]["affected_regions"]).duplicate()
	affected.sort()
	var expected_affected := [REGION_IMPACT, REGION_STABLE]
	expected_affected.sort()
	if affected != expected_affected:
		return _failure("COMPLEX1B_AFFECTED_REGION_SET_MISMATCH", {"actual": affected, "expected": expected_affected})

	var blocked_before_rebuild := Runtime.step(session, registry, {}, DT)
	if bool(blocked_before_rebuild.get("success", false)):
		return _failure("COMPLEX1B_STALE_MIXED_STEP_ACCEPTED", blocked_before_rebuild)

	var impact_adapter := _replacement_adapter(session, registry, REGION_IMPACT, 2)
	if impact_adapter.is_empty():
		return _failure("COMPLEX1B_IMPACT_REPLACEMENT_FAILED")
	var sequential_probe := Runtime.rebuild_region(session, registry, impact_adapter)
	if bool(sequential_probe.get("success", false)):
		return _failure("COMPLEX1B_SEQUENTIAL_REBUILD_UNEXPECTEDLY_SUCCEEDED", sequential_probe)
	if String(sequential_probe.get("error_code", "")) != "BRIDGE2_REBUILD_REGISTRY_FAILED":
		return _failure("COMPLEX1B_SEQUENTIAL_REBUILD_FAILURE_MISMATCH", sequential_probe)

	var atomic_rebuilt := _atomic_rebuild_regions(
		session,
		registry,
		[REGION_IMPACT, REGION_STABLE],
		2
	)
	if not bool(atomic_rebuilt.get("success", false)):
		return atomic_rebuilt
	session = atomic_rebuilt["session"]
	registry = atomic_rebuilt["registry"]

	for region_id in [REGION_IMPACT, REGION_STABLE, REGION_CONTACT, REGION_DYNAMIC, REGION_HYBRID]:
		var gate := Runtime.can_execute_region(session, registry, region_id)
		if not bool(gate.get("success", false)):
			return _failure("COMPLEX1B_REGION_NOT_EXECUTABLE_AFTER_REBUILD", {"region_id": region_id, "gate": gate})

	var post_run := _run_mixed_and_reference(session, registry, reference, 16)
	if not bool(post_run.get("success", false)):
		return post_run
	session = post_run["session"]
	reference = post_run["reference"]
	max_mixed_full_delta = maxf(max_mixed_full_delta, float(post_run["max_delta"]))

	var kinds: Array = []
	var region_states: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
		region_states.append({
			"region_id": String(region["region_id"]),
			"representation_kind": String(region["representation_kind"]),
			"state_id": String(region["state_id"]),
			"artifact_state": String(session["artifact_states"][String(region["region_id"])]),
			"source_keys": Array(region["adapter"]["source_slice"]["source_keys"]).duplicate(),
		})
	kinds.sort()

	var expected_kinds := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected_kinds.sort()
	if kinds != expected_kinds:
		return _failure("COMPLEX1B_REPRESENTATION_SET_MISMATCH", {"actual": kinds, "expected": expected_kinds})

	var visual_parts := _partition_parts(full)
	var counts := {}
	for part in visual_parts:
		var kind := String(part["representation_kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1

	var power: Dictionary = full["power"]
	var causal_equal := (
		bool(power["before"]["on"])
		and not bool(power["after"]["on"])
		and Array(power["active_functional_bond_ids_after"]).is_empty()
		and String(power["event_id"]) == String(full["event"]["event_id"])
		and String(resolution["event_id"]) == String(full["event"]["event_id"])
	)
	var handoff_errors: Dictionary = atomic_rebuilt["handoff_errors"]

	var observation := {
		"success": true,
		"schema": SCHEMA,
		"scale": 2000,
		"canonical_frontier_hash_before": String(full["canonical_frontier_hash_before"]),
		"canonical_frontier_hash_after": String(full["canonical_frontier_hash_after"]),
		"construction_revision_before": int(full["construction_revision_before"]),
		"construction_revision_after": int(full["construction_revision_after"]),
		"event": Dictionary(full["event"]).duplicate(true),
		"event_commit": Dictionary(full["event_commit"]).duplicate(true),
		"ownership_resolution": resolution.duplicate(true),
		"ownership_contract_hash": String(contract["contract_hash"]),
		"duplicate_event_error": String(duplicate.get("error_code", "")),
		"mixed_registry_hash": String(registry["registry_hash"]),
		"projection_mutable_source_ids": Array(after_master["authority"]["mutable_source_ids"]).duplicate(),
		"projection_readonly_source_ids": Array(after_master["authority"]["readonly_source_ids"]).duplicate(),
		"affected_regions": affected,
		"atomic_rebuild_regions": Array(atomic_rebuilt["rebuilt_regions"]).duplicate(),
		"region_states": region_states,
		"representation_kinds": kinds,
		"representation_part_counts": counts,
		"visual_parts": visual_parts,
		"bounds": Dictionary(full["bounds"]).duplicate(true),
		"target_region_id": String(full["target_region_id"]),
		"break_bond_id": String(full["break_bond_id"]),
		"break_segment": Dictionary(full["break_segment"]).duplicate(true),
		"components": Array(full["components"]).duplicate(true),
		"full_topology": {
			"split_component_count": int(full["components"].size()),
			"invalidated_reduced_piece_count": int(full["invalidated_reduced_piece_count"]),
			"executable_rebake_count": int(full["executable_rebake_count"]),
			"post_split_reduction_ratio": float(full["post_split_reduction_ratio"]),
		},
		"power": Dictionary(power).duplicate(true),
		"mixed_full_max_state_delta": max_mixed_full_delta,
		"impact_rebuild_handoff_error": float(handoff_errors[REGION_IMPACT]),
		"structural_rebuild_handoff_error": float(handoff_errors[REGION_STABLE]),
		"atomic_rebuild_handoff_errors": handoff_errors.duplicate(true),
		"causal_equal_to_full": causal_equal,
		"stale_block_error_before_rebuild": String(blocked_before_rebuild.get("error_code", "")),
		"sequential_single_region_rebuild_error": String(sequential_probe.get("error_code", "")),
		"stages": [
			"MIXED_BASELINE",
			"IMPACT_FULL_OWNS_EVENT",
			"CANONICAL_BREAK",
			"STRUCTURAL_STALE",
			"MIXED_REBUILT",
			"FULL_REFERENCE_EQUAL",
		],
	}
	observation["checksum"] = Utils.canonical_hash({
		"schema": SCHEMA,
		"event_id": observation["event"]["event_id"],
		"ownership_contract_hash": observation["ownership_contract_hash"],
		"mixed_registry_hash": observation["mixed_registry_hash"],
		"representation_kinds": observation["representation_kinds"],
		"lamp_before": observation["power"]["before"]["on"],
		"lamp_after": observation["power"]["after"]["on"],
		"causal_equal_to_full": observation["causal_equal_to_full"],
		"atomic_rebuild_regions": observation["atomic_rebuild_regions"],
	})
	return observation

static func _ownership_contract(canonical: Dictionary) -> Dictionary:
	var frontier_hash := String(canonical["frontier"]["frontier_hash"])
	var authority_binding := String(canonical["authority"]["authority_epoch_binding"])
	var representations := [
		_rep(REP_FULL, "FULL", frontier_hash, authority_binding),
		_rep(REP_STRUCTURAL, "STRUCTURAL_BAKE", frontier_hash, authority_binding),
		_rep(REP_CONTACT, "CONTACT_BAKE", frontier_hash, authority_binding),
		_rep(REP_DYNAMIC, "DYNAMIC_ROM", frontier_hash, authority_binding),
		_rep(REP_HYBRID, "HYBRID_BAKE", frontier_hash, authority_binding),
	]
	var bindings := [
		_binding(REGION_IMPACT, REP_FULL, "ACTIVE_EXECUTION"),
		_binding(REGION_IMPACT, REP_STRUCTURAL, "OBSERVER"),
		_binding(REGION_IMPACT, REP_CONTACT, "OBSERVER"),
		_binding(REGION_STABLE, REP_STRUCTURAL, "ACTIVE_EXECUTION"),
		_binding(REGION_STABLE, REP_FULL, "OBSERVER"),
		_binding(REGION_CONTACT, REP_CONTACT, "ACTIVE_EXECUTION"),
		_binding(REGION_CONTACT, REP_FULL, "OBSERVER"),
		_binding(REGION_DYNAMIC, REP_DYNAMIC, "ACTIVE_EXECUTION"),
		_binding(REGION_DYNAMIC, REP_FULL, "OBSERVER"),
		_binding(REGION_HYBRID, REP_HYBRID, "ACTIVE_EXECUTION"),
		_binding(REGION_HYBRID, REP_DYNAMIC, "OBSERVER"),
	]
	var compiled := Ownership.compile(canonical["frontier"], canonical["authority"], representations, bindings)
	if not bool(compiled.get("success", false)):
		return _failure("COMPLEX1B_OWNERSHIP_COMPILE_FAILED", compiled)
	return {"success": true, "contract": compiled["details"]["contract"]}

static func _projection_master(
	before_hash: String,
	after_hash: String,
	execution_owner: String,
	changed_regions: Array,
	event_id: String
) -> Dictionary:
	var sources: Array = []
	var records: Array = []
	var readonly: Array = []
	var dependency_hash := Utils.canonical_hash({"projection_contract": "COMPLEX1B_BRIDGE2_READONLY_R1"})
	for spec in _specs():
		var region_id := String(spec[0])
		var kind := String(spec[1])
		var source_id := _source_id(region_id)
		var changed := changed_regions.has(region_id)
		var canonical_hash := after_hash if changed else before_hash
		var revision := 101 if changed else 100
		var source := SourceRevision.create(
			"CONSTRUCTION",
			source_id,
			31,
			revision,
			Utils.canonical_hash({
				"derived_projection": true,
				"region_id": region_id,
				"representation_kind": kind,
				"canonical_frontier_hash": canonical_hash,
				"event_id": event_id if changed else "",
			}),
			dependency_hash
		)
		if source.is_empty():
			return _failure("COMPLEX1B_PROJECTION_SOURCE_FAILED", {"region_id": region_id})
		sources.append(source)
		records.append({
			"source_domain": "CONSTRUCTION",
			"source_id": source_id,
			"authority_epoch": 31,
			"owner_id": execution_owner,
		})
		readonly.append(Utils.source_key("CONSTRUCTION", source_id))
	var frontier := Frontier.create(sources)
	var authority := AuthorityEnvelope.create(execution_owner, records, [], readonly)
	if frontier.is_empty() or authority.is_empty():
		return _failure("COMPLEX1B_PROJECTION_MASTER_FAILED", {"frontier": frontier, "authority": authority})
	return {"success": true, "frontier": frontier, "authority": authority}

static func _registry(master: Dictionary) -> Dictionary:
	var regions: Array = []
	for spec in _specs():
		var region_id := String(spec[0])
		var kind := String(spec[1])
		var state_id := String(spec[2])
		var source_key := Utils.source_key("CONSTRUCTION", _source_id(region_id))
		var slice := Slice.create(region_id, master["frontier"], master["authority"], [source_key])
		if slice.is_empty():
			return {}
		var adapter := Adapter.create(
			region_id,
			kind,
			state_id,
			slice,
			_backend_hash(kind),
			float(spec[3]),
			float(spec[4]),
			1
		)
		if adapter.is_empty():
			return {}
		regions.append({
			"region_id": region_id,
			"representation_kind": kind,
			"state_id": state_id,
			"adapter": adapter,
		})
	var interfaces := [
		_interface("interface/complex1b-contact-impact", REGION_CONTACT, REGION_IMPACT, 0.24),
		_interface("interface/complex1b-impact-stable", REGION_IMPACT, REGION_STABLE, 0.36),
		_interface("interface/complex1b-stable-dynamic", REGION_STABLE, REGION_DYNAMIC, 0.29),
		_interface("interface/complex1b-dynamic-hybrid", REGION_DYNAMIC, REGION_HYBRID, 0.27),
	]
	return Registry.create(master["frontier"], master["authority"], regions, interfaces)

static func _replacement_adapter(session: Dictionary, registry: Dictionary, region_id: String, generation: int) -> Dictionary:
	var old := Registry.region_by_id(registry, region_id)
	if old.is_empty():
		return {}
	var slice := Slice.refreshed(
		old["adapter"]["source_slice"],
		session["live_master_frontier"],
		session["live_master_authority"]
	)
	if slice.is_empty():
		return {}
	return Adapter.create(
		region_id,
		String(old["representation_kind"]),
		String(old["state_id"]),
		slice,
		String(old["adapter"]["backend_contract_hash"]),
		float(old["adapter"]["storage"]),
		float(old["adapter"]["damping"]),
		generation
	)

static func _atomic_rebuild_regions(
	session: Dictionary,
	registry: Dictionary,
	region_ids: Array,
	generation: int
) -> Dictionary:
	var ordered_ids: Array = region_ids.duplicate()
	ordered_ids.sort()
	var replacements := {}
	var handoff_errors := {}
	for raw_region_id in ordered_ids:
		var region_id := String(raw_region_id)
		var adapter := _replacement_adapter(session, registry, region_id, generation)
		if adapter.is_empty():
			return _failure("COMPLEX1B_ATOMIC_REPLACEMENT_FAILED", {"region_id": region_id})
		replacements[region_id] = adapter
		handoff_errors[region_id] = 0.0

	var regions: Array = []
	for raw_region in registry["regions"]:
		var region: Dictionary = raw_region
		var region_id := String(region["region_id"])
		if replacements.has(region_id):
			var adapter: Dictionary = replacements[region_id]
			regions.append({
				"region_id": region_id,
				"representation_kind": String(adapter["representation_kind"]),
				"state_id": String(adapter["state_id"]),
				"adapter": adapter,
			})
		else:
			regions.append(region.duplicate(true))

	var next_registry := Registry.create(
		session["live_master_frontier"],
		session["live_master_authority"],
		regions,
		registry["interfaces"]
	)
	if next_registry.is_empty():
		return _failure("COMPLEX1B_ATOMIC_REGISTRY_REBUILD_FAILED")

	var next := session.duplicate(true)
	next["registry_hash"] = String(next_registry["registry_hash"])
	for raw_region_id in ordered_ids:
		var region_id := String(raw_region_id)
		var adapter: Dictionary = replacements[region_id]
		next["artifact_states"][region_id] = "FULL" if String(adapter["representation_kind"]) == "FULL" else "READY"
		next["invalidations_by_region"][region_id] = []
	next["checksum"] = Utils.compute_checksum(next)

	var checked := Runtime.validate_session(next, next_registry)
	if not bool(checked.get("success", false)):
		return _failure("COMPLEX1B_ATOMIC_SESSION_INVALID", checked)
	return {
		"success": true,
		"session": next,
		"registry": next_registry,
		"rebuilt_regions": ordered_ids,
		"handoff_errors": handoff_errors,
	}

static func _run_mixed_and_reference(session: Dictionary, registry: Dictionary, reference: Dictionary, steps: int) -> Dictionary:
	var live_session := session
	var live_reference := reference.duplicate(true)
	var max_delta := 0.0
	for step_index in range(steps):
		var mixed := Runtime.step(live_session, registry, {}, DT)
		if not bool(mixed.get("success", false)):
			return _failure("COMPLEX1B_MIXED_STEP_FAILED", {"step": step_index, "result": mixed})
		var full := Runtime.full_reference_step(registry, live_reference, {}, DT)
		if not bool(full.get("success", false)):
			return _failure("COMPLEX1B_FULL_REFERENCE_STEP_FAILED", {"step": step_index, "result": full})
		live_session = mixed["details"]["session"]
		live_reference = full["details"]["state_values"]
		max_delta = maxf(max_delta, _state_error(live_session["state_values"], live_reference))
	return {
		"success": true,
		"session": live_session,
		"reference": live_reference,
		"max_delta": max_delta,
	}

static func _partition_parts(full: Dictionary) -> Array:
	var result: Array = []
	var target_region := String(full["target_region_id"])
	var target_index := floori(float(int(full["break_index"])) / 20.0)
	var contact_region := "region/b0-2-%03d" % (target_index + 1)
	for raw_part in full["parts"]:
		var part: Dictionary = raw_part
		var part_id := String(part["part_id"])
		var index := int(part_id.get_slice("-", 2))
		var kind := "STRUCTURAL_BAKE"
		if String(part["region_id"]) == target_region:
			kind = "FULL"
		elif String(part["region_id"]) == contact_region:
			kind = "CONTACT_BAKE"
		elif index < 200:
			kind = "DYNAMIC_ROM"
		elif index >= 1800:
			kind = "HYBRID_BAKE"
		var copy := part.duplicate(true)
		copy["representation_kind"] = kind
		result.append(copy)
	return result

static func _specs() -> Array:
	return [
		[REGION_CONTACT, "CONTACT_BAKE", STATE_CONTACT, 0.90, 0.10],
		[REGION_DYNAMIC, "DYNAMIC_ROM", STATE_DYNAMIC, 1.25, 0.06],
		[REGION_HYBRID, "HYBRID_BAKE", STATE_HYBRID, 1.05, 0.09],
		[REGION_IMPACT, "FULL", STATE_IMPACT, 1.15, 0.07],
		[REGION_STABLE, "STRUCTURAL_BAKE", STATE_STABLE, 1.00, 0.08],
	]

static func _initial_state() -> Dictionary:
	return {
		STATE_CONTACT: 0.44,
		STATE_DYNAMIC: 0.21,
		STATE_HYBRID: -0.08,
		STATE_IMPACT: 0.72,
		STATE_STABLE: 1.0,
	}

static func _source_id(region_id: String) -> String:
	return "construct/complex1b-%s-projection" % region_id.replace("region/", "").replace("/", "-")

static func _backend_hash(kind: String) -> String:
	match kind:
		"STRUCTURAL_BAKE":
			return Utils.canonical_hash({"bridge1_exact": "e128cf9d49f84691b8a5428c97ab7acd53b92d90"})
		"CONTACT_BAKE":
			return Utils.canonical_hash({"b0_3_closure": "9575a63d6aeb4c455f8beade7588505e600c12d6"})
		"DYNAMIC_ROM":
			return Utils.canonical_hash({"b0_4_exact": "e33ac10ac94d8b70f1387d442a3ae9d3801bb08a"})
		"HYBRID_BAKE":
			return Utils.canonical_hash({"b0_5_a_exact": "d819fffa0dc86cc09cda0000f20c310aec23c799"})
		_:
			return Utils.canonical_hash({"fabric0_18_exact": "e079565b4b9cd0dae530ff5042f057ce8fa0d0cc"})

static func _interface(interface_id: String, a: String, b: String, conductance: float) -> Dictionary:
	return {
		"interface_id": interface_id,
		"region_a": a,
		"region_b": b,
		"port_a": Adapter.port_id(a, "right"),
		"port_b": Adapter.port_id(b, "left"),
		"conductance": conductance,
	}

static func _rep(id: String, kind: String, frontier_hash: String, authority_binding: String) -> Dictionary:
	return {
		"representation_id": id,
		"representation_kind": kind,
		"derived_only": true,
		"canonical_write_authorized": false,
		"source_frontier_hash": frontier_hash,
		"authority_epoch_binding": authority_binding,
	}

static func _binding(region_id: String, representation_id: String, role: String) -> Dictionary:
	return {
		"region_id": region_id,
		"representation_id": representation_id,
		"ownership_role": role,
	}

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for key in a.keys():
		error = maxf(error, absf(float(a[key]) - float(b[key])))
	return error

static func _failure(error_code: String, details = null) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details,
	}
