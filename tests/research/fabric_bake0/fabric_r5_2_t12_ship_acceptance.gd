extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
const Ship = preload("res://scripts/research/fabric_bake0/r5_t12_ship_runtime_v1.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_fixture.gd")
const STEPS := 2048
const DT := 0.002
var checks := 0
var failures: Array = []

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("T12: " + label + " " + JSON.stringify(details))

func failed_atomically(result: Dictionary, before: Dictionary, state: Dictionary, label: String) -> void:
	check(not result.success and not result.details.has("next_state") and before == state, label, result)

func _initialize() -> void:
	var compiled := F.make_ship()
	check(compiled.success, "compile nested ship", compiled)
	if not compiled.success: quit(1); return
	var b: Dictionary = compiled.details
	var ship = Ship.new()
	var prepared: Dictionary = ship.prepare(b, b.capsule.checksum)
	check(prepared.success, "prepare externally anchored ship", prepared)
	if not prepared.success: quit(1); return
	if "--preflight" in OS.get_cmdline_user_args():
		print("FABRIC_R5_2_T12_PREFLIGHT=PASS"); quit(0); return
	check(int(prepared.details.state_scalars) == 31, "31 independently owned state scalars")
	check(int(b.capsule.source_component_count) == 4275, "4275 leaf components represented")
	check(b.children.bank.capsule.executable_kind == "T12_BANK" and b.children.bank.children.unit03.capsule.executable_kind == "T12_TURRET", "bank and modules own capsules")
	var live := C.live_tree(b)
	var initial: Dictionary = ship.initial_state()
	var state: Dictionary = initial.duplicate(true)
	var max_energy := 0.0; var max_bus := 0.0; var total_optical := 0.0; var total_pump := 0.0
	var traversals := 0; var evaluations := 0; var max_evaluations := 0; var calls := 0; var group_visits := 0
	var max_reference_current_error := 0.0
	var min_voltage := INF; var max_voltage := 0.0
	var moved := false; var nonidentical := false
	for tick in range(STEPS):
		var commands := F.commands()
		for i in range(3):
			var slot := "unit%02d" % (i + 1)
			commands[slot].laser_current_a = 400.0 if (tick + 11 * i) % 96 < 32 else 0.0
			commands[slot].target_position_rad = (0.25 if tick < 1100 else -0.15) * float(i + 1) / 3.0
			commands[slot].external_torque_nm = -float(i)
		var before: Dictionary = state.duplicate(true)
		var step: Dictionary = ship.execute(live, state, commands, 294.0, DT)
		check(step.success, "coupled sequence step", {"tick":tick, "error":step.error_code})
		if not step.success: break
		check(state == before, "trials never mutate caller state")
		var d: Dictionary = step.details
		max_energy = maxf(max_energy, absf(float(d.energy_residual_j)))
		max_bus = maxf(max_bus, absf(float(d.bus_residual_j)))
		check(absf(float(d.battery_electrical_j) - float(d.load_electrical_j)) <= Ship.BUS_TOL_J, "shared-bus electrical closure")
		var draw := float(d.battery_current_a) * DT
		check(absf(float(before.battery.group_charge_c[0]) - float(d.next_state.battery.group_charge_c[0]) - draw) < 1.0e-8, "canonical charge integrates solved current")
		traversals += int(d.metrics.leaf_traversals)
		evaluations += int(d.metrics.evaluations); max_evaluations = maxi(max_evaluations, int(d.metrics.evaluations))
		calls += int(d.metrics.boundary_calls); group_visits += int(d.metrics.compiled_group_visits)
		total_optical += float(d.muzzle_j); total_pump += float(d.pump_j)
		min_voltage = minf(min_voltage, float(d.bus_voltage_v)); max_voltage = maxf(max_voltage, float(d.bus_voltage_v))
		if tick % 128 == 0:
			var reference: Dictionary = ship.execute(live, before, commands, 294.0, DT, true)
			check(reference.success, "independent bisection bus oracle", reference.error_code)
			if reference.success:
				max_reference_current_error = maxf(max_reference_current_error, absf(float(reference.details.battery_current_a) - float(d.battery_current_a)))
		state = d.next_state
		moved = moved or absf(float(state.bank.unit03.servo.output_position_rad)) > 0.01
		nonidentical = nonidentical or state.bank.unit01 != state.bank.unit03
	check(float(state.battery.group_charge_c[0]) < float(initial.battery.group_charge_c[0]), "battery discharged by actual loads")
	check(moved and nonidentical, "independent module commands change physical state")
	check(total_optical > 0.0 and total_pump > 0.0, "emission and pump work paid")
	check(traversals == 0, "no source leaf traversal in any solver evaluation")
	check(group_visits == evaluations * 12, "compiled battery-group work honestly counted")
	check(max_reference_current_error < 1.0e-6, "safeguarded solver agrees with bisection", max_reference_current_error)

	var active: Dictionary = ship.execute(live, initial, F.commands(3, 400.0, 0.0), 294.0, DT)
	var idle: Dictionary = ship.execute(live, initial, F.commands(3, 0.0, 0.0), 294.0, DT)
	var driven: Dictionary = ship.execute(live, initial, F.commands(3, 0.0, 1.0), 294.0, DT)
	check(active.success and idle.success and driven.success, "load comparison probes")
	if active.success and idle.success and driven.success:
		check(float(active.details.battery_current_a) > float(idle.details.battery_current_a) and float(active.details.bus_voltage_v) < float(idle.details.bus_voltage_v), "firing causes current demand and battery droop")
		check(float(driven.details.battery_current_a) > float(idle.details.battery_current_a), "servo load reaches same battery")
		check(float(idle.details.battery_current_a) > 0.0 and float(idle.details.pump_j) > 0.0, "idle cooling is not free energy")

	var regen_state: Dictionary = initial.duplicate(true)
	for slot in regen_state.bank: regen_state.bank[slot].servo.motor_angular_velocity_rad_s = -36.0
	var regen: Dictionary = ship.execute(live, regen_state, F.commands(3, 0.0, 0.0), 294.0, DT)
	check(regen.success, "regeneration step", regen)
	if regen.success:
		check(float(regen.details.battery_current_a) < 0.0 and float(regen.details.chemical_delta_j) < 0.0, "reverse energy charges battery")
		check(float(regen.details.next_state.battery.group_charge_c[0]) > float(regen_state.battery.group_charge_c[0]), "regenerated charge retained")

	var before: Dictionary = initial.duplicate(true)
	var overload: Dictionary = ship.execute(live, initial, F.commands(3, 600.0, 0.0), 294.0, DT)
	failed_atomically(overload, before, initial, "overload fails atomically")
	check(overload.error_code == "T12_SHARED_POWER_LIMIT", "overload is electrical limit", overload)
	var depleted: Dictionary = ship.initial_state(0.0)
	failed_atomically(ship.execute(live, depleted, F.commands(), 294.0, DT), depleted.duplicate(true), depleted, "depleted battery does not power loads")
	var full: Dictionary = ship.initial_state(1.0)
	for slot in full.bank: full.bank[slot].servo.motor_angular_velocity_rad_s = -36.0
	failed_atomically(ship.execute(live, full, F.commands(3, 0.0, 0.0), 294.0, DT), full.duplicate(true), full, "full battery cannot accept forced regeneration")
	var fast: Dictionary = initial.duplicate(true)
	for slot in fast.bank: fast.bank[slot].servo.motor_angular_velocity_rad_s = -200.0
	failed_atomically(ship.execute(live, fast, F.commands(3, 0.0, 0.0), 294.0, DT), fast.duplicate(true), fast, "converter voltage headroom enforced")
	var invalid_commands := F.commands(); invalid_commands.unit01.target_position_rad = NAN
	failed_atomically(ship.execute(live, initial, invalid_commands, 294.0, DT), before, initial, "nonfinite command rejected")
	var invalid_state: Dictionary = initial.duplicate(true); invalid_state.battery.group_charge_c[1] = NAN
	check(not ship.execute(live, invalid_state, F.commands(), 294.0, DT).success, "nonfinite stored charge rejected")

	var snap: Dictionary = ship.snapshot(state)
	check(snap.success, "snapshot generated")
	var restored: Dictionary = ship.restore(snap.details.text, snap.details.sha256)
	check(restored.success and restored.details.next_state == state, "binary-scalar JSON envelope preserves doubles")
	var changed_text: String = String(snap.details.text).replace('"schema":"t12.snapshot.v1"', '"schema":"tampered"')
	check(not ship.restore(changed_text, snap.details.sha256).success, "external snapshot anchor rejects modified payload")
	var replay_a: Dictionary = state.duplicate(true)
	var replay_b: Dictionary = restored.details.next_state
	for i in range(64):
		var a: Dictionary = ship.execute(live, replay_a, F.commands(3, 0.0, -0.1), 294.0, DT)
		var z: Dictionary = ship.execute(live, replay_b, F.commands(3, 0.0, -0.1), 294.0, DT)
		check(a.success and z.success, "replay step")
		if not a.success or not z.success: break
		check(a.details.next_state == z.details.next_state and a.details.battery_current_a == z.details.battery_current_a, "replay bit exact")
		replay_a = a.details.next_state; replay_b = z.details.next_state

	var stale := live.duplicate(true)
	var path := "root/bank/unit03/cannon/emitter"
	stale[path].artifact_state = "STALE"
	var invalidation: Dictionary = ship.execute(stale, state, F.commands(), 294.0, DT)
	failed_atomically(invalidation, state.duplicate(true), state, "deep child stale blocks old ship")
	check(invalidation.details.get("refine_path") == path and not str(invalidation.details).contains("unit01") and not str(invalidation.details).contains("battery"), "refinement names only affected path")
	var drift := live.duplicate(true)
	drift[path].authority_envelope.source_authority_frontier[0].authority_epoch += 1
	failed_atomically(ship.execute(drift, state, F.commands(), 294.0, DT), state.duplicate(true), state, "authority drift rejected even with old advertised checksum")
	var child_tamper: Dictionary = b.duplicate(true)
	child_tamper.children.bank.children.unit03.children.cannon.children.emitter.descriptor.total_max_current_a *= 2.0
	var bad = Ship.new()
	check(not bad.prepare(child_tamper, b.capsule.checksum).success, "nested descriptor tamper rejected at prepare")
	check(not bad.prepare(b, "0".repeat(64)).success, "root external anchor mandatory")
	var alias := F.assemble(b.children.battery, {"unit01":b.children.bank.children.unit01, "unit02":b.children.bank.children.unit01})
	check(not alias.success and alias.error_code == "T12_ALIASED_INSTANCE", "same mutable module cannot be counted twice", alias)

	# Rebuild only Cannon #3's affected route; untouched siblings are reused verbatim.
	var replacement := F.replace_third_emitter(b)
	check(replacement.success, "selective emitter rebuild", replacement.error_code)
	if replacement.success:
		var updated: Dictionary = replacement.details
		check(updated.children.bank.children.unit01 == b.children.bank.children.unit01 and updated.children.bank.children.unit02 == b.children.bank.children.unit02 and updated.children.battery == b.children.battery, "unaffected capsules remain byte-identical")
		var new_ship = Ship.new()
		var np: Dictionary = new_ship.prepare(updated, updated.capsule.checksum)
		check(np.success, "rebuilt ship prepares", np)
		if np.success:
			var rebind: Dictionary = new_ship.rebind_state(ship, state)
			check(rebind.success and rebind.details.next_state == state, "compatible rebuild preserves all stored state")
			check(not new_ship.restore(snap.details.text, snap.details.sha256).success, "old snapshot cannot silently cross capsule identity")
			failed_atomically(ship.execute(C.live_tree(updated), state, F.commands(), 294.0, DT), state.duplicate(true), state, "old parent rejects new child epoch")
			var result: Dictionary = new_ship.execute(C.live_tree(updated), rebind.details.next_state, F.commands(3, 380.0, 0.0), 294.0, DT)
			check(result.success, "rebuilt affected subtree resumes compact execution", result.error_code)

	# A second bank size uses the same compact modules without rebuilding leaves.
	var two := F.assemble(b.children.battery, {"unit01":b.children.bank.children.unit01, "unit02":b.children.bank.children.unit02})
	check(two.success, "two-instance bank compiles")
	if two.success:
		var pair = Ship.new()
		var pp: Dictionary = pair.prepare(two.details, two.details.capsule.checksum)
		check(pp.success and int(pp.details.state_scalars) == 25, "two-instance state count")
		if pp.success:
			var pstep: Dictionary = pair.execute(C.live_tree(two.details), pair.initial_state(), F.commands(2, 400.0, 0.0), 294.0, DT)
			check(pstep.success and active.success and float(pstep.details.battery_current_a) < float(active.details.battery_current_a), "third load increases shared battery draw")
	var children: Dictionary = b.children
	var foreign_request := F.request(C.graph_hash("T12_SHIP", children), "", "t12-foreign", children)
	var records: Array = foreign_request.authority_envelope.source_authority_frontier.duplicate(true)
	for record in records: record.owner_id = "server/foreign"
	foreign_request.authority_envelope = F.Authority.create("server/foreign", records, foreign_request.authority_envelope.mutable_source_ids)
	var foreign := C.compile("T12_SHIP", children, foreign_request)
	check(not foreign.success and foreign.error_code == "T12_CROSS_AUTHORITY", "cross-owner hierarchy is NO_SAFE_BAKE", foreign)
	var malformed: Dictionary = b.duplicate(true); malformed.children.bank = 3
	check(not bad.prepare(malformed, b.capsule.checksum).success, "malformed child fails without script error")
	var weak_battery := F.child(F.B, F.BF.make_graph("LFP", 0.8), "t12-battery", 2)
	check(weak_battery.success, "different storage law compiles")
	if weak_battery.success:
		var weak := F.assemble(weak_battery.details, b.children.bank.children, 2)
		check(weak.success, "weak-battery parent compiles")
		if weak.success:
			var weak_ship = Ship.new()
			var wp: Dictionary = weak_ship.prepare(weak.details, weak.details.capsule.checksum)
			check(wp.success, "weak-battery runtime prepares")
			if wp.success:
				var transfer: Dictionary = weak_ship.rebind_state(ship, ship.initial_state(0.1))
				check(not transfer.success and transfer.error_code == "T12_CANONICAL_STATE_PROJECTOR_REQUIRED", "capacity-changing rebuild cannot silently copy hidden energy")

	var deterministic := {"schema":"fabric.t12.result.v1", "capsule_checksum":b.capsule.checksum,
		"instances":3, "leaf_components":4275, "state_scalars":31, "steps":STEPS,
		"checks":checks, "failures":failures, "max_energy_residual_j":max_energy,
		"max_bus_residual_j":max_bus, "max_reference_current_error_a":max_reference_current_error,
		"total_optical_j":total_optical, "total_pump_j":total_pump,
		"leaf_traversals":traversals, "evaluations":evaluations, "max_evaluations_per_step":max_evaluations,
		"boundary_calls":calls, "compiled_group_visits":group_visits,
		"min_bus_voltage_v":min_voltage, "max_bus_voltage_v":max_voltage,
		"final_state_hash":U.canonical_hash(state), "regeneration_current_a":regen.details.get("battery_current_a", 0),
		"overload_error":overload.error_code, "refine_path":invalidation.details.get("refine_path", "")}
	print("FABRIC_R5_2_T12_RESULT=" + JSON.stringify(deterministic, "", true, true))
	print("FABRIC R5.2 T12 SHIP MATRYOSHKA: " + ("PASS" if failures.is_empty() else "FAIL") + " (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)
