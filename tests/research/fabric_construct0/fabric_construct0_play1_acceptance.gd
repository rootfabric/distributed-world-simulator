extends SceneTree

const Contract = preload("res://scripts/labs/fabric_construct0/construct0_toybox_contract.gd")
const Factory = preload("res://scripts/labs/fabric_construct0/construct0_toybox_factory.gd")
const Runtime = preload("res://scripts/labs/fabric_construct0/construct0_toybox_runtime.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")

var _assertions := 0
var _failures: Array[String] = []

func _init() -> void:
	_test_contract()
	_test_all_presets()
	_test_inclined_plane()
	_test_seesaw()
	_test_cart()
	_test_catapult()
	_test_breakable_bridge()
	_test_determinism()
	_test_scene()
	_finish()

func _test_contract() -> void:
	_check(Contract.EXPERIMENTS == [
		"INCLINED_PLANE",
		"SEESAW",
		"CART",
		"CATAPULT",
		"BREAKABLE_BRIDGE",
	], "mandatory experiment order")
	_check(Contract.PART_KINDS.has("WHEEL"), "generic WHEEL part")
	_check(Contract.RELATION_KINDS.has("HINGE"), "generic HINGE relation")
	_check(Contract.RELATION_KINDS.has("SLIDER"), "generic SLIDER relation")
	_check(Contract.RELATION_KINDS.has("SPRING_DAMPER"), "generic SPRING_DAMPER relation")
	_check(Contract.RELATION_KINDS.has("BREAKABLE"), "generic BREAKABLE relation")
	_check(not Contract.RELATION_KINDS.has("GEARBOX"), "no device-specific GEARBOX relation")
	_check(not Contract.RELATION_KINDS.has("MOTOR"), "no device-specific MOTOR relation")

func _test_all_presets() -> void:
	for experiment_id in Contract.EXPERIMENTS:
		var built := Factory.build(experiment_id)
		_check(bool(built.get("success", false)), "%s canonical build" % experiment_id)
		if not bool(built.get("success", false)):
			continue
		var snapshot: Dictionary = built["snapshot"]
		_check(bool(SnapshotScript.validate(snapshot).get("success", false)), "%s snapshot validates" % experiment_id)
		_check(Array(snapshot["parts"]).size() >= 2, "%s compound part count" % experiment_id)
		_check(Array(snapshot["bonds"]).size() >= 1, "%s relation/bond count" % experiment_id)
		_check(String(snapshot["checksum"]).length() == 64, "%s canonical checksum" % experiment_id)
		for relation_any in built["relations"]:
			var relation: Dictionary = relation_any
			_check(Contract.RELATION_KINDS.has(String(relation["kind"])), "%s relation generic" % experiment_id)

func _test_inclined_plane() -> void:
	var built := Factory.build("INCLINED_PLANE")
	var runtime = Runtime.new()
	var ready := runtime.setup(built)
	_check(bool(ready.get("success", false)), "inclined runtime setup")
	if not bool(ready.get("success", false)):
		return
	var initial := runtime.state()
	_check(String(initial["metrics"]["contact_mode"]) == "STICK", "20 degree ramp initially sticks")
	_check(String(initial["metrics"]["b0_3_model_hash"]).length() == 64, "inclined uses real B0.3 model")
	_check(int(initial["metrics"]["b0_3_generator_count"]) >= 4, "inclined B0.3 reduced generators")
	var before_q := float(initial["metrics"]["coordinate_m"])
	var stepped := runtime.advance(0.1)
	_check(bool(stepped.get("success", false)), "inclined stick advance")
	_check(absf(float(runtime.state()["metrics"]["coordinate_m"]) - before_q) <= 1.0e-10, "stick holds coordinate")
	var force := runtime.apply_tool("FORCE", 100.0)
	_check(bool(force.get("success", false)), "inclined FORCE tool")
	_check(String(runtime.state()["metrics"]["contact_mode"]) == "SLIDE", "force pushes ramp contact into slide")
	runtime.advance(0.2)
	_check(float(runtime.state()["metrics"]["coordinate_m"]) > before_q, "sliding coordinate advances")

func _test_seesaw() -> void:
	var built := Factory.build("SEESAW")
	var runtime = Runtime.new()
	var ready := runtime.setup(built)
	_check(bool(ready.get("success", false)), "seesaw runtime setup")
	if not bool(ready.get("success", false)):
		return
	var q0 := float(runtime.state()["metrics"]["angle_rad"])
	runtime.advance(0.25)
	var q1 := float(runtime.state()["metrics"]["angle_rad"])
	_check(q1 < q0, "seesaw responds to unbalanced torque")
	var torque := runtime.apply_tool("TORQUE", 100.0)
	_check(bool(torque.get("success", false)), "seesaw TORQUE tool")
	runtime.advance(0.25)
	_check(is_finite(float(runtime.state()["metrics"]["angle_rad"])), "seesaw angle finite")
	_check(is_finite(float(runtime.state()["metrics"]["omega_rad_s"])), "seesaw omega finite")

