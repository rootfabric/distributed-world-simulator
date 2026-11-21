extends SceneTree

const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const Perf = preload("res://scripts/research/fabric_bake0/complex2_perf_scaling_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _check(ok: bool, label: String, details = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", details)

func _two_node(resistance: float) -> Dictionary:
	return {
		"nodes": [{"node_id": "a"}, {"node_id": "b"}],
		"elements": [{"element_id": "r", "node_a": "a", "node_b": "b", "resistance_ohm": resistance, "active": true}],
	}

func _f64_le(bits: String) -> float:
	var bytes: PackedByteArray = bits.hex_decode()
	return bytes.decode_double(0)

func _initialize() -> void:
	var nominal := Graph.solve_resistive(_two_node(1.0), {"a": 1.0, "b": 0.0})
	_check(nominal.success, "R4.1 nominal graph succeeds", nominal)
	if nominal.success:
		_check(is_finite(float(nominal.details.edge_currents_a.r)) and absf(float(nominal.details.edge_currents_a.r) - 1.0) <= 1.0e-12, "R4.1 nominal current finite/exact", nominal.details)
		_check(is_finite(float(nominal.details.joule_power_w)) and absf(float(nominal.details.joule_power_w) - 1.0) <= 1.0e-12, "R4.1 nominal power finite/exact", nominal.details)

	var extreme_voltage := Graph.solve_resistive(_two_node(1.0), {"a": 1.0e308, "b": -1.0e308})
	_check(not extreme_voltage.success and String(extreme_voltage.error_code) == "R3_NUMERIC_ENVELOPE", "R4.1 overflowing voltage fails closed", extreme_voltage)

	var large_finite := Graph.solve_resistive(_two_node(1.0e-200), {"a": 1.0, "b": 0.0})
	_check(large_finite.success, "R4.1 large finite conductance remains supported", large_finite)
	if large_finite.success:
		_check(is_finite(float(large_finite.details.edge_currents_a.r)) and is_finite(float(large_finite.details.joule_power_w)), "R4.1 large finite outputs stay finite", large_finite.details)
		_check(absf(float(large_finite.details.edge_currents_a.r) / 1.0e200 - 1.0) <= 1.0e-12, "R4.1 large finite current scale", large_finite.details.edge_currents_a.r)
		_check(absf(float(large_finite.details.joule_power_w) / 1.0e200 - 1.0) <= 1.0e-12, "R4.1 stable Joule evaluation", large_finite.details.joule_power_w)

	# Fresh-review regressions: all inputs and final physical outputs are finite;
	# only naive intermediate arithmetic would overflow.
	var common_offset := Graph.solve_resistive(_two_node(5.0e306), {"a": 1.0e308, "b": 9.0e307})
	_check(common_offset.success, "R4.1 common-potential power remains representable", common_offset)
	if common_offset.success:
		_check(is_finite(float(common_offset.details.boundary_power_w)) and absf(float(common_offset.details.boundary_power_w) / 2.0e307 - 1.0) <= 1.0e-12, "R4.1 common-offset boundary power stable", common_offset.details)

	var finite_power_scale := Graph.solve_resistive(_two_node(1.0e308), {"a": 1.0e308, "b": 0.0})
	_check(finite_power_scale.success, "R4.1 finite 1e308 power does not overflow residual scale", finite_power_scale)
	if finite_power_scale.success:
		_check(is_finite(float(finite_power_scale.details.power_residual_w)) and float(finite_power_scale.details.power_residual_w) <= 1.0e292, "R4.1 extreme finite power residual bounded", finite_power_scale.details)

	# GDScript source literals below ~1e-308 are not a reliable way to express
	# a positive subnormal in this acceptance. Construct the exact f64 bytes.
	var compensated_r := _f64_le("f8ad43bd58010400") # 5.57e-309
	var compensated_i := 0.51 / compensated_r
	_check(compensated_r > 0.0 and is_finite(1.0 / compensated_r), "R4.1 subnormal resistance fixture is valid", compensated_r)
	_check(is_finite(compensated_i) and not is_finite(compensated_i + compensated_i), "R4.1 fixture forces naive partial overflow", compensated_i)
	var compensated_model := {
		"nodes": [{"node_id": "hub"}, {"node_id": "p1"}, {"node_id": "p2"}, {"node_id": "n1"}],
		"elements": [
			{"element_id": "e1", "node_a": "p1", "node_b": "hub", "resistance_ohm": compensated_r, "active": true},
			{"element_id": "e2", "node_a": "p2", "node_b": "hub", "resistance_ohm": compensated_r, "active": true},
			{"element_id": "e3", "node_a": "n1", "node_b": "hub", "resistance_ohm": compensated_r, "active": true},
		],
	}
	var compensated := Graph.solve_resistive(compensated_model, {"hub": 0.0, "p1": 0.51, "p2": 0.51, "n1": -0.51})
	_check(compensated.success, "R4.1 compensated node balance survives partial overflow", compensated)
	if compensated.success:
		var hub_balance := float(compensated.details.port_currents_a.hub)
		_check(is_finite(hub_balance) and absf(hub_balance / (-compensated_i) - 1.0) <= 1.0e-12, "R4.1 compensated node balance finite/analytic", compensated.details.port_currents_a)

	var conductance_overflow_r := _f64_le("e807000000000000") # 1e-320
	var conductance_overflow := Graph.solve_resistive(_two_node(conductance_overflow_r), {"a": 1.0, "b": 0.0})
	_check(not conductance_overflow.success, "R4.1 conductance overflow fails closed", conductance_overflow)
	_check(String(conductance_overflow.error_code) == "R3_NUMERIC_ENVELOPE", "R4.1 conductance overflow reports numeric envelope", conductance_overflow)

	# Regression for the old diagnostic masker: matrix-level failures must carry an
	# explicitly empty hash so a caller can preserve the primary error code/details.
	var matrix_failure := Perf._matrix_case_failure_for_diagnostics(500, {"success": false, "error_code": "PRIMARY_SENTINEL", "details": {"cause": "test"}})
	_check(not matrix_failure.success, "R4.1 PERF diagnostic failure remains failure", matrix_failure)
	_check(String(matrix_failure.error_code) == "COMPLEX2PERF_CASE_FAILED", "R4.1 PERF wrapper error preserved", matrix_failure)
	_check(String(matrix_failure.get("matrix_hash", "forged")) == "", "R4.1 PERF failed matrix has explicit empty hash", matrix_failure)
	_check(String(matrix_failure.details.case.error_code) == "PRIMARY_SENTINEL", "R4.1 PERF primary failure survives wrapper", matrix_failure)

	print("FABRIC_R4_1_NUMERIC_DIAGNOSTICS_ASSERTIONS=%d FAILURES=%d" % [assertions, failures.size()])
	if failures.is_empty():
		print("FABRIC-R4.1-NUMERIC-DIAGNOSTICS: PASS")
		quit(0)
	else:
		print("FABRIC_R4_1_NUMERIC_DIAGNOSTICS_FAILURES=" + JSON.stringify(failures))
		quit(1)
