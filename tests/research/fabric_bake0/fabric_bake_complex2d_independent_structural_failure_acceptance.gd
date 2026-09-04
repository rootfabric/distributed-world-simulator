extends SceneTree

const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const Structural = preload("res://scripts/research/fabric_bake0/complex2_independent_structural_failure_v1.gd")
const Extension = preload("res://scripts/research/fabric_bake0/complex2d_modular_machine_extension_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")

const SCENE := "res://scenes/labs/fabric/complex2d_structural_failure_lab.tscn"

var _checks := 0
var _failures: Array[String] = []
var _experiment_hash := ""

func _initialize() -> void:
	var built := Extension.build()
	_check(bool(built.get("success", false)), "COMPLEX2-D extension builds")
	if not bool(built.get("success", false)):
		_finish()
		return
	_test_contract(built)
	_test_failure(built)
	_test_visual_scene()
	_finish()

func _test_contract(built: Dictionary) -> void:
	var structural: Dictionary = built["structural_assembly"]
	var registry: Dictionary = built["registry"]
	_check(String(built["schema"]) == Extension.SCHEMA, "extension schema exact")
	_check(String(structural["schema"]) == Structural.SCHEMA, "structural schema exact")
	_check(String(structural["backend_contract_id"]) == Structural.BACKEND_CONTRACT_ID, "structural backend contract exact")
	_check(String(structural["failure_support_id"]) == Structural.FAILURE_SUPPORT_ID, "independent failure support exact")
	_check(String(structural["failure_support_id"]) != Fixture.DETACH_SUPPORT_ID, "D failure is not detachable endpoint support")
	_check(String(structural["failure_support_id"]) != Fixture.SECOND_SUPPORT_ID, "D failure is not prior functional support")
	_check(Array(structural["node_ids"]).size() == 5, "five-node redundant structural subnetwork")
	_check(Array(structural["edges"]).size() == 5, "four chain supports plus one redundant brace")
	_check(bool(Registry.validate(registry).get("success", false)), "parent C registry valid")
	_check(registry["regions"].size() == 5, "D adds no sixth representation owner")
	var parent_c: Dictionary = built["parent_c"]
	var dynamic := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	var hybrid := Registry.region_by_id(registry, Fixture.REGION_HYBRID)
	_check(String(dynamic["adapter"]["backend_contract_hash"]) == String(parent_c["extended_dynamic_backend_hash"]), "C coupled DYNAMIC backend retained")
	_check(not String(hybrid["adapter"]["backend_contract_hash"]).is_empty(), "B compliant HYBRID backend retained")

