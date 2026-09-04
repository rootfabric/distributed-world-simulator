extends SceneTree

const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const ParentB = preload("res://scripts/research/fabric_bake0/complex2b_modular_machine_extension_v1.gd")
const Coupled = preload("res://scripts/research/fabric_bake0/complex2_coupled_motion_v1.gd")
const Extension = preload("res://scripts/research/fabric_bake0/complex2c_modular_machine_extension_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")

const SCENE := "res://scenes/labs/fabric/complex2c_coupled_motion_lab.tscn"

var _checks := 0
var _failures: Array[String] = []
var _experiment_hash := ""

func _initialize() -> void:
	var built := Extension.build()
	_check(bool(built.get("success", false)), "COMPLEX2-C extension builds")
	if not bool(built.get("success", false)):
		_finish()
		return
	_test_contract(built)
	_test_physics(built)
	_test_visual_scene()
	_finish()

func _test_contract(built: Dictionary) -> void:
	var assembly: Dictionary = built["coupled_assembly"]
	var parent_b: Dictionary = built["parent_b"]
	var registry: Dictionary = built["registry"]
	_check(String(built["schema"]) == Extension.SCHEMA, "extension schema exact")
	_check(bool(Coupled.validate(assembly).get("success", false)), "coupled assembly validates")
	_check(bool(Registry.validate(registry).get("success", false)), "extended BRIDGE-2 registry validates")
	_check(String(assembly["backend_contract_id"]) == Coupled.BACKEND_CONTRACT_ID, "coupled backend contract exact")
	_check(int(assembly["full_state_count"]) == 8, "coupled physical state has q+v for four DOFs")
	_check(int(assembly["compiled_state_count"]) == 8, "compiled evaluator preserves all eight states")
	_check(Array(assembly["dof_ids"]) == Coupled.DOF_IDS, "DOF identity exact")
	_check(Array(assembly["module_ids"]) == Coupled.MODULE_IDS, "coupled modules bind machine modules 8..11")
	_check(Array(assembly["couplings"]).size() == 4, "four reciprocal physical couplings compiled")
	_check(registry["regions"].size() == 5, "C adds no sixth physical owner")
	var kinds: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
	kinds.sort()
	var expected := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected.sort()
	_check(kinds == expected, "five representation kinds preserved")
	_check(String(built["parent_registry_hash"]) != String(built["extended_registry_hash"]), "C changes registry identity only through DYNAMIC backend extension")
	_check(String(built["parent_dynamic_backend_hash"]) != String(built["extended_dynamic_backend_hash"]), "DYNAMIC backend identity extended by coupled assembly")

	var parent_hybrid := Registry.region_by_id(parent_b["registry"], Fixture.REGION_HYBRID)
	var current_hybrid := Registry.region_by_id(registry, Fixture.REGION_HYBRID)
	_check(String(parent_hybrid["adapter"]["backend_contract_hash"]) == String(current_hybrid["adapter"]["backend_contract_hash"]), "COMPLEX2-B HYBRID backend unchanged")
	_check(String(parent_b["compliant_section"]["backend_contract_id"]) == "COMPLEX2B_COHERENT_KELVIN_VOIGT_R1", "COMPLEX2-B compliant contract retained")

	var zero := Coupled.zero_state(assembly)
	var packet := Coupled.encode_state(assembly, zero)
	_check(bool(packet.get("success", false)), "coupled q/v state serializes for representation handoff")
	var restored := Coupled.decode_state(assembly, packet.get("packet", {}))
	_check(bool(restored.get("success", false)), "coupled q/v state reconstructs after handoff")
	if bool(restored.get("success", false)):
		_check(restored["state"]["q_path_m"] == zero["q_path_m"] and restored["state"]["v_path_m_s"] == zero["v_path_m_s"], "state packet roundtrip exact")
	var corrupt := Dictionary(packet.get("packet", {})).duplicate(true)
	corrupt["checksum"] = "corrupt"
	var rejected := Coupled.decode_state(assembly, corrupt)
	_check(String(rejected.get("error_code", "")) == "COMPLEX2C_STATE_PACKET_CHECKSUM_MISMATCH", "corrupt representation handoff rejected")

