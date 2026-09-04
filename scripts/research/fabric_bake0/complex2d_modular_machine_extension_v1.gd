extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const ParentC = preload("res://scripts/research/fabric_bake0/complex2c_modular_machine_extension_v1.gd")
const Structural = preload("res://scripts/research/fabric_bake0/complex2_independent_structural_failure_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2d_modular_machine_extension.v1"
const DT := 0.01
const AFFECTED_REGIONS := [Fixture.REGION_CONTACT, Fixture.REGION_FULL]

static func build() -> Dictionary:
	var parent := ParentC.build()
	if not bool(parent.get("success", false)):
		return _failure("COMPLEX2D_PARENT_C_FAILED", parent)
	var machine: Dictionary = parent["parent_machine"]
	var structural := Structural.compile_from_machine(machine)
	if not bool(structural.get("success", false)):
		return _failure("COMPLEX2D_STRUCTURAL_COMPILE_FAILED", structural)
	return {
		"success": true,
		"schema": SCHEMA,
		"parent_c": parent,
		"parent_machine": machine,
		"structural_assembly": structural,
		"registry": parent["registry"],
		"extension_hash": Utils.canonical_hash({
			"schema": SCHEMA,
			"parent_c_extension_hash": String(parent["extension_hash"]),
			"structural_backend_hash": Structural.backend_family_hash(),
		}),
	}

static func run_experiment() -> Dictionary:
	var built := build()
	if not bool(built.get("success", false)):
		return built
	var machine: Dictionary = built["parent_machine"]
	var registry: Dictionary = built["registry"]
	var structural := Structural.run_failure(machine)
	if not bool(structural.get("success", false)):
		return _failure("COMPLEX2D_STRUCTURAL_FAILURE_FAILED", structural)
	var failed_machine: Dictionary = structural["failed_machine"]

	var started := Runtime.start(registry, machine["initial_state"])
	if not bool(started.get("success", false)):
		return _failure("COMPLEX2D_SESSION_START_FAILED", started)
	var session: Dictionary = started["details"]["session"]
	var reference: Dictionary = machine["initial_state"].duplicate(true)
	var max_runtime_delta := 0.0
	var pre := _run_runtime_pair(session, registry, reference, 3, {Fixture.REGION_FULL: 0.03})
	if not bool(pre.get("success", false)):
		return pre
	session = pre["session"]
	reference = pre["reference"]
	max_runtime_delta = maxf(max_runtime_delta, float(pre["max_delta"]))

	var master_after := _master_source({Fixture.REGION_FULL: 1, Fixture.REGION_CONTACT: 1})
	if master_after.is_empty():
		return _failure("COMPLEX2D_MASTER_UPDATE_BUILD_FAILED")
	var invalidated := Runtime.apply_master_update(
		session,
		registry,
		master_after["frontier"],
		master_after["authority"],
		3100
	)
	if not bool(invalidated.get("success", false)):
		return _failure("COMPLEX2D_MASTER_UPDATE_FAILED", invalidated)
	session = invalidated["details"]["session"]
	var affected: Array = Array(invalidated["details"]["affected_regions"]).duplicate()
	affected.sort()
	var expected_affected: Array = AFFECTED_REGIONS.duplicate()
	expected_affected.sort()
	if affected != expected_affected:
		return _failure("COMPLEX2D_AFFECTED_REGION_SET_MISMATCH", {"affected": affected})
	var blocked := Runtime.step(session, registry, {}, DT)
	if bool(blocked.get("success", false)):
		return _failure("COMPLEX2D_STALE_EXECUTION_ALLOWED")

	var single_adapter := _replacement_adapter(session, registry, Fixture.REGION_FULL, 5)
	if single_adapter.is_empty():
		return _failure("COMPLEX2D_SINGLE_REBUILD_PROBE_ADAPTER_FAILED")
	var sequential_probe := Runtime.rebuild_region(session, registry, single_adapter)
	if bool(sequential_probe.get("success", false)):
		return _failure("COMPLEX2D_SEQUENTIAL_MULTI_REGION_REBUILD_ALLOWED")

	var rebuilt := _atomic_rebuild_regions(session, registry, expected_affected, 5)
	if not bool(rebuilt.get("success", false)):
		return rebuilt
	session = rebuilt["session"]
	registry = rebuilt["registry"]
	var post := _run_runtime_pair(session, registry, reference, 5, {Fixture.REGION_CONTACT: 0.05})
	if not bool(post.get("success", false)):
		return post
	session = post["session"]
	reference = post["reference"]
	max_runtime_delta = maxf(max_runtime_delta, float(post["max_delta"]))

	var parent_dynamic := Registry.region_by_id(built["parent_c"]["registry"], Fixture.REGION_DYNAMIC)
	var final_dynamic := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	var parent_hybrid := Registry.region_by_id(built["parent_c"]["registry"], Fixture.REGION_HYBRID)
	var final_hybrid := Registry.region_by_id(registry, Fixture.REGION_HYBRID)
	var kinds: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
	kinds.sort()
	var handoff_errors: Dictionary = rebuilt["handoff_errors"]
	var result := {
		"success": true,
		"schema": SCHEMA,
		"extension_hash": String(built["extension_hash"]),
		"structural": structural,
		"affected_regions": affected,
		"stale_error": String(blocked.get("error_code", "")),
		"sequential_rebuild_error": String(sequential_probe.get("error_code", "")),
		"atomic_rebuild_regions": Array(rebuilt["rebuilt_regions"]).duplicate(),
		"atomic_handoff_errors": handoff_errors.duplicate(true),
		"runtime_mixed_full_max_delta": max_runtime_delta,
		"parent_c_dynamic_backend_hash": String(parent_dynamic["adapter"]["backend_contract_hash"]),
		"final_dynamic_backend_hash": String(final_dynamic["adapter"]["backend_contract_hash"]),
		"parent_b_hybrid_backend_hash": String(parent_hybrid["adapter"]["backend_contract_hash"]),
		"final_hybrid_backend_hash": String(final_hybrid["adapter"]["backend_contract_hash"]),
		"final_representation_kinds": kinds,
		"final_registry_hash": String(registry["registry_hash"]),
		"final_state_hash": Utils.canonical_hash(session["state_values"]),
		"experiment_hash": "",
		"continuation": {
			"machine": failed_machine,
			"session": session,
			"registry": registry,
			"reference": reference,
		},
	}
	result["experiment_hash"] = Utils.canonical_hash({
		"extension_hash": result["extension_hash"],
		"structural_experiment_hash": structural["experiment_hash"],
		"affected_regions": result["affected_regions"],
		"final_registry_hash": result["final_registry_hash"],
		"final_state_hash": result["final_state_hash"],
	})
	return result

static func _master_source(revisions: Dictionary) -> Dictionary:
	var dependency_hash := Utils.canonical_hash({"complex2": "MODULAR_MACHINE_R1"})
	var specs := [
		[Fixture.REGION_CONTACT], [Fixture.REGION_DYNAMIC], [Fixture.REGION_FULL],
		[Fixture.REGION_HYBRID], [Fixture.REGION_STRUCTURAL],
	]
	var sources: Array = []
	var records: Array = []
	var mutable: Array = []
	for spec in specs:
		var region_id := String(spec[0])
		var source_id := "construct/%s" % region_id.replace("region/", "")
		var revision_offset := int(revisions.get(region_id, 0))
		var source := SourceRevision.create(
			"CONSTRUCTION", source_id, 41, 100 + revision_offset,
			Utils.canonical_hash({"machine": "COMPLEX2", "region_id": region_id, "revision_offset": revision_offset}),
			dependency_hash
		)
		if source.is_empty():
			return {}
		sources.append(source)
		records.append({"source_domain": "CONSTRUCTION", "source_id": source_id, "authority_epoch": 41, "owner_id": "server/complex2"})
		mutable.append(Utils.source_key("CONSTRUCTION", source_id))
	var frontier := Frontier.create(sources)
	var authority := AuthorityEnvelope.create("server/complex2", records, mutable)
	if frontier.is_empty() or authority.is_empty():
		return {}
	return {"frontier": frontier, "authority": authority}

static func _replacement_adapter(session: Dictionary, registry: Dictionary, region_id: String, generation: int) -> Dictionary:
	var old := Registry.region_by_id(registry, region_id)
	if old.is_empty():
		return {}
	var refreshed := Slice.refreshed(old["adapter"]["source_slice"], session["live_master_frontier"], session["live_master_authority"])
	if refreshed.is_empty():
		return {}
	return Adapter.create(
		region_id,
		String(old["representation_kind"]),
		String(old["state_id"]),
		refreshed,
		String(old["adapter"]["backend_contract_hash"]),
		float(old["adapter"]["storage"]),
		float(old["adapter"]["damping"]),
		generation
	)

static func _atomic_rebuild_regions(session: Dictionary, registry: Dictionary, region_ids: Array, generation: int) -> Dictionary:
	var ordered: Array = region_ids.duplicate()
	ordered.sort()
	var replacements := {}
	var handoff_errors := {}
	for raw_region_id in ordered:
		var region_id := String(raw_region_id)
		var adapter := _replacement_adapter(session, registry, region_id, generation)
		if adapter.is_empty():
			return _failure("COMPLEX2D_ATOMIC_REPLACEMENT_FAILED", {"region_id": region_id})
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
	var next_registry := Registry.create(session["live_master_frontier"], session["live_master_authority"], regions, registry["interfaces"])
	if next_registry.is_empty():
		return _failure("COMPLEX2D_ATOMIC_REGISTRY_REBUILD_FAILED")
	var next := session.duplicate(true)
	next["registry_hash"] = String(next_registry["registry_hash"])
	for raw_region_id in ordered:
		var region_id := String(raw_region_id)
		var adapter: Dictionary = replacements[region_id]
		next["artifact_states"][region_id] = "FULL" if String(adapter["representation_kind"]) == "FULL" else "READY"
		next["invalidations_by_region"][region_id] = []
	next["checksum"] = Utils.compute_checksum(next)
	var checked := Runtime.validate_session(next, next_registry)
	if not bool(checked.get("success", false)):
		return _failure("COMPLEX2D_ATOMIC_SESSION_INVALID", checked)
	return {"success": true, "session": next, "registry": next_registry, "rebuilt_regions": ordered, "handoff_errors": handoff_errors}

static func _run_runtime_pair(session: Dictionary, registry: Dictionary, reference: Dictionary, steps: int, flows: Dictionary) -> Dictionary:
	var live_session := session
	var live_reference := reference.duplicate(true)
	var max_delta := 0.0
	for step_index in range(steps):
		var mixed := Runtime.step(live_session, registry, flows, DT)
		var full := Runtime.full_reference_step(registry, live_reference, flows, DT)
		if not bool(mixed.get("success", false)):
			return _failure("COMPLEX2D_RUNTIME_MIXED_STEP_FAILED", {"step": step_index, "result": mixed})
		if not bool(full.get("success", false)):
			return _failure("COMPLEX2D_RUNTIME_FULL_STEP_FAILED", {"step": step_index, "result": full})
		live_session = mixed["details"]["session"]
		live_reference = full["details"]["state_values"]
		max_delta = maxf(max_delta, _state_error(live_session["state_values"], live_reference))
	return {"success": true, "session": live_session, "reference": live_reference, "max_delta": max_delta}

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for key in a.keys():
		error = maxf(error, absf(float(a[key]) - float(b[key])))
	return error

static func _failure(error_code: String, details = null) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
