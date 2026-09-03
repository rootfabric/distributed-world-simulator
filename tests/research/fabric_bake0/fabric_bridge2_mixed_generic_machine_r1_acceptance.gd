extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Fabric = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")

const DT := 0.01
const REGION_A := "region/bridge2-a"
const REGION_B := "region/bridge2-b"
const REGION_C := "region/bridge2-c"
const REGION_D := "region/bridge2-d"
const REGION_E := "region/bridge2-e"

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var subject := _build_subject(0)
	if subject.is_empty():
		_finish()
		return
	_test_registry_contract(subject)
	_test_mixed_flow_and_full_reference(subject)
	_test_event_driven_representation_swap(subject)
	_test_local_invalidation_and_rebuild(subject)
	_test_deterministic_replay(subject)
	_test_fail_closed_ownership(subject)
	_finish()

func _build_subject(revision_a: int) -> Dictionary:
	var master := _master_source(revision_a)
	if master.is_empty():
		_check(false, "master PhysicalSource fixture builds")
		return {}
	var specs := [
		[REGION_A, "STRUCTURAL_BAKE", "state/bridge2-a", 1.00, 0.08],
		[REGION_B, "FULL",            "state/bridge2-b", 1.15, 0.07],
		[REGION_C, "CONTACT_BAKE",    "state/bridge2-c", 0.90, 0.10],
		[REGION_D, "DYNAMIC_ROM",     "state/bridge2-d", 1.25, 0.06],
		[REGION_E, "HYBRID_BAKE",     "state/bridge2-e", 1.05, 0.09],
	]
	var regions: Array = []
	for spec in specs:
		var region_id := String(spec[0])
		var source_key := Utils.source_key("CONSTRUCTION", _source_id(region_id))
		var slice := Slice.create(region_id, master["frontier"], master["authority"], [source_key])
		_check(not slice.is_empty(), "%s source slice builds" % region_id)
		if slice.is_empty():
			return {}
		var adapter := Adapter.create(
			region_id, String(spec[1]), String(spec[2]), slice,
			_backend_hash(String(spec[1])), float(spec[3]), float(spec[4]), 1
		)
		_check(not adapter.is_empty(), "%s adapter builds" % region_id)
		if adapter.is_empty():
			return {}
		regions.append({
			"region_id": region_id,
			"representation_kind": String(spec[1]),
			"state_id": String(spec[2]),
			"adapter": adapter,
		})
	var interfaces := [
		_interface("interface/bridge2-ab", REGION_A, REGION_B, 0.35),
		_interface("interface/bridge2-bc", REGION_B, REGION_C, 0.28),
		_interface("interface/bridge2-cd", REGION_C, REGION_D, 0.31),
		_interface("interface/bridge2-de", REGION_D, REGION_E, 0.26),
	]
	var registry := Registry.create(master["frontier"], master["authority"], regions, interfaces)
	_check(not registry.is_empty(), "five-kind mixed registry builds")
	if registry.is_empty():
		return {}
	return {
		"master": master,
		"registry": registry,
		"initial": {
			"state/bridge2-a": 1.0,
			"state/bridge2-b": 0.72,
			"state/bridge2-c": 0.44,
			"state/bridge2-d": 0.21,
			"state/bridge2-e": -0.08,
		},
	}

func _test_registry_contract(subject: Dictionary) -> void:
	var registry: Dictionary = subject["registry"]
	_check(bool(Registry.validate(registry).get("success", false)), "mixed registry validates")
	_check(registry["regions"].size() == 5, "five explicit regions")
	_check(registry["interfaces"].size() == 4, "four explicit boundary interfaces")
	var kinds: Array = []
	var state_ids: Array = []
	var source_keys: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
		state_ids.append(String(region["state_id"]))
		for key in region["adapter"]["source_slice"]["source_keys"]:
			source_keys.append(String(key))
		var adapter: Dictionary = region["adapter"]
		_check(bool(Adapter.validate(adapter).get("success", false)), "%s adapter validates" % region["region_id"])
		_check(bool(Slice.validate_against_master(adapter["source_slice"], registry["master_frontier"], registry["master_authority"]).get("success", false)), "%s slice proves master ancestry" % region["region_id"])
		if String(region["representation_kind"]) == "FULL":
			_check(adapter["artifact"].is_empty(), "FULL owns no PhysicalBakeArtifact")
		else:
			_check(bool(Artifact.validate(adapter["artifact"]).get("success", false)), "%s owns common PhysicalBakeArtifact" % region["representation_kind"])
			_check(String(adapter["artifact"]["source_binding"]["frontier_hash"]) == String(adapter["source_slice"]["frontier"]["frontier_hash"]), "artifact binds regional exact slice")
	kinds.sort()
	var expected := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected.sort()
	_check(kinds == expected, "all five representation kinds present exactly once")
	var state_unique := state_ids.duplicate(); state_unique.sort()
	_check(state_unique.size() == 5 and state_unique[0] != state_unique[1] and state_unique[1] != state_unique[2] and state_unique[2] != state_unique[3] and state_unique[3] != state_unique[4], "no overlapping state ownership")
	var source_unique := source_keys.duplicate(); source_unique.sort()
	_check(source_unique.size() == 5 and source_unique[0] != source_unique[1] and source_unique[1] != source_unique[2] and source_unique[2] != source_unique[3] and source_unique[3] != source_unique[4], "no overlapping source ownership")

