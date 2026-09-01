extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const Model = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const Solver = preload("res://scripts/research/fabric_bake0/dynamic_full_reference_solver_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	_test_compile_contract()
	_test_order_determinism()
	_test_fail_closed_contracts()
	_test_full_reference_zero_equilibrium()
	_test_passive_decay()
	_test_boundary_power_and_orientation()
	_test_reference_determinism()
	_finish()

func _test_compile_contract() -> void:
	var fixture := Fixture.build("PATTERN")
	var compiled := Compiler.compile(fixture["request"])
	_check(bool(compiled.get("success", false)), "B0.4-A compiles reference model")
	if not bool(compiled.get("success", false)):
		return
	_check(String(compiled["status"]) == Compiler.STATUS_READY, "ready status exact")
	var model: Dictionary = compiled["model"]
	_check(bool(Model.validate(model).get("success", false)), "dynamic model validates")
	_check(int(model["full_state_schema"]["state_count"]) == 512, "reference has 512 dynamic states")
	_check(model["boundary_contract"]["ports"].size() == 4, "reference has four boundary ports")
	_check(String(model["model_class"]) == Model.MODEL_CLASS, "generic model class exact")
	_check(String(model["reference_solver"]["method"]) == Model.SOLVER_METHOD, "reference solver exact")
	_check(bool(model["passivity_certificate"]["strictly_stable"]), "structural strict stability certified")
	_check(bool(model["passivity_certificate"]["all_edges_positive"]), "all internal couplings dissipative")
	_check(bool(model["passivity_certificate"]["all_shunts_positive"]), "all shunts dissipative")
	_check(bool(model["passivity_certificate"]["connected_path"]), "reference graph connected")
	_check(float(model["passivity_certificate"]["minimum_storage_coefficient"]) > 0.0, "positive storage lower bound")
	_check(float(model["passivity_certificate"]["minimum_edge_conductance"]) > 0.0, "positive edge lower bound")
	_check(float(model["passivity_certificate"]["minimum_shunt_conductance"]) > 0.0, "positive shunt lower bound")
	_check(String(model["source_binding"]["frontier_hash"]) == String(fixture["frontier"]["frontier_hash"]), "canonical source frontier bound")
	_check(String(model["source_binding"]["dependency_hash"]) == String(fixture["dependencies"]["dependency_hash"]), "dependency set bound")
	_check(String(model["source_binding"]["boundary_contract_hash"]) == String(fixture["boundary"]["contract_hash"]), "boundary contract bound")
	_check(String(model["source_binding"]["fabric_compiler_version"]) == Compiler.COMPILER_VERSION, "compiler version bound")
	_check(String(model["source_binding"]["fabric_graph_hash"]) == Model.dynamic_graph_hash(model), "dynamic graph hash bound")
	_check(String(model["model_hash"]).length() == 64, "model hash present")
	_check(String(model["full_state_schema"]["schema_hash"]).length() == 64, "full state schema hash present")
	_check(String(model["passivity_certificate"]["certificate_hash"]).length() == 64, "passivity certificate hash present")

	for binding in model["port_bindings"]:
		var port: Dictionary = _port_by_id(model["boundary_contract"], String(binding["port_id"]))
		_check(not port.is_empty(), "binding port exists")
		_check(String(binding["frame"]) == String(port["frame"]), "binding frame exact")
		_check(String(binding["orientation"]) == String(port["orientation"]), "binding orientation exact")
		_check(String(binding["reference_causalization"]) == Model.REFERENCE_CAUSALIZATION, "causalization explicitly reference-only")

func _test_order_determinism() -> void:
	var fixture := Fixture.build("PATTERN")
	var forward := Compiler.compile(fixture["request"])
	var reversed := Compiler.compile(Fixture.reversed_request(fixture))
	_check(bool(forward.get("success", false)) and bool(reversed.get("success", false)), "forward/reversed compilation succeeds")
	if not bool(forward.get("success", false)) or not bool(reversed.get("success", false)):
		return
	_check(String(forward["model"]["model_hash"]) == String(reversed["model"]["model_hash"]), "presentation order does not change model identity")
	_check(String(forward["model"]["checksum"]) == String(reversed["model"]["checksum"]), "presentation order does not change model bytes contract")
	_check(String(forward["model"]["source_binding"]["fabric_graph_hash"]) == String(reversed["model"]["source_binding"]["fabric_graph_hash"]), "presentation order does not change dynamic graph identity")
	_check(String(forward["model"]["full_state_schema"]["schema_hash"]) == String(reversed["model"]["full_state_schema"]["schema_hash"]), "presentation order does not change state schema")

func _test_fail_closed_contracts() -> void:
	var fixture := Fixture.build("PATTERN")

	var cross_request: Dictionary = fixture["request"].duplicate(true)
	var construction_key := Utils.source_key("CONSTRUCTION", String(fixture["construction"]["source_id"]))
	var matter_key := Utils.source_key("MATTER", String(fixture["matter"]["source_id"]))
	cross_request["authority_envelope"] = AuthorityEnvelope.create(
		"server/fabric-b04",
		[
			{
				"source_domain": "CONSTRUCTION",
				"source_id": String(fixture["construction"]["source_id"]),
				"authority_epoch": int(fixture["construction"]["authority_epoch"]),
				"owner_id": "server/fabric-b04",
			},
			{
				"source_domain": "MATTER",
				"source_id": String(fixture["matter"]["source_id"]),
				"authority_epoch": int(fixture["matter"]["authority_epoch"]),
				"owner_id": "server/foreign",
			},
		],
		[construction_key, matter_key]
	)
	var cross := Compiler.compile(cross_request)
	_check(not bool(cross.get("success", false)), "cross-authority model rejected")
	_check(String(cross.get("status", "")) == Compiler.STATUS_NO_SAFE_BAKE, "cross-authority uses NO_SAFE_BAKE")
	_check(String(cross.get("reason", "")) == "AUTHORITY_ENVELOPE_CROSSED", "cross-authority reason exact")

	var small_request: Dictionary = fixture["request"].duplicate(true)
	small_request["states"] = Array(small_request["states"]).slice(0, 128)
	small_request["storage_nodes"] = Array(small_request["storage_nodes"]).slice(0, 128)
	small_request["edges"] = Array(small_request["edges"]).slice(0, 127)
	small_request["shunts"] = Array(small_request["shunts"]).slice(0, 128)
	small_request["port_bindings"] = [Array(small_request["port_bindings"])[0], Array(small_request["port_bindings"])[1]]
	var small_ports: Array = [Array(fixture["boundary"]["ports"])[0], Array(fixture["boundary"]["ports"])[1]]
	small_request["boundary_contract"] = BoundaryContract.create(small_ports)
	var small := Compiler.compile(small_request)
	_check(not bool(small.get("success", false)), "sub-512 reference rejected")
	_check(String(small.get("reason", "")) == "B0_4_A_REFERENCE_STATE_COUNT_BELOW_512", "sub-512 reason exact")

	var negative_storage_request: Dictionary = fixture["request"].duplicate(true)
	negative_storage_request["storage_nodes"] = Array(negative_storage_request["storage_nodes"]).duplicate(true)
	negative_storage_request["storage_nodes"][17] = Dictionary(negative_storage_request["storage_nodes"][17]).duplicate(true)
	negative_storage_request["storage_nodes"][17]["storage_coefficient"] = 0.0
	var negative_storage := Compiler.compile(negative_storage_request)
	_check(not bool(negative_storage.get("success", false)), "zero storage rejected")
	_check(String(negative_storage.get("reason", "")) == "NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_STORAGE", "zero storage fail-closed reason")

	var negative_edge_request: Dictionary = fixture["request"].duplicate(true)
	negative_edge_request["edges"] = Array(negative_edge_request["edges"]).duplicate(true)
	negative_edge_request["edges"][23] = Dictionary(negative_edge_request["edges"][23]).duplicate(true)
	negative_edge_request["edges"][23]["conductance"] = -0.1
	var negative_edge := Compiler.compile(negative_edge_request)
	_check(not bool(negative_edge.get("success", false)), "negative dissipation edge rejected")
	_check(String(negative_edge.get("reason", "")) == "NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_COUPLING", "negative edge fail-closed reason")

	var frame_request: Dictionary = fixture["request"].duplicate(true)
	frame_request["port_bindings"] = Array(frame_request["port_bindings"]).duplicate(true)
	frame_request["port_bindings"][0] = Dictionary(frame_request["port_bindings"][0]).duplicate(true)
	frame_request["port_bindings"][0]["frame"] = "frame/wrong/reference"
	var frame_result := Compiler.compile(frame_request)
	_check(not bool(frame_result.get("success", false)), "frame mismatch rejected")
	_check(String(frame_result.get("reason", "")) == "DYNAMIC_PORT_FRAME_MISMATCH", "frame mismatch reason exact")

	var orientation_request: Dictionary = fixture["request"].duplicate(true)
	orientation_request["port_bindings"] = Array(orientation_request["port_bindings"]).duplicate(true)
	orientation_request["port_bindings"][0] = Dictionary(orientation_request["port_bindings"][0]).duplicate(true)
	orientation_request["port_bindings"][0]["orientation"] = "OUT_OF_SUBSYSTEM"
	var orientation_result := Compiler.compile(orientation_request)
	_check(not bool(orientation_result.get("success", false)), "orientation mismatch rejected")
	_check(String(orientation_result.get("reason", "")) == "DYNAMIC_PORT_ORIENTATION_MISMATCH", "orientation mismatch reason exact")

	var dimension_request: Dictionary = fixture["request"].duplicate(true)
	dimension_request["storage_nodes"] = Array(dimension_request["storage_nodes"]).duplicate(true)
	dimension_request["storage_nodes"][0] = Dictionary(dimension_request["storage_nodes"][0]).duplicate(true)
	dimension_request["storage_nodes"][0]["storage_coefficient_dimension"] = Fixture.CONDUCTANCE_DIM.duplicate(true)
	var dimension_result := Compiler.compile(dimension_request)
	_check(not bool(dimension_result.get("success", false)), "storage/port dimensional mismatch rejected")

	var dependency_request: Dictionary = fixture["request"].duplicate(true)
	dependency_request["dependency_set"] = DependencySet.create([
		{
			"dependency_id": "dependency/b0-3-contact-wrench",
			"dependency_hash": Utils.canonical_hash({"closure": "changed"}),
		},
		{
			"dependency_id": "dependency/fabric0-18-physical-core",
			"dependency_hash": Utils.canonical_hash({"closure": "b9f4a11cb7c31e47884d12eaad2985811e0b6563"}),
		},
		{
			"dependency_id": "dependency/full-reference-policy",
			"dependency_hash": Utils.canonical_hash({"solver": Model.SOLVER_METHOD, "revision": 1}),
		},
	])
	var baseline := Compiler.compile(fixture["request"])
	var changed_dependency := Compiler.compile(dependency_request)
	_check(bool(changed_dependency.get("success", false)), "changed dependency can compile as a different bound model")
	if bool(changed_dependency.get("success", false)) and bool(baseline.get("success", false)):
		_check(String(changed_dependency["model"]["source_binding"]["dependency_hash"]) != String(baseline["model"]["source_binding"]["dependency_hash"]), "dependency mutation changes binding")
		_check(String(changed_dependency["model"]["model_hash"]) != String(baseline["model"]["model_hash"]), "dependency mutation changes model identity")

func _test_full_reference_zero_equilibrium() -> void:
	var fixture := Fixture.build("ZERO")
	var compiled := Compiler.compile(fixture["request"])
	_check(bool(compiled.get("success", false)), "zero fixture compiles")
	if not bool(compiled.get("success", false)):
		return
	var model: Dictionary = compiled["model"]
	var initial := Solver.initial_state(model)
	_check(bool(initial.get("success", false)), "zero initial state creates")
	if not bool(initial.get("success", false)):
		return
	_check(absf(float(initial["stored_energy"])) <= 1.0e-15, "zero state has zero stored energy")
	var result := Solver.advance_constant(model, initial["state"], Fixture.zero_flows(model["boundary_contract"]), 0.01, 100)
	_check(bool(result.get("success", false)), "zero equilibrium advances")
	if not bool(result.get("success", false)):
		return
	_check(float(result["summary"]["final_stored_energy"]) <= 1.0e-15, "zero equilibrium remains zero")
	_check(float(result["summary"]["max_balance_residual"]) <= 1.0e-12, "zero equilibrium energy balance exact")
	for value in result["state"]["values"]:
		_check(absf(float(value)) <= 1.0e-15, "zero equilibrium state remains zero")

func _test_passive_decay() -> void:
	var fixture := Fixture.build("PATTERN")
	var compiled := Compiler.compile(fixture["request"])
	_check(bool(compiled.get("success", false)), "pattern fixture compiles")
	if not bool(compiled.get("success", false)):
		return
	var model: Dictionary = compiled["model"]
	var initial := Solver.initial_state(model)
	_check(bool(initial.get("success", false)), "pattern initial state creates")
	if not bool(initial.get("success", false)):
		return
	var initial_energy := float(initial["stored_energy"])
	_check(initial_energy > 0.0, "pattern starts with stored energy")
	var result := Solver.advance_constant(model, initial["state"], Fixture.zero_flows(model["boundary_contract"]), 0.01, 200)
	_check(bool(result.get("success", false)), "passive zero-input decay advances")
	if not bool(result.get("success", false)):
		return
	_check(float(result["summary"]["final_stored_energy"]) < initial_energy, "zero-input energy decays")
	_check(float(result["summary"]["dissipated_energy"]) > 0.0, "physical dissipation positive")
	_check(float(result["summary"]["numerical_dissipation_energy"]) >= 0.0, "backward Euler numerical dissipation nonnegative")
	_check(float(result["summary"]["max_unaccounted_energy_creation"]) <= 1.0e-12, "no unaccounted energy creation")
	_check(float(result["summary"]["max_balance_residual"]) <= 2.0e-11, "discrete energy balance bounded")

func _test_boundary_power_and_orientation() -> void:
	var zero_fixture := Fixture.build("ZERO")
	var compiled := Compiler.compile(zero_fixture["request"])
	_check(bool(compiled.get("success", false)), "flow-driven fixture compiles")
	if not bool(compiled.get("success", false)):
		return
	var model: Dictionary = compiled["model"]
	var initial := Solver.initial_state(model)
	var flows := Fixture.zero_flows(model["boundary_contract"])
	flows["port/electrical/000-left"] = 0.75
	var driven := Solver.advance_constant(model, initial["state"], flows, 0.01, 50)
	_check(bool(driven.get("success", false)), "positive INTO flow drives network")
	if bool(driven.get("success", false)):
		_check(float(driven["summary"]["final_stored_energy"]) > 0.0, "boundary input stores energy")
		_check(float(driven["summary"]["boundary_energy_in"]) > 0.0, "INTO orientation produces positive input energy")
		_check(float(driven["summary"]["max_unaccounted_energy_creation"]) <= 1.0e-12, "driven case has no invented energy")

	var positive_fixture := Fixture.build("POSITIVE")
	var positive_compiled := Compiler.compile(positive_fixture["request"])
	_check(bool(positive_compiled.get("success", false)), "positive orientation fixture compiles")
	if not bool(positive_compiled.get("success", false)):
		return
	var positive_model: Dictionary = positive_compiled["model"]
	var positive_initial := Solver.initial_state(positive_model)
	var out_flows := Fixture.zero_flows(positive_model["boundary_contract"])
	out_flows["port/electrical/511-right"] = 0.20
	var extracted := Solver.step(positive_model, positive_initial["state"], out_flows, 0.01)
	_check(bool(extracted.get("success", false)), "positive OUT flow reference step succeeds")
	if bool(extracted.get("success", false)):
		var right := _boundary_by_id(extracted["boundary"], "port/electrical/511-right")
		_check(float(right["power_into"]) < 0.0, "OUT orientation flips boundary power sign")
		_check(float(extracted["energy"]["stored_after"]) < float(extracted["energy"]["stored_before"]), "positive outflow extracts stored energy")
		_check(float(extracted["energy"]["unaccounted_energy_creation"]) <= 1.0e-12, "extraction case no invented energy")

	var too_large := Solver.step(positive_model, positive_initial["state"], out_flows, 0.03)
	_check(not bool(too_large.get("success", false)), "step over certified maximum rejected")
	_check(String(too_large.get("error_code", "")) == "B0_4_A_REFERENCE_STEP_EXCEEDS_CERTIFIED_MAX", "large-step reason exact")

	var missing_flow := Fixture.zero_flows(positive_model["boundary_contract"])
	missing_flow.erase("port/electrical/000-left")
	var missing_result := Solver.step(positive_model, positive_initial["state"], missing_flow, 0.01)
	_check(not bool(missing_result.get("success", false)), "missing boundary flow rejected")
	_check(String(missing_result.get("error_code", "")) == "B0_4_A_REFERENCE_PORT_FLOW_COVERAGE_MISMATCH", "missing-flow reason exact")

func _test_reference_determinism() -> void:
	var fixture := Fixture.build("PATTERN")
	var compiled := Compiler.compile(fixture["request"])
	_check(bool(compiled.get("success", false)), "determinism fixture compiles")
	if not bool(compiled.get("success", false)):
		return
	var model: Dictionary = compiled["model"]
	var a := Solver.initial_state(model)
	var b := Solver.initial_state(model)
	_check(bool(a.get("success", false)) and bool(b.get("success", false)), "determinism initial states create")
	if not bool(a.get("success", false)) or not bool(b.get("success", false)):
		return
	var flows := Fixture.zero_flows(model["boundary_contract"])
	flows["port/electrical/000-left"] = 0.25
	flows["port/electrical/170-mid-a"] = -0.10
	flows["port/electrical/341-mid-b"] = 0.05
	flows["port/electrical/511-right"] = 0.02
	var run_a := Solver.advance_constant(model, a["state"], flows, 0.005, 160)
	var run_b := Solver.advance_constant(model, b["state"], flows, 0.005, 160)
	_check(bool(run_a.get("success", false)) and bool(run_b.get("success", false)), "deterministic twin runs succeed")
	if bool(run_a.get("success", false)) and bool(run_b.get("success", false)):
		_check(String(run_a["state"]["checksum"]) == String(run_b["state"]["checksum"]), "FULL reference state checksum deterministic")
		_check(run_a["state"]["values"] == run_b["state"]["values"], "FULL reference state bytes-equivalent values")
		_check(run_a["summary"] == run_b["summary"], "FULL reference energy summary deterministic")

	var wrong_state: Dictionary = a["state"].duplicate(true)
	wrong_state["model_hash"] = Utils.canonical_hash({"wrong": "model"})
	wrong_state["checksum"] = Utils.compute_checksum(wrong_state)
	var wrong_result := Solver.step(model, wrong_state, flows, 0.005)
	_check(not bool(wrong_result.get("success", false)), "state from wrong model rejected")
	_check(String(wrong_result.get("error_code", "")) == "B0_4_A_FULL_STATE_MODEL_MISMATCH", "wrong-model state reason exact")

func _port_by_id(boundary: Dictionary, port_id: String) -> Dictionary:
	for port in boundary["ports"]:
		if String(port["port_id"]) == port_id:
			return port
	return {}

func _boundary_by_id(boundary: Array, port_id: String) -> Dictionary:
	for entry in boundary:
		if String(entry["port_id"]) == port_id:
			return entry
	return {}

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC-BAKE B0.4-A Dynamic Model / Port Contract Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("B0.4-A: %s" % failure)
	print("FABRIC-BAKE B0.4-A Dynamic Model / Port Contract Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
