extends SceneTree

const EventStep = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_event_step_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_runtime_v1.gd")
const Bridge = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_fixture_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")

const TARGET_BOND_ID := "bond/g2|weak|support"

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	var guard := EventStep._parse_transition_id("guard|bond/support|segment|1.0")
	_check(guard.get("ok", false), "G2-BOND-ID guard transition parses", guard)
	_check(str(guard.get("element_id", "")) == "bond/support|segment", "G2-BOND-ID embedded delimiter preserved", guard)
	_check(float(guard.get("sign", 0.0)) == 1.0, "G2-BOND-ID positive sign preserved", guard)
	var polynomials := {"bond/support|segment": {"sentinel": true}}
	_check(polynomials.has(str(guard.get("element_id", ""))), "G2-BOND-ID parsed key reaches polynomial lookup", guard)

	var failure := EventStep._parse_transition_id("failure|bond/a|b|c|-1.0")
	_check(failure.get("ok", false) and str(failure.get("element_id", "")) == "bond/a|b|c" and float(failure.get("sign", 0.0)) == -1.0, "G2-BOND-ID failure transition preserves full id", failure)

	var runtime_failure := Runtime._failure_transition("failure|bond/a|b|c|-1.0")
	_check(runtime_failure.get("ok", false) and str(runtime_failure.get("bond_id", "")) == "bond/a|b|c", "G2-BOND-ID runtime proposal preserves full id", runtime_failure)
	var runtime_initial := Runtime._failure_transition("failure|bond/a|b|c|-1.0|initial")
	_check(runtime_initial.get("ok", false) and str(runtime_initial.get("bond_id", "")) == "bond/a|b|c", "G2-BOND-ID initial-condition suffix preserves full id", runtime_initial)
	_check(not Runtime._failure_transition("guard|bond/a|1.0").get("ok", true), "G2-BOND-ID runtime rejects non-failure transition")

	var malformed := EventStep._parse_transition_id("guard||1.0")
	_check(not malformed.get("ok", true) and malformed.get("code") == "R3_GENERAL_EVENT_TRANSITION_SHAPE", "G2-BOND-ID empty element fails closed", malformed)
	malformed = EventStep._parse_transition_id("other|bond/a|1.0")
	_check(not malformed.get("ok", true) and malformed.get("code") == "R3_GENERAL_EVENT_TRANSITION_SHAPE", "G2-BOND-ID unknown transition kind fails closed", malformed)

	_end_to_end_failure_commit()

	print("G2_BOND_ID_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FABRIC-HOLDOUT-R4-G2-BOND-ID: PASS")
		quit(0)
	else:
		print("G2_BOND_ID_FAILURES=", JSON.stringify(failures))
		print("FABRIC-HOLDOUT-R4-G2-BOND-ID: FAIL")
		quit(1)

func _end_to_end_failure_commit() -> void:
	var sources := _generalized_sources()
	var authority := Fixture.authority(sources, "server/g2-bond-id", 19)
	var bridge = Bridge.new()
	var initialized: Dictionary = bridge.initialize(sources, authority)
	_check(initialized.success, "G2-BOND-ID generalized runtime initializes", initialized)
	if not initialized.success: return

	var snapshot: Dictionary = bridge.inspect()
	var dt := minf(0.005, float(snapshot.max_step_s))
	for step_index in range(600):
		snapshot = bridge.inspect()
		if not snapshot.pending_proposal.is_empty(): break
		var advanced := bridge.execute(bridge.make_command("advance", {"dt_s": dt}, authority), authority)
		if not advanced.success:
			_check(false, "G2-BOND-ID advance reaches failure proposal step %d" % step_index, advanced)
			return

	snapshot = bridge.inspect()
	_check(not snapshot.pending_proposal.is_empty(), "G2-BOND-ID runtime creates failure proposal", snapshot)
	if snapshot.pending_proposal.is_empty(): return
	_check(str(snapshot.pending_proposal.bond_id) == TARGET_BOND_ID, "G2-BOND-ID pending proposal keeps full bond id", snapshot.pending_proposal)

	var committed := bridge.execute(bridge.make_command("commit_failure", {"event_id": snapshot.pending_proposal.event_id}, authority), authority)
	_check(committed.success, "G2-BOND-ID canonical failure commit accepts full bond id", committed)
	if not committed.success: return

	var after: Dictionary = bridge.inspect()
	_check(after.pending_proposal.is_empty(), "G2-BOND-ID committed proposal clears pending state", after.pending_proposal)
	var canonical_bond_state := ""
	for bond in bridge.sources().mechanical.bonds:
		if str(bond.bond_id) == TARGET_BOND_ID:
			canonical_bond_state = str(bond.state)
			break
	_check(canonical_bond_state == "BROKEN", "G2-BOND-ID canonical successor breaks exact bond", canonical_bond_state)
	var support_found := false
	var support_active := true
	for support in after.supports:
		if str(support.bond_id) == TARGET_BOND_ID:
			support_found = true
			support_active = bool(support.active)
			break
	_check(support_found and not support_active, "G2-BOND-ID rebuilt physical system removes exact bond", after.supports)

func _generalized_sources() -> Dictionary:
	var sources: Dictionary = Fixture.create({"label": "g2-delimiter-runtime", "capacity": [0.35, 1000.0]})
	var mechanical: Dictionary = sources.mechanical.duplicate(true)
	mechanical.bonds[0].bond_id = TARGET_BOND_ID
	var controls: Dictionary = mechanical.compiled_facets.composition_r3.duplicate(true)
	controls["coupler_node_id"] = "part/g2-delimiter-runtime-slider"
	var mechanical_facets := {"composition_r3": controls}
	sources.mechanical = Snapshot.create(mechanical.construct_id, mechanical.root_item_instance_id, mechanical.state_revision, mechanical.build_state, mechanical.parts, mechanical.bonds, mechanical_facets)

	var electrical: Dictionary = sources.electrical.duplicate(true)
	var boundary_voltages := {str(electrical.parts[0].part_id): 12.0, str(electrical.parts[2].part_id): 0.0}
	var electrical_facets := {"composition_r3_boundary_voltages_v": boundary_voltages}
	sources.electrical = Snapshot.create(electrical.construct_id, electrical.root_item_instance_id, electrical.state_revision, electrical.build_state, electrical.parts, electrical.bonds, electrical_facets)
	return sources

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)