func _test_mixed_flow_and_full_reference(subject: Dictionary) -> void:
	var registry: Dictionary = subject["registry"]
	var started := Runtime.start(registry, subject["initial"])
	_check(bool(started.get("success", false)), "mixed session starts")
	if not bool(started.get("success", false)):
		return
	var session: Dictionary = started["details"]["session"]
	var reference: Dictionary = subject["initial"].duplicate(true)
	var previous_energy := _energy(registry, session["state_values"])
	var max_error := 0.0
	for step in range(5):
		var mixed := Runtime.step(session, registry, {}, DT)
		var full := Runtime.full_reference_step(registry, reference, {}, DT)
		_check(bool(mixed.get("success", false)), "mixed FLOW step %d succeeds" % step)
		_check(bool(full.get("success", false)), "FULL reference step %d succeeds" % step)
		if not bool(mixed.get("success", false)) or not bool(full.get("success", false)):
			return
		session = mixed["details"]["session"]
		reference = full["details"]["state_values"]
		var error := _state_error(session["state_values"], reference)
		max_error = maxf(max_error, error)
		_check(error <= 1.0e-12, "mixed/FULL state agreement step %d" % step)
		_check(float(mixed["details"]["energy_after"]) <= previous_energy + 1.0e-12, "zero-input mixed network is passive step %d" % step)
		previous_energy = float(mixed["details"]["energy_after"])
		for flow in mixed["details"]["interface_flows"]:
			_check(float(flow["power_dissipation"]) >= -1.0e-12, "interface dissipation non-negative")
	print("BRIDGE-2 initial mixed-flow max FULL delta=%s" % String.num_scientific(max_error))

func _test_event_driven_representation_swap(subject: Dictionary) -> void:
	var registry: Dictionary = subject["registry"]
	var started := Runtime.start(registry, subject["initial"])
	if not bool(started.get("success", false)):
		_check(false, "event scenario starts")
		return
	var session: Dictionary = started["details"]["session"]
	for step in range(5):
		var result := Runtime.step(session, registry, {}, DT)
		if not bool(result.get("success", false)):
			_check(false, "event scenario reaches exact event time")
			return
		session = result["details"]["session"]
	var event := _fabric_event()
	_check(not event.is_empty(), "real FABRIC localized event produced")
	_check(absf(float(event.get("time", -1.0)) - 0.05) <= 1.0e-8, "FABRIC event localized at expected instant")
	var old_b := Registry.region_by_id(registry, REGION_B)
	var old_e := Registry.region_by_id(registry, REGION_E)
	var b_hybrid := Adapter.create(
		REGION_B, "HYBRID_BAKE", String(old_b["state_id"]), old_b["adapter"]["source_slice"],
		_backend_hash("HYBRID_BAKE"), float(old_b["adapter"]["storage"]), float(old_b["adapter"]["damping"]), 2
	)
	var e_full := Adapter.create(
		REGION_E, "FULL", String(old_e["state_id"]), old_e["adapter"]["source_slice"],
		_backend_hash("FULL"), float(old_e["adapter"]["storage"]), float(old_e["adapter"]["damping"]), 1
	)
	_check(not b_hybrid.is_empty() and not e_full.is_empty(), "event replacement adapters build")
	var swapped := Runtime.consume_representation_swap_event(
		session, registry, event, REGION_B, b_hybrid, REGION_E, e_full
	)
	_check(bool(swapped.get("success", false)), "one FABRIC event atomically swaps two representation owners")
	if not bool(swapped.get("success", false)):
		return
	var next_registry: Dictionary = swapped["details"]["registry"]
	var next_session: Dictionary = swapped["details"]["session"]
	_check(String(Registry.region_by_id(next_registry, REGION_B)["representation_kind"]) == "HYBRID_BAKE", "region B becomes HYBRID_BAKE")
	_check(String(Registry.region_by_id(next_registry, REGION_E)["representation_kind"]) == "FULL", "region E becomes FULL")
	_check(next_session["event_ledger"].size() == 1, "one physical event creates one ledger record")
	_check(swapped["details"]["handoffs"].size() == 2, "one event performs two explicit state handoffs")
	for handoff in swapped["details"]["handoffs"]:
		_check(float(handoff["state_error"]) == 0.0, "representation handoff preserves exact scalar FULL state")
	var duplicate := Runtime.consume_representation_swap_event(
		next_session, next_registry, event, REGION_E, old_e["adapter"], REGION_B, old_b["adapter"]
	)
	_check(not bool(duplicate.get("success", false)), "same FABRIC event cannot commit twice")
	_check(String(duplicate.get("error_code", "")) == "BRIDGE2_DUPLICATE_FABRIC_EVENT", "duplicate physical event rejection exact")
	var next_step := Runtime.step(next_session, next_registry, {}, DT)
	_check(bool(next_step.get("success", false)), "mixed FLOW resumes after representation handoff")

