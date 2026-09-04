extends SceneTree

const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const Compliance = preload("res://scripts/research/fabric_bake0/complex2_compliant_response_v1.gd")
const Extension = preload("res://scripts/research/fabric_bake0/complex2b_modular_machine_extension_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")

var _checks := 0
var _failures: Array[String] = []
var _experiment_hash := ""

func _initialize() -> void:
	var built := Extension.build()
	_check(bool(built.get("success", false)), "COMPLEX2-B extension builds")
	if not bool(built.get("success", false)):
		_finish()
		return
	_test_contract(built)
	_test_response(built)
	_finish()

func _test_contract(built: Dictionary) -> void:
	var machine: Dictionary = built["parent_machine"]
	var section: Dictionary = built["compliant_section"]
	var registry: Dictionary = built["registry"]
	_check(String(built["schema"]) == Extension.SCHEMA, "extension schema exact")
	_check(bool(Compliance.validate(section).get("success", false)), "compliant section validates")
	_check(bool(Registry.validate(registry).get("success", false)), "extended BRIDGE-2 registry validates")
	_check(String(section["schema"]) == Compliance.SCHEMA, "compliant schema exact")
	_check(String(section["backend_contract_id"]) == Compliance.BACKEND_CONTRACT_ID, "backend contract exact")
	_check(String(section["module_id"]) == Compliance.MODULE_ID, "compliance binds module 20")
	_check(String(section["region_id"]) == Fixture.REGION_HYBRID, "compliance owned by HYBRID region")
	_check(int(section["full_state_count"]) == 80, "FULL coherent section has 80 canonical part states")
	_check(int(section["reduced_state_count"]) == 1, "reduced compliance has one state")
	_check(Array(section["part_ids"]).size() == 80, "compliant part coverage exact")
	_check(Array(section["fibers"]).size() == 80, "80 canonical spring/damper fibers")
	_check(float(section["total_stiffness_n_per_m"]) > 0.0, "aggregate stiffness positive")
	_check(float(section["total_damping_n_s_per_m"]) > 0.0, "aggregate damping positive")
	_check(bool(StateMapping.validate(section["state_mapping"]).get("success", false)), "BakeStateMapping valid")
	_check(bool(ReconstructionDescriptor.validate(section["reconstruction_descriptor"]).get("success", false)), "ReconstructionDescriptor valid")
	_check(String(section["state_mapping"]["reconstruction_descriptor_hash"]) == String(section["reconstruction_descriptor"]["checksum"]), "state mapping binds reconstruction descriptor")
	_check(String(section["backend_family_hash"]) == Compliance.backend_family_hash(), "backend family hash deterministic")
	_check(String(built["parent_registry_hash"]) != String(built["extended_registry_hash"]), "nested compliant backend changes registry identity")
	_check(String(built["parent_backend_hash"]) != String(built["extended_backend_hash"]), "nested compliant backend changes HYBRID backend identity")

	var hybrid := Registry.region_by_id(registry, Fixture.REGION_HYBRID)
	_check(not hybrid.is_empty(), "extended HYBRID region present")
	if not hybrid.is_empty():
		_check(String(hybrid["representation_kind"]) == "HYBRID_BAKE", "representation kind remains HYBRID_BAKE")
		_check(String(hybrid["state_id"]) == Fixture.STATE_HYBRID, "HYBRID state owner identity unchanged")
		_check(String(hybrid["adapter"]["backend_contract_hash"]) == String(built["extended_backend_hash"]), "HYBRID adapter binds compliant backend hash")
		_check(bool(Artifact.validate(hybrid["adapter"]["artifact"]).get("success", false)), "extended HYBRID owns common PhysicalBakeArtifact")
		_check(int(hybrid["adapter"]["artifact"]["build_generation"]) == 2, "extended HYBRID artifact generation increments")

	var kinds: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
	kinds.sort()
	var expected_kinds := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected_kinds.sort()
	_check(kinds == expected_kinds, "extension preserves exact five representation kinds")
	_check(registry["regions"].size() == 5, "extension adds no sixth physical owner")
	_check(machine["parts"].size() == 2000, "parent machine remains 2000 canonical parts")

	var mover_found := false
	for mover in machine["moving_subsystems"]:
		if String(mover["module_id"]) == Compliance.MODULE_ID:
			mover_found = String(mover["kind"]) == "COMPLIANT"
	_check(mover_found, "existing moving subsystem marks module 20 COMPLIANT")

