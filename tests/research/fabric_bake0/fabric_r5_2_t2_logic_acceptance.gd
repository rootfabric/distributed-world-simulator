extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/logic_component_graph_v1.gd")
const Interpreter = preload("res://scripts/research/fabric_bake0/logic_graph_interpreter_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/logic_lookup_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/logic_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t2_logic_lookup_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t2_logic_lookup_runtime_v1.gd")
const Measure = preload("res://scripts/research/fabric_bake0/r5_measurement_harness_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t2_logic_fixture.gd")

const ADDER_EXHAUSTIVE_CASES := 131072
const COUNTER_EXHAUSTIVE_CASES := 1024
const COUNTER_SEQUENCE_TICKS := 2048
const INTERPRETER_HOT_CALLS := 4096
const LOOKUP_HOT_CALLS := 65536

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T2: " + label + " " + JSON.stringify(details))

func begin_stage(m: Object, name: String) -> void:
	var r: Dictionary = m.begin_stage(name)
	check(r.success, "measurement begin " + name, r)

func end_stage(m: Object, name: String) -> void:
	var r: Dictionary = m.end_stage(name)
	check(r.success, "measurement end " + name, r)

func compile_fixture(graph: Dictionary, source_id: String, revision: int, capsule_id: String) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, source_id, revision), capsule_id)

