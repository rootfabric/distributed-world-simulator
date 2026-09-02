extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const RuntimeCertificate = preload("res://scripts/research/fabric_bake0/rom_runtime_certificate_v1.gd")
const RuntimeMonitor = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_monitor_v1.gd")
const ExecutionArtifact = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_artifact_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_lifecycle_v1.gd")
const ExecutionRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

const DT := 0.01
var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var built := _build()
	if built.is_empty():
		_finish()
		return
	_test_execution_artifact(built)
	_test_lifecycle_contract(built)
	_test_governed_runtime(built)
	_test_session_determinism(built)
	_test_source_stale_is_sticky(built)
	_test_refinement_to_local_unbake(built)
	_test_residual_certificate_invalidation(built)
	_test_constraint_invalidation_to_local_unbake(built)
	_test_full_handoff_and_new_session(built)
	_test_fail_closed_tamper(built)
	_finish()

func _build() -> Dictionary:
	var fixture := Fixture.build("ZERO")
	var full := FullCompiler.compile(fixture["request"])
	_check(bool(full.get("success", false)), "B0.4-D FULL predecessor compiles")
	if not bool(full.get("success", false)):
		return {}
	var reduced := ROMCompiler.compile(full["model"])
	_check(bool(reduced.get("success", false)), "B0.4-D ROM predecessor compiles")
	if not bool(reduced.get("success", false)):
		return {}
	var certification := Certification.create(full["model"], reduced["descriptor"])
	_check(not certification.is_empty(), "B0.4-D C certification creates")
	if certification.is_empty():
		return {}
	var artifact := ExecutionArtifact.create(
		full["model"], reduced["descriptor"], reduced["artifact_binding"], certification,
		"artifact/dynamic-rom-b0-4-d-r1", 1
	)
	_check(not artifact.is_empty(), "B0.4-D execution artifact creates")
	if artifact.is_empty():
		return {}
	return {
		"fixture": fixture,
		"full_model": full["model"],
		"descriptor": reduced["descriptor"],
		"binding": reduced["artifact_binding"],
		"certification": certification,
		"artifact": artifact,
	}

func _test_execution_artifact(built: Dictionary) -> void:
	var artifact: Dictionary = built["artifact"]
	_check(bool(ExecutionArtifact.validate(artifact).get("success", false)), "execution artifact validates")
	_check(bool(artifact["execution_ready"]), "D artifact is execution-ready")
	_check(String(artifact["source_binding_checksum"]) == String(built["descriptor"]["source_binding_checksum"]), "D artifact binds source")
	_check(String(artifact["rom_descriptor_hash"]) == String(built["descriptor"]["descriptor_hash"]), "D artifact binds ROM descriptor")
	_check(String(artifact["runtime_certification_hash"]) == String(built["certification"]["certification_hash"]), "D artifact binds C certification")
	_check(String(artifact["reduction_binding_hash"]) == String(built["binding"]["binding_hash"]), "D artifact binds immutable B reduction binding")
	_check(built["binding"]["execution_ready"] == false, "B binding remains permanently non-runtime-ready")
	_check(artifact["recovery_modes"] == ExecutionArtifact.RECOVERY_MODES, "D recovery modes frozen")
	_check(artifact["certified_components"] == ExecutionArtifact.CERTIFIED_COMPONENTS, "D certified components frozen")
	_check(bool(ExecutionArtifact.verify_bindings(
		artifact, built["full_model"], built["descriptor"], built["binding"], built["certification"]
	).get("success", false)), "execution artifact exact binding verification passes")

