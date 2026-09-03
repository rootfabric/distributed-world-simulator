extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")
const ReductionBinding = preload("res://scripts/research/fabric_bake0/dynamic_rom_artifact_binding_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const RuntimeMonitor = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_monitor_v1.gd")
const RuntimeCertificate = preload("res://scripts/research/fabric_bake0/rom_runtime_certificate_v1.gd")
const RomRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_v1.gd")
const RomState = preload("res://scripts/research/fabric_bake0/dynamic_rom_state_v1.gd")
const ExecutionArtifact = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_artifact_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_lifecycle_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_execution_session.v1"
const HANDOFF_PROJECTION_C_NORM_TOLERANCE := 1.0e-10
const FIELDS: Array[String] = [
	"schema", "execution_artifact_hash", "lifecycle", "runtime_monitor", "rom_state",
	"error_c_norm_bound", "elapsed_s", "last_runtime_certificate", "checksum",
]

static func start(
	artifact: Dictionary,
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary
) -> Dictionary:
	var checked := ExecutionArtifact.verify_bindings(artifact, full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return checked
	var lifecycle := Lifecycle.create(artifact)
	if lifecycle.is_empty():
		return Utils.failure("DYNAMIC_ROM_LIFECYCLE_CREATE_FAILED")
	var transitioned := Lifecycle.certify(lifecycle, artifact)
	if not bool(transitioned.get("success", false)):
		return transitioned
	lifecycle = transitioned["details"]["lifecycle"]
	transitioned = Lifecycle.mark_ready(lifecycle, artifact)
	if not bool(transitioned.get("success", false)):
		return transitioned
	lifecycle = transitioned["details"]["lifecycle"]
	transitioned = Lifecycle.activate(lifecycle, artifact)
	if not bool(transitioned.get("success", false)):
		return transitioned
	lifecycle = transitioned["details"]["lifecycle"]
	var initial := RomRuntime.initial_state(descriptor)
	if not bool(initial.get("success", false)):
		return initial
	var monitor := RuntimeMonitor.create(String(artifact["source_binding_checksum"]), String(artifact["rom_descriptor_hash"]))
	if monitor.is_empty():
		return Utils.failure("DYNAMIC_ROM_RUNTIME_MONITOR_CREATE_FAILED")
	var session := {
		"schema": SCHEMA,
		"execution_artifact_hash": String(artifact["artifact_hash"]),
		"lifecycle": lifecycle,
		"runtime_monitor": monitor,
		"rom_state": initial["state"],
		"error_c_norm_bound": 0.0,
		"elapsed_s": 0.0,
		"last_runtime_certificate": {},
		"checksum": "",
	}
	session["checksum"] = Utils.compute_checksum(session)
	checked = validate(session, artifact)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"session": session, "status": "DYNAMIC_ROM_ACTIVE"})

static func start_from_full_handoff(
	artifact: Dictionary,
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary,
	full_values: Array,
	time_s: float,
	step_index: int
) -> Dictionary:
	var started := start(artifact, full_model, descriptor, reduction_binding, certification)
	if not bool(started.get("success", false)):
		return started
	var projected := project_full_state(full_model, descriptor, full_values, time_s, step_index)
	if not bool(projected.get("success", false)):
		return projected
	if float(projected["details"]["projection_error_c_norm"]) > HANDOFF_PROJECTION_C_NORM_TOLERANCE:
		return Utils.failure("DYNAMIC_ROM_HANDOFF_PROJECTION_OUTSIDE_CERTIFIED_SUBSPACE", {
			"projection_error_c_norm": projected["details"]["projection_error_c_norm"],
			"tolerance": HANDOFF_PROJECTION_C_NORM_TOLERANCE,
		})
	var session: Dictionary = started["details"]["session"]
	session["rom_state"] = projected["details"]["rom_state"]
	session["error_c_norm_bound"] = float(projected["details"]["projection_error_c_norm"])
	session["elapsed_s"] = time_s
	session["lifecycle"] = session["lifecycle"].duplicate(true)
	session["lifecycle"]["last_accepted_step"] = step_index
	session["lifecycle"]["checksum"] = Utils.compute_checksum(session["lifecycle"])
	session["checksum"] = Utils.compute_checksum(session)
	var checked := validate(session, artifact)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"session": session,
		"projection_error": projected["details"]["projection_error"],
		"projection_error_c_norm": projected["details"]["projection_error_c_norm"],
	})

