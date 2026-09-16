extends SceneTree

const Transport = preload("res://scripts/research/fabric_holdout_r4_g2/lossless_json_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const Mechanics = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_mechanics_v1.gd")
const EventStep = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_event_step_v1.gd")

const ABS_TOL := 1.0e-10
const REL_TOL := 1.0e-10
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991

var _failures: Array[String] = []
var _assertions := 0

func _initialize() -> void:
	_verify_lossless_transport_oracle()
	_verify_resistive_graph_oracle()
	_verify_mechanics_oracle()
	_verify_event_math_oracle()
	if not _failures.is_empty():
		print("FABRIC_HOLDOUT_R4_G2_INDEPENDENT_VERIFIER_R1_FAILURES=", JSON.stringify(_failures))
		print("FABRIC-HOLDOUT-R4-G2-INDEPENDENT-VERIFIER-R1: FAIL")
		quit(1)
		return
	print("FABRIC_HOLDOUT_R4_G2_INDEPENDENT_VERIFIER_R1_ASSERTIONS=", _assertions)
	print("FABRIC-HOLDOUT-R4-G2-INDEPENDENT-VERIFIER-R1: PASS")
	quit(0)

func _verify_lossless_transport_oracle() -> void:
	var payload := {
		"neg_zero": _negative_zero(),
		"pos_zero": 0.0,
		"fraction": 1.0 / 3.0,
		"small": 1.0e-300,
		"large": 1000000000000.125,
		"integer": MAX_SAFE_JSON_INTEGER,
		"nested": [true, null, "iv-r1", {"x": -17.25}],
	}
	var text := Transport.canonical_json(payload)
	_expect(not text.is_empty(), "transport canonical text emitted")
	var parsed := Transport.parse_json(text)
	_expect(bool(parsed.get("success", false)), "transport canonical round-trip succeeds")
	if bool(parsed.get("success", false)):
		var value: Dictionary = parsed.value
		for key in ["neg_zero", "pos_zero", "fraction", "small", "large"]:
			_expect(_f64_hex(float(value[key])) == _f64_hex(float(payload[key])), "transport f64 bits preserved: %s" % key)
		_expect(_f64_hex(float(value.neg_zero)) != _f64_hex(float(value.pos_zero)), "transport preserves signed zero")
		_expect(int(value.integer) == MAX_SAFE_JSON_INTEGER, "transport safe integer boundary preserved")
		_expect(value.nested == payload.nested, "transport nested payload preserved")

	var too_large := Transport.encode(MAX_SAFE_JSON_INTEGER + 1)
	_expect(not bool(too_large.get("success", false)) and String(too_large.get("error", "")) == "WIRE_INTEGER_RANGE", "transport rejects integer above safe boundary")
	var nonfinite := Transport.encode(INF)
	_expect(not bool(nonfinite.get("success", false)) and String(nonfinite.get("error", "")) == "WIRE_NONFINITE", "transport rejects nonfinite")
	var noncanonical := Transport.parse_json(text + "\n")
	_expect(not bool(noncanonical.get("success", false)) and String(noncanonical.get("error", "")) == "WIRE_JSON_NONCANONICAL", "transport rejects noncanonical JSON spelling")

	var encoded := Transport.encode({"k": 1.25})
	_expect(bool(encoded.get("success", false)), "transport tamper fixture encodes")
	if bool(encoded.get("success", false)):
		var wire: Dictionary = encoded.value.duplicate(true)
		wire.payload = ["d", [["k", ["f64le", _f64_hex(1.5)]]]]
		var tampered := Transport.decode(wire)
		_expect(not bool(tampered.get("success", false)) and String(tampered.get("error", "")) == "WIRE_CHECKSUM_MISMATCH", "transport rejects checksum-preserving payload tamper")