func _test_local_invalidation_and_rebuild(subject: Dictionary) -> void:
	var registry: Dictionary = subject["registry"]
	var started := Runtime.start(registry, subject["initial"])
	if not bool(started.get("success", false)):
		_check(false, "invalidation scenario starts")
		return
	var session: Dictionary = started["details"]["session"]
	var reference: Dictionary = subject["initial"].duplicate(true)
	for step in range(10):
		var mixed := Runtime.step(session, registry, {}, DT)
		var full := Runtime.full_reference_step(registry, reference, {}, DT)
		if not bool(mixed.get("success", false)) or not bool(full.get("success", false)):
			_check(false, "pre-mutation mixed/FULL evolution succeeds")
			return
		session = mixed["details"]["session"]
		reference = full["details"]["state_values"]

	var updated := _master_source(1)
	var invalidated := Runtime.apply_master_update(
		session, registry, updated["frontier"], updated["authority"], 100
	)
	_check(bool(invalidated.get("success", false)), "canonical master mutation fans out invalidation")
	if not bool(invalidated.get("success", false)):
		return
	session = invalidated["details"]["session"]
	_check(invalidated["details"]["affected_regions"] == [REGION_A], "only causally affected region A invalidated")
	_check(invalidated["details"]["unaffected_regions"].size() == 4, "four unaffected regions remain live")
	_check(String(session["artifact_states"][REGION_A]) == "STALE", "region A artifact marked STALE")
	_check(session["invalidations_by_region"][REGION_A].size() == 1, "region A gets exact BakeInvalidation")
	var blocked := Runtime.step(session, registry, {}, DT)
	_check(not bool(blocked.get("success", false)), "full mixed step blocked while required region is stale")
	_check(String(blocked.get("error_code", "")) == "BRIDGE2_MIXED_STEP_BLOCKED", "stale mixed-step rejection exact")
	for region_id in [REGION_B, REGION_C, REGION_D, REGION_E]:
		var gate := Runtime.can_execute_region(session, registry, region_id)
		_check(bool(gate.get("success", false)), "%s remains executable after unrelated source mutation" % region_id)
	var a_gate := Runtime.can_execute_region(session, registry, REGION_A)
	_check(not bool(a_gate.get("success", false)), "affected region A cannot execute stale artifact")

	var old_a := Registry.region_by_id(registry, REGION_A)
	var fresh_slice := Slice.refreshed(
		old_a["adapter"]["source_slice"], updated["frontier"], updated["authority"]
	)
	var rebuilt_adapter := Adapter.create(
		REGION_A, "STRUCTURAL_BAKE", String(old_a["state_id"]), fresh_slice,
		_backend_hash("STRUCTURAL_BAKE"), float(old_a["adapter"]["storage"]), float(old_a["adapter"]["damping"]), 2
	)
	_check(not rebuilt_adapter.is_empty(), "affected region A fresh adapter rebuilds")
	var rebuilt := Runtime.rebuild_region(session, registry, rebuilt_adapter)
	_check(bool(rebuilt.get("success", false)), "region A rebuild rebinds current master frontier")
	if not bool(rebuilt.get("success", false)):
		return
	session = rebuilt["details"]["session"]
	registry = rebuilt["details"]["registry"]
	_check(float(rebuilt["details"]["state_handoff_error"]) == 0.0, "region rebuild preserves physical state exactly")
	_check(bool(Runtime.can_execute_region(session, registry, REGION_A).get("success", false)), "fresh region A executes after rebuild")
	for step in range(20):
		var mixed := Runtime.step(session, registry, {}, DT)
		var full := Runtime.full_reference_step(subject["registry"], reference, {}, DT)
		if not bool(mixed.get("success", false)) or not bool(full.get("success", false)):
			_check(false, "post-rebuild mixed/FULL evolution succeeds")
			return
		session = mixed["details"]["session"]
		reference = full["details"]["state_values"]
	var final_error := _state_error(session["state_values"], reference)
	_check(final_error <= 1.0e-12, "local invalidation/rebuild leaves mixed outcome equal to FULL reference")

