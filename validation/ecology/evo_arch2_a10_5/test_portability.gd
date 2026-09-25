extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P13 SCENE PORTABILITY (§26) +
# PRESENTATION ISOLATION (§27) acceptance validation.
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
#
# §26 SCENE PORTABILITY — the SAME EcologyWorkbench scene runs in two hosts:
#   Variant A: PolygonLabHost (existing lab scene, lab fixtures).
#   Variant B: SimulatorLikeHost (minimal simulator-like host with a
#   pre-existing world stub: ground + external camera + light + player stub;
#   then the workbench is added and ITS controller is bound into it).
# Checks:
#   a) both hosts instantiate the same workbench scene with a bound controller;
#   b) in Variant B the workbench did NOT create its own world/camera/light/
#      player authority — camera/light/player belong to the host's
#      ExistingWorld, never to the workbench (both variants);
#   c) identical manifest + seed -> IDENTICAL canonical_state_hash after 8
#      ticks in both hosts (host composition does not affect canonical truth);
#   d) the same hash equals a plain controller run of the same manifest
#      (composition-independence baseline).
#
# §27 PRESENTATION ISOLATION — for each presentation configuration the final
# canonical hash after 8 ticks is IDENTICAL:
#   presentation OFF / ON LOW LOD / ON HIGH LOD / inspector OPEN (full
#   inspector compile + render through the selection path) / inspector CLOSED.