func _test_lifecycle_contract(built: Dictionary) -> void:
	var artifact: Dictionary = built["artifact"]
	var lifecycle := Lifecycle.create(artifact)
	_check(not lifecycle.is_empty(), "lifecycle CREATED creates")
	_check(String(lifecycle["state"]) == Lifecycle.CREATED, "initial lifecycle state CREATED")
	_check(not bool(Lifecycle.activate(lifecycle, artifact).get("success", false)), "CREATED cannot skip directly to ACTIVE")
	var certified := Lifecycle.certify(lifecycle, artifact)
	_check(bool(certified.get("success", false)), "CREATED -> CERTIFIED")
	if not bool(certified.get("success", false)):
		return
	lifecycle = certified["details"]["lifecycle"]
	_check(String(lifecycle["state"]) == Lifecycle.CERTIFIED, "state CERTIFIED exact")
	var ready := Lifecycle.mark_ready(lifecycle, artifact)
	_check(bool(ready.get("success", false)), "CERTIFIED -> READY")
	if not bool(ready.get("success", false)):
		return
	lifecycle = ready["details"]["lifecycle"]
	_check(String(lifecycle["state"]) == Lifecycle.READY, "state READY exact")
	var active := Lifecycle.activate(lifecycle, artifact)
	_check(bool(active.get("success", false)), "READY -> ACTIVE")
	if not bool(active.get("success", false)):
		return
	lifecycle = active["details"]["lifecycle"]
	_check(String(lifecycle["state"]) == Lifecycle.ACTIVE, "state ACTIVE exact")
	_check(int(lifecycle["activation_count"]) == 1, "activation count exact")
	_check(bool(Lifecycle.can_execute(lifecycle, artifact).get("success", false)), "ACTIVE lifecycle execution allowed")

func _test_governed_runtime(built: Dictionary) -> void:
	var started := _start(built)
	_check(bool(started.get("success", false)), "governed runtime starts")
	if not bool(started.get("success", false)):
		return
	var session: Dictionary = started["details"]["session"]
	_check(String(session["lifecycle"]["state"]) == Lifecycle.ACTIVE, "started runtime ACTIVE")
	_check(String(session["runtime_monitor"]["state"]) == RuntimeMonitor.ROM_ACTIVE, "started runtime monitor ACTIVE")
	var source_hash := String(built["artifact"]["source_binding_checksum"])
	for step_index in range(18):
		var result := ExecutionRuntime.step(
			session, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
			_safe_flows(step_index), DT, source_hash, false
		)
		_check(bool(result.get("success", false)), "governed safe step %d accepted" % step_index)
		if not bool(result.get("success", false)):
			return
		session = result["details"]["session"]
		_check(String(result["details"]["status"]) == "DYNAMIC_ROM_STEP_ACCEPTED", "accepted step status exact")
		_check(bool(result["details"]["runtime_certificate"]["valid"]), "accepted step has valid runtime certificate")
		_check(String(session["lifecycle"]["state"]) == Lifecycle.ACTIVE, "safe step remains ACTIVE")
		_check(String(session["runtime_monitor"]["state"]) == RuntimeMonitor.ROM_ACTIVE, "safe step monitor remains ACTIVE")
		_check(int(session["rom_state"]["step_index"]) == step_index + 1, "accepted ROM step index advances")
		_check(int(session["lifecycle"]["last_accepted_step"]) == step_index + 1, "lifecycle accepted step tracks ROM")
	_check(absf(float(session["elapsed_s"]) - 18.0 * DT) <= 1.0e-15, "session elapsed time governed by accepted state")
	_check(not session["last_runtime_certificate"].is_empty(), "last runtime certificate retained")

