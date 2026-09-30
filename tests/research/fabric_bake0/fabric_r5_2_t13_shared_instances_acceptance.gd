extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Shared = preload("res://scripts/research/fabric_bake0/r5_t13_shared_instances_runtime_v1.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_fixture.gd")

const INSTANCE_COUNT := 100
const DAMAGE_INDEX := 41
const DT := 0.002
const AMBIENT_K := 294.0

var checks := 0
var failures: Array = []

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("T13: " + label + " " + JSON.stringify(details))

func iid(index: int) -> String:
	return "instance-%03d" % (index + 1)

func commands_for(index: int) -> Dictionary:
	var laser := 180.0 + 20.0 * float(index % 5)
	var position := -0.12 + 0.06 * float(index % 5)
	return F.commands(3, laser, position)

func exact_binary_hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func accumulate_metrics(result: Dictionary, metrics: Dictionary) -> void:
	if not result.success:
		return
	var m: Dictionary = result.details.physical.metrics
	metrics.steps += 1
	metrics.leaf_traversals += int(m.leaf_traversals)
	metrics.evaluations += int(m.evaluations)
	metrics.boundary_calls += int(m.boundary_calls)
	metrics.compiled_group_visits += int(m.compiled_group_visits)

func _initialize() -> void:
	# The only compile path in T13 acceptance. Everything below shares this object.
	var compiled := F.make_ship()
	check(compiled.success, "compile shared T12 model once", compiled)
	if not compiled.success:
		quit(1)
		return
	var bundle: Dictionary = compiled.details
	var caller_model_hash_before := exact_binary_hash(bundle)
	check(U.is_lower_hex_64(caller_model_hash_before), "caller model binary hash valid")

	var shared = Shared.new()
	var prepared: Dictionary = shared.prepare(bundle, bundle.capsule.checksum)
	check(prepared.success, "prepare shared compiled model once", prepared)
	if not prepared.success:
		quit(1)
		return
	check(int(prepared.details.prepare_count) == 1, "single prepare")
	check(int(prepared.details.source_component_count) == 4275, "shared model still represents 4275 leaf components")
	check(int(prepared.details.state_scalars_per_instance) == 31, "31 physical scalars per instance")
	check(shared.model_intact(), "frozen compiled model passes initial integrity audit")
	# Prove prepare severed the caller alias: mutate then restore only the caller copy.
	var caller_capsule_id: String = String(bundle.capsule.capsule_id)
	bundle.capsule.capsule_id = caller_capsule_id + "-caller-probe"
	check(shared.model_intact(), "caller bundle mutation cannot alter frozen compiled model")
	bundle.capsule.capsule_id = caller_capsule_id
	check(exact_binary_hash(bundle) == caller_model_hash_before, "caller probe restored byte-equivalent model")

	if "--preflight" in OS.get_cmdline_user_args():
		print("FABRIC_R5_2_T13_PREFLIGHT=PASS")
		quit(0)
		return

	var bindings := {}
	var states := {}
	var unique_binding_checksums := {}
	for i in range(INSTANCE_COUNT):
		var id := iid(i)
		var bound: Dictionary = shared.create_binding(id, "world/slot-%03d" % (i + 1))
		check(bound.success, "create independent binding " + id, bound)
		if not bound.success:
			continue
		var binding: Dictionary = bound.details
		check(binding.compiled_model_checksum == bundle.capsule.checksum, "binding references shared model " + id)
		check(not unique_binding_checksums.has(binding.checksum), "binding checksum unique " + id)
		unique_binding_checksums[binding.checksum] = true
		bindings[id] = binding
		var soc := 0.78 + 0.0002 * float(i % 20)
		var state: Dictionary = shared.initial_state(binding, soc, 300.0 + 0.01 * float(i % 7))
		check(not state.is_empty() and shared.state_valid(binding, state), "create independent state " + id)
		states[id] = state

	check(bindings.size() == INSTANCE_COUNT, "100 bindings created")
	check(states.size() == INSTANCE_COUNT, "100 states created")
	check(unique_binding_checksums.size() == INSTANCE_COUNT, "100 unique binding checksums")
	var caller_states_hash_before := U.canonical_hash(states)

	# 1 -> 10 -> 100: execute increasing prefixes without another compile/prepare.
	var gate_counts := {}
	var metrics := {"steps":0, "leaf_traversals":0, "evaluations":0, "boundary_calls":0, "compiled_group_visits":0}
	for count in [1, 10, 100]:
		var passed := 0
		for i in range(count):
			var id := iid(i)
			var before: Dictionary = states[id].duplicate(true)
			var step: Dictionary = shared.execute(bindings[id], states[id], commands_for(i), AMBIENT_K, DT)
			check(step.success, "%d-instance gate step %s" % [count, id], step)
			if step.success:
				passed += 1
				accumulate_metrics(step, metrics)
				check(step.details.compiled_model_checksum == bundle.capsule.checksum, "same compiled checksum at scale " + id)
				check(int(step.details.prepare_count) == 1 and int(step.details.recompile_events) == 0, "no reprepare/recompile at scale " + id)
			check(states[id] == before, "caller-owned state unchanged at scale " + id)
		gate_counts[str(count)] = passed
		check(passed == count, "scale gate complete %d" % count)

	check(int(gate_counts["1"]) == 1 and int(gate_counts["10"]) == 10 and int(gate_counts["100"]) == 100, "1 -> 10 -> 100 complete")

	# Binding/state isolation rejects cross-wiring and checksum tamper.
	var tampered_binding: Dictionary = bindings[iid(0)].duplicate(true)
	tampered_binding.world_slot = "world/tampered"
	check(not shared.validate_binding(tampered_binding).success, "binding checksum catches metadata tamper")
	var cross: Dictionary = shared.execute(bindings[iid(1)], states[iid(0)], commands_for(0), AMBIENT_K, DT)
	check(not cross.success and cross.error_code == "T13_INSTANCE_STATE_INVALID", "state cannot cross instance binding")

	# Damage exactly one instance, without rebuilding the shared model or the other 99.
	var damaged_id := iid(DAMAGE_INDEX)
	var damaged: Dictionary = shared.apply_damage(bindings[damaged_id], states[damaged_id], true)
	check(damaged.success, "apply instance-local damage overlay", damaged)
	var damaged_state: Dictionary = damaged.details.next_state if damaged.success else {}
	if damaged.success:
		check(bool(damaged_state.disabled) and int(damaged_state.damage_revision) == 1, "damage revision belongs to target instance")
		check(int(damaged.details.prepare_count) == 1 and int(damaged.details.recompile_events) == 0, "damage does not compile")

	var healthy_equivalent := 0
	var damaged_diverged := false
	var control_hashes: Array = []
	var candidate_hashes: Array = []
	for i in range(INSTANCE_COUNT):
		var id := iid(i)
		var control: Dictionary = shared.execute(bindings[id], states[id], commands_for(i), AMBIENT_K, DT)
		var candidate_input: Dictionary = damaged_state if i == DAMAGE_INDEX else states[id]
		var candidate: Dictionary = shared.execute(bindings[id], candidate_input, commands_for(i), AMBIENT_K, DT)
		check(control.success and candidate.success, "control/damage isolation step " + id, {"control":control, "candidate":candidate})
		if not control.success or not candidate.success:
			continue
		accumulate_metrics(control, metrics)
		accumulate_metrics(candidate, metrics)
		control_hashes.append(U.canonical_hash(control.details.next_state))
		candidate_hashes.append(U.canonical_hash(candidate.details.next_state))
		check(int(control.details.prepare_count) == 1 and int(candidate.details.prepare_count) == 1, "single prepare survives isolation " + id)
		check(int(control.details.recompile_events) == 0 and int(candidate.details.recompile_events) == 0, "zero recompiles in isolation " + id)
		if i == DAMAGE_INDEX:
			check(bool(candidate.details.damage_masked), "damaged instance uses local command mask")
			damaged_diverged = candidate.details.next_state != control.details.next_state
			check(damaged_diverged, "damaged instance diverges from healthy control")
			check(int(candidate.details.next_state.damage_revision) == 1, "damaged revision retained")
		else:
			var same: bool = candidate.details.next_state == control.details.next_state and candidate.details.physical == control.details.physical
			if same:
				healthy_equivalent += 1
			check(same, "healthy sibling byte-equivalent " + id)
			check(not bool(candidate.details.damage_masked), "healthy sibling not damage-masked " + id)

	check(healthy_equivalent == 99, "damage leaves other 99 byte-equivalent", healthy_equivalent)
	check(damaged_diverged, "only target behavior diverged")
	check(U.canonical_hash(states) == caller_states_hash_before, "all baseline caller states remain unchanged")
	check(exact_binary_hash(bundle) == caller_model_hash_before, "caller compiled bundle remains immutable")
	check(shared.model_intact(), "shared compiled model hash remains intact")
	check(int(shared.model_identity().prepare_count) == 1, "prepare count remains one after 311 executions")
	check(int(damaged.details.get("recompile_events", -1)) == 0, "damage repair path did not recompile")
	check(int(metrics.leaf_traversals) == 0, "all 311 instance steps stay on compact compiled execution")

	var snap: Dictionary = shared.snapshot_instance(bindings[damaged_id], damaged_state)
	check(snap.success, "damaged instance snapshot")
	if snap.success:
		check(String(snap.details.text).contains(bindings[damaged_id].checksum), "snapshot anchored to instance binding")
		check(String(snap.details.text).contains(bundle.capsule.checksum), "snapshot anchored to shared compiled model")

	var deterministic := {
		"schema": "fabric.t13.result.v1",
		"failures": failures,
		"checks": checks,
		"instance_gates": [1, 10, 100],
		"gate_counts": gate_counts,
		"bindings": bindings.size(),
		"unique_binding_checksums": unique_binding_checksums.size(),
		"shared_compiled_model_checksum": bundle.capsule.checksum,
		"shared_compiled_model_hash": shared.model_identity().compiled_model_hash,
		"source_components_per_model": int(bundle.capsule.source_component_count),
		"state_scalars_per_instance": int(prepared.details.state_scalars_per_instance),
		"prepare_count": int(shared.model_identity().prepare_count),
		"recompile_events": 0,
		"runtime_steps": int(metrics.steps),
		"leaf_traversals": int(metrics.leaf_traversals),
		"evaluations": int(metrics.evaluations),
		"boundary_calls": int(metrics.boundary_calls),
		"compiled_group_visits": int(metrics.compiled_group_visits),
		"damaged_instance": damaged_id,
		"damage_revision": int(damaged_state.get("damage_revision", -1)),
		"healthy_equivalent_after_damage": healthy_equivalent,
		"damaged_diverged": damaged_diverged,
		"model_hash_unchanged": exact_binary_hash(bundle) == caller_model_hash_before and shared.model_intact(),
		"caller_states_unchanged": U.canonical_hash(states) == caller_states_hash_before,
		"isolation_hash": U.canonical_hash({"control":control_hashes, "candidate":candidate_hashes}),
	}
	print("FABRIC_R5_2_T13_RESULT=" + JSON.stringify(deterministic, "", true, true))
	print("FABRIC R5.2 T13 SHARED INSTANCES: " + ("PASS" if failures.is_empty() else "FAIL") + " (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)
