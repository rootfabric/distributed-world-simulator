extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const D = C.D
const G = C.G
const EventStep = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_event_step_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")

var _model: Dictionary = {}
var _model_hash := ""
var _system: Dictionary = {}
var _fidelity := "FULL"
var _fracture_j := 0.0
var _pending: Dictionary = {}
var _events: Array = []
var _certificate: Dictionary = {}

func initialize(sources: Dictionary, authority: Dictionary) -> Dictionary:
	if not _model.is_empty(): return U.failure("R3_ALREADY_INITIALIZED")
	var compiled := C.compile(sources, authority)
	if not compiled.success: return compiled
	var built := C.system(compiled.details.model, "FULL")
	if not built.success: return built
	_model = compiled.details.model
	_model_hash = U.canonical_hash(_model)
	_system = built.details.system
	return U.success()

func fence(sources: Dictionary, authority: Dictionary) -> Dictionary:
	if _model.is_empty() or U.canonical_hash(_model) != _model_hash: return U.failure("R3_MODEL_INVALID")
	if U.canonical_hash(sources) != _model.source_hash or not C.A.validate_b0_safety(authority).success or authority.checksum != _model.authority_hash: return U.failure("R3_SOURCE_OR_AUTHORITY_STALE")
	return U.success()

func set_fidelity(target: String, sources: Dictionary, authority: Dictionary, artifact: Dictionary = {}) -> Dictionary:
	var checked := fence(sources, authority)
	if not checked.success: return checked
	if not target in ["FULL", "BAKE"] or not _pending.is_empty(): return U.failure("R3_FIDELITY_NOT_ADMISSIBLE")
	if target == "BAKE" and _utilization() >= _model.controls.guard_fraction: return U.failure("R3_GUARD_REQUIRES_FULL")
	var expected := _make_certificate()
	if not artifact.is_empty() and (not U.validate_checksum(artifact).success or U.canonical_hash(artifact) != U.canonical_hash(expected)): return U.failure("R3_BAKE_ARTIFACT_STALE_OR_TAMPERED")
	var built := C.system(_model, target, _values(), _system.time, "LIVE" if target == "BAKE" else _system.mode)
	if not built.success: return built
	_system = built.details.system
	_fidelity = target
	_certificate = expected if target == "BAKE" else {}
	return U.success({"certificate": _certificate})

func advance(dt: float, sources: Dictionary, authority: Dictionary) -> Dictionary:
	var checked := fence(sources, authority)
	if not checked.success: return checked
	if not U.is_positive_number(dt) or dt < 1.0e-7 or dt > _model.max_step_s: return U.failure("R3_TIMESTEP_OUTSIDE_ENVELOPE", {"max_step_s": _model.max_step_s})
	if not _pending.is_empty(): return U.failure("R3_WAITING_CANONICAL_COMMIT")
	var candidate: Dictionary = _system.duplicate(true)
	candidate.events = []
	var condition := D._next_enabled_condition_transition(candidate, {})
	if not condition.is_empty():
		var stats := {"event_iterations": 0}
		var instant := D._process_event_instant(candidate, condition, stats)
		if not instant.get("ok", false): return U.failure("R3_INITIAL_EVENT_FAILED", instant)
	if candidate.mode != "WAIT_CANONICAL":
		var advanced := _advance_candidate(candidate, dt)
		if not advanced.get("ok", false): return U.failure("R3_DAE_FAILED", advanced)
	var events: Array = candidate.events.duplicate(true)
	var next_fidelity := _fidelity
	if _fidelity == "BAKE":
		for instant in events:
			var guarded := false
			for transition in instant.transitions:
				if str(transition.transition_id).begins_with("guard|"): guarded = true
			if not guarded: continue
			var last: Dictionary = instant.transitions.back()
			var built := C.system(_model, "FULL", last.post_states, instant.time, last.post_mode)
			if not built.success: return built
			var full: Dictionary = built.details.system
			var remaining := float(_system.time) + dt - float(instant.time)
			if remaining > D.EPSILON and full.mode != "WAIT_CANONICAL":
				var continued := _advance_candidate(full, remaining)
				if not continued.get("ok", false): return U.failure("R3_REFINEMENT_FAILED", continued)
			var prefix: Array = []
			for prior in events:
				if float(prior.time) <= float(instant.time): prefix.append(prior)
			events = prefix + full.events
			candidate = full
			next_fidelity = "FULL"
			break
	var pending := {}
	for instant in events:
		for transition in instant.transitions:
			var token: String = transition.transition_id
			if token.begins_with("failure|"):
				candidate.time = instant.time
				pending = {"bond_id": token.get_slice("|", 1), "time_s": instant.time, "source_hash": _model.source_hash, "authority_hash": _model.authority_hash, "event_id": "event/r3-" + U.canonical_hash([_model.source_hash, instant.time, token])}
	for spec in candidate.states.values():
		if not U.is_finite_number(spec.value): return U.failure("R3_NONFINITE_TRAJECTORY")
	_system = candidate
	_fidelity = next_fidelity
	if next_fidelity == "FULL": _certificate = {}
	_pending = pending
	for instant in events:
		for transition in instant.transitions: _events.append({"time_s": instant.time, "transition": transition.transition_id, "source_hash": _model.source_hash})
	return U.success({"snapshot": inspect()})

