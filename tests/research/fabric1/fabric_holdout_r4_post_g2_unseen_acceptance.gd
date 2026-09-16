extends SceneTree

const Transport = preload("res://scripts/research/fabric_holdout_r4_g2/lossless_json_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const Mechanics = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_mechanics_v1.gd")
const EventStep = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_event_step_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const U = Compiler.U
const EXPECTED_HEAD := "e6228a39b6b3006a3d14ad0884c09266570fcd00"
const EXPECTED_TREE := "1b84960369868aa6d5ec23c1eae3019250ff9a8f"
var assertions := 0
var failures: Array[String] = []

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)

func _bits(value: float) -> String:
	var buffer := StreamPeerBuffer.new(); buffer.big_endian = false; buffer.put_double(value); return buffer.data_array.hex_encode()
func _from_bits(hex_value: String) -> float:
	var buffer := StreamPeerBuffer.new(); buffer.big_endian = false; buffer.data_array = hex_value.hex_decode(); return buffer.get_double()
func _roundtrip(value) -> Dictionary:
	var encoded := Transport.encode(value)
	if not encoded.success: return encoded
	return Transport.decode(JSON.parse_string(JSON.stringify(encoded.value, "", true, true)))

func _initialize() -> void:
	var path := OS.get_environment("FABRIC_R4_POST_G2_CASES")
	if path.is_empty(): path = "res://config/research/fabric-holdout-r4-post-g2-unseen-cases.generated.json"
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(manifest is Dictionary, "UNSEEN manifest parses", path)
	if not manifest is Dictionary: _finish(); return
	_check(str(manifest.get("schema", "")) == "distributed_world_simulator.fabric_holdout_r4_post_g2_unseen_cases.v1", "UNSEEN manifest schema")
	var subject: Dictionary = manifest.get("subject", {})
	_check(str(subject.get("head", "")) == EXPECTED_HEAD, "UNSEEN exact frozen HEAD binding", subject)
	_check(str(subject.get("tree", "")) == EXPECTED_TREE, "UNSEEN exact frozen TREE binding", subject)
	var families: Dictionary = manifest.get("families", {})
	_transport(families.get("transport", {})); _graph(families.get("graph", {})); _mechanics(families.get("mechanics", {})); _events(families.get("events", {})); _finish()

func _transport(case: Dictionary) -> void:
	var values: Array = case.get("float64_le_hex", []); _check(values.size() == 11, "UNSEEN-T generated float corpus size", values.size()); var payload := {}
	for i in range(values.size()):
		var expected_bits := str(values[i]); var value := _from_bits(expected_bits); _check(is_finite(value), "UNSEEN-T generated float finite %d" % i, expected_bits)
		var decoded := _roundtrip(value); _check(decoded.success and typeof(decoded.value) == TYPE_FLOAT, "UNSEEN-T float type %d" % i, decoded)
		if decoded.success:
			_check(_bits(decoded.value) == expected_bits, "UNSEEN-T exact bits %d" % i, [_bits(decoded.value), expected_bits]); _check(Transport.payload_hash(decoded.value) == Transport.payload_hash(value), "UNSEEN-T hash orbit %d" % i)
		payload["v%02d" % i] = value
	var nested_key := str(case.get("nested_key", "unseen")); var nested := {nested_key: payload, "kind": "post-g2-unseen", "count": values.size()}; var encoded := Transport.encode(nested); _check(encoded.success, "UNSEEN-T nested encode", encoded)
	if encoded.success:
		var decoded_nested := Transport.decode(encoded.value); _check(decoded_nested.success and Transport.payload_hash(decoded_nested.value) == Transport.payload_hash(nested), "UNSEEN-T nested lossless hash", decoded_nested)
		var reordered := {"count": values.size(), "kind": "post-g2-unseen", nested_key: payload}; _check(Transport.payload_hash(reordered) == Transport.payload_hash(nested), "UNSEEN-T dictionary insertion order canonical")
		var tampered: Dictionary = encoded.value.duplicate(true)
		if tampered.get("payload") is Array and tampered.payload.size() > 1: tampered.payload[1] = ["s", "tampered"]
		_check(not Transport.decode(tampered).success, "UNSEEN-T checksum tamper rejected")

func _graph(case: Dictionary) -> void:
	var model: Dictionary = case.get("model", {}); var boundaries: Dictionary = case.get("boundaries_v", {}); var oracle: Dictionary = case.get("oracle", {}); var tolerance := float(case.get("tolerance", 1.0e-9)); var solved := Graph.solve_resistive(model, boundaries)
	_check(solved.success, "UNSEEN-G randomized cyclic graph solves", solved); if not solved.success: return
	for key in oracle.get("potentials_v", {}).keys(): _check(absf(float(solved.details.potentials_v.get(key, INF)) - float(oracle.potentials_v[key])) <= tolerance, "UNSEEN-G potential " + str(key))
	for key in oracle.get("edge_currents_a", {}).keys(): _check(absf(float(solved.details.edge_currents_a.get(key, INF)) - float(oracle.edge_currents_a[key])) <= tolerance, "UNSEEN-G edge current " + str(key))
	for key in oracle.get("port_currents_a", {}).keys(): _check(absf(float(solved.details.port_currents_a.get(key, INF)) - float(oracle.port_currents_a[key])) <= tolerance, "UNSEEN-G port current " + str(key))
	_check(float(solved.details.kcl_residual_a) < 1.0e-9, "UNSEEN-G KCL residual", solved.details.kcl_residual_a); _check(float(solved.details.power_residual_w) < 1.0e-8, "UNSEEN-G power residual", solved.details.power_residual_w)
	var permuted := model.duplicate(true); permuted.nodes.reverse(); permuted.elements.reverse(); var replay := Graph.solve_resistive(permuted, boundaries); _check(replay.success and U.canonical_hash(replay.details) == U.canonical_hash(solved.details), "UNSEEN-G permutation invariant", replay)
	var floating := model.duplicate(true); var negative: Dictionary = case.get("floating_negative", {}); floating.nodes.append({"node_id": str(negative.nodes[0])}); floating.nodes.append({"node_id": str(negative.nodes[1])}); floating.elements.append({"element_id": "ge_floating", "node_a": str(negative.nodes[0]), "node_b": str(negative.nodes[1]), "resistance_ohm": float(negative.resistance_ohm), "active": true}); var rejected := Graph.solve_resistive(floating, boundaries); _check(not rejected.success and rejected.error_code == str(negative.expected_error), "UNSEEN-G floating component fails closed", rejected)