func _test_failure(built: Dictionary) -> void:
	var result := Extension.run_experiment()
	_check(bool(result.get("success", false)), "COMPLEX2-D integrated failure experiment completes")
	if not bool(result.get("success", false)):
		_failures.append("experiment details=%s" % str(result))
		return
	var structural: Dictionary = result["structural"]
	var before: Dictionary = structural["before"]
	var after: Dictionary = structural["after"]
	_check(String(structural["event_id"]) == Structural.EVENT_ID, "D event identity exact")
	_check(int(structural["machine_after_revision"]) == int(structural["machine_before_revision"]) + 1, "canonical machine revision advances exactly once")
	_check(String(structural["before_topology_hash"]) != String(structural["after_topology_hash"]), "canonical structural topology hash changes")
	_check(int(structural["component_count_after"]) == 1, "independent brace failure does not detach machine component")
	_check(Array(structural["components_after"])[0].size() == Fixture.MODULE_COUNT, "all 25 modules remain connected")
	_check(float(before["brace_force_n"]) > 30.0, "brace carries measurable load before failure")
	_check(float(after["brace_force_n"]) == 0.0, "failed brace carries zero load")
	_check(float(after["tip_deflection_m"]) > float(before["tip_deflection_m"]) * 2.0, "loss of redundant brace materially increases deflection")
	_check(float(structural["tip_deflection_ratio"]) > 2.0, "tip deflection redistribution ratio above 2x")
	_check(float(after["max_chain_force_n"]) > float(before["max_chain_force_n"]) * 2.0, "chain load materially increases after brace loss")
	_check(float(structural["chain_force_ratio"]) > 2.0, "chain force redistribution ratio above 2x")
	_check(float(before["equilibrium_residual_n"]) <= 1.0e-10, "baseline static equilibrium closes")
	_check(float(after["equilibrium_residual_n"]) <= 1.0e-10, "post-failure static equilibrium closes")
	_check(float(before["work_identity_residual_j"]) <= 1.0e-10, "baseline strain-energy/work identity closes")
	_check(float(after["work_identity_residual_j"]) <= 1.0e-10, "post-failure strain-energy/work identity closes")
	_check(String(structural["functional_before_hash"]) == String(structural["functional_after_hash"]), "independent structural failure leaves functional solution unchanged")
	_check(String(structural["functional_subject_hash_before"]) == String(structural["functional_subject_hash_after"]), "functional topology is not mutated by D event")
	_check(String(structural["duplicate_error"]) == "COMPLEX2D_EVENT_ALREADY_APPLIED", "duplicate D structural event fails closed")
	_check(String(structural["over_load_error"]) == "COMPLEX2D_REFINEMENT_REQUIRED_LOAD", "out-of-envelope structural load requests refinement")

	var affected: Array = Array(result["affected_regions"]).duplicate()
	affected.sort()
	var expected := [Fixture.REGION_CONTACT, Fixture.REGION_FULL]
	expected.sort()
	_check(affected == expected, "only FULL and CONTACT source partitions invalidate")
	_check(String(result["stale_error"]) == "BRIDGE2_MIXED_STEP_BLOCKED", "mixed execution blocked while structural artifacts stale")
	_check(String(result["sequential_rebuild_error"]) == "BRIDGE2_REBUILD_REGISTRY_FAILED", "single-region rebuild cannot partially refresh a two-region event")
	_check(Array(result["atomic_rebuild_regions"]) == expected, "atomic rebuild covers exact affected set")
	_check(float(result["atomic_handoff_errors"][Fixture.REGION_FULL]) == 0.0, "FULL rebuild handoff zero")
	_check(float(result["atomic_handoff_errors"][Fixture.REGION_CONTACT]) == 0.0, "CONTACT rebuild handoff zero")
	_check(float(result["runtime_mixed_full_max_delta"]) <= 1.0e-12, "post-failure mixed runtime remains equal to FULL reference")
	_check(String(result["parent_c_dynamic_backend_hash"]) == String(result["final_dynamic_backend_hash"]), "C coupled DYNAMIC backend survives D failure unchanged")
	_check(String(result["parent_b_hybrid_backend_hash"]) == String(result["final_hybrid_backend_hash"]), "B compliant HYBRID backend survives D failure unchanged")
	var kinds: Array = Array(result["final_representation_kinds"]).duplicate()
	var expected_kinds := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected_kinds.sort()
	_check(kinds == expected_kinds, "five-kind representation set preserved after D rebuild")

	var replay := Structural.run_failure(built["parent_machine"])
	_check(bool(replay.get("success", false)), "pure structural failure replay completes")
	if bool(replay.get("success", false)):
		_check(String(replay["experiment_hash"]) == String(structural["experiment_hash"]), "structural failure hash deterministic")
		_check(replay["before"]["state_hash"] == before["state_hash"] and replay["after"]["state_hash"] == after["state_hash"], "structural states deterministic")

	_experiment_hash = String(result["experiment_hash"])
	_check(not _experiment_hash.is_empty(), "integrated COMPLEX2-D hash present")
	print("COMPLEX2-D metrics brace_before=%.6fN tip_before=%.9fm tip_after=%.9fm chain_ratio=%.6f residual=%s" % [
		float(before["brace_force_n"]), float(before["tip_deflection_m"]), float(after["tip_deflection_m"]),
		float(structural["chain_force_ratio"]), String.num_scientific(float(after["equilibrium_residual_n"])),
	])

func _test_visual_scene() -> void:
	var packed := load(SCENE)
	_check(packed is PackedScene, "COMPLEX2-D visual lab loads")
	if packed is PackedScene:
		var scene := (packed as PackedScene).instantiate()
		_check(scene != null, "COMPLEX2-D visual lab instantiates")
		if scene != null:
			_check(String(scene.name) == "COMPLEX2DStructuralFailureLab", "COMPLEX2-D visual root exact")
			scene.free()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("COMPLEX2D_EXPERIMENT_HASH=%s" % _experiment_hash)
		print("FABRIC COMPLEX2-D Independent Structural Failure Acceptance: PASS (%d assertions) redundant_path=FAIL redistributed=PASS connected=PASS atomic_rebuild=FULL+CONTACT mixed=FULL_REFERENCE scene=PASS" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("COMPLEX2-D FAILURE: %s" % failure)
	print("FABRIC COMPLEX2-D Independent Structural Failure Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)