func _initialize() -> void:
	var m = Measure.new("R5.2-T2-LOGIC-ADDER-COUNTER-R1")

	var adder_graph := Fixture.make_adder_graph()
	var counter_graph := Fixture.make_counter_graph()
	check(Graph.validate(adder_graph).success, "adder graph contract")
	check(Graph.validate(counter_graph).success, "counter graph contract")
	check(adder_graph.components.size() == 40, "adder source component count", {"count": adder_graph.components.size()})
	check(counter_graph.components.size() == 32, "counter source component count", {"count": counter_graph.components.size()})

	var adder_reordered := Fixture.make_adder_graph(0, true)
	var counter_reordered := Fixture.make_counter_graph(0, true)
	check(String(adder_reordered.graph_hash) == String(adder_graph.graph_hash), "adder raw order invariant")
	check(String(counter_reordered.graph_hash) == String(counter_graph.graph_hash), "counter raw order invariant")

	begin_stage(m, "adder_compile")
	var adder := compile_fixture(adder_graph, "construct/r5-t2-adder", 0, "capsule/r5-t2-adder")
	end_stage(m, "adder_compile")
	check(adder.success, "adder compile", adder)
	if not adder.success:
		_finish()
		return

	begin_stage(m, "counter_compile")
	var counter := compile_fixture(counter_graph, "construct/r5-t2-counter", 0, "capsule/r5-t2-counter")
	end_stage(m, "counter_compile")
	check(counter.success, "counter compile", counter)
	if not counter.success:
		_finish()
		return

	var adder_descriptor: Dictionary = adder.details.descriptor
	var counter_descriptor: Dictionary = counter.details.descriptor
	var adder_artifact: Dictionary = adder.details.artifact
	var counter_artifact: Dictionary = counter.details.artifact
	var adder_capsule: Dictionary = adder.details.capsule
	var counter_capsule: Dictionary = counter.details.capsule
	check(Descriptor.validate(adder_descriptor).success, "adder descriptor")
	check(Descriptor.validate(counter_descriptor).success, "counter descriptor")
	check(Artifact.verify_descriptor(adder_artifact, adder_descriptor).success, "adder artifact")
	check(Artifact.verify_descriptor(counter_artifact, counter_descriptor).success, "counter artifact")
	check(Capsule.validate(adder_capsule).success, "adder capsule")
	check(Capsule.validate(counter_capsule).success, "counter capsule")
	check(int(adder_descriptor.entry_count) == ADDER_EXHAUSTIVE_CASES, "adder LUT entries")
	check(int(counter_descriptor.entry_count) == COUNTER_EXHAUSTIVE_CASES, "counter LUT entries")
	check(int(adder_capsule.runtime_source_traversals_per_execute) == 0, "adder zero source traversal")
	check(int(counter_capsule.runtime_source_traversals_per_execute) == 0, "counter zero source traversal")
	check(float(adder_capsule.operation_compression_ratio) > 10.0, "adder operation compression", adder_capsule)
	check(float(counter_capsule.operation_compression_ratio) > 10.0, "counter operation compression", counter_capsule)

	var adder_recompiled := compile_fixture(adder_reordered, "construct/r5-t2-adder", 0, "capsule/r5-t2-adder")
	var counter_recompiled := compile_fixture(counter_reordered, "construct/r5-t2-counter", 0, "capsule/r5-t2-counter")
	check(adder_recompiled.success and String(adder_recompiled.details.descriptor.descriptor_hash) == String(adder_descriptor.descriptor_hash), "adder compiler ordering invariant")
	check(counter_recompiled.success and String(counter_recompiled.details.descriptor.descriptor_hash) == String(counter_descriptor.descriptor_hash), "counter compiler ordering invariant")
	check(adder_recompiled.success and String(adder_recompiled.details.capsule.checksum) == String(adder_capsule.checksum), "adder capsule ordering invariant")
	check(counter_recompiled.success and String(counter_recompiled.details.capsule.checksum) == String(counter_capsule.checksum), "counter capsule ordering invariant")

	var adder_live := Fixture.live_from(adder_artifact)
	var counter_live := Fixture.live_from(counter_artifact)
	var adder_runtime = Runtime.new()
	var counter_runtime = Runtime.new()
	begin_stage(m, "runtime_prepare")
	var adder_prepared := adder_runtime.prepare(adder_capsule, adder_artifact, adder_descriptor, adder_live)
	var counter_prepared := counter_runtime.prepare(counter_capsule, counter_artifact, counter_descriptor, counter_live)
	end_stage(m, "runtime_prepare")
	check(adder_prepared.success, "adder runtime prepare", adder_prepared)
	check(counter_prepared.success, "counter runtime prepare", counter_prepared)
	if not adder_prepared.success or not counter_prepared.success:
		_finish()
		return
	check(int(adder_prepared.details.lookup_bytes) == ADDER_EXHAUSTIVE_CASES * 4, "adder lookup byte accounting")
	check(int(counter_prepared.details.lookup_bytes) == COUNTER_EXHAUSTIVE_CASES * 4, "counter lookup byte accounting")

	begin_stage(m, "adder_exhaustive_capsule")
	var adder_cases := 0
	for a in range(256):
		for b in range(256):
			for carry_in in range(2):
				var input_word := Fixture.adder_input_word(adder_artifact.interface_contract, a, b, carry_in)
				var executed := adder_runtime.execute(adder_live, input_word, 0)
				if not executed.success:
					check(false, "adder exhaustive runtime", {"a": a, "b": b, "carry": carry_in, "result": executed})
					continue
				var expected := Fixture.adder_expected_output_word(adder_artifact.interface_contract, a, b, carry_in)
				if int(executed.details.output_word) != expected:
					check(false, "adder exhaustive equivalence", {"a": a, "b": b, "carry": carry_in, "actual": executed.details.output_word, "expected": expected})
				if int(executed.details.next_state_word) != 0:
					check(false, "adder stateless next state")
				adder_cases += 1
	end_stage(m, "adder_exhaustive_capsule")
	check(adder_cases == ADDER_EXHAUSTIVE_CASES, "adder exhaustive case count", {"count": adder_cases})

	begin_stage(m, "counter_exhaustive_capsule")
	var counter_cases := 0
	for state in range(256):
		for enable_i in range(2):
			for reset_i in range(2):
				var enable := enable_i == 1
				var reset := reset_i == 1
				var input_word := Fixture.counter_input_word(counter_artifact.interface_contract, enable, reset)
				var executed := counter_runtime.execute(counter_live, input_word, state)
				if not executed.success:
					check(false, "counter exhaustive runtime", {"state": state, "enable": enable, "reset": reset, "result": executed})
					continue
				var expected_output := Fixture.counter_expected_output_word(counter_artifact.interface_contract, state)
				var expected_next := Fixture.counter_expected_next_state(state, enable, reset)
				if int(executed.details.output_word) != expected_output or int(executed.details.next_state_word) != expected_next:
					check(false, "counter exhaustive equivalence", {"state": state, "enable": enable, "reset": reset, "actual": executed.details, "expected_output": expected_output, "expected_next": expected_next})
				if executed.details.event_order != ["OUTPUT_EVALUATED", "REGISTER_COMMIT"]:
					check(false, "counter deterministic event order", executed.details)
				counter_cases += 1
	end_stage(m, "counter_exhaustive_capsule")
	check(counter_cases == COUNTER_EXHAUSTIVE_CASES, "counter exhaustive case count", {"count": counter_cases})

	begin_stage(m, "counter_sequence")
	var sequence_state := counter_runtime.initial_state_word()
	var sequence_hash_rows: Array = []
	for tick in range(COUNTER_SEQUENCE_TICKS):
		var reset := tick % 257 == 0
		var enable := tick % 3 != 0
		var input_word := Fixture.counter_input_word(counter_artifact.interface_contract, enable, reset)
		var before := sequence_state
		var executed := counter_runtime.execute(counter_live, input_word, before)
		check(executed.success, "counter sequence runtime", {"tick": tick, "result": executed} if not executed.success else {})
		if not executed.success:
			break
		var expected_output := Fixture.counter_expected_output_word(counter_artifact.interface_contract, before)
		var expected_next := Fixture.counter_expected_next_state(before, enable, reset)
		check(int(executed.details.output_word) == expected_output, "counter sequence output", {"tick": tick})
		check(int(executed.details.next_state_word) == expected_next, "counter sequence next state", {"tick": tick})
		sequence_state = int(executed.details.next_state_word)
		if tick % 64 == 0:
			sequence_hash_rows.append({"tick": tick, "state": sequence_state, "output": int(executed.details.output_word)})
	end_stage(m, "counter_sequence")
	var sequence_hash := U.canonical_hash(sequence_hash_rows)

	var adder_plan: Dictionary = adder.details.plan
	var counter_plan: Dictionary = counter.details.plan
	begin_stage(m, "adder_interpreter_hot_loop")
	var adder_full_acc := 0
	for i in range(INTERPRETER_HOT_CALLS):
		var a := (i * 37) & 0xff
		var b := (i * 91 + 17) & 0xff
		var carry := i & 1
		var input_word := Fixture.adder_input_word(adder_artifact.interface_contract, a, b, carry)
		var full := Interpreter.evaluate(adder_plan, input_word, 0)
		check(full.success, "adder interpreter hot", {"index": i} if not full.success else {})
		if full.success:
			adder_full_acc ^= int(full.details.output_word)
	end_stage(m, "adder_interpreter_hot_loop")

	begin_stage(m, "adder_lookup_hot_loop")
	var adder_lookup_acc := 0
	for i in range(LOOKUP_HOT_CALLS):
		var a := (i * 37) & 0xff
		var b := (i * 91 + 17) & 0xff
		var carry := i & 1
		var input_word := Fixture.adder_input_word(adder_artifact.interface_contract, a, b, carry)
		var fast := adder_runtime.execute(adder_live, input_word, 0)
		check(fast.success, "adder lookup hot", {"index": i} if not fast.success else {})
		if fast.success:
			adder_lookup_acc ^= int(fast.details.output_word)
	end_stage(m, "adder_lookup_hot_loop")

	begin_stage(m, "counter_interpreter_hot_loop")
	var counter_full_acc := 0
	for i in range(INTERPRETER_HOT_CALLS):
		var state := (i * 53) & 0xff
		var input_word := Fixture.counter_input_word(counter_artifact.interface_contract, i % 2 == 0, i % 257 == 0)
		var full := Interpreter.evaluate(counter_plan, input_word, state)
		check(full.success, "counter interpreter hot", {"index": i} if not full.success else {})
		if full.success:
			counter_full_acc ^= int(full.details.next_state_word)
	end_stage(m, "counter_interpreter_hot_loop")

	begin_stage(m, "counter_lookup_hot_loop")
	var counter_lookup_acc := 0
	for i in range(LOOKUP_HOT_CALLS):
		var state := (i * 53) & 0xff
		var input_word := Fixture.counter_input_word(counter_artifact.interface_contract, i % 2 == 0, i % 257 == 0)
		var fast := counter_runtime.execute(counter_live, input_word, state)
		check(fast.success, "counter lookup hot", {"index": i} if not fast.success else {})
		if fast.success:
			counter_lookup_acc ^= int(fast.details.next_state_word)
	end_stage(m, "counter_lookup_hot_loop")
	check(is_finite(float(adder_full_acc + adder_lookup_acc + counter_full_acc + counter_lookup_acc)), "hot-loop accumulators finite")

	begin_stage(m, "mutation_recompile")
	var mutated_graph := Fixture.make_adder_graph(1)
	var mutated := compile_fixture(mutated_graph, "construct/r5-t2-adder", 1, "capsule/r5-t2-adder")
	end_stage(m, "mutation_recompile")
	check(mutated.success, "mutated adder compile", mutated)
	if mutated.success:
		check(String(mutated.details.descriptor.table_hash) != String(adder_descriptor.table_hash), "gate mutation changes lookup")
		check(String(mutated.details.capsule.checksum) != String(adder_capsule.checksum), "gate mutation changes capsule")
		var mutated_live := Fixture.live_from(mutated.details.artifact)
		check(not adder_runtime.execute(mutated_live, 0, 0).success, "old capsule rejects mutated graph live context")
		var mutated_runtime = Runtime.new()
		check(mutated_runtime.prepare(mutated.details.capsule, mutated.details.artifact, mutated.details.descriptor, mutated_live).success, "mutated runtime prepare")
		var witness_input := Fixture.adder_input_word(mutated.details.artifact.interface_contract, 1, 1, 0)
		var mutated_exec := mutated_runtime.execute(mutated_live, witness_input, 0)
		var expected_original := Fixture.adder_expected_output_word(mutated.details.artifact.interface_contract, 1, 1, 0)
		check(mutated_exec.success and int(mutated_exec.details.output_word) != expected_original, "gate mutation changes behavior")

	var mismatched_request := Fixture.build_request(mutated_graph, "construct/r5-t2-adder", 1)
	var mismatched := Compiler.compile(adder_graph, mismatched_request, "capsule/r5-t2-adder")
	check(not mismatched.success and String(mismatched.error_code) == "LOGIC_CANONICAL_GRAPH_SOURCE_MISMATCH", "graph/frontier mismatch rejected", mismatched)

	var stale_live: Dictionary = adder_live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not adder_runtime.execute(stale_live, 0, 0).success, "lookup runtime rejects STALE")
	var invalidated_live: Dictionary = adder_live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not adder_runtime.execute(invalidated_live, 0, 0).success, "lookup runtime rejects invalidation")
	var authority_drift: Dictionary = adder_live.duplicate(true)
	authority_drift.authority_envelope = adder_live.authority_envelope.duplicate(true)
	authority_drift.authority_envelope.checksum = "0".repeat(64)
	check(not adder_runtime.execute(authority_drift, 0, 0).success, "lookup runtime rejects authority drift")

	begin_stage(m, "cycle_fail_closed")
	var cycle_graph := Fixture.make_cycle_graph()
	var cycle := compile_fixture(cycle_graph, "construct/r5-t2-cycle", 0, "capsule/r5-t2-cycle")
	end_stage(m, "cycle_fail_closed")
	check(not cycle.success and String(cycle.error_code) == "LOGIC_COMBINATIONAL_CYCLE", "combinational cycle fail closed", cycle)

	begin_stage(m, "oversize_fail_closed")
	var oversize_graph := Fixture.make_oversize_graph()
	var oversize := compile_fixture(oversize_graph, "construct/r5-t2-oversize", 0, "capsule/r5-t2-oversize")
	end_stage(m, "oversize_fail_closed")
	check(not oversize.success and String(oversize.error_code) == "LOGIC_STATE_SPACE_TOO_LARGE", "oversize state space fail closed", oversize)

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t2_logic_result.v1",
		"adder_graph_hash": adder_graph.graph_hash,
		"counter_graph_hash": counter_graph.graph_hash,
		"adder_descriptor_hash": adder_descriptor.descriptor_hash,
		"counter_descriptor_hash": counter_descriptor.descriptor_hash,
		"adder_table_hash": adder_descriptor.table_hash,
		"counter_table_hash": counter_descriptor.table_hash,
		"adder_capsule_checksum": adder_capsule.checksum,
		"counter_capsule_checksum": counter_capsule.checksum,
		"adder_source_components": adder_graph.components.size(),
		"counter_source_components": counter_graph.components.size(),
		"adder_lut_entries": int(adder_descriptor.entry_count),
		"counter_lut_entries": int(counter_descriptor.entry_count),
		"adder_lookup_bytes": int(adder_descriptor.entry_count) * 4,
		"counter_lookup_bytes": int(counter_descriptor.entry_count) * 4,
		"adder_exhaustive_cases": adder_cases,
		"counter_exhaustive_cases": counter_cases,
		"counter_sequence_ticks": COUNTER_SEQUENCE_TICKS,
		"counter_sequence_hash": sequence_hash,
		"runtime_source_traversals_per_execute": 0,
		"compiled_operations": 3,
		"counter_event_order": ["OUTPUT_EVALUATED", "REGISTER_COMMIT"],
		"mutation_changed_lookup": mutated.success and String(mutated.details.descriptor.table_hash) != String(adder_descriptor.table_hash),
		"cycle_error": String(cycle.get("error_code", "")),
		"oversize_error": String(oversize.get("error_code", "")),
	}
	m.set_counter("adder_source_components", adder_graph.components.size())
	m.set_counter("counter_source_components", counter_graph.components.size())
	m.set_counter("adder_lut_entries", int(adder_descriptor.entry_count))
	m.set_counter("counter_lut_entries", int(counter_descriptor.entry_count))
	m.set_counter("adder_exhaustive_cases", adder_cases)
	m.set_counter("counter_exhaustive_cases", counter_cases)
	m.set_counter("counter_sequence_ticks", COUNTER_SEQUENCE_TICKS)
	m.set_counter("runtime_source_traversals_per_execute", 0)
	m.set_counter("interpreter_hot_calls", INTERPRETER_HOT_CALLS)
	m.set_counter("lookup_hot_calls", LOOKUP_HOT_CALLS)
	var measured := m.finish(deterministic, {
		"physical_power": {"applicable": false, "reason": "T2 is a discrete logic compilation fixture, not a power-conjugate physical subsystem."},
		"persistent_register_state_owner": {"applicable": false, "reason": "T2 runtime receives current state explicitly and returns next state; it does not own canonical persistent state."},
	})
	check(measured.success, "measurement finalize", measured)
	if measured.success:
		print("FABRIC_R5_2_T2_DETERMINISTIC_HASH=" + String(measured.details.deterministic_hash))
		print("FABRIC_R5_2_T2_RESULT=" + JSON.stringify(measured.details))
	if not failed:
		print("FABRIC R5.2 T2 LOGIC ADDER COUNTER: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T2 LOGIC ADDER COUNTER: FAIL (%d assertions)" % checks)
	quit(1)