func _test_session_determinism(built: Dictionary) -> void:
	var started_a := _start(built)
	var started_b := _start(built)
	_check(bool(started_a.get("success", false)) and bool(started_b.get("success", false)), "deterministic twin sessions start")
	if not bool(started_a.get("success", false)) or not bool(started_b.get("success", false)):
		return
	var a: Dictionary = started_a["details"]["session"]
	var b: Dictionary = started_b["details"]["session"]
	var source_hash := String(built["artifact"]["source_binding_checksum"])
	for step_index in range(10):
		var flows := _safe_flows(step_index)
		var ra := ExecutionRuntime.step(
			a, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
			flows, DT, source_hash, false
		)
		var rb := ExecutionRuntime.step(
			b, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
			flows, DT, source_hash, false
		)
		_check(bool(ra.get("success", false)) and bool(rb.get("success", false)), "deterministic twin step %d executes" % step_index)
		if not bool(ra.get("success", false)) or not bool(rb.get("success", false)):
			return
		a = ra["details"]["session"]
		b = rb["details"]["session"]
	_check(String(a["rom_state"]["checksum"]) == String(b["rom_state"]["checksum"]), "twin ROM state identity deterministic")
	_check(String(a["lifecycle"]["checksum"]) == String(b["lifecycle"]["checksum"]), "twin lifecycle identity deterministic")
	_check(String(a["runtime_monitor"]["checksum"]) == String(b["runtime_monitor"]["checksum"]), "twin runtime monitor identity deterministic")
	_check(String(a["last_runtime_certificate"]["checksum"]) == String(b["last_runtime_certificate"]["checksum"]), "twin runtime certificate identity deterministic")
	_check(String(a["checksum"]) == String(b["checksum"]), "twin execution session checksum deterministic")

func _test_source_stale_is_sticky(built: Dictionary) -> void:
	var started := _start(built)
	if not bool(started.get("success", false)):
		_check(false, "stale test runtime starts")
		return
	var session: Dictionary = started["details"]["session"]
	var source_hash := String(built["artifact"]["source_binding_checksum"])
	var safe := ExecutionRuntime.step(
		session, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
		_safe_flows(0), DT, source_hash, false
	)
	_check(bool(safe.get("success", false)), "pre-stale step accepted")
	if not bool(safe.get("success", false)):
		return
	session = safe["details"]["session"]
	var accepted_checksum := String(session["rom_state"]["checksum"])
	var changed_source := "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
	if changed_source == source_hash:
		changed_source = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
	var stale := ExecutionRuntime.step(
		session, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
		_safe_flows(1), DT, changed_source, false
	)
	_check(not bool(stale.get("success", false)), "source revision mismatch forbids execution")
	_check(String(stale.get("error_code", "")) == "DYNAMIC_ROM_STALE_EXECUTION_FORBIDDEN", "stale rejection code exact")
	if bool(stale.get("success", false)):
		return
	var stale_session: Dictionary = stale["details"]["session"]
	_check(String(stale_session["lifecycle"]["state"]) == Lifecycle.STALE, "source revision transitions ACTIVE -> STALE")
	_check(String(stale_session["lifecycle"]["recovery_action"]) == "REBUILD_REQUIRED", "stale recovery requires rebuild")
	_check(String(stale["details"]["recovery"]["canonical_state_owner"]) == "PHYSICAL_SOURCE", "recovery keeps PhysicalSource canonical")
	_check(String(stale_session["rom_state"]["checksum"]) == accepted_checksum, "rejected stale step does not advance ROM state")
	var retry := ExecutionRuntime.step(
		stale_session, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
		_safe_flows(2), DT, source_hash, false
	)
	_check(not bool(retry.get("success", false)), "STALE lifecycle cannot silently reactivate")
	_check(String(retry.get("error_code", "")) == "DYNAMIC_ROM_EXECUTION_FORBIDDEN", "sticky STALE execution rejection exact")