func _test_cart() -> void:
	var built := Factory.build("CART")
	var runtime = Runtime.new()
	var ready := runtime.setup(built)
	_check(bool(ready.get("success", false)), "cart runtime setup")
	if not bool(ready.get("success", false)):
		return
	runtime.advance(0.5)
	var state1 := runtime.state()
	_check(float(state1["metrics"]["coordinate_m"]) > 0.0, "cart moves under ideal force")
	var v1 := float(state1["metrics"]["velocity_m_s"])
	var impulse := runtime.apply_tool("IMPULSE", 20.0)
	_check(bool(impulse.get("success", false)), "cart IMPULSE tool")
	_check(float(runtime.state()["metrics"]["velocity_m_s"]) > v1, "cart impulse increases velocity")
	var mass1 := float(runtime.state()["metrics"]["effective_mass_kg"])
	var load := runtime.apply_tool("ADD_LOAD", 250.0)
	_check(bool(load.get("success", false)), "cart ADD_LOAD tool")
	_check(float(runtime.state()["metrics"]["effective_mass_kg"]) > mass1, "cart load increases effective mass")
	runtime.advance(0.2)
	_check(is_finite(float(runtime.state()["metrics"]["wheel_angle_rad"])), "wheel/axle ratio state finite")

func _test_catapult() -> void:
	var built := Factory.build("CATAPULT")
	var runtime = Runtime.new()
	var ready := runtime.setup(built)
	_check(bool(ready.get("success", false)), "catapult runtime setup")
	if not bool(ready.get("success", false)):
		return
	var initial_revision := int(runtime.state()["canonical_revision"])
	var released := false
	for _i in range(500):
		var step := runtime.advance(0.005)
		if not bool(step.get("success", false)):
			_check(false, "catapult DAE advance")
			return
		if bool(runtime.state()["metrics"]["released"]):
			released = true
			break
	_check(released, "spring/hinge catapult releases breakable payload")
	if released:
		_check(String(runtime.state()["metrics"]["mode"]) == "released", "catapult hybrid mode released")
		_check(int(runtime.state()["canonical_revision"]) == initial_revision + 1, "payload release mutates canonical bond state")
		var snapshot := runtime.canonical_snapshot()
		var latch_broken := false
		for bond_any in snapshot["bonds"]:
			var bond: Dictionary = bond_any
			if String(bond["bond_id"]).ends_with("payload-latch"):
				latch_broken = String(bond["state"]) == "BROKEN"
		_check(latch_broken, "breakable payload latch is canonical BROKEN")
		runtime.advance(0.2)
		var payload_override: Dictionary = runtime.state()["part_overrides"][String(built["runtime_params"]["payload_part_id"])]
		var p: Vector3 = payload_override["position"]
		_check(is_finite(p.x) and is_finite(p.y), "released payload ballistic pose finite")

func _test_breakable_bridge() -> void:
	var built := Factory.build("BREAKABLE_BRIDGE")
	var runtime = Runtime.new()
	var ready := runtime.setup(built)
	_check(bool(ready.get("success", false)), "bridge runtime setup")
	if not bool(ready.get("success", false)):
		return
	var initial_revision := int(runtime.state()["canonical_revision"])
	var broke := false
	for _i in range(12):
		var result := runtime.apply_tool("ADD_LOAD", 250.0)
		if not bool(result.get("success", false)):
			_check(false, "bridge ADD_LOAD execution")
			return
		if int(runtime.state()["canonical_revision"]) > initial_revision:
			broke = true
			break
	_check(broke, "bridge overload breaks canonical BREAKABLE bond")
	if broke:
		_check(int(runtime.state()["metrics"]["intact_bonds"]) < Array(built["snapshot"]["bonds"]).size(), "bridge intact bond count drops")
		var found_event := false
		for event_any in runtime.state()["events"]:
			if String(Dictionary(event_any).get("event", "")) == "BREAKABLE_BOND_FAILED":
				found_event = true
		_check(found_event, "bridge failure event emitted")

func _test_determinism() -> void:
	var built := Factory.build("CART")
	var a = Runtime.new()
	var b = Runtime.new()
	_check(bool(a.setup(built).get("success", false)), "determinism runtime A")
	_check(bool(b.setup(built).get("success", false)), "determinism runtime B")
	for _i in range(60):
		a.advance(1.0 / 120.0)
		b.advance(1.0 / 120.0)
	_check(a.state_hash() == b.state_hash(), "fixed-step toybox state deterministic")

func _test_scene() -> void:
	var packed = load("res://scenes/labs/fabric_construct0_play1_lab.tscn")
	_check(packed is PackedScene, "PLAY1 scene parses")
	if packed is PackedScene:
		var instance = packed.instantiate()
		_check(instance is Node3D, "PLAY1 scene instantiates")
		instance.free()

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC CONSTRUCT0 PLAY1 Acceptance: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error("CONSTRUCT0 PLAY1: %s" % failure)
	print("FABRIC CONSTRUCT0 PLAY1 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _assertions])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)