func _advance_candidate(candidate: Dictionary, dt: float) -> Dictionary:
	if _is_general(): return D.advance(candidate, dt)
	return EventStep.advance(candidate, dt, _model)

func prepare_successor(previous: Dictionary, successor: Dictionary, authority: Dictionary, kind: String) -> Dictionary:
	var checked := fence(previous, authority)
	if not checked.success: return checked
	var compiled := C.compile(successor, authority)
	if not compiled.success: return compiled
	var released := 0.0
	if kind == "failure":
		if _pending.is_empty(): return U.failure("R3_NO_FAILURE_PROPOSAL")
		checked = Adapter.validate_successor(previous.mechanical, successor.mechanical, previous.mechanical_matter, successor.mechanical_matter, _pending.bond_id)
		if not checked.success: return checked
		for key in ["electrical", "electrical_matter"]:
			if previous[key] != successor[key]: return U.failure("R3_UNRELATED_SUCCESSOR_CHANGE")
		if _is_general(): released = G.element_elastic_energy(_model, _system, _pending.bond_id)
		else:
			for element in _model.mechanical_model.elements:
				if element.element_id == _pending.bond_id: released = 0.5 * float(element.stiffness_n_per_m) * pow(_value("x"), 2)
	elif kind == "input":
		if not _pending.is_empty(): return U.failure("R3_PENDING_FAILURE")
		for key in ["electrical", "electrical_matter", "mechanical_matter"]:
			if previous[key] != successor[key]: return U.failure("R3_UNRELATED_SUCCESSOR_CHANGE")
		var before: Dictionary = previous.mechanical.duplicate(true)
		var after: Dictionary = successor.mechanical.duplicate(true)
		for field in ["source_voltage_v", "external_force_n"]: after.compiled_facets.composition_r3[field] = before.compiled_facets.composition_r3[field]
		checked = _only_revision_changed(before, after)
		if not checked.success: return checked
	elif kind == "load":
		if not _pending.is_empty(): return U.failure("R3_PENDING_FAILURE")
		for key in ["mechanical", "mechanical_matter", "electrical_matter"]:
			if previous[key] != successor[key]: return U.failure("R3_UNRELATED_SUCCESSOR_CHANGE")
		var before: Dictionary = previous.electrical.duplicate(true)
		var after: Dictionary = successor.electrical.duplicate(true)
		if before.bonds.size() != after.bonds.size(): return U.failure("R3_LOAD_TOPOLOGY_CHANGE")
		var load_id: String = str(_model.get("load_id", ""))
		if load_id.is_empty(): return U.failure("R3_LOAD_MUTATION_AMBIGUOUS")
		for i in range(before.bonds.size()):
			if before.bonds[i].bond_id == load_id: after.bonds[i].metadata.area_m2 = before.bonds[i].metadata.area_m2
		checked = _only_revision_changed(before, after)
		if not checked.success: return checked
	else: return U.failure("R3_SUCCESSOR_KIND")
	var built := C.system(compiled.details.model, "FULL", _values(), _system.time, "LIVE")
	if not built.success: return built
	return {"success": true, "prepared": {"model": compiled.details.model, "system": built.details.system, "fracture_j": _fracture_j + released, "prior_source_hash": _model.source_hash, "events": _events.duplicate(true)}}

func _adopt_prepared(prepared: Dictionary) -> void:
	_model = prepared.model
	_model_hash = U.canonical_hash(_model)
	_system = prepared.system
	_fracture_j = prepared.fracture_j
	_events = prepared.events
	_pending = {}
	_fidelity = "FULL"
	_certificate = {}

