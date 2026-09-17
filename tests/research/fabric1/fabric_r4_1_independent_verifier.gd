extends SceneTree

const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const Perf = preload("res://scripts/research/fabric_bake0/complex2_perf_scaling_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var assertions := 0
var failures: Array[String] = []

func _check(ok: bool, label: String, details = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", details)

func _model(resistors: Array) -> Dictionary:
	return {"nodes": [{"node_id":"a"},{"node_id":"x"},{"node_id":"y"},{"node_id":"b"}], "elements": [
		{"element_id":"ax","node_a":"a","node_b":"x","resistance_ohm":resistors[0],"active":true},
		{"element_id":"xb","node_a":"x","node_b":"b","resistance_ohm":resistors[1],"active":true},
		{"element_id":"ay","node_a":"a","node_b":"y","resistance_ohm":resistors[2],"active":true},
		{"element_id":"yb","node_a":"y","node_b":"b","resistance_ohm":resistors[3],"active":true},
		{"element_id":"xy","node_a":"x","node_b":"y","resistance_ohm":resistors[4],"active":true},
	]}

func _finite(value) -> bool:
	match typeof(value):
		TYPE_FLOAT: return is_finite(float(value))
		TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_NIL: return true
		TYPE_ARRAY:
			for v in value:
				if not _finite(v): return false
			return true
		TYPE_DICTIONARY:
			for k in value:
				if not _finite(value[k]): return false
			return true
		_: return true

func _initialize() -> void:
	var exact := Graph.solve_resistive(_model([2.0,3.0,4.0,5.0,7.0]), {"a":1.0,"b":0.0})
	_check(exact.success, "V-R41 branched graph solves", exact)
	if exact.success:
		_check(absf(float(exact.details.potentials_v.x) - 279.0/469.0) < 1e-12, "V-R41 independent x potential", exact.details)
		_check(absf(float(exact.details.potentials_v.y) - 265.0/469.0) < 1e-12, "V-R41 independent y potential", exact.details)
		_check(absf(float(exact.details.edge_currents_a.xy) - 2.0/469.0) < 1e-12, "V-R41 independent bridge current", exact.details)
		_check(_finite(exact.details), "V-R41 successful graph details contain no nonfinite", exact.details)
		var perm := _model([2.0,3.0,4.0,5.0,7.0]); perm.nodes.reverse(); perm.elements.reverse()
		var replay := Graph.solve_resistive(perm, {"b":0.0,"a":1.0})
		_check(replay.success and U.canonical_hash(replay.details)==U.canonical_hash(exact.details), "V-R41 permutation deterministic", replay)

	var high := Graph.solve_resistive({"nodes":[{"node_id":"a"},{"node_id":"b"}],"elements":[{"element_id":"r","node_a":"a","node_b":"b","resistance_ohm":1e-200,"active":true}]},{"a":1.0,"b":0.0})
	_check(high.success and _finite(high.details), "V-R41 high finite result remains finite", high)
	if high.success:
		_check(absf(float(high.details.edge_currents_a.r)/1e200 - 1.0) < 1e-12, "V-R41 high finite current", high.details)
		_check(absf(float(high.details.joule_power_w)/1e200 - 1.0) < 1e-12, "V-R41 high finite power", high.details)

	var rhs_over := Graph.solve_resistive({"nodes":[{"node_id":"a"},{"node_id":"x"}],"elements":[{"element_id":"r","node_a":"a","node_b":"x","resistance_ohm":0.1,"active":true}]},{"a":1e308})
	_check(not rhs_over.success and String(rhs_over.error_code)=="R3_NUMERIC_ENVELOPE", "V-R41 RHS overflow fails closed", rhs_over)
	var current_over := Graph.solve_resistive({"nodes":[{"node_id":"a"},{"node_id":"b"}],"elements":[{"element_id":"r","node_a":"a","node_b":"b","resistance_ohm":1.0,"active":true}]},{"a":1e308,"b":-1e308})
	_check(not current_over.success and String(current_over.error_code)=="R3_NUMERIC_ENVELOPE", "V-R41 voltage subtraction/current overflow fails closed", current_over)
	var power_over := Graph.solve_resistive({"nodes":[{"node_id":"a"},{"node_id":"b"}],"elements":[{"element_id":"r","node_a":"a","node_b":"b","resistance_ohm":1e-100,"active":true}]},{"a":1e200,"b":0.0})
	_check(not power_over.success and String(power_over.error_code)=="R3_NUMERIC_ENVELOPE", "V-R41 finite current but power overflow fails closed", power_over)
	var cond_over := Graph.solve_resistive({"nodes":[{"node_id":"a"},{"node_id":"b"}],"elements":[{"element_id":"r","node_a":"a","node_b":"b","resistance_ohm":1e-320,"active":true}]},{"a":1.0,"b":0.0})
	_check(not cond_over.success, "V-R41 reciprocal overflow fails closed", cond_over)

	var primary := {"success":false,"error_code":"INDEPENDENT_PRIMARY_SENTINEL","details":{"stage":"verifier"}}
	var wrapped := Perf._matrix_case_failure_for_diagnostics(2000, primary)
	_check(not wrapped.success, "V-R41 diagnostic wrapper remains failure", wrapped)
	_check(String(wrapped.get("matrix_hash","forged"))=="", "V-R41 failed matrix hash explicit empty", wrapped)
	_check(String(wrapped.details.case.error_code)=="INDEPENDENT_PRIMARY_SENTINEL", "V-R41 primary error survives wrapper", wrapped)
	_check(int(wrapped.details.part_count)==2000, "V-R41 failing scale survives wrapper", wrapped)

	print("FABRIC_R4_1_INDEPENDENT_VERIFIER_ASSERTIONS=%d FAILURES=%d" % [assertions, failures.size()])
	if failures.is_empty():
		print("FABRIC-R4.1-INDEPENDENT-VERIFIER: PASS")
		quit(0)
	else:
		print("FABRIC_R4_1_INDEPENDENT_VERIFIER_FAILURES="+JSON.stringify(failures)); quit(1)
