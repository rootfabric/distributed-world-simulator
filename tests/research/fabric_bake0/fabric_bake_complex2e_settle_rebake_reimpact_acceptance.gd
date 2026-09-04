extends SceneTree

const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/complex2_settle_rebake_reimpact_v1.gd")
const Extension = preload("res://scripts/research/fabric_bake0/complex2e_modular_machine_extension_v1.gd")

const SCENE := "res://scenes/labs/fabric/complex2e_settle_rebake_reimpact_lab.tscn"

var _checks := 0
var _failures: Array[String] = []
var _experiment_hash := ""

func _initialize() -> void:
	var built := Extension.build()
	_check(bool(built.get("success", false)), "COMPLEX2-E extension builds")
	if not bool(built.get("success", false)):
		_finish()
		return
	_test_lifecycle()
	_test_visual_scene()
	_finish()

func _test_lifecycle() -> void:
	var result := Extension.run_experiment()
	_check(bool(result.get("success", false)), "COMPLEX2-E integrated lifecycle completes")
	if not bool(result.get("success", false)):
		_failures.append("experiment details=%s" % str(result))
		return
	var settled: Dictionary = result["settled"]
	var reimpact: Dictionary = result["reimpact"]
	_check(String(result["premature_rebake_error"]) == "COMPLEX2E_REBAKE_REQUIRES_SETTLED", "rebake before settle fails closed")
	_check(String(result["premature_reimpact_error"]) == "COMPLEX2E_REIMPACT_REQUIRES_REBAKED", "re-impact before rebake fails closed")
	_check(int(settled["settled_step"]) >= Lifecycle.FIRST_IMPACT_STEPS, "settle occurs only after first impact release")
	_check(int(settled["settled_step"]) < Lifecycle.MAX_SETTLE_STEPS, "settle threshold reached inside certified horizon")
	_check(float(settled["settled_energy_j"]) <= Lifecycle.SETTLE_ENERGY_J, "settled energy below threshold")
	_check(float(settled["peak_energy_j"]) > float(settled["settled_energy_j"]) * 100.0, "first impact transient decays by more than 100x")
	_check(bool(settled["release_energy_monotonic"]), "first-impact release energy decays monotonically")
	_check(float(settled["max_active_full_delta"]) <= 1.0e-12, "settling DYNAMIC trajectory equals FULL reference")
	_check(float(settled["max_energy_balance_residual_j"]) <= 1.0e-10, "settling energy identity closes")
	_check(float(settled["min_dissipated_energy_j"]) >= -1.0e-12, "settling damping never creates energy")
	_check(float(settled["state_handoff_error"]) == 0.0, "settled q/v state packet roundtrip exact")
	_check(not String(settled["settled_state_hash"]).is_empty(), "settled q/v state hash present")

	_check(int(result["rebake_generation"]) == Extension.REBAKE_GENERATION, "settled DYNAMIC artifact rebuilt at exact generation")
	_check(float(result["rebake_state_handoff_error"]) == 0.0, "runtime rebake scalar state handoff zero")
	_check(String(result["old_dynamic_backend_hash"]) != String(result["rebaked_dynamic_backend_hash"]), "rebake changes DYNAMIC backend identity")
	_check(String(result["old_source_slice_hash"]) == String(result["rebaked_source_slice_hash"]), "settle-triggered rebake does not falsify canonical source slice")
	_check(String(result["registry_hash_before_rebake"]) != String(result["registry_hash_after_rebake"]), "rebake changes registry identity")
	_check(not String(result["rebake_artifact_hash"]).is_empty(), "rebake artifact checksum present")
	_check(String(result["parent_b_hybrid_backend_hash"]) == String(result["final_hybrid_backend_hash"]), "B compliant HYBRID backend survives E lifecycle")

	_check(String(result["reimpact_event_id"]) == Lifecycle.REIMPACT_EVENT_ID, "re-impact event identity exact")
	_check(Array(result["applied_reimpact_ids"]) == [Lifecycle.REIMPACT_EVENT_ID], "re-impact event committed exactly once")
	_check(String(result["duplicate_reimpact_error"]) == "COMPLEX2E_REIMPACT_ALREADY_APPLIED", "duplicate re-impact fails closed")
	_check(float(reimpact["peak_energy_j"]) > float(settled["settled_energy_j"]) * 100.0, "post-rebake impact re-excites machine by more than 100x")
	_check(float(reimpact["peak_energy_j"]) > 0.5, "re-impact produces measurable coupled energy")
	_check(float(reimpact["max_active_full_delta"]) <= 1.0e-12, "post-rebake DYNAMIC response equals FULL reference")
	_check(float(reimpact["max_energy_balance_residual_j"]) <= 1.0e-10, "re-impact energy identity closes")
	_check(float(reimpact["min_dissipated_energy_j"]) >= -1.0e-12, "re-impact damping remains passive")
	var peak_q: Array = reimpact["peak_native_abs"]
	_check(float(peak_q[2]) > 0.5, "shaft receives material re-impact rotation")
	_check(float(peak_q[3]) > 0.03, "re-impact transfers motion into carriage")
	_check(float(peak_q[0]) > 0.05, "re-impact propagates back into shoulder")
	_check(float(peak_q[1]) > 0.05, "re-impact propagates through elbow")

	_check(float(result["runtime_quiet_mixed_full_delta"]) <= 1.0e-12, "quiet post-rebake mixed runtime equals FULL")
	_check(float(result["runtime_reimpact_mixed_full_delta"]) <= 1.0e-12, "runtime re-impact mixed result equals FULL")
	_check(float(result["runtime_contact_state_delta"]) > 0.0, "re-impact changes CONTACT runtime state")
	_check(String(result["structural_topology_hash_before_rebake"]) == String(result["structural_topology_hash_after_reimpact"]), "settle/rebake/re-impact adds no hidden structural mutation")
	_check(not String(result["functional_subject_hash"]).is_empty(), "functional topology identity retained")
	var kinds: Array = Array(result["final_representation_kinds"]).duplicate()
	var expected := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected.sort()
	_check(kinds == expected, "five-kind representation set preserved through E")

	var replay := Extension.run_experiment()
	_check(bool(replay.get("success", false)), "independent E replay completes")
	if bool(replay.get("success", false)):
		_check(String(replay["experiment_hash"]) == String(result["experiment_hash"]), "E integrated experiment hash deterministic")
		_check(String(replay["settled"]["settled_state_hash"]) == String(settled["settled_state_hash"]), "settled state deterministic")
		_check(String(replay["reimpact"]["experiment_hash"]) == String(reimpact["experiment_hash"]), "re-impact response deterministic")

	_experiment_hash = String(result["experiment_hash"])
	_check(not _experiment_hash.is_empty(), "integrated COMPLEX2-E hash present")
	print("COMPLEX2-E metrics settle_step=%d settle_E=%s rebake_gen=%d reimpact_peak_E=%.9f contact_delta=%s" % [
		int(settled["settled_step"]), String.num_scientific(float(settled["settled_energy_j"])),
		int(result["rebake_generation"]), float(reimpact["peak_energy_j"]), String.num_scientific(float(result["runtime_contact_state_delta"])),
	])

func _test_visual_scene() -> void:
	var packed := load(SCENE)
	_check(packed is PackedScene, "COMPLEX2-E visual lab loads")
	if packed is PackedScene:
		var scene := (packed as PackedScene).instantiate()
		_check(scene != null, "COMPLEX2-E visual lab instantiates")
		if scene != null:
			_check(String(scene.name) == "COMPLEX2ESettleRebakeReimpactLab", "COMPLEX2-E visual root exact")
			scene.free()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("COMPLEX2E_EXPERIMENT_HASH=%s" % _experiment_hash)
		print("FABRIC COMPLEX2-E Settle Rebake Re-impact Acceptance: PASS (%d assertions) settle=PASS rebake=DYNAMIC_ROM reimpact=PASS mixed=FULL_REFERENCE scene=PASS" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("COMPLEX2-E FAILURE: %s" % failure)
	print("FABRIC COMPLEX2-E Settle Rebake Re-impact Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)