static func validate(session: Dictionary, artifact: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(session, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if session.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_EXECUTION_SESSION_SCHEMA")
	checked = ExecutionArtifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	if String(session.get("execution_artifact_hash", "")) != String(artifact["artifact_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_SESSION_ARTIFACT_MISMATCH")
	if typeof(session.get("lifecycle")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_SESSION_LIFECYCLE")
	checked = Lifecycle.validate(session["lifecycle"])
	if not bool(checked.get("success", false)):
		return checked
	if String(session["lifecycle"]["execution_artifact_hash"]) != String(artifact["artifact_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_SESSION_LIFECYCLE_MISMATCH")
	if typeof(session.get("runtime_monitor")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_SESSION_MONITOR")
	checked = RuntimeMonitor.validate(session["runtime_monitor"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(session.get("rom_state")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_SESSION_STATE")
	checked = RomState.validate(session["rom_state"])
	if not bool(checked.get("success", false)):
		return checked
	if String(session["rom_state"]["rom_descriptor_hash"]) != String(artifact["rom_descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_SESSION_STATE_DESCRIPTOR_MISMATCH")
	if not Utils.is_non_negative_number(session.get("error_c_norm_bound")) or not Utils.is_non_negative_number(session.get("elapsed_s")):
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_SESSION_BOUND")
	if absf(float(session["elapsed_s"]) - float(session["rom_state"]["time_s"])) > 1.0e-12:
		return Utils.failure("DYNAMIC_ROM_EXECUTION_SESSION_TIME_MISMATCH")
	var last = session.get("last_runtime_certificate")
	if typeof(last) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_SESSION_CERTIFICATE")
	if not last.is_empty():
		checked = RuntimeCertificate.validate(last)
		if not bool(checked.get("success", false)):
			return checked
	return Utils.validate_checksum(session)

static func step(
	session: Dictionary,
	artifact: Dictionary,
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary,
	port_flows: Dictionary,
	delta_s: float,
	current_source_binding_checksum: String,
	local_unbake_available: bool = false
) -> Dictionary:
	var checked := validate(session, artifact)
	if not bool(checked.get("success", false)):
		return checked
	checked = ExecutionArtifact.verify_bindings(artifact, full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return _terminate_invalid(session, artifact, descriptor, "EXECUTION_BINDING_MISMATCH", "NONE", false, checked.get("error_code", "BINDING_MISMATCH"))
	if not Utils.is_lower_hex_64(current_source_binding_checksum) or current_source_binding_checksum != String(artifact["source_binding_checksum"]):
		return _terminate_stale(session, artifact, descriptor, "SOURCE_REVISION_MISMATCH")
	checked = Lifecycle.can_execute(session["lifecycle"], artifact)
	if not bool(checked.get("success", false)):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_FORBIDDEN", {"session": session, "cause": checked})
	checked = RuntimeMonitor.can_execute(session["runtime_monitor"])
	if not bool(checked.get("success", false)):
		return _terminate_invalid(session, artifact, descriptor, "RUNTIME_MONITOR_FORBIDDEN", "NONE", local_unbake_available, checked.get("error_code", "MONITOR_FORBIDDEN"))

	var old_state: Dictionary = session["rom_state"]
	var candidate := RomRuntime.step(descriptor, old_state, port_flows, delta_s)
	if not bool(candidate.get("success", false)):
		return _terminate_invalid(session, artifact, descriptor, "ROM_STEP_FAILED", "NONE", local_unbake_available, candidate.get("error_code", "ROM_STEP_FAILED"))
	var candidate_state: Dictionary = candidate["state"]
	var estimate := Certification.estimate_after_step(
		certification,
		full_model,
		descriptor,
		float(session["error_c_norm_bound"]),
		old_state["values"],
		candidate_state["values"],
		port_flows,
		delta_s,
		float(candidate_state["time_s"])
	)
	if not bool(estimate.get("success", false)):
		return _terminate_invalid(session, artifact, descriptor, "RUNTIME_ESTIMATE_FAILED", "NONE", local_unbake_available, estimate.get("error_code", "RUNTIME_ESTIMATE_FAILED"))
	var built_certificate := Certification.build_runtime_certificate(certification, estimate["details"])
	if not bool(built_certificate.get("success", false)):
		return _terminate_invalid(session, artifact, descriptor, "CERTIFICATE_UNAVAILABLE", "region/dynamic/all", local_unbake_available, built_certificate.get("error_code", "CERTIFICATE_UNAVAILABLE"))
	var runtime_certificate: Dictionary = built_certificate["details"]["certificate"]
	var observed := RuntimeMonitor.observe(
		session["runtime_monitor"], runtime_certificate, current_source_binding_checksum, int(candidate_state["step_index"])
	)
	if not bool(observed.get("success", false)):
		return _terminate_invalid(session, artifact, descriptor, "RUNTIME_MONITOR_OBSERVE_FAILED", "NONE", local_unbake_available, observed.get("error_code", "RUNTIME_MONITOR_OBSERVE_FAILED"))
	var next_monitor: Dictionary = observed["details"]["monitor"]
	if String(next_monitor["state"]) == RuntimeMonitor.ROM_INVALID:
		return _terminate_invalid_with_monitor(
			session, artifact, descriptor, next_monitor,
			String(next_monitor["invalidation_reason"]), "region/dynamic/all", local_unbake_available,
			"DYNAMIC_ROM_RUNTIME_CERTIFICATE_INVALID"
		)
	var safety := Certification.evaluate_runtime(certification, estimate["details"])
	if not bool(safety.get("success", false)):
		var region := _region_for_safety_failure(safety)
		return _terminate_invalid_with_monitor(
			session, artifact, descriptor, _force_monitor_invalid(next_monitor, String(safety.get("error_code", "RUNTIME_SAFETY_EXIT")), int(candidate_state["step_index"])),
			String(safety.get("error_code", "RUNTIME_SAFETY_EXIT")), region, local_unbake_available,
			String(safety.get("error_code", "DYNAMIC_ROM_RUNTIME_SAFETY_EXIT"))
		)

	var accepted_lifecycle := Lifecycle.accept_step(session["lifecycle"], artifact, int(candidate_state["step_index"]))
	if not bool(accepted_lifecycle.get("success", false)):
		return accepted_lifecycle
	var next := session.duplicate(true)
	next["lifecycle"] = accepted_lifecycle["details"]["lifecycle"]
	next["runtime_monitor"] = next_monitor
	next["rom_state"] = candidate_state
	next["error_c_norm_bound"] = float(estimate["details"]["error_c_norm_bound"])
	next["elapsed_s"] = float(candidate_state["time_s"])
	next["last_runtime_certificate"] = runtime_certificate
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate(next, artifact)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"session": next,
		"status": "DYNAMIC_ROM_STEP_ACCEPTED",
		"boundary": candidate["boundary"],
		"energy": candidate["energy"],
		"runtime_certificate": runtime_certificate,
		"remaining_validity_margin": safety["details"]["remaining_validity_margin"],
		"guard_margin": safety["details"]["guard_margin"],
	})

static func observe_runtime_certificate(
	session: Dictionary,
	artifact: Dictionary,
	descriptor: Dictionary,
	runtime_certificate: Dictionary,
	current_source_binding_checksum: String,
	step_index: int,
	local_unbake_available: bool = false
) -> Dictionary:
	var checked := validate(session, artifact)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_lower_hex_64(current_source_binding_checksum) or current_source_binding_checksum != String(artifact["source_binding_checksum"]):
		return _terminate_stale(session, artifact, descriptor, "SOURCE_REVISION_MISMATCH")
	var observed := RuntimeMonitor.observe(session["runtime_monitor"], runtime_certificate, current_source_binding_checksum, step_index)
	if not bool(observed.get("success", false)):
		return observed
	var monitor: Dictionary = observed["details"]["monitor"]
	if String(monitor["state"]) == RuntimeMonitor.ROM_INVALID:
		return _terminate_invalid_with_monitor(
			session, artifact, descriptor, monitor,
			String(monitor["invalidation_reason"]), "region/dynamic/all", local_unbake_available,
			"DYNAMIC_ROM_RUNTIME_CERTIFICATE_INVALID"
		)
	return Utils.success({"session": session.duplicate(true), "monitor": monitor, "execution_allowed": true})

static func full_handoff(session: Dictionary, artifact: Dictionary, descriptor: Dictionary) -> Dictionary:
	var checked := validate(session, artifact)
	if not bool(checked.get("success", false)):
		return checked
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if String(descriptor["descriptor_hash"]) != String(artifact["rom_descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_HANDOFF_DESCRIPTOR_MISMATCH")
	return _full_handoff_from_state(descriptor, session["rom_state"], String(artifact["source_binding_checksum"]))

static func project_full_state(
	full_model: Dictionary,
	descriptor: Dictionary,
	full_values: Array,
	time_s: float,
	step_index: int
) -> Dictionary:
	var checked := FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return checked
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if String(descriptor["full_model_hash"]) != String(full_model["model_hash"]):
		return Utils.failure("DYNAMIC_ROM_PROJECTION_FULL_MODEL_MISMATCH")
	if full_values.size() != int(descriptor["full_state_count"]):
		return Utils.failure("DYNAMIC_ROM_PROJECTION_STATE_LENGTH_MISMATCH")
	for raw in full_values:
		if not Utils.is_finite_number(raw):
			return Utils.failure("DYNAMIC_ROM_PROJECTION_NONFINITE_STATE")
	var reduced: Array = []
	reduced.resize(int(descriptor["reduced_state_count"]))
	reduced.fill(0.0)
	for full_index in range(full_values.size()):
		var weighted := float(full_model["storage_nodes"][full_index]["storage_coefficient"]) * float(full_values[full_index])
		for reduced_index in range(reduced.size()):
			reduced[reduced_index] = float(reduced[reduced_index]) + float(descriptor["basis_matrix"][full_index][reduced_index]) * weighted
	var rom_state := RomState.create(String(descriptor["descriptor_hash"]), String(descriptor["reduced_state_schema_hash"]), time_s, step_index, reduced)
	if rom_state.is_empty():
		return Utils.failure("DYNAMIC_ROM_PROJECTED_STATE_CREATE_FAILED")
	var reconstructed := _reconstruct(descriptor, reduced)
	var max_error := 0.0
	var c_error_squared := 0.0
	for index in range(full_values.size()):
		var delta := float(full_values[index]) - float(reconstructed[index])
		max_error = maxf(max_error, absf(delta))
		c_error_squared += float(full_model["storage_nodes"][index]["storage_coefficient"]) * delta * delta
	return Utils.success({
		"rom_state": rom_state,
		"projection_error": max_error,
		"projection_error_c_norm": sqrt(maxf(0.0, c_error_squared)),
	})

static func _terminate_stale(session: Dictionary, artifact: Dictionary, descriptor: Dictionary, reason: String) -> Dictionary:
	var transitioned := Lifecycle.mark_stale(session["lifecycle"], artifact, reason, "REBUILD_REQUIRED")
	if not bool(transitioned.get("success", false)):
		return transitioned
	var next := session.duplicate(true)
	next["lifecycle"] = transitioned["details"]["lifecycle"]
	next["checksum"] = Utils.compute_checksum(next)
	var handoff := _full_handoff_from_state(descriptor, session["rom_state"], String(artifact["source_binding_checksum"]))
	return Utils.failure("DYNAMIC_ROM_STALE_EXECUTION_FORBIDDEN", {
		"session": next,
		"recovery": _recovery_payload("REBUILD_REQUIRED", "NONE", reason),
		"full_handoff": handoff.get("details", {}),
	})

static func _terminate_invalid(
	session: Dictionary,
	artifact: Dictionary,
	descriptor: Dictionary,
	reason: String,
	region_id: String,
	local_unbake_available: bool,
	cause
) -> Dictionary:
	var monitor := _force_monitor_invalid(session["runtime_monitor"], reason, int(session["rom_state"]["step_index"]) + 1)
	return _terminate_invalid_with_monitor(session, artifact, descriptor, monitor, reason, region_id, local_unbake_available, cause)

static func _terminate_invalid_with_monitor(
	session: Dictionary,
	artifact: Dictionary,
	descriptor: Dictionary,
	monitor: Dictionary,
	reason: String,
	region_id: String,
	local_unbake_available: bool,
	cause
) -> Dictionary:
	var recovery_action := "LOCAL_UNBAKE_REQUIRED" if local_unbake_available and region_id != "NONE" else "FULL_FALLBACK"
	var transitioned := Lifecycle.mark_invalid(session["lifecycle"], artifact, _upper_reason(reason), region_id, recovery_action)
	if not bool(transitioned.get("success", false)):
		return transitioned
	var next := session.duplicate(true)
	next["lifecycle"] = transitioned["details"]["lifecycle"]
	next["runtime_monitor"] = monitor
	next["checksum"] = Utils.compute_checksum(next)
	var handoff := _full_handoff_from_state(descriptor, session["rom_state"], String(artifact["source_binding_checksum"]))
	return Utils.failure("DYNAMIC_ROM_EXECUTION_INVALIDATED", {
		"cause": cause,
		"session": next,
		"recovery": _recovery_payload(recovery_action, region_id, _upper_reason(reason)),
		"full_handoff": handoff.get("details", {}),
	})

static func _full_handoff_from_state(descriptor: Dictionary, rom_state: Dictionary, source_binding_checksum: String) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = RomState.validate(rom_state)
	if not bool(checked.get("success", false)):
		return checked
	var full_values := _reconstruct(descriptor, rom_state["values"])
	var payload := {
		"source_binding_checksum": source_binding_checksum,
		"rom_descriptor_hash": String(descriptor["descriptor_hash"]),
		"rom_state_checksum": String(rom_state["checksum"]),
		"time_s": float(rom_state["time_s"]),
		"step_index": int(rom_state["step_index"]),
		"values": full_values,
		"full_state_hash": Utils.canonical_hash(full_values),
		"continuity_policy": "LAST_ACCEPTED_ROM_STATE_ONLY",
	}
	return Utils.success(payload)

static func _reconstruct(descriptor: Dictionary, reduced_values: Array) -> Array:
	var full: Array = []
	full.resize(int(descriptor["full_state_count"]))
	for full_index in range(full.size()):
		var value := 0.0
		for reduced_index in range(reduced_values.size()):
			value += float(descriptor["basis_matrix"][full_index][reduced_index]) * float(reduced_values[reduced_index])
		full[full_index] = value
	return full

static func _force_monitor_invalid(monitor: Dictionary, reason: String, step_index: int) -> Dictionary:
	var invalidated := RuntimeMonitor.invalidate(monitor, _upper_reason(reason), maxi(0, step_index))
	if not bool(invalidated.get("success", false)):
		return monitor
	return invalidated["details"]["monitor"]

static func _region_for_safety_failure(safety: Dictionary) -> String:
	if String(safety.get("error_code", "")) == "DYNAMIC_ROM_REFINEMENT_REQUIRED":
		return "region/dynamic/all"
	return "NONE"

static func _recovery_payload(action: String, region_id: String, reason: String) -> Dictionary:
	return {
		"action": action,
		"region_id": region_id,
		"reason": reason,
		"local_unbake_contract": "B0.2-D" if action == "LOCAL_UNBAKE_REQUIRED" else "NONE",
		"canonical_state_owner": "PHYSICAL_SOURCE",
		"rom_state_role": "DERIVED_HANDOFF_ONLY",
	}

static func _upper_reason(value) -> String:
	var text := String(value).strip_edges().to_upper()
	var output := ""
	for character in text:
		var c := String(character)
		output += c if "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".find(c) >= 0 else "_"
	while output.find("__") >= 0:
		output = output.replace("__", "_")
	return output if not output.is_empty() else "UNKNOWN_INVALIDATION"