func _verify_resistive_graph_oracle() -> void:
	# Two equal-ratio divider legs plus a cross-link. Analytically X=Y=20/3 V,
	# so the cross-link current is exactly zero and source current is 25/9 A.
	var model := {
		"nodes": [_node("L"), _node("X"), _node("Y"), _node("R")],
		"elements": [
			_edge("lx", "L", "X", 2.0),
			_edge("xr", "X", "R", 4.0),
			_edge("ly", "L", "Y", 3.0),
			_edge("yr", "Y", "R", 6.0),
			_edge("xy", "X", "Y", 5.0),
		],
	}
	var solved := Graph.solve_resistive(model, {"L": 10.0, "R": 0.0})
	_expect(bool(solved.get("success", false)), "graph analytic fixture solves")
	if bool(solved.get("success", false)):
		var d: Dictionary = solved.details
		_expect(_near(float(d.potentials_v.X), 20.0 / 3.0), "graph X analytic voltage")
		_expect(_near(float(d.potentials_v.Y), 20.0 / 3.0), "graph Y analytic voltage")
		_expect(_near(float(d.edge_currents_a.lx), 5.0 / 3.0), "graph lx analytic current")
		_expect(_near(float(d.edge_currents_a.ly), 10.0 / 9.0), "graph ly analytic current")
		_expect(_near(float(d.edge_currents_a.xy), 0.0), "graph bridge cross-current analytic zero")
		_expect(_near(float(d.port_currents_a.L), 25.0 / 9.0), "graph source current analytic")
		_expect(_near(float(d.port_currents_a.R), -25.0 / 9.0), "graph sink current analytic")
		_expect(float(d.kcl_residual_a) <= 1.0e-12, "graph KCL residual bounded")
		_expect(float(d.power_residual_w) <= 1.0e-10, "graph power residual bounded")

	var permuted := {
		"nodes": [_node("Y"), _node("R"), _node("L"), _node("X")],
		"elements": [
			_edge("xy", "X", "Y", 5.0),
			_edge("yr", "Y", "R", 6.0),
			_edge("ly", "L", "Y", 3.0),
			_edge("xr", "X", "R", 4.0),
			_edge("lx", "L", "X", 2.0),
		],
	}
	var reordered := Graph.solve_resistive(permuted, {"R": 0.0, "L": 10.0})
	_expect(bool(reordered.get("success", false)), "graph permuted fixture solves")
	if bool(solved.get("success", false)) and bool(reordered.get("success", false)):
		for key in ["L", "X", "Y", "R"]:
			_expect(_near(float(solved.details.potentials_v[key]), float(reordered.details.potentials_v[key])), "graph insertion order invariant potential: %s" % key)
		for key in ["lx", "xr", "ly", "yr", "xy"]:
			_expect(_near(float(solved.details.edge_currents_a[key]), float(reordered.details.edge_currents_a[key])), "graph insertion order invariant current: %s" % key)

	var floating := model.duplicate(true)
	floating.nodes.append(_node("F0"))
	floating.nodes.append(_node("F1"))
	floating.elements.append(_edge("floating", "F0", "F1", 7.0))
	var rejected := Graph.solve_resistive(floating, {"L": 10.0, "R": 0.0})
	_expect(not bool(rejected.get("success", false)) and String(rejected.get("error_code", "")) == "R3_GENERAL_FLOATING_COMPONENT", "graph floating component fails closed")

func _verify_mechanics_oracle() -> void:
	# Unit load at M2 for K=[[300,-200],[-200,500]] gives
	# x(M1)=1/550 m and x(M2)=3/1100 m.
	var model := _mechanical_chain(false, false)
	var solved := Mechanics.solve_mechanical_static(model, "M2")
	_expect(bool(solved.get("success", false)), "mechanics analytic fixture solves")
	if bool(solved.get("success", false)):
		_expect(_near(float(solved.details.displacement_per_newton.M1), 1.0 / 550.0), "mechanics M1 analytic displacement")
		_expect(_near(float(solved.details.displacement_per_newton.M2), 3.0 / 1100.0), "mechanics M2 analytic displacement")

	var controls := {"coupler_node_id": "M2"}
	var compiled := Mechanics.compile_mechanics(model, controls)
	_expect(bool(compiled.get("success", false)), "mechanics generalized compile succeeds")
	if bool(compiled.get("success", false)):
		_expect(_vec_near(compiled.details.axis, [1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0]), "mechanics geometric axis analytic")
		_expect(compiled.details.mobile_nodes == ["M1", "M2"], "mechanics deterministic mobile ordering")
		_expect(_near(float(compiled.details.mobile_masses_kg[0]), 2.0) and _near(float(compiled.details.mobile_masses_kg[1]), 3.0), "mechanics masses preserved")

	var reversed := Mechanics.compile_mechanics(_mechanical_chain(true, true), controls)
	_expect(bool(reversed.get("success", false)), "mechanics endpoint/id reversed compile succeeds")
	if bool(compiled.get("success", false)) and bool(reversed.get("success", false)):
		_expect(_vec_near(compiled.details.axis, reversed.details.axis), "mechanics axis invariant under endpoint/id reversal")

	var tiny := _mechanical_chain(false, false)
	tiny.nodes[1].mass_kg = 1.0e-15
	var tiny_rejected := Mechanics.compile_mechanics(tiny, controls)
	_expect(not bool(tiny_rejected.get("success", false)) and String(tiny_rejected.get("error_code", "")) == "R3_MASS_INVALID", "mechanics DAE divisor floor fails closed")