func inspect() -> Dictionary:
	if _model.is_empty(): return {}
	if _is_general():
		var observed := G.observe(_model, _system, _fidelity, _fracture_j)
		if observed.has("error_code"): return {}
		observed["pending_proposal"] = _pending.duplicate(true)
		observed["events"] = _events.duplicate(true)
		observed["source_hash"] = _model.source_hash
		observed["authority_hash"] = _model.authority_hash
		observed["mechanical_revision"] = _model.mechanical_model.construct_revision
		observed["electrical_revision"] = _model.electrical_model.construct_revision
		observed["model_hash"] = _model_hash
		observed["certificate"] = _certificate.duplicate(true)
		return observed
	var x := _value("x")
	var v := _value("v")
	var g: float = _model.controls.coupling_n_per_a
	var current := float(D.read_algebraic(_system, "i")) if _fidelity == "FULL" else (float(_model.controls.source_voltage_v) - g * v) / float(_model.resistance_ohm)
	var kinetic := 0.5 * float(_model.mass_kg) * v * v
	var elastic := 0.5 * float(_model.stiffness_n_per_m) * x * x
	var supports: Array = []
	for element in _model.mechanical_model.elements: supports.append({"bond_id": element.element_id, "active": element.active, "effort_n": (float(element.stiffness_n_per_m) * x + float(element.damping_ns_per_m) * v) if element.active else 0.0, "capacity_n": element.capacity_n})
	return {"time_s": _system.time, "displacement_m": x, "velocity_m_per_s": v, "current_a": current, "back_emf_v": g * v, "actuator_force_n": g * current, "constraint_residual_v": float(_model.resistance_ohm) * current + g * v - float(_model.controls.source_voltage_v), "source_power_w": float(_model.controls.source_voltage_v) * current, "coupler_electrical_power_w": g * v * current, "coupler_mechanical_power_w": g * current * v, "kinetic_j": kinetic, "elastic_j": elastic, "fracture_heat_j": _fracture_j, "source_work_j": _value("source_work"), "external_work_j": _value("external_work"), "joule_heat_j": _value("joule_heat"), "damper_heat_j": _value("damper_heat"), "energy_residual_j": kinetic + elastic + _fracture_j + _value("joule_heat") + _value("damper_heat") - _value("source_work") - _value("external_work"), "coupler_power_residual_w": g * v * current - g * current * v, "supports": supports, "fidelity": _fidelity, "mode": _system.mode, "pending_proposal": _pending.duplicate(true), "events": _events.duplicate(true), "source_hash": _model.source_hash, "authority_hash": _model.authority_hash, "mechanical_revision": _model.mechanical_model.construct_revision, "electrical_revision": _model.electrical_model.construct_revision, "max_step_s": _model.max_step_s, "guard_fraction": _model.controls.guard_fraction, "utilization": _utilization(), "model_hash": _model_hash, "axis": _model.axis.duplicate(), "certificate": _certificate.duplicate(true)}

func _make_certificate() -> Dictionary:
	var dynamic_states := 2
	var identity := "i=(u-g*v)/r; g*i*v=g*v*i"
	if _is_general():
		dynamic_states = 2 * int(_model.mobile_nodes.size())
		identity = "i_source=i0+iv*v_coupler; nodal KCL/Ohm readback; electrical power=joule+coupler"
	var value := {"schema": "planet_simulator.fabric_composition_r3_elimination_certificate.v1", "source_hash": _model.source_hash, "authority_hash": _model.authority_hash, "model_hash": _model_hash, "eliminated_algebraics": 1, "dynamic_states_before": dynamic_states, "dynamic_states_after": dynamic_states, "energy_accounting_states": 4, "identity": identity, "checksum": ""}
	value.checksum = U.compute_checksum(value)
	return value

func _utilization() -> float:
	if _is_general():
		var observed := G.observe(_model, _system, _fidelity, _fracture_j)
		return float(observed.get("utilization", INF))
	var result := 0.0
	for element in _model.mechanical_model.elements:
		if element.active: result = maxf(result, absf(float(element.stiffness_n_per_m) * _value("x") + float(element.damping_ns_per_m) * _value("v")) / float(element.capacity_n))
	return result

func _values() -> Dictionary:
	var values := {}
	for name in _system.states: values[name] = _system.states[name].value
	return values

func _value(name: String) -> float:
	return float(_system.states[name].value)

func _is_general() -> bool:
	return _model.get("solver_kind") == G.SOLVER_KIND

static func _only_revision_changed(before: Dictionary, after: Dictionary) -> Dictionary:
	if int(after.state_revision) != int(before.state_revision) + 1: return U.failure("R3_SUCCESSOR_REVISION")
	after.state_revision = before.state_revision
	after.checksum = before.checksum
	return U.success() if before == after else U.failure("R3_UNRELATED_SUCCESSOR_CHANGE")