func _test_deterministic_replay(subject: Dictionary) -> void:
	var left := _run_plain(subject, 25)
	var right := _run_plain(subject, 25)
	_check(bool(left.get("success", false)) and bool(right.get("success", false)), "twin mixed replays complete")
	if bool(left.get("success", false)) and bool(right.get("success", false)):
		_check(left["details"]["state_values"] == right["details"]["state_values"], "mixed state replay byte-deterministic")
		_check(String(left["details"]["state_hash"]) == String(right["details"]["state_hash"]), "mixed replay state hash deterministic")
	var rebuilt := _build_subject(0)
	_check(not rebuilt.is_empty(), "independent registry rebuild succeeds")
	if not rebuilt.is_empty():
		_check(String(rebuilt["registry"]["registry_hash"]) == String(subject["registry"]["registry_hash"]), "mixed registry identity deterministic")

func _test_fail_closed_ownership(subject: Dictionary) -> void:
	var registry: Dictionary = subject["registry"]
	var bad_regions: Array = []
	for region in registry["regions"]:
		var copy := Dictionary(region).duplicate(true)
		if String(copy["region_id"]) == REGION_C:
			copy["state_id"] = String(Registry.region_by_id(registry, REGION_A)["state_id"])
			copy["adapter"] = copy["adapter"].duplicate(true)
			copy["adapter"]["state_id"] = copy["state_id"]
			copy["adapter"]["adapter_hash"] = Utils.canonical_hash(_adapter_payload(copy["adapter"]))
			copy["adapter"]["checksum"] = Utils.compute_checksum(copy["adapter"])
		bad_regions.append(copy)
	var overlap := Registry.create(registry["master_frontier"], registry["master_authority"], bad_regions, registry["interfaces"])
	_check(overlap.is_empty(), "overlapping state ownership fails closed")

	var same_source_regions: Array = []
	for region in registry["regions"]:
		var copy := Dictionary(region).duplicate(true)
		if String(copy["region_id"]) == REGION_C:
			var a := Registry.region_by_id(registry, REGION_A)
			var a_slice: Dictionary = a["adapter"]["source_slice"]
			var replacement := Adapter.create(
				REGION_C, "CONTACT_BAKE", String(copy["state_id"]),
				Slice.create(REGION_C, registry["master_frontier"], registry["master_authority"], a_slice["source_keys"]),
				_backend_hash("CONTACT_BAKE"),
				float(copy["adapter"]["storage"]), float(copy["adapter"]["damping"]), 1
			)
			copy["adapter"] = replacement
		same_source_regions.append(copy)
	var source_overlap := Registry.create(registry["master_frontier"], registry["master_authority"], same_source_regions, registry["interfaces"])
	_check(source_overlap.is_empty(), "overlapping canonical source ownership fails closed")