func _test_refinement_to_local_unbake(built: Dictionary) -> void:
	var started := _start(built)
	if not bool(started.get("success", false)):
		_check(false, "refinement runtime starts")
		return
	var session: Dictionary = started["details"]["session"]
	var source_hash := String(built["artifact"]["source_binding_checksum"])
	var result := ExecutionRuntime.step(
		session, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
		_flows([0.96, 0.0, 0.0, 0.0]), DT, source_hash, true
	)
	_check(not bool(result.get("success", false)), "refinement guard stops ROM step")
	_check(String(result.get("error_code", "")) == "DYNAMIC_ROM_EXECUTION_INVALIDATED", "refinement invalidation code exact")
	if bool(result.get("success", false)):
		return
	var invalid_session: Dictionary = result["details"]["session"]
	_check(String(invalid_session["lifecycle"]["state"]) == Lifecycle.INVALID, "refinement transitions ACTIVE -> INVALID")
	_check(String(invalid_session["runtime_monitor"]["state"]) == RuntimeMonitor.ROM_INVALID, "lifecycle and runtime monitor invalidate together")
	_check(String(invalid_session["lifecycle"]["terminal_region_id"]) == "region/dynamic/all", "refinement region explicit")
	_check(String(invalid_session["lifecycle"]["recovery_action"]) == "LOCAL_UNBAKE_REQUIRED", "bounded local unbake preferred when available")
	_check(String(result["details"]["recovery"]["local_unbake_contract"]) == "B0.2-D", "B0.2-D recovery contract explicit")
	_check(String(result["details"]["recovery"]["canonical_state_owner"]) == "PHYSICAL_SOURCE", "local unbake recovery does not transfer canonical ownership")
	_check(int(invalid_session["rom_state"]["step_index"]) == 0, "rejected refinement candidate never commits")
	var retry := ExecutionRuntime.step(
		invalid_session, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
		_flows([0.0, 0.0, 0.0, 0.0]), DT, source_hash, true
	)
	_check(not bool(retry.get("success", false)), "INVALID lifecycle cannot silently continue")
	_check(String(retry.get("error_code", "")) == "DYNAMIC_ROM_EXECUTION_FORBIDDEN", "sticky INVALID execution rejection exact")

func _test_residual_certificate_invalidation(built: Dictionary) -> void:
	var started := _start(built)
	if not bool(started.get("success", false)):
		_check(false, "certificate invalidation runtime starts")
		return
	var session: Dictionary = started["details"]["session"]
	var thresholds := Certification.runtime_component_thresholds()
	var invalid_certificate := RuntimeCertificate.create(
		String(built["artifact"]["source_binding_checksum"]),
		String(built["artifact"]["rom_descriptor_hash"]),
		float(thresholds["state"]) * 1.1,
		float(thresholds["state"]) * 1.1,
		0.0, 0.0, 0.0, thresholds, 0.0
	)
	_check(not invalid_certificate.is_empty(), "synthetic over-threshold certificate creates")
	_check(not bool(invalid_certificate["valid"]), "synthetic certificate invalid")
	var observed := ExecutionRuntime.observe_runtime_certificate(
		session, built["artifact"], built["descriptor"], invalid_certificate,
		String(built["artifact"]["source_binding_checksum"]), 1, false
	)
	_check(not bool(observed.get("success", false)), "invalid residual certificate terminates execution")
	_check(String(observed.get("error_code", "")) == "DYNAMIC_ROM_EXECUTION_INVALIDATED", "residual invalidation code exact")
	if bool(observed.get("success", false)):
		return
	var invalid_session: Dictionary = observed["details"]["session"]
	_check(String(invalid_session["lifecycle"]["state"]) == Lifecycle.INVALID, "residual certificate lifecycle INVALID")
	_check(String(invalid_session["lifecycle"]["terminal_reason"]) == "STATE_RESIDUAL_EXCEEDED", "residual invalidation reason preserved")
	_check(String(invalid_session["lifecycle"]["recovery_action"]) == "FULL_FALLBACK", "FULL fallback selected without local unbake")
	_check(String(observed["details"]["full_handoff"]["continuity_policy"]) == "LAST_ACCEPTED_ROM_STATE_ONLY", "fallback handoff excludes rejected candidate")