func _verify_event_math_oracle() -> void:
	var parsed := EventStep._parse_transition_id("failure|bond/a|b|c|-1.0")
	_expect(bool(parsed.get("ok", false)), "event delimiter-rich transition parses")
	if bool(parsed.get("ok", false)):
		_expect(String(parsed.element_id) == "bond/a|b|c", "event parser preserves complete bond id")
		_expect(_near(float(parsed.sign), -1.0), "event parser preserves sign")
	var malformed := EventStep._parse_transition_id("failure|bond/a|0.5")
	_expect(not bool(malformed.get("ok", false)), "event parser rejects non-unit sign")

	var roots := EventStep._roots([0.16, -1.0, 1.0]) # (u-0.2)*(u-0.8)
	_expect(roots.size() == 2, "event polynomial finds two transient roots")
	if roots.size() == 2:
		_expect(_near(float(roots[0]), 0.2, 1.0e-9, 1.0e-9), "event first analytic root")
		_expect(_near(float(roots[1]), 0.8, 1.0e-9, 1.0e-9), "event second analytic root")
	var tangent := EventStep._roots([0.25, -1.0, 1.0]) # (u-0.5)^2
	_expect(tangent.size() == 1 and _near(float(tangent[0]), 0.5, 1.0e-9, 1.0e-9), "event tangent root retained for fail-closed detection")

func _node(id: String) -> Dictionary:
	return {"node_id": id}

func _edge(id: String, a: String, b: String, resistance: float) -> Dictionary:
	return {"element_id": id, "node_a": a, "node_b": b, "resistance_ohm": resistance, "active": true}

func _mechanical_chain(reverse_endpoints: bool, rename_elements: bool) -> Dictionary:
	var nodes := [
		{"node_id": "A", "anchored": true, "mass_kg": 1.0, "local_position_m": [0.0, 0.0, 0.0]},
		{"node_id": "M1", "anchored": false, "mass_kg": 2.0, "local_position_m": [1.0, 2.0, 2.0]},
		{"node_id": "M2", "anchored": false, "mass_kg": 3.0, "local_position_m": [2.0, 4.0, 4.0]},
		{"node_id": "Z", "anchored": true, "mass_kg": 1.0, "local_position_m": [3.0, 6.0, 6.0]},
	]
	var specs := [
		["e1", "A", "M1", 100.0],
		["e2", "M1", "M2", 200.0],
		["e3", "M2", "Z", 300.0],
	]
	var elements: Array = []
	for i in range(specs.size()):
		var row: Array = specs[i]
		var a: String = row[1]
		var b: String = row[2]
		if reverse_endpoints:
			var tmp := a
			a = b
			b = tmp
		var element_id := ("zz-%d" % (specs.size() - i)) if rename_elements else String(row[0])
		elements.append({
			"element_id": element_id,
			"node_a": a,
			"node_b": b,
			"stiffness_n_per_m": float(row[3]),
			"damping_ns_per_m": 2.0 + i,
			"capacity_n": 1000.0,
			"active": true,
		})
	return {"nodes": nodes, "elements": elements}

func _negative_zero() -> float:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = "0000000000000080".hex_decode()
	return buffer.get_double()

func _f64_hex(value: float) -> String:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_double(value)
	return buffer.data_array.hex_encode()

func _vec_near(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size(): return false
	for i in range(actual.size()):
		if not _near(float(actual[i]), float(expected[i])): return false
	return true

func _near(a: float, b: float, abs_tol: float = ABS_TOL, rel_tol: float = REL_TOL) -> bool:
	return absf(a - b) <= maxf(abs_tol, rel_tol * maxf(absf(a), absf(b)))

func _expect(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)