const LabScene = preload("res://scenes/labs/ecology/eco_arch2_polygon_lab.tscn")
const SimulatorLikeHost = preload("res://scripts/labs/ecology/eco_arch2_simulator_like_host.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Inspector = preload("res://scripts/ecology/workbench/organism_inspector_v1.gd")

const TICKS := 8

var checks := 0
var failures: Array[String] = []
var lab: Node = null
var sim_host: Node = null
var workbench_a: Node = null
var workbench_b: Node = null

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P13_PORT_FAIL " + message)

# --- §26 scene portability --------------------------------------------------------

func _run_variant(variant_name: String, host: Node) -> Node:
	var workbench: Node = host.get_node_or_null("EcologyWorkbench")
	_check(workbench != null, "%s host instantiated the EcologyWorkbench" % variant_name)
	var controller: Object = host.get("controller")
	_check(controller != null, "%s host created its ExperimentController" % variant_name)
	if workbench == null or controller == null:
		return null
	_check(workbench.get("controller") == controller, "%s workbench is bound to the host controller" % variant_name)
	# Ownership: no camera / light / player authority inside the workbench.
	var cameras: Array = workbench.find_children("*", "Camera3D", true, false)
	_check(cameras.is_empty(), "%s workbench owns no camera" % variant_name)
	var lights: Array = workbench.find_children("*", "DirectionalLight3D", true, false)
	_check(lights.is_empty(), "%s workbench owns no light" % variant_name)
	_check(workbench.get_node_or_null("ExistingWorld") == null, "%s workbench creates no world root" % variant_name)
	_check(workbench.get_node_or_null("PlayerStub") == null, "%s workbench creates no player" % variant_name)
	return workbench

func _run() -> void:
	# --- Variant A: the existing polygon lab scene -----------------------------
	lab = LabScene.instantiate()
	root.add_child(lab)
	workbench_a = _run_variant("A(lab)", lab)

	# --- Variant B: the simulator-like host (world stub FIRST, workbench after)
	sim_host = SimulatorLikeHost.new()
	root.add_child(sim_host)
	workbench_b = _run_variant("B(simulator-like)", sim_host)
	if workbench_a == null or workbench_b == null:
		_finish()
		return

	# Variant B host-owned authority: camera/light/player belong to the host's
	# pre-existing world stub, not to the workbench.
	var world_stub: Node = sim_host.get_node_or_null("ExistingWorld")
	_check(world_stub != null, "B host created the pre-existing world stub")
	if world_stub != null:
		var sim_cameras: Array = world_stub.find_children("*", "Camera3D", true, false)
		_check(sim_cameras.size() == 1 and String(sim_cameras[0].name) == "SimCamera", "B world camera belongs to the host world stub")
		var sim_lights: Array = world_stub.find_children("*", "DirectionalLight3D", true, false)
		_check(sim_lights.size() == 1 and String(sim_lights[0].name) == "SimLight", "B world light belongs to the host world stub")
		_check(world_stub.get_node_or_null("PlayerStub") != null, "B player stub belongs to the host world stub")
		for node in world_stub.find_children("*", "", true, false):
			_check(node.get_parent() != workbench_b, "B world-stub node %s is not parented under the workbench" % String(node.name))
	# The workbench in Variant B never created a SECOND camera anywhere.
	var all_host_cameras: Array = sim_host.find_children("*", "Camera3D", true, false)
	_check(all_host_cameras.size() == 1, "B exactly one camera exists in the whole composition (host-owned), got %d" % all_host_cameras.size())

	# --- identical manifest+seed -> identical canonical hash after 8 ticks -----
	var ok_a: bool = workbench_a.command_step_n(TICKS)
	var ok_b: bool = workbench_b.command_step_n(TICKS)
	_check(ok_a, "A 8 ticks through the workbench command path succeed")
	_check(ok_b, "B 8 ticks through the workbench command path succeed")
	var controller_a: Object = lab.get("controller")
	var controller_b: Object = sim_host.get("controller")
	var hash_a := String(controller_a.get_snapshot().canonical_state_hash)
	var hash_b := String(controller_b.get_snapshot().canonical_state_hash)
	_check(not hash_a.is_empty() and not hash_b.is_empty(), "both variants expose a canonical_state_hash")
	_check(hash_a == hash_b, "§26 same manifest+seed -> SAME canonical_state_hash in both hosts (%s vs %s)" % [hash_a.substr(0, 12), hash_b.substr(0, 12)])

	# Composition-independence baseline: a plain controller run of the same
	# manifest (no workbench at all) reaches the identical hash.
	var bare := Controller.new()
	var bare_manifest: Dictionary = controller_a.get_manifest()
	_check(bare.initialize(bare_manifest, {}).get("success", false), "bare controller initialize succeeds")
	_check(bare.run(TICKS).get("success", false), "bare controller run(8) succeeds")
	_check(String(bare.get_snapshot().canonical_state_hash) == hash_a, "§26 both host hashes equal the bare controller run hash")

	# --- §27 presentation isolation --------------------------------------------
	_test_presentation_isolation("A(lab)", workbench_a, controller_a, hash_a)
	_test_presentation_isolation("B(simulator-like)", workbench_b, controller_b, hash_b)

	_finish()

# --- §27 presentation isolation ---------------------------------------------------

func _hash_after_8(variant_name: String, workbench: Node) -> String:
	if not bool(workbench.command_reset()):
		_check(false, "%s command_reset succeeds" % variant_name)
		return ""
	if not bool(workbench.command_step_n(TICKS)):
		_check(false, "%s 8 ticks after reset succeed" % variant_name)
		return ""
	var snapshot: Dictionary = workbench.get("controller").get_snapshot()
	return String(snapshot.canonical_state_hash)

func _test_presentation_isolation(variant_name: String, workbench: Node, controller: Object, baseline_hash: String) -> void:
	var first_id := ""
	for view in workbench.get("organism_views"):
		first_id = String(view.canonical_entity_id)
		break

	# 1. Presentation fully OFF (LOD-minimal marker fallback).
	workbench.set_morphology_enabled(false)
	var hash_off := _hash_after_8(variant_name, workbench)
	_check(hash_off == baseline_hash, "%s §27 presentation OFF: canonical hash identical" % variant_name)

	# 2. ON, LOW LOD.
	workbench.set_morphology_enabled(true)
	workbench.set_morphology_lod("LOW")
	var hash_low := _hash_after_8(variant_name, workbench)
	_check(hash_low == baseline_hash, "%s §27 presentation ON LOW LOD: canonical hash identical" % variant_name)

	# 3. ON, HIGH LOD (default detail).
	workbench.set_morphology_lod("HIGH")
	var hash_high := _hash_after_8(variant_name, workbench)
	_check(hash_high == baseline_hash, "%s §27 presentation ON HIGH LOD: canonical hash identical" % variant_name)

	# 4. Inspector OPEN: selection fires the full inspector compile + render.
	if first_id.is_empty():
		_check(false, "%s an organism exists for the inspector path" % variant_name)
	else:
		workbench.select_entity(first_id)
		var content: Label = workbench.get_node_or_null("WorkbenchUI/InspectorPanel/InspectorContent") as Label
		_check(content != null and not content.text.is_empty(), "%s inspector opened and rendered content" % variant_name)
		if content != null:
			_check(content.text.contains("GENOME") and content.text.contains("LINEAGE"), "%s inspector render covers genome..lineage chain" % variant_name)
		var hash_open := _hash_after_8(variant_name, workbench)
		_check(hash_open == baseline_hash, "%s §27 inspector OPEN during ticks: canonical hash identical" % variant_name)
		# Direct read-only compile+render also changes nothing.
		var inspected: Dictionary = Inspector.compile(controller, first_id)
		_check(bool(inspected.get("success", false)), "%s direct inspector compile succeeds" % variant_name)
		if bool(inspected.get("success", false)):
			var text := Inspector.render_text(inspected.view)
			_check(not text.is_empty(), "%s direct inspector render produces text" % variant_name)
		_check(String(controller.get_snapshot().canonical_state_hash) == hash_open, "%s §27 direct inspector compile leaves the hash unchanged" % variant_name)

		# 5. Inspector CLOSED (empty selection).
		workbench.select_entity("")
		var content_closed: Label = workbench.get_node_or_null("WorkbenchUI/InspectorPanel/InspectorContent") as Label
		_check(content_closed != null and content_closed.text.is_empty(), "%s inspector closed clears content" % variant_name)
		var hash_closed := _hash_after_8(variant_name, workbench)
		_check(hash_closed == baseline_hash, "%s §27 inspector CLOSED: canonical hash identical" % variant_name)

	# Restore the default presentation state for later users.
	workbench.set_morphology_enabled(true)
	workbench.set_morphology_lod("HIGH")

func _finish() -> void:
	print("EVO_ARCH2_A10_5_PORTABILITY_P13 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_PORTABILITY_P13 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P13_PORT_FAILURE " + failure)
		quit(1)