func _test_constraint_invalidation_to_local_unbake(built: Dictionary) -> void:
	var started := _start(built)
	if not bool(started.get("success", false)):
		_check(false, "constraint invalidation runtime starts")
		return
	var session: Dictionary = started["details"]["session"]
	var thresholds := Certification.runtime_component_thresholds()
	var invalid_certificate := RuntimeCertificate.create(
		String(built["artifact"]["source_binding_checksum"]),
		String(built["artifact"]["rom_descriptor_hash"]),
		float(thresholds["constraint"]) * 2.0,
		0.0, 0.0, 0.0, float(thresholds["constraint"]) * 2.0, thresholds, 0.0
	)
	_check(not invalid_certificate.is_empty(), "constraint over-threshold certificate creates")
	_check(String(invalid_certificate["reason"]) == "CONSTRAINT_RESIDUAL_EXCEEDED", "constraint certificate reason exact")
	var observed := ExecutionRuntime.observe_runtime_certificate(
		session, built["artifact"], built["descriptor"], invalid_certificate,
		String(built["artifact"]["source_binding_checksum"]), 1, true
	)
	_check(not bool(observed.get("success", false)), "constraint residual terminates ROM execution")
	if bool(observed.get("success", false)):
		return
	var invalid_session: Dictionary = observed["details"]["session"]
	_check(String(invalid_session["lifecycle"]["terminal_reason"]) == "CONSTRAINT_RESIDUAL_EXCEEDED", "constraint invalidation reason preserved")
	_check(String(invalid_session["lifecycle"]["recovery_action"]) == "LOCAL_UNBAKE_REQUIRED", "constraint exit requests local unbake when available")
	_check(String(observed["details"]["recovery"]["local_unbake_contract"]) == "B0.2-D", "constraint recovery wired to B0.2-D")

func _test_full_handoff_and_new_session(built: Dictionary) -> void:
	var started := _start(built)
	if not bool(started.get("success", false)):
		_check(false, "handoff runtime starts")
		return
	var session: Dictionary = started["details"]["session"]
	var source_hash := String(built["artifact"]["source_binding_checksum"])
	for step_index in range(8):
		var result := ExecutionRuntime.step(
			session, built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"],
			_safe_flows(step_index), DT, source_hash, false
		)
		_check(bool(result.get("success", false)), "handoff predecessor safe step %d" % step_index)
		if not bool(result.get("success", false)):
			return
		session = result["details"]["session"]
	var handoff := ExecutionRuntime.full_handoff(session, built["artifact"], built["descriptor"])
	_check(bool(handoff.get("success", false)), "FULL handoff reconstructs from last accepted ROM state")
	if not bool(handoff.get("success", false)):
		return
	var full_values: Array = handoff["details"]["values"]
	_check(full_values.size() == int(built["descriptor"]["full_state_count"]), "handoff has complete FULL state")
	_check(String(handoff["details"]["rom_state_checksum"]) == String(session["rom_state"]["checksum"]), "handoff identifies exact accepted ROM state")
	var rebuilt_artifact := ExecutionArtifact.create(
		built["full_model"], built["descriptor"], built["binding"], built["certification"],
		"artifact/dynamic-rom-b0-4-d-rebuild-r2", 2
	)
	_check(not rebuilt_artifact.is_empty(), "fresh rebuild generation artifact creates")
	_check(String(rebuilt_artifact["artifact_hash"]) != String(built["artifact"]["artifact_hash"]), "rebuild generation has fresh artifact identity")
	var resumed := ExecutionRuntime.start_from_full_handoff(
		rebuilt_artifact, built["full_model"], built["descriptor"], built["binding"], built["certification"],
		full_values, float(handoff["details"]["time_s"]), int(handoff["details"]["step_index"])
	)
	_check(bool(resumed.get("success", false)), "new rebuild execution session can project a FULL handoff")
	if not bool(resumed.get("success", false)):
		return
	_check(float(resumed["details"]["projection_error_c_norm"]) <= ExecutionRuntime.HANDOFF_PROJECTION_C_NORM_TOLERANCE, "ROM->FULL->ROM handoff C-norm projection certified")
	var resumed_session: Dictionary = resumed["details"]["session"]
	_check(String(resumed_session["lifecycle"]["state"]) == Lifecycle.ACTIVE, "new post-rebuild session ACTIVE")
	_check(int(resumed_session["lifecycle"]["activation_count"]) == 1, "new session has fresh activation identity")
	_check(int(resumed_session["rom_state"]["step_index"]) == int(session["rom_state"]["step_index"]), "handoff preserves step index")
	_check(absf(float(resumed_session["rom_state"]["time_s"]) - float(session["rom_state"]["time_s"])) <= 1.0e-15, "handoff preserves time")
	var max_delta := _max_abs_delta(resumed_session["rom_state"]["values"], session["rom_state"]["values"])
	_check(max_delta <= 1.0e-10, "handoff preserves reduced state through full representation")
	var outside_values: Array = full_values.duplicate()
	outside_values[7] = float(outside_values[7]) + 0.1
	var unsafe_resume := ExecutionRuntime.start_from_full_handoff(
		rebuilt_artifact, built["full_model"], built["descriptor"], built["binding"], built["certification"],
		outside_values, float(handoff["details"]["time_s"]), int(handoff["details"]["step_index"])
	)
	_check(not bool(unsafe_resume.get("success", false)), "arbitrary FULL state outside ROM subspace cannot silently resume")
	_check(String(unsafe_resume.get("error_code", "")) == "DYNAMIC_ROM_HANDOFF_PROJECTION_OUTSIDE_CERTIFIED_SUBSPACE", "outside-subspace resume fails closed")

