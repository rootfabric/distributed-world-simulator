extends SceneTree

const Runtime = preload("res://scripts/labs/fabric_construct0/construct0_lifecycle_runtime.gd")

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var runtime = Runtime.new()
	var ready: Dictionary = runtime.setup()
	_check(bool(ready.get("success", false)), "C0.6 setup")
	if bool(ready.get("success", false)):
		var local: Dictionary = runtime.trigger_local_unbake(30.0)
		_check(bool(local.get("success", false)), "bounded local unbake succeeds")
		if bool(local.get("success", false)):
			var state: Dictionary = runtime.state()
			var m: Dictionary = state["metrics"]
			_check(String(state["status"]) == "STRUCTURAL_BOUNDED_LOCAL_UNBAKE_READY", "local unbake status ready")
			_check(String(state["effective_representation"]) == "MIXED_FULL_BAKED", "mixed representation visible")
			_check(int(m["full_part_count"]) == 20, "only 20 parts go FULL")
			_check(int(m["retained_part_count"]) == 480, "480 parts remain reduced")
			_check(int(m["retained_component_count"]) == 2, "two retained reduced components")
			_check(int(m["cut_interface_count"]) == 2, "two cut interfaces")
			_check(int(m["full_dof"]) == 6500, "full baseline 6500 DOF")
			_check(int(m["mixed_dof"]) == 286, "mixed lifecycle 286 DOF")
			_check(float(m["preserved_reduction_ratio"]) > 22.7, "local unbake retains >22.7x reduction")
			_check(absf(float(m["unbaked_fraction"]) - 0.04) <= 1.0e-12, "only 4 percent unbaked")
			_check(float(m["mass_error"]) <= 1.0e-8, "local unbake mass conserved")
			_check(float(m["linear_momentum_error"]) <= 1.0e-8, "local unbake linear momentum conserved")
			_check(float(m["angular_momentum_error"]) <= 1.0e-8, "local unbake angular momentum conserved")
			_check(float(m["max_interface_position_error"]) <= 1.0e-9, "interface position continuity")
			_check(float(m["max_interface_velocity_error"]) <= 1.0e-9, "interface velocity continuity")
			_check(String(m["next_required_stage"]) == "B0.2-E_TOPOLOGY_SPLIT_REBAKE", "topology stage explicitly next")
			_check(Array(state["full_part_ids"]).size() == 20, "20 FULL part IDs exposed for visualization")

		var rebaked: Dictionary = runtime.break_split_and_rebake()
		_check(bool(rebaked.get("success", false)), "bond break split/rebake succeeds")
		if bool(rebaked.get("success", false)):
			var state2: Dictionary = runtime.state()
			var m2: Dictionary = state2["metrics"]
			_check(String(state2["status"]) == "STRUCTURAL_TOPOLOGY_SPLIT_REBAKED", "topology lifecycle status ready")
			_check(String(state2["effective_representation"]) == "REBAKED_COMPONENTS", "rebaked representation visible")
			_check(String(m2["event_state"]) == "APPLIED", "topology event exactly applied")
			_check(int(m2["split_component_count"]) == 2, "split yields two components")
			_check(int(m2["invalidated_reduced_piece_count"]) == 3, "three predecessor reduced pieces invalidated")
			_check(int(m2["executable_artifact_count"]) == 2, "two executable new bake artifacts")
			_check(int(m2["full_dof"]) == 6500, "split baseline full DOF")
			_check(int(m2["mixed_before_event_dof"]) == 286, "event starts from mixed 286 DOF")
			_check(int(m2["rebaked_dof"]) == 26, "two rebaked rigid components = 26 DOF")
			_check(absf(float(m2["post_split_reduction_ratio"]) - 250.0) <= 1.0e-12, "post split reduction 250x")
			_check(float(m2["mass_error"]) <= 1.0e-8, "split/rebake mass conserved")
			_check(float(m2["linear_momentum_error"]) <= 1.0e-8, "split/rebake linear momentum conserved")
			_check(float(m2["angular_momentum_error"]) <= 1.0e-8, "split/rebake angular momentum conserved")
			_check(float(m2["max_state_handoff_error"]) <= 1.0e-9, "split/rebake state continuity")
			_check(bool(m2["physical_bake_artifact_emitted"]), "new PhysicalBakeArtifacts emitted")
			_check(Array(state2["rebaked_components"]).size() == 2, "two rebaked component descriptors visible")

	var a = Runtime.new()
	var b = Runtime.new()
	var ra: Dictionary = a.setup()
	var rb: Dictionary = b.setup()
	_check(bool(ra.get("success", false)) and bool(rb.get("success", false)), "determinism pair setup")
	if bool(ra.get("success", false)) and bool(rb.get("success", false)):
		a.trigger_local_unbake(30.0)
		b.trigger_local_unbake(30.0)
		_check(JSON.stringify(a.state()["metrics"]) == JSON.stringify(b.state()["metrics"]), "local unbake deterministic")
		a.break_split_and_rebake()
		b.break_split_and_rebake()
		_check(JSON.stringify(a.state()["metrics"]) == JSON.stringify(b.state()["metrics"]), "split/rebake deterministic")

	var packed = load("res://scenes/labs/fabric_construct0_c0_4_c0_6_lab.tscn")
	_check(packed is PackedScene, "lifecycle lab scene parses")
	if packed is PackedScene:
		var instance = packed.instantiate()
		_check(instance is Node3D, "lifecycle lab scene instantiates")
		instance.free()

	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC CONSTRUCT0 C0.6 Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("CONSTRUCT0 C0.6: %s" % failure)
	print("FABRIC CONSTRUCT0 C0.6 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
