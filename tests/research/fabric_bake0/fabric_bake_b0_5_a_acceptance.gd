extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fabric = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const PhysicalBridge = preload("res://scripts/research/fabric_bake0/dynamic_rom_physical_bake_bridge_v1.gd")
const PhysicalArtifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const P0Transition = preload("res://scripts/research/fabric_bake0/hybrid_transition_descriptor_v1.gd")
const ExecutableMode = preload("res://scripts/research/fabric_bake0/hybrid_executable_mode_v1.gd")
const ExecutableCache = preload("res://scripts/research/fabric_bake0/hybrid_executable_cache_entry_v1.gd")
const ExecutableTransition = preload("res://scripts/research/fabric_bake0/hybrid_executable_transition_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/hybrid_bake_executable_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

const DT := 0.01
const MODE_A := "mode/hybrid/a"
const MODE_B := "mode/hybrid/b"
const TRANSITION_ID := "transition/hybrid/release"

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var subject := _build_subject()
	if subject.is_empty():
		_finish()
		return
	_test_contract_layers(subject)
	_test_fabric_owned_jump_and_lazy_compile(subject)
	_test_exact_cache_hit_replay(subject)
	_test_duplicate_event_rejection(subject)
	_test_stale_cache_fail_closed(subject)
	_test_unknown_mode_fallback(subject)
	_test_b0_4_runtime_guard_authority(subject)
	_test_determinism(subject)
	_finish()

func _build_subject() -> Dictionary:
	var fixture := Fixture.build("ZERO")
	var full := FullCompiler.compile(fixture["request"])
	_check(bool(full.get("success", false)), "FULL predecessor compiles")
	if not bool(full.get("success", false)):
		return {}
	var rom := ROMCompiler.compile(full["model"])
	_check(bool(rom.get("success", false)), "B0.4 ROM predecessor compiles")
	if not bool(rom.get("success", false)):
		return {}
	var certification := Certification.create(full["model"], rom["descriptor"])
	_check(not certification.is_empty(), "B0.4 runtime certification creates")
	if certification.is_empty():
		return {}

	var a_bundle_result := PhysicalBridge.compile_bundle(
		full["model"], rom["descriptor"], rom["artifact_binding"], certification,
		"bake/hybrid/mode-a", "artifact/hybrid/mode-a", 1
	)
	var b_bundle_result := PhysicalBridge.compile_bundle(
		full["model"], rom["descriptor"], rom["artifact_binding"], certification,
		"bake/hybrid/mode-b", "artifact/hybrid/mode-b", 2
	)
	_check(bool(a_bundle_result.get("success", false)), "mode A common B0.4 PhysicalBakeArtifact builds")
	_check(bool(b_bundle_result.get("success", false)), "mode B common B0.4 PhysicalBakeArtifact builds")
	if not bool(a_bundle_result.get("success", false)) or not bool(b_bundle_result.get("success", false)):
		return {}
	var a_bundle: Dictionary = a_bundle_result["details"]["bundle"]
	var b_bundle: Dictionary = b_bundle_result["details"]["bundle"]

	var a_blueprint := _blueprint(MODE_A, "hybrid-mode/executable-a", a_bundle, full["model"], rom, certification, "a")
	var b_blueprint := _blueprint(MODE_B, "hybrid-mode/executable-b", b_bundle, full["model"], rom, certification, "b")
	var compiled_a := Runtime.compile_mode(a_blueprint)
	_check(bool(compiled_a.get("success", false)), "mode A executable hybrid wrapper compiles eagerly")
	if not bool(compiled_a.get("success", false)):
		return {}
	var a_package: Dictionary = compiled_a["details"]["package"]
	var registry_result := Runtime.register_mode({}, a_package)
	_check(bool(registry_result.get("success", false)), "mode A executable cache registers")
	if not bool(registry_result.get("success", false)):
		return {}
	var registry: Dictionary = registry_result["details"]["registry"]

	var preview_b := Runtime.preview_mode(b_blueprint)
	_check(bool(preview_b.get("success", false)), "mode B identity can be previewed without executable wrapper")
	if not bool(preview_b.get("success", false)):
		return {}
	var transition := _transition(
		a_package,
		preview_b["details"]["mode_descriptor"],
		b_bundle,
		String(certification["conservation_envelope"]["checksum"])
	)
	_check(not transition.is_empty(), "P0 transition binds real A/B StateMapping and ReconstructionDescriptor")
	if transition.is_empty():
		return {}

	return {
		"fixture": fixture,
		"full_model": full["model"],
		"rom_descriptor": rom["descriptor"],
		"reduction_binding": rom["artifact_binding"],
		"certification": certification,
		"a_bundle": a_bundle,
		"b_bundle": b_bundle,
		"a_blueprint": a_blueprint,
		"b_blueprint": b_blueprint,
		"a_package": a_package,
		"registry": registry,
		"transition": transition,
	}

func _test_contract_layers(subject: Dictionary) -> void:
	var a: Dictionary = subject["a_package"]
	_check(bool(Runtime.validate_package(a).get("success", false)), "mode A executable package validates")
	_check(bool(ExecutableMode.validate(a["mode_contract"], a["mode_descriptor"], a["physical_bundle"]).get("success", false)), "B0.5-A mode contract validates")
	_check(bool(ExecutableCache.validate(a["executable_cache_entry"]).get("success", false)), "B0.5-A executable cache validates")
	_check(String(a["mode_descriptor"]["execution_qualification"]) == "B0_4_INTERFACE_BOUND", "P0 mode descriptor remains B0.4-bound")
	_check(String(a["p0_cache_entry"]["execution_qualification"]) == "PREFLIGHT_ONLY", "P0 cache remains preflight-only")
	_check(String(a["mode_contract"]["execution_qualification"]) == ExecutableMode.QUALIFICATION, "new executable mode layer is explicit")
	_check(String(a["executable_cache_entry"]["execution_qualification"]) == ExecutableCache.QUALIFICATION, "new executable cache layer is explicit")
	_check(bool(a["executable_cache_entry"]["derived_only"]), "executable cache remains derived-only")
	_check(bool(PhysicalArtifact.validate(a["physical_bundle"]["physical_artifact"]).get("success", false)), "mode A uses common PhysicalBakeArtifact")
	_check(bool(PhysicalArtifact.validate(subject["b_bundle"]["physical_artifact"]).get("success", false)), "mode B uses common PhysicalBakeArtifact")
	_check(String(a["mode_contract"]["state_mapping_checksum"]) == String(a["physical_bundle"]["physical_artifact"]["state_mapping"]["checksum"]), "mode A binds real StateMapping")
	_check(String(a["mode_contract"]["reconstruction_descriptor_checksum"]) == String(a["physical_bundle"]["physical_artifact"]["reconstruction_descriptor"]["checksum"]), "mode A binds real ReconstructionDescriptor")
	_check(String(subject["transition"]["execution_qualification"]) == "PREFLIGHT_ONLY", "P0 transition remains preflight-only")
	_check(String(subject["transition"]["event_ownership"]["owner"]) == "FABRIC_PHYSICAL_EVENT", "FABRIC remains physical event owner")
	_check(String(subject["transition"]["event_ownership"]["semantics"]) == "EXACTLY_ONCE", "P0 exactly-once semantics preserved")
	_check(String(subject["transition"]["event_ownership"]["canonical_revision_policy"]) == "EXTERNAL_AUTHORITY_ONLY", "hybrid reset cannot seize canonical revision")

func _test_fabric_owned_jump_and_lazy_compile(subject: Dictionary) -> void:
	var run := _run_first_transition(subject, subject["registry"])
	_check(bool(run.get("success", false)), "FABRIC-owned A→B executable transition succeeds")
	if not bool(run.get("success", false)):
		return
	var details: Dictionary = run["details"]
	_check(String(details["cache_action"]) == "LAZY_COMPILED", "first mode-B encounter lazily compiles executable hybrid wrapper")
	_check(String(details["session"]["current_mode_id"]) == MODE_B, "hybrid session commits mode B")
	_check(int(details["session"]["transition_count"]) == 1, "exactly one hybrid transition committed")
	_check(details["session"]["event_ledger"].size() == 1, "exactly one FABRIC event ledger record")
	_check(String(details["event_id"]) == "fabric0/instant/000001", "FABRIC physical event identity propagated")
	_check(float(details["projection_error_c_norm"]) <= 1.0e-10, "A reconstruction → B StateMapping handoff certified")
	_check(String(details["transition_contract"]["execution_qualification"]) == ExecutableTransition.QUALIFICATION, "executable transition wrapper explicit")
	_check(String(details["transition_contract"]["p0_transition"]["execution_qualification"]) == "PREFLIGHT_ONLY", "P0 transition not mutated into executable contract")
	_check(bool(ExecutableTransition.validate(
		details["transition_contract"],
		subject["a_package"]["mode_contract"],
		details["target_package"]["mode_contract"]
	).get("success", false)), "executable transition validates against both B0.4-backed modes")
	_check(details["registry"].size() == 2, "lazy mode-B compile adds exactly one cache entry")

	var b_flow := Runtime.flow_step(
		details["session"],
		details["target_package"],
		_safe_flows(9),
		DT
	)
	_check(bool(b_flow.get("success", false)), "mode B continues FLOW through common B0.4 gate")
	if bool(b_flow.get("success", false)):
		_check(String(b_flow["details"]["status"]) == "B0_5_A_FLOW_ACCEPTED", "mode B FLOW status exact")
		_check(not b_flow["details"]["runtime_certificate"].is_empty(), "mode-local B0.4 runtime certificate remains active")

func _test_exact_cache_hit_replay(subject: Dictionary) -> void:
	var first := _run_first_transition(subject, subject["registry"])
	if not bool(first.get("success", false)):
		_check(false, "cache-hit prerequisite first transition succeeds")
		return
	var populated: Dictionary = first["details"]["registry"]
	var replay := _run_first_transition(subject, populated)
	_check(bool(replay.get("success", false)), "second deterministic A→B replay succeeds")
	if not bool(replay.get("success", false)):
		return
	_check(String(replay["details"]["cache_action"]) == "EXACT_CACHE_HIT", "second mode-B encounter is exact cache hit")
	_check(String(replay["details"]["target_package"]["package_hash"]) == String(first["details"]["target_package"]["package_hash"]), "cache hit reuses exact compiled mode package")
	_check(String(replay["details"]["transition_contract"]["transition_contract_hash"]) == String(first["details"]["transition_contract"]["transition_contract_hash"]), "transition wrapper deterministic across replay")
	_check(String(replay["details"]["event_hash"]) == String(first["details"]["event_hash"]), "FABRIC event replay identity deterministic")

func _test_duplicate_event_rejection(subject: Dictionary) -> void:
	var first := _run_first_transition(subject, subject["registry"])
	if not bool(first.get("success", false)):
		_check(false, "duplicate-event prerequisite transition succeeds")
		return
	var duplicate := Runtime.consume_fabric_event(
		first["details"]["session"],
		first["details"]["target_package"],
		subject["transition"],
		first["details"]["fabric_event"],
		subject["b_blueprint"],
		first["details"]["registry"]
	)
	_check(not bool(duplicate.get("success", false)), "same FABRIC physical event cannot commit twice")
	_check(String(duplicate.get("error_code", "")) == "B0_5_A_DUPLICATE_FABRIC_PHYSICAL_EVENT", "duplicate event rejection exact")

func _test_stale_cache_fail_closed(subject: Dictionary) -> void:
	var first := _run_first_transition(subject, subject["registry"])
	if not bool(first.get("success", false)):
		_check(false, "stale-cache prerequisite transition succeeds")
		return
	var b_key := String(first["details"]["target_package"]["mode_descriptor"]["cache_key"])
	var invalidated := Runtime.invalidate_cached_mode(first["details"]["registry"], b_key, "DEPENDENCY_CHANGED")
	_check(bool(invalidated.get("success", false)), "mode-B executable cache invalidates")
	if not bool(invalidated.get("success", false)):
		return
	var stale_registry: Dictionary = invalidated["details"]["registry"]
	_check(String(stale_registry[b_key]["executable_cache_entry"]["validity_state"]) == "STALE", "invalidated executable cache becomes STALE")
	var start_a := Runtime.start(subject["a_package"])
	_check(bool(start_a.get("success", false)), "fresh A session starts for stale cache probe")
	if not bool(start_a.get("success", false)):
		return
	var advanced_a := _advance_a_to_event(start_a["details"]["session"], subject["a_package"])
	if not bool(advanced_a.get("success", false)):
		_check(false, "A reaches event for stale cache probe")
		return
	var fabric_event := _fabric_event()
	var result := Runtime.consume_fabric_event(
		advanced_a["session"], subject["a_package"], subject["transition"],
		fabric_event, subject["b_blueprint"], stale_registry
	)
	_check(not bool(result.get("success", false)), "stale mode-B cache cannot execute")
	_check(String(result.get("error_code", "")) == "B0_5_A_TARGET_MODE_UNAVAILABLE", "stale cache returns target unavailable")
	_check(String(result["details"]["fallback"]) == "FULL", "stale cache fails to FULL")
	_check(String(result["details"]["reason"]) == "DEPENDENCY_CHANGED", "stale cache reason preserved")

func _test_unknown_mode_fallback(subject: Dictionary) -> void:
	var first := _run_first_transition(subject, subject["registry"])
	if not bool(first.get("success", false)):
		_check(false, "unknown-mode prerequisite transition succeeds")
		return
	var physical: Dictionary = subject["a_bundle"]["physical_artifact"]
	var unknown := ModeSignature.create(
		String(physical["source_binding"]["frontier_hash"]),
		String(physical["source_binding"]["fabric_graph_hash"]),
		["relation/hybrid/unknown-c"],
		["active-set/hybrid/c"],
		String(physical["boundary_contract"]["contract_hash"]),
		[
			{"dependency_id": "dependency/b04/artifact", "version_hash": String(physical["checksum"])},
			{"dependency_id": "dependency/sync3/closure", "version_hash": Utils.canonical_hash({"sync3": "28fdc16d12ddf1233a82103cb290c831342a3022"})},
		],
		Runtime.COMPILER_VERSION
	)
	_check(not unknown.is_empty(), "unknown mode-C exact signature creates")
	var fallback := Runtime.unknown_mode_fallback(unknown, first["details"]["registry"], "FULL")
	_check(bool(fallback.get("success", false)), "unknown C fail-closed decision succeeds")
	_check(String(fallback["details"]["action"]) == "FALLBACK", "unknown C action is fallback")
	_check(String(fallback["details"]["fallback"]) == "FULL", "unknown C falls back FULL")
	_check(not bool(fallback["details"]["nearest_mode_reuse"]), "unknown C never nearest-matches A/B cache")
	_check(not bool(fallback["details"]["execution_authorized"]), "unknown C never executes")

func _test_b0_4_runtime_guard_authority(subject: Dictionary) -> void:
	var first := _run_first_transition(subject, subject["registry"])
	if not bool(first.get("success", false)):
		_check(false, "B0.4 guard prerequisite transition succeeds")
		return
	var unsafe := Runtime.flow_step(
		first["details"]["session"],
		first["details"]["target_package"],
		_flows([1.05, 0.0, 0.0, 0.0]),
		DT
	)
	_check(not bool(unsafe.get("success", false)), "B0.5-A cannot bypass mode-local B0.4 validity/refinement guard")
	_check(String(unsafe.get("error_code", "")) == "B0_5_A_MODE_EXECUTION_FAILED", "B0.4 guard failure wrapped exactly")
	_check(String(unsafe["details"]["fallback"]) == "REFINE_OR_FULL", "B0.4 guard breach routes to refine/full")

func _test_determinism(subject: Dictionary) -> void:
	var twin_a := Runtime.compile_mode(subject["a_blueprint"])
	var twin_b1 := Runtime.compile_mode(subject["b_blueprint"])
	var twin_b2 := Runtime.compile_mode(subject["b_blueprint"])
	_check(bool(twin_a.get("success", false)), "deterministic twin A compiles")
	_check(bool(twin_b1.get("success", false)) and bool(twin_b2.get("success", false)), "deterministic twin B compiles")
	if bool(twin_a.get("success", false)):
		_check(String(twin_a["details"]["package"]["package_hash"]) == String(subject["a_package"]["package_hash"]), "mode A package identity deterministic")
	if bool(twin_b1.get("success", false)) and bool(twin_b2.get("success", false)):
		_check(String(twin_b1["details"]["package"]["package_hash"]) == String(twin_b2["details"]["package"]["package_hash"]), "mode B package identity deterministic")
		_check(String(twin_b1["details"]["package"]["mode_descriptor"]["cache_key"]) == String(twin_b2["details"]["package"]["mode_descriptor"]["cache_key"]), "mode B cache key deterministic")

func _run_first_transition(subject: Dictionary, registry: Dictionary) -> Dictionary:
	var started := Runtime.start(subject["a_package"])
	if not bool(started.get("success", false)):
		return started
	var advanced := _advance_a_to_event(started["details"]["session"], subject["a_package"])
	if not bool(advanced.get("success", false)):
		return Utils.failure("TEST_A_FLOW_FAILED")
	var fabric_event := _fabric_event()
	var consumed := Runtime.consume_fabric_event(
		advanced["session"],
		subject["a_package"],
		subject["transition"],
		fabric_event,
		subject["b_blueprint"],
		registry
	)
	if not bool(consumed.get("success", false)):
		return consumed
	var details: Dictionary = consumed["details"].duplicate(true)
	details["fabric_event"] = fabric_event
	return Utils.success(details)

func _advance_a_to_event(session: Dictionary, package: Dictionary) -> Dictionary:
	var current := session
	for step in range(5):
		var advanced := Runtime.flow_step(current, package, _safe_flows(step), DT)
		if not bool(advanced.get("success", false)):
			return advanced
		current = advanced["details"]["session"]
	return {"success": true, "session": current}

func _fabric_event() -> Dictionary:
	var system := Fabric.new_system()
	var rate_dimension := Fabric.dim_div(Fabric.dim_dimensionless(), Fabric.dim_time())
	if not Fabric.add_state(system, "phase", 0.0, Fabric.dim_dimensionless(), 1.0):
		return {}
	if not Fabric.add_parameter(system, "rate", 1.0, rate_dimension):
		return {}
	if not Fabric.add_mode(system, MODE_A, {"phase": Fabric.expr_parameter("rate")}, []):
		return {}
	if not Fabric.add_mode(system, MODE_B, {"phase": Fabric.expr_constant(0.0, rate_dimension)}, []):
		return {}
	if not Fabric.set_initial_mode(system, MODE_A):
		return {}
	var transition := {
		"id": TRANSITION_ID,
		"from_modes": [MODE_A],
		"to_mode": MODE_B,
		"guard": {
			"expr": Fabric.expr_sub(
				Fabric.expr_state("phase"),
				Fabric.expr_constant(0.05, Fabric.dim_dimensionless())
			),
			"nominal": 1.0,
			"direction": 1,
			"kind": "crossing",
		},
		"jump": {},
		"topology_ops": [],
		"priority": 0,
	}
	if not Fabric.add_transition(system, transition):
		return {}
	var advanced := Fabric.advance(system, 0.10)
	if not bool(advanced.get("ok", false)):
		return {}
	if system["events"].size() != 1:
		return {}
	return system["events"][0].duplicate(true)

func _blueprint(
	mode_id: String,
	descriptor_id: String,
	bundle: Dictionary,
	full_model: Dictionary,
	rom: Dictionary,
	certification: Dictionary,
	label: String
) -> Dictionary:
	var physical: Dictionary = bundle["physical_artifact"]
	return {
		"mode_id": mode_id,
		"mode_descriptor_id": descriptor_id,
		"active_relation_ids": ["relation/hybrid/branch-%s" % label],
		"complementarity_active_ids": ["active-set/hybrid/%s" % label],
		"dependency_versions": [
			{"dependency_id": "dependency/b04/artifact", "version_hash": String(physical["checksum"])},
			{"dependency_id": "dependency/sync3/closure", "version_hash": Utils.canonical_hash({"sync3": "28fdc16d12ddf1233a82103cb290c831342a3022"})},
		],
		"physical_bundle": bundle,
		"full_model": full_model,
		"rom_descriptor": rom["descriptor"],
		"reduction_binding": rom["artifact_binding"],
		"certification": certification,
	}

func _transition(
	a_package: Dictionary,
	b_descriptor: Dictionary,
	b_bundle: Dictionary,
	conservation_checksum: String
) -> Dictionary:
	var a_physical: Dictionary = a_package["physical_bundle"]["physical_artifact"]
	var b_physical: Dictionary = b_bundle["physical_artifact"]
	var handoff := {
		"contract_kind": "B0_4_STATE_HANDOFF_INTERFACE",
		"interface_status": "B0_4_INTERFACE_BOUND",
		"from_state_mapping_checksum": String(a_physical["state_mapping"]["checksum"]),
		"to_state_mapping_checksum": String(b_physical["state_mapping"]["checksum"]),
		"from_reconstruction_descriptor_checksum": String(a_physical["reconstruction_descriptor"]["checksum"]),
		"to_reconstruction_descriptor_checksum": String(b_physical["reconstruction_descriptor"]["checksum"]),
		"conservation_envelope_checksum": conservation_checksum,
	}
	var guard := {
		"guard_id": "guard/hybrid/release",
		"kind": "CROSSING",
		"direction": 1,
		"observed_quantity_id": "quantity/hybrid/phase",
		"dimension": [0, 0, 0, 0, 0, 0, 0],
		"nominal": 1.0,
		"threshold": 0.05,
		"mapped_source_region": "region/dynamic/all",
	}
	return P0Transition.create(
		TRANSITION_ID,
		String(a_package["mode_descriptor"]["mode_signature"]["source_frontier_hash"]),
		String(a_package["mode_contract"]["mode_hash"]),
		String(b_descriptor["mode_signature"]["mode_hash"]),
		guard,
		handoff,
		"NONE",
		P0Transition.exactly_once_event_ownership(),
		0
	)

func _safe_flows(step: int) -> Dictionary:
	var t := float(step + 1) * DT
	return _flows([
		0.10 * sin(TAU * 0.2 * t),
		-0.04 * sin(TAU * 0.3 * t),
		0.02,
		0.0,
	])

func _flows(values: Array) -> Dictionary:
	return {
		"port/electrical/000-left": float(values[0]),
		"port/electrical/170-mid-a": float(values[1]),
		"port/electrical/341-mid-b": float(values[2]),
		"port/electrical/511-right": float(values[3]),
	}

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC-BAKE B0.5-A Executable Hybrid Bake Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("B0.5-A: %s" % failure)
	print("FABRIC-BAKE B0.5-A Executable Hybrid Bake Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