func _test_fail_closed_tamper(built: Dictionary) -> void:
	var artifact: Dictionary = built["artifact"].duplicate(true)
	artifact["runtime_certification_hash"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	artifact["artifact_hash"] = Utils.canonical_hash(_artifact_payload(artifact))
	artifact["checksum"] = Utils.compute_checksum(artifact)
	_check(bool(ExecutionArtifact.validate(artifact).get("success", false)), "self-consistent foreign artifact still structurally valid")
	var checked := ExecutionArtifact.verify_bindings(
		artifact, built["full_model"], built["descriptor"], built["binding"], built["certification"]
	)
	_check(not bool(checked.get("success", false)), "foreign certification binding rejected before execution")
	_check(String(checked.get("error_code", "")) == "DYNAMIC_ROM_EXECUTION_ARTIFACT_BINDING_MISMATCH", "foreign certification binding code exact")
	var started := _start(built)
	if not bool(started.get("success", false)):
		_check(false, "tamper session starts")
		return
	var session: Dictionary = started["details"]["session"]
	var tampered_session := session.duplicate(true)
	tampered_session["elapsed_s"] = 1.0
	tampered_session["checksum"] = Utils.compute_checksum(tampered_session)
	var session_check := ExecutionRuntime.validate(tampered_session, built["artifact"])
	_check(not bool(session_check.get("success", false)), "session time/state mismatch fails closed")
	_check(String(session_check.get("error_code", "")) == "DYNAMIC_ROM_EXECUTION_SESSION_TIME_MISMATCH", "session time mismatch code exact")

func _start(built: Dictionary) -> Dictionary:
	return ExecutionRuntime.start(
		built["artifact"], built["full_model"], built["descriptor"], built["binding"], built["certification"]
	)

func _safe_flows(step_index: int) -> Dictionary:
	var t := DT * float(step_index + 1)
	return _flows([
		0.20 * sin(TAU * 0.35 * t),
		0.08 * sin(TAU * 0.11 * t),
		0.04 * float(int((step_index * 37 + 11) % 101) - 50) / 50.0,
		0.03 * sin(TAU * (0.08 * t + 0.08 * t * t)),
	])

func _flows(values: Array) -> Dictionary:
	return {
		"port/electrical/000-left": float(values[0]),
		"port/electrical/170-mid-a": float(values[1]),
		"port/electrical/341-mid-b": float(values[2]),
		"port/electrical/511-right": float(values[3]),
	}

func _max_abs_delta(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var result := 0.0
	for index in range(a.size()):
		result = maxf(result, absf(float(a[index]) - float(b[index])))
	return result

func _artifact_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("artifact_hash")
	payload.erase("checksum")
	return payload

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC-BAKE B0.4-D Runtime Execution / Lifecycle Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("B0.4-D: %s" % failure)
	print("FABRIC-BAKE B0.4-D Runtime Execution / Lifecycle Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
