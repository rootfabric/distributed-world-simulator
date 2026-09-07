extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/complex4_real_world_machine_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric1/complex4_real_world_machine_fixture_v1.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_run()
	_finish()

func _run() -> void:
	var initial := Fixture.initial_snapshot()
	var matter := Fixture.matter_batch()
	_assert_ok(Snapshot.validate(initial), "initial canonical machine invalid")
	_assert_ok(MatterBatch.validate(matter), "machine Matter invalid")
	var created := Fixture.create_store(initial)
	_assert_ok(created.result, "canonical store create failed")
	var store = created.store
	var rev0: Dictionary = store.get_snapshot(Fixture.CONSTRUCT_ID)
	var runtime := Runtime.new()
	_assert_ok(runtime.start(rev0, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH, 10), "COMPLEX4 runtime start failed")
	_assert(runtime.status().mode == "BAKED", "machine did not start BAKED")
	_assert(runtime.status().machine_state == "ON", "machine did not start ON")
	_assert(runtime.status().active_power_link_ids == [Fixture.POWER_A, Fixture.POWER_B], "initial power redundancy missing")
	var base := runtime.execute(rev0, matter, [1.0, 0.0])
	_assert_ok(base, "initial machine execution failed")
	_assert(base.details.machine_state == "ON", "initial execution state wrong")
	_assert(absf(float(base.details.functional.load_absorbed_power) - 36.0) <= 1.0e-9, "initial load power wrong")
	var canonical_start_hash := String(store.to_dict().checksum)

	var safe_a := runtime.observe_load(rev0, matter, Fixture.SUPPORT_A, 70.0, 11)
	_assert_ok(safe_a, "primary subcritical load failed")
	_assert(String(store.to_dict().checksum) == canonical_start_hash, "subcritical physical observation mutated canonical store")
	var overload_a := runtime.observe_load(rev0, matter, Fixture.SUPPORT_A, 90.0, 12)
	_assert_ok(overload_a, "primary overload failed")
	_assert(overload_a.details.proposal.canonical == false and overload_a.details.proposal.write_authorized == false, "primary overload claimed canonical authority")
	_assert(runtime.status().mode == "FULL", "primary overload did not refine to FULL")
	_assert(String(store.to_dict().checksum) == canonical_start_hash, "primary proposal mutated canonical store")

	var desired1 := Fixture.successor_with_broken_support(rev0, Fixture.SUPPORT_A)
	var applied1 := Fixture.apply_successor(store, rev0, desired1)
	_assert_ok(applied1.result, "external primary canonical mutation failed")
	var rev1: Dictionary = store.get_snapshot(Fixture.CONSTRUCT_ID)
	_assert(int(rev1.state_revision) == 1, "primary canonical revision did not advance")
	var event1 := "event/complex4/support-primary-broken"
	var observed1 := runtime.observe_canonical_successor(rev1, matter, event1, 13)
	_assert_ok(observed1, "primary canonical successor not observed")
	_assert(String(observed1.details.stale_error) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "primary stale BAKE not fenced")
	_assert(runtime.status().machine_state == "ON", "backup path did not keep machine ON")
	_assert(runtime.status().active_power_link_ids == [Fixture.POWER_B], "primary power path remained active")
	_assert(String(Fixture.bond(rev1, Fixture.POWER_A).state) == "INTACT", "derived primary functional failure mutated canonical power bond")
	_assert_error(runtime.execute(rev0, matter, [1.0, 0.0]), "BRIDGE4_CANONICAL_BINDING_STALE", "revision 0 remained executable")
	var full1 := runtime.execute(rev1, matter, [1.0, 0.0])
	_assert_ok(full1, "revision 1 FULL execution failed")
	_assert_ok(runtime.rebake(14), "revision 1 rebake failed")
	var baked1 := runtime.execute(rev1, matter, [1.0, 0.0])
	_assert_ok(baked1, "revision 1 BAKED execution failed")
	_assert(_max_error(full1.details.physical.boundary_flow, baked1.details.physical.boundary_flow) <= 2.0e-8, "revision 1 FULL/BAKE parity failed")

	var overload_b := runtime.observe_load(rev1, matter, Fixture.SUPPORT_B, 90.0, 15)
	_assert_ok(overload_b, "backup overload failed")
	_assert(runtime.status().mode == "FULL", "backup overload did not refine to FULL")
	var canonical_before_second := String(store.to_dict().checksum)
	_assert(runtime.status().canonical_writes == 0, "COMPLEX4 gained canonical write authority")
	_assert(String(store.to_dict().checksum) == canonical_before_second, "backup proposal mutated canonical store")
	var desired2 := Fixture.successor_with_broken_support(rev1, Fixture.SUPPORT_B)
	var applied2 := Fixture.apply_successor(store, rev1, desired2)
	_assert_ok(applied2.result, "external backup canonical mutation failed")
	var rev2: Dictionary = store.get_snapshot(Fixture.CONSTRUCT_ID)
	_assert(int(rev2.state_revision) == 2, "backup canonical revision did not advance")
	var event2 := "event/complex4/support-backup-broken"
	var observed2 := runtime.observe_canonical_successor(rev2, matter, event2, 16)
	_assert_ok(observed2, "backup canonical successor not observed")
	_assert(runtime.status().machine_state == "OFF", "machine did not switch OFF after redundant support loss")
	_assert(runtime.status().active_power_link_ids.is_empty(), "power path remained active after both structural failures")
	_assert(runtime.status().disabled_power_link_ids == [Fixture.POWER_A, Fixture.POWER_B], "disabled power set wrong after second failure")
	_assert(absf(float(runtime.status().load_absorbed_power)) < 1.0, "OFF machine still has load power")
	_assert(String(Fixture.bond(rev2, Fixture.POWER_A).state) == "INTACT" and String(Fixture.bond(rev2, Fixture.POWER_B).state) == "INTACT", "derived OFF state mutated canonical power bonds")
	_assert(runtime.status().functional_events.size() == 2, "functional event history count wrong")
	_assert(runtime.status().functional_events[0].before_state == "ON" and runtime.status().functional_events[0].after_state == "ON", "primary redundancy transition wrong")
	_assert(runtime.status().functional_events[1].before_state == "ON" and runtime.status().functional_events[1].after_state == "OFF", "backup loss transition wrong")
	var full2 := runtime.execute(rev2, matter, [1.0, 0.0])
	_assert_ok(full2, "revision 2 FULL execution failed")
	_assert_ok(runtime.rebake(17), "revision 2 rebake failed")
	var baked2 := runtime.execute(rev2, matter, [1.0, 0.0])
	_assert_ok(baked2, "revision 2 BAKED execution failed")
	_assert(baked2.details.machine_state == "OFF", "rebake changed functional OFF state")
	_assert(_max_error(full2.details.physical.boundary_flow, baked2.details.physical.boundary_flow) <= 2.0e-8, "revision 2 FULL/BAKE parity failed")

	var cap_result := runtime.capture_capsule()
	_assert_ok(cap_result, "COMPLEX4 capsule capture failed")
	var capsule: Dictionary = cap_result.details.capsule
	_assert(capsule.canonical == false and capsule.derived == true and capsule.discardable == true, "COMPLEX4 capsule truth boundary wrong")
	var restart_authority := Runtime.Bridge.Adapter.authority_for(rev2, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH)
	var authoritative_events := Utils.sorted_strings([event1, event2])
	var restarted := Runtime.new()
	_assert_ok(restarted.restore(rev2, matter, capsule, restart_authority, authoritative_events), "COMPLEX4 restart failed")
	var restarted_exec := restarted.execute(rev2, matter, [1.0, 0.0])
	_assert_ok(restarted_exec, "restarted machine execution failed")
	_assert(restarted_exec.details.machine_state == "OFF", "restart resurrected powered machine")
	_assert(absf(float(restarted_exec.details.functional.load_absorbed_power)) < 1.0, "restart restored nonzero load power")
	_assert(restarted.status().functional_events == runtime.status().functional_events, "restart changed functional event history")
	_assert_error(Runtime.new().restore(rev1, matter, capsule, restart_authority, authoritative_events), "COMPLEX4_CAPSULE_STALE", "revision 1 accepted revision 2 capsule")
	_assert(restarted.status().canonical_writes == 0, "restarted COMPLEX4 gained canonical authority")

	var hash := Utils.canonical_hash({
		"canonical_store": store.to_dict().checksum,
		"events": restarted.status().functional_events,
		"state": restarted.status().machine_state,
		"links": restarted.status().active_power_link_ids,
		"load_power": restarted.status().load_absorbed_power,
		"bridge_binding": restarted.status().bridge.binding_checksum,
		"transition_hash": restarted.status().bridge.fabric1.transition_hash,
	})
	print("COMPLEX4_BCD_REV0_STATE=ON")
	print("COMPLEX4_BCD_REV1_STATE=" + str(runtime.status().functional_events[0].after_state))
	print("COMPLEX4_BCD_REV2_STATE=" + str(restarted.status().machine_state))
	print("COMPLEX4_BCD_FINAL_POWER=" + str(restarted.status().load_absorbed_power))
	print("COMPLEX4_BCD_HASH=%s" % hash)

func _max_error(left: Array, right: Array) -> float:
	var result := 0.0
	for index in range(mini(left.size(), right.size())):
		result = maxf(result, absf(float(left[index]) - float(right[index])))
	return result

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("FABRIC COMPLEX4-BCD Real World Machine: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FABRIC COMPLEX4-BCD Real World Machine: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
