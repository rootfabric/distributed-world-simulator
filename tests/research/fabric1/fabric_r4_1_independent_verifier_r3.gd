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

func _two_node(resistance: float) -> Dictionary:
	return {"nodes":[{"node_id":"a"},{"node_id":"b"}],"elements":[{"element_id":"r","node_a":"a","node_b":"b","resistance_ohm":resistance,"active":true}]}

func _f64_le(bits: String) -> float:\n\tvar bytes: PackedByteArray = bits.hex_decode()\n\treturn bytes.decode_double(0)\n\nfunc _initialize() -> void:
	# Independent rational oracle, not copied expected values from product acceptance.
	var exact := Graph.solve_resistive(_model([2.0,3.0,4.0,5.0,7.0]), {"a":1.0,"b":0.0})
	_check(exact.success, "V-R41-R3 branched graph solves", exact)
	if exact.success:
		_check(absf(float(exact.details.potentials_v.x) - 279.0/469.0) < 1e-12, "V-R41-R3 independent x potential", exact.details)
		_check(absf(float(exact.details.potentials_v.y) - 265.0/469.0) < 1e-12, "V-R41-R3 independent y potential", exact.details)
		_check(absf(float(exact.details.edge_currents_a.xy) - 2.0/469.0) < 1e-12, "V-R41-R3 independent bridge current", exact.details)
		_check(_finite(exact.details), "V-R41-R3 successful graph details contain no nonfinite", exact.details)
		var perm := _model([2.0,3.0,4.0,5.0,7.0])
		perm.nodes.reverse()
		perm.elements.reverse()
		var replay := Graph.solve_resistive(perm, {"b":0.0,"a":1.0})
		_check(replay.success and U.canonical_hash(replay.details)==U.canonical_hash(exact.details), "V-R41-R3 permutation deterministic", replay)

	var high := Graph.solve_resistive(_two_node(1e-200), {"a":1.0,"b":0.0})
	_check(high.success and _finite(high.details), "V-R41-R3 high finite result remains finite", high)
	if high.success:
		_check(absf(float(high.details.edge_currents_a.r)/1e200 - 1.0) < 1e-12, "V-R41-R3 high finite current", high.details)
		_check(absf(float(high.details.joule_power_w)/1e200 - 1.0) < 1e-12, "V-R41-R3 high finite power", high.details)

	# Fresh-review P1: huge common-mode potential must not overflow individual V*I terms.
	var common_offset := Graph.solve_resistive(_two_node(5e306), {"a":1e308,"b":9e307})
	_check(common_offset.success and _finite(common_offset.details), "V-R41-R3 common-offset finite solution accepted", common_offset)
	if common_offset.success:
		_check(absf(float(common_offset.details.edge_currents_a.r) - 2.0) < 1e-12, "V-R41-R3 common-offset current analytic", common_offset.details)
		_check(absf(float(common_offset.details.boundary_power_w)/2e307 - 1.0) < 1e-12, "V-R41-R3 common-offset power analytic", common_offset.details)

	# Fresh-review P1: two finite ~1e308 powers cannot overflow the residual scale itself.
	var scale_extreme := Graph.solve_resistive(_two_node(1e308), {"a":1e308,"b":0.0})
	_check(scale_extreme.success and _finite(scale_extreme.details), "V-R41-R3 max-based residual scale stays finite", scale_extreme)

	# Fresh-review P1: prove the fixture really overflows a naive partial balance.
	var compensated_r := _f64_le("f8ad43bd58010400") # exact 5.57e-309\n\tvar i := 0.51 / compensated_r
	_check(is_finite(i) and not is_finite(i + i), "V-R41-R3 fixture forces naive partial overflow", i)
	var compensated_model := {
		"nodes":[{"node_id":"hub"},{"node_id":"p1"},{"node_id":"p2"},{"node_id":"n1"}],
		"elements":[
			{"element_id":"e1","node_a":"p1","node_b":"hub","resistance_ohm":compensated_r,"active":true},
			{"element_id":"e2","node_a":"p2","node_b":"hub","resistance_ohm":compensated_r,"active":true},
			{"element_id":"e3","node_a":"n1","node_b":"hub","resistance_ohm":compensated_r,"active":true},
		]
	}
	var compensated := Graph.solve_resistive(compensated_model, {"hub":0.0,"p1":0.51,"p2":0.51,"n1":-0.51})
	_check(compensated.success and _finite(compensated.details), "V-R41-R3 compensated finite balance accepted", compensated)
	if compensated.success:
		_check(absf(float(compensated.details.port_currents_a.hub) / (-i) - 1.0) < 1e-12, "V-R41-R3 compensated hub balance analytic", compensated.details.port_currents_a)

	# Non-representable or invalid cases still fail closed.
	var rhs_over := Graph.solve_resistive({"nodes":[{"node_id":"a"},{"node_id":"x"}],"elements":[{"element_id":"r","node_a":"a","node_b":"x","resistance_ohm":0.1,"active":true}]},{"a":1e308})
	_check(not rhs_over.success and String(rhs_over.error_code)=="R3_NUMERIC_ENVELOPE", "V-R41-R3 RHS overflow fails closed", rhs_over)
	var current_over := Graph.solve_resistive(_two_node(1.0), {"a":1e308,"b":-1e308})
	_check(not current_over.success and String(current_over.error_code)=="R3_NUMERIC_ENVELOPE", "V-R41-R3 voltage/current overflow fails closed", current_over)
	var power_over := Graph.solve_resistive(_two_node(1e-100), {"a":1e200,"b":0.0})
	_check(not power_over.success and String(power_over.error_code)=="R3_NUMERIC_ENVELOPE", "V-R41-R3 finite current but power overflow fails closed", power_over)
	var cond_over := Graph.solve_resistive(_two_node(_f64_le("e807000000000000")), {"a":1.0,"b":0.0})
	_check(not cond_over.success and String(cond_over.error_code)=="R3_NUMERIC_ENVELOPE", "V-R41-R3 reciprocal overflow fails closed", cond_over)

	# Diagnostic integrity is independently checked with a sentinel primary error.
	var primary := {"success":false,"error_code":"INDEPENDENT_PRIMARY_SENTINEL","details":{"stage":"verifier-r3"}}
	var wrapped := Perf._matrix_case_failure_for_diagnostics(2000, primary)
	_check(not wrapped.success, "V-R41-R3 diagnostic wrapper remains failure", wrapped)
	_check(String(wrapped.get("matrix_hash","forged"))=="", "V-R41-R3 failed matrix hash explicit empty", wrapped)
	_check(String(wrapped.details.case.error_code)=="INDEPENDENT_PRIMARY_SENTINEL", "V-R41-R3 primary error survives wrapper", wrapped)
	_check(int(wrapped.details.part_count)==2000, "V-R41-R3 failing scale survives wrapper", wrapped)

	print("FABRIC_R4_1_INDEPENDENT_VERIFIER_R3_ASSERTIONS=%d FAILURES=%d" % [assertions, failures.size()])
	if failures.is_empty():
		print("FABRIC-R4.1-INDEPENDENT-VERIFIER-R3: PASS")
		quit(0)
	else:
		print("FABRIC_R4_1_INDEPENDENT_VERIFIER_R3_FAILURES="+JSON.stringify(failures))
		quit(1)