func _mechanics(case: Dictionary) -> void:
	var model: Dictionary = case.get("model", {}); var coupler := str(case.get("coupler_node_id", "")); var tolerance := float(case.get("tolerance", 1.0e-10)); var compiled := Mechanics.compile_mechanics(model, {"coupler_node_id": coupler})
	_check(compiled.success, "UNSEEN-M oblique generalized mechanics compiles", compiled); if not compiled.success: return
	_check(compiled.details.mobile_nodes == case.get("expected_mobile_nodes", []), "UNSEEN-M coordinate order", compiled.details.mobile_nodes); var static_response := Mechanics.solve_mechanical_static(model, coupler); _check(static_response.success, "UNSEEN-M independent static response", static_response)
	if static_response.success:
		var expected: Dictionary = case.oracle.displacement_per_newton
		for key in expected.keys(): _check(absf(float(static_response.details.displacement_per_newton.get(key, INF)) - float(expected[key])) <= tolerance, "UNSEEN-M displacement " + str(key))
	var permuted := model.duplicate(true); permuted.nodes.reverse(); permuted.elements.reverse(); var replay := Mechanics.solve_mechanical_static(permuted, coupler); _check(replay.success and U.canonical_hash(replay.details.displacement_per_newton) == U.canonical_hash(static_response.details.displacement_per_newton), "UNSEEN-M permutation invariant", replay)
	var renamed := model.duplicate(true)
	for i in range(renamed.elements.size()):
		var edge: Dictionary = renamed.elements[i]; edge.element_id = "unseen_renamed_%02d" % (renamed.elements.size() - i)
		if i % 2 == 0:
			var tmp = edge.node_a; edge.node_a = edge.node_b; edge.node_b = tmp
	var renamed_compiled := Mechanics.compile_mechanics(renamed, {"coupler_node_id": coupler}); _check(renamed_compiled.success and U.canonical_hash(renamed_compiled.details.axis) == U.canonical_hash(compiled.details.axis), "UNSEEN-M axis invariant under rename/reversal", renamed_compiled)
	var tiny := model.duplicate(true)
	for node in tiny.nodes:
		if str(node.node_id) == coupler: node.mass_kg = float(case.get("tiny_mass_kg", 1.0e-15))
	var tiny_result := Mechanics.compile_mechanics(tiny, {"coupler_node_id": coupler}); _check(not tiny_result.success and tiny_result.error_code == str(case.get("tiny_mass_expected_error", "R3_MASS_INVALID")), "UNSEEN-M divisor floor fails closed", tiny_result)

func _events(case: Dictionary) -> void:
	var coefficients: Array = case.get("polynomial_coefficients", []); var expected: Array = case.get("expected_roots", []); var tolerance := float(case.get("root_tolerance", 5.0e-8)); var raw_roots := EventStep._roots(coefficients); var roots: Array = []
	for raw_root in raw_roots:
		if roots.is_empty() or absf(float(raw_root) - float(roots.back())) > 1.0e-6: roots.append(raw_root)
	_check(roots.size() == expected.size(), "UNSEEN-E root cluster count", [raw_roots, roots, expected])
	if roots.size() == expected.size():
		for i in range(expected.size()): _check(absf(float(roots[i]) - float(expected[i])) <= tolerance, "UNSEEN-E root %d" % i, [roots[i], expected[i]])
	var parsed := EventStep._parse_transition_id(str(case.get("transition_token", ""))); _check(parsed.get("ok", false), "UNSEEN-E delimiter-rich transition parses", parsed)
	if parsed.get("ok", false): _check(str(parsed.element_id) == str(case.expected_element_id), "UNSEEN-E full element id preserved", parsed); _check(float(parsed.sign) == float(case.expected_sign), "UNSEEN-E sign preserved", parsed)
	var malformed := EventStep._parse_transition_id(str(case.get("malformed_token", ""))); _check(not malformed.get("ok", true), "UNSEEN-E malformed sign rejected", malformed)

func _finish() -> void:
	print("FABRIC_R4_POST_G2_UNSEEN_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty(): print("FABRIC-HOLDOUT-R4-POST-G2-UNSEEN: PASS"); quit(0)
	else: print("FABRIC_R4_POST_G2_UNSEEN_FAILURES=", JSON.stringify(failures)); print("FABRIC-HOLDOUT-R4-POST-G2-UNSEEN: FAIL"); quit(1)