func _test_response(built: Dictionary) -> void:
	var machine: Dictionary = built["parent_machine"]
	var section: Dictionary = built["compliant_section"]
	var result := Compliance.run_envelope(machine)
	_check(bool(result.get("success", false)), "compliant load/hold/release envelope executes")
	if not bool(result.get("success", false)):
		_failures.append("response details=%s" % str(result))
		return

	_check(int(result["full_state_count"]) == 80, "response FULL state count 80")
	_check(int(result["reduced_state_count"]) == 1, "response reduced state count 1")
	_check(absf(float(result["reduction_ratio"]) - 80.0) <= 1.0e-12, "compliance reduction ratio 80x")
	_check(float(result["max_full_reduced_delta_m"]) <= 1.0e-12, "FULL and HYBRID deflection agree")
	_check(float(result["max_reconstruction_error_m"]) <= 1.0e-12, "reconstruction of 80 FULL deflections exact")
	_check(float(result["handoff_roundtrip_error_m"]) <= 1.0e-12, "FULL -> reduced -> FULL handoff scalar continuity exact")
	_check(float(result["handoff_reconstruction_error_m"]) <= 1.0e-12, "handoff reconstruction matches FULL state")
	_check(float(result["max_energy_balance_residual_j"]) <= 1.0e-10, "energy balance residual bounded")
	_check(float(result["min_dissipated_energy_j"]) >= -1.0e-10, "damping never creates energy")
	_check(bool(result["release_energy_monotonic"]), "stored energy decreases monotonically after release")
	_check(float(result["peak_abs_deflection_m"]) > 0.05, "spring section deflects materially under load")
	_check(float(result["peak_abs_deflection_m"]) < Compliance.MAX_DEFLECTION_M, "accepted response remains inside certified deflection envelope")
	_check(float(result["final_abs_deflection_m"]) < float(result["peak_abs_deflection_m"]) * 0.10, "release returns section close to neutral")
	_check(float(result["total_dissipated_energy_j"]) > 0.0, "damper dissipates positive energy")
	_check(String(result["over_force_error"]) == "COMPLEX2B_REFINEMENT_REQUIRED_FORCE", "over-force guard fails closed to refinement")
	_check(String(result["over_deflection_error"]) == "COMPLEX2B_REFINEMENT_REQUIRED_DEFLECTION", "over-deflection guard fails closed to refinement")
	_check(String(result["incoherent_projection_error"]) == "COMPLEX2B_COHERENT_MODE_VIOLATION", "non-coherent FULL state cannot be hidden by one-mode bake")
	_check(Array(result["samples"]).size() >= 6, "response trace records every load phase")

	var load_sample: Dictionary = {}
	var release_sample: Dictionary = {}
	for sample in result["samples"]:
		if String(sample["phase"]) == "HOLD_80":
			load_sample = sample
		elif String(sample["phase"]) == "RELEASE":
			release_sample = sample
	_check(not load_sample.is_empty() and float(load_sample["q_m"]) > 0.05, "80N hold produces positive compliant deflection")
	_check(not release_sample.is_empty() and absf(float(release_sample["q_m"])) < absf(float(load_sample["q_m"])), "release relaxes compliant deflection")

	var full_state := Compliance.reconstruct_full(section, float(load_sample["q_m"]))
	var projected := Compliance.project_full(section, full_state)
	_check(bool(projected.get("success", false)), "explicit FULL reconstruction can project back")
	if bool(projected.get("success", false)):
		_check(absf(float(projected["q_m"]) - float(load_sample["q_m"])) <= 1.0e-12, "explicit handoff state is continuous")

	var integrated := Extension.run_experiment()
	_check(bool(integrated.get("success", false)), "extended HYBRID registry and parent COMPLEX2 lifecycle execute together")
	if bool(integrated.get("success", false)):
		_check(float(integrated["extended_step_full_delta"]) <= 1.0e-12, "extended registry mixed step equals FULL reference")
		_check(String(integrated["compliance"]["experiment_hash"]) == String(result["experiment_hash"]), "extension consumes same compliant envelope identity")
		_check(float(integrated["parent_mixed_full_max_state_delta"]) <= 1.0e-12, "COMPLEX2-A mixed/FULL regression preserved")
		_check(float(integrated["parent_representation_swap_handoff_error"]) == 0.0, "COMPLEX2-A representation handoff preserved")

	var replay := Compliance.run_envelope(machine)
	_check(bool(replay.get("success", false)), "second compliant replay completes")
	if bool(replay.get("success", false)):
		_check(String(replay["experiment_hash"]) == String(result["experiment_hash"]), "compliant response hash deterministic")
		_check(replay["samples"] == result["samples"], "compliant response trace deterministic")

	_experiment_hash = String(integrated.get("experiment_hash", result["experiment_hash"]))
	_check(not _experiment_hash.is_empty(), "COMPLEX2-B integrated experiment hash present")
	print("COMPLEX2-B metrics K=%.6f C=%.6f peak_q=%.9f final_q=%.9f max_full_delta=%s energy_residual=%s" % [
		float(result["total_stiffness_n_per_m"]),
		float(result["total_damping_n_s_per_m"]),
		float(result["peak_abs_deflection_m"]),
		float(result["final_abs_deflection_m"]),
		String.num_scientific(float(result["max_full_reduced_delta_m"])),
		String.num_scientific(float(result["max_energy_balance_residual_j"])),
	])

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("COMPLEX2B_EXPERIMENT_HASH=%s" % _experiment_hash)
		print("FABRIC COMPLEX2-B Compliant Response Acceptance: PASS (%d assertions) full=80 reduced=1 Kelvin-Voigt energy=PASS guards=PASS extended=FULL_REFERENCE" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("COMPLEX2-B FAILURE: %s" % failure)
	print("FABRIC COMPLEX2-B Compliant Response Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)