func _test_physics(built: Dictionary) -> void:
	var result := Extension.run_experiment()
	_check(bool(result.get("success", false)), "COMPLEX2-C executable integrated experiment completes")
	if not bool(result.get("success", false)):
		_failures.append("experiment details=%s" % str(result))
		return
	var coupled: Dictionary = result["coupled"]
	_check(int(coupled["dof_count"]) == 4, "four coupled moving DOFs")
	_check(int(coupled["state_count"]) == 8, "four positions plus four velocities")
	_check(int(coupled["coupling_count"]) == 4, "four coupling links active")
	_check(float(coupled["max_active_full_delta"]) <= 1.0e-12, "compiled DYNAMIC and canonical FULL trajectories agree")
	_check(float(coupled["max_energy_balance_residual_j"]) <= 1.0e-10, "implicit midpoint energy balance closes")
	_check(float(coupled["min_dissipated_energy_j"]) >= -1.0e-12, "damping never creates energy")
	_check(float(coupled["total_dissipated_energy_j"]) > 1.0, "coupled mechanism dissipates measurable energy")
	_check(float(coupled["peak_total_energy_j"]) > 0.5, "drive loads coupled mechanism with measurable energy")
	_check(bool(coupled["release_energy_monotonic"]), "stored plus kinetic energy decays monotonically after release")
	_check(Array(coupled["representation_switch_steps"]) == [150, 230], "physical evaluator switches twice while moving")
	_check(Array(coupled["handoff_errors"]) == [0.0, 0.0], "physical q/v handoff has zero discontinuity")
	_check(Array(coupled["samples"]).size() == 6, "coupled motion trace records swap boundaries and settle endpoint")
	_check(String(coupled["samples"][1]["evaluator"]) == "COMPILED_DYNAMIC_ROM", "pre-swap evaluator is DYNAMIC_ROM")
	_check(String(coupled["samples"][2]["evaluator"]) == "FULL_CANONICAL_SUM", "mid-motion evaluator switches to FULL")
	_check(String(coupled["samples"][4]["evaluator"]) == "COMPILED_DYNAMIC_ROM", "second handoff returns to DYNAMIC_ROM")
	_check(float(coupled["samples"][5]["energy_j"]) < float(coupled["peak_total_energy_j"]) * 0.02, "free ringdown settles below two percent of peak energy")

	var peak: Array = coupled["peak_native_abs"]
	_check(float(peak[0]) > 0.15, "shoulder articulates materially")
	_check(float(peak[1]) > 0.15, "elbow articulates through coupling")
	_check(float(peak[2]) > 0.50, "shaft rotates materially")
	_check(float(peak[3]) > 0.05, "carriage translates materially")
	for index in range(4):
		_check(float(peak[index]) < float(Coupled.MAX_NATIVE_ABS[index]), "all DOFs stay inside certified native range")

	var transfer: Dictionary = coupled["transfer_probe"]
	_check(float(transfer["coupled_shaft_peak_m"]) > 0.03, "shoulder-only drive transfers motion into shaft")
	_check(float(transfer["coupled_carriage_peak_m"]) > 0.03, "shoulder-only drive transfers motion into carriage")
	_check(float(transfer["decoupled_shaft_peak_m"]) == 0.0, "decoupled control leaves shaft motionless")
	_check(float(transfer["decoupled_carriage_peak_m"]) == 0.0, "decoupled control leaves carriage motionless")

	_check(String(coupled["nonreciprocal_error"]) == "COMPLEX2C_NONRECIPROCAL_COUPLING", "nonreciprocal coupling fails closed")
	_check(String(coupled["over_force_error"]) == "COMPLEX2C_REFINEMENT_REQUIRED_FORCE", "over-force requests refinement")
	_check(String(coupled["over_angle_error"]) == "COMPLEX2C_REFINEMENT_REQUIRED_NATIVE_RANGE", "out-of-envelope articulation requests refinement")
	_check(String(coupled["over_speed_error"]) == "COMPLEX2C_REFINEMENT_REQUIRED_SPEED", "out-of-envelope speed requests refinement")

	_check(float(result["runtime_mixed_full_max_delta"]) <= 1.0e-12, "BRIDGE-2 mixed runtime remains equal to FULL through swaps")
	_check(float(result["representation_swap_handoff_error"]) == 0.0, "BRIDGE-2 swap handoff error zero")
	_check(int(result["representation_event_ledger_size"]) == 2, "two mid-motion representation events committed exactly once")
	var final_kinds: Array = Array(result["final_representation_kinds"]).duplicate()
	var expected := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected.sort()
	_check(final_kinds == expected, "representation set returns to original five-kind arrangement")
	_check(String(result["parent_b_hybrid_backend_hash"]) == String(result["final_hybrid_backend_hash"]), "COMPLEX2-B compliant HYBRID backend survives C swaps unchanged")
	_check(not String(result["parent_b_compliance_hash"]).is_empty(), "B compliant envelope still executes")

	var replay := Coupled.run_envelope(built["parent_machine"])
	_check(bool(replay.get("success", false)), "pure coupled replay completes")
	if bool(replay.get("success", false)):
		_check(String(replay["experiment_hash"]) == String(coupled["experiment_hash"]), "pure coupled trajectory hash deterministic")
		_check(replay["samples"] == coupled["samples"], "pure coupled sampled trajectory deterministic")

	_experiment_hash = String(result["experiment_hash"])
	_check(not _experiment_hash.is_empty(), "integrated COMPLEX2-C experiment hash present")
	print("COMPLEX2-C metrics active_full_delta=%s energy_residual=%s shaft_transfer=%.9f carriage_transfer=%.9f final_energy=%.9f" % [
		String.num_scientific(float(coupled["max_active_full_delta"])),
		String.num_scientific(float(coupled["max_energy_balance_residual_j"])),
		float(transfer["coupled_shaft_peak_m"]),
		float(transfer["coupled_carriage_peak_m"]),
		float(coupled["samples"][5]["energy_j"]),
	])

func _test_visual_scene() -> void:
	var packed := load(SCENE)
	_check(packed is PackedScene, "COMPLEX2-C visual lab loads")
	if packed is PackedScene:
		var scene := (packed as PackedScene).instantiate()
		_check(scene != null, "COMPLEX2-C visual lab instantiates")
		if scene != null:
			_check(String(scene.name) == "COMPLEX2CCoupledMotionLab", "COMPLEX2-C visual root exact")
			scene.free()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("COMPLEX2C_EXPERIMENT_HASH=%s" % _experiment_hash)
		print("FABRIC COMPLEX2-C Coupled Motion Acceptance: PASS (%d assertions) dof=4 state=8 reciprocal=PASS energy=PASS swaps=2 mixed=FULL_REFERENCE scene=PASS" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("COMPLEX2-C FAILURE: %s" % failure)
	print("FABRIC COMPLEX2-C Coupled Motion Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)