func _master_source(revision_a: int) -> Dictionary:
	var dependency_hash := Utils.canonical_hash({"bridge2": "MIXED_GENERIC_MACHINE_R1"})
	var sources: Array = []
	var records: Array = []
	var mutable: Array = []
	for index in range(5):
		var region_id := "region/bridge2-%s" % String.chr(97 + index)
		var source_id := _source_id(region_id)
		var revision := revision_a if index == 0 else 0
		var source := SourceRevision.create(
			"CONSTRUCTION", source_id, 21, 100 + revision,
			Utils.canonical_hash({
				"region_id": region_id,
				"revision": revision,
				"physical_parameters_unchanged": true,
			}),
			dependency_hash
		)
		if source.is_empty():
			return {}
		sources.append(source)
		records.append({
			"source_domain": "CONSTRUCTION",
			"source_id": source_id,
			"authority_epoch": 21,
			"owner_id": "server/bridge2",
		})
		mutable.append(Utils.source_key("CONSTRUCTION", source_id))
	var frontier := Frontier.create(sources)
	var authority := AuthorityEnvelope.create("server/bridge2", records, mutable)
	if frontier.is_empty() or authority.is_empty():
		return {}
	return {"frontier": frontier, "authority": authority}

func _source_id(region_id: String) -> String:
	return "construct/%s" % region_id.replace("region/", "")

func _backend_hash(kind: String) -> String:
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

func _interface(interface_id: String, a: String, b: String, conductance: float) -> Dictionary:
	return {
		"interface_id": interface_id,
		"region_a": a,
		"region_b": b,
		"port_a": Adapter.port_id(a, "right"),
		"port_b": Adapter.port_id(b, "left"),
		"conductance": conductance,
	}

func _fabric_event() -> Dictionary:
	var system := Fabric.new_system()
	var rate_dimension := Fabric.dim_div(Fabric.dim_dimensionless(), Fabric.dim_time())
	if not Fabric.add_state(system, "phase", 0.0, Fabric.dim_dimensionless(), 1.0):
		return {}
	if not Fabric.add_parameter(system, "rate", 1.0, rate_dimension):
		return {}
	if not Fabric.add_mode(system, "mode/bridge2-before", {"phase": Fabric.expr_parameter("rate")}, []):
		return {}
	if not Fabric.add_mode(system, "mode/bridge2-after", {"phase": Fabric.expr_constant(0.0, rate_dimension)}, []):
		return {}
	if not Fabric.set_initial_mode(system, "mode/bridge2-before"):
		return {}
	if not Fabric.add_transition(system, {
		"id": "transition/bridge2-representation-trigger",
		"from_modes": ["mode/bridge2-before"],
		"to_mode": "mode/bridge2-after",
		"guard": {
			"expr": Fabric.expr_sub(Fabric.expr_state("phase"), Fabric.expr_constant(0.05, Fabric.dim_dimensionless())),
			"nominal": 1.0,
			"direction": 1,
			"kind": "crossing",
		},
		"jump": {},
		"topology_ops": [],
		"priority": 0,
	}):
		return {}
	var advanced := Fabric.advance(system, 0.10)
	if not bool(advanced.get("ok", false)) or system["events"].size() != 1:
		return {}
	return Dictionary(system["events"][0]).duplicate(true)

func _run_plain(subject: Dictionary, count: int) -> Dictionary:
	var started := Runtime.start(subject["registry"], subject["initial"])
	if not bool(started.get("success", false)):
		return started
	var session: Dictionary = started["details"]["session"]
	for step in range(count):
		var result := Runtime.step(session, subject["registry"], {}, DT)
		if not bool(result.get("success", false)):
			return result
		session = result["details"]["session"]
	return Utils.success({
		"state_values": session["state_values"],
		"state_hash": Utils.canonical_hash(session["state_values"]),
	})

func _energy(registry: Dictionary, values: Dictionary) -> float:
	var total := 0.0
	for region in registry["regions"]:
		var x := float(values[String(region["state_id"])])
		total += 0.5 * float(region["adapter"]["storage"]) * x * x
	return total

func _state_error(a: Dictionary, b: Dictionary) -> float:
	var result := 0.0
	for key in a.keys():
		result = maxf(result, absf(float(a[key]) - float(b[key])))
	return result

func _adapter_payload(adapter: Dictionary) -> Dictionary:
	var payload := adapter.duplicate(true)
	payload.erase("adapter_hash")
	payload.erase("checksum")
	return payload

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC BRIDGE-2 Mixed Generic Machine R1 Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("BRIDGE-2: %s" % failure)
	print("FABRIC BRIDGE-2 Mixed Generic Machine R1 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
