extends SceneTree

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Transport = preload("res://scripts/research/fabric_holdout_r4_g2/lossless_json_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)

func _bits(value: float) -> String:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_double(value)
	return buffer.data_array.hex_encode()

func _raw_node(node: Array) -> Dictionary:
	var wire := {"schema": Transport.SCHEMA, "payload": node}
	wire["checksum"] = NetworkUtils.payload_hash(wire)
	return wire

func _roundtrip(value) -> Dictionary:
	var encoded := Transport.encode(value)
	if not encoded.success: return encoded
	var wire = JSON.parse_string(JSON.stringify(encoded.value, "", true, true))
	return Transport.decode(wire)

func _initialize() -> void:
	_check(_bits(1.0) == "000000000000f03f", "G2 wire byte order is explicit IEEE754 little endian")
	var subnormal := StreamPeerBuffer.new()
	subnormal.big_endian = false
	subnormal.data_array = "0100000000000000".hex_decode()
	var negative_zero_buffer := StreamPeerBuffer.new()
	negative_zero_buffer.big_endian = false
	negative_zero_buffer.data_array = "0000000000000080".hex_decode()
	var negative_zero := negative_zero_buffer.get_double()
	var values := [0.0, negative_zero, 0.1, 0.3333333333333333, 17.000000000000004,
		1.2345678901234567, 1.2345678901234567e-169, 1.5868896825778374e-155,
		-1.5868896825778374e-155, 1.0e-300, subnormal.get_double()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 592
	for _index in range(100):
		values.append(rng.randf_range(-2.0, 2.0) * pow(10.0, -rng.randi_range(1, 305)))
	for value in values:
		var decoded := _roundtrip(value)
		_check(decoded.success and typeof(decoded.value) == TYPE_FLOAT, "G2 finite float type preserved", _bits(value))
		if decoded.success:
			_check(_bits(decoded.value) == _bits(value), "G2 finite float bits preserved", [_bits(value), _bits(decoded.value)])
			_check(Transport.payload_hash(value) == Transport.payload_hash(decoded.value), "G2 lossless hash idempotent")
	var long_value: float = values[7]
	var legacy := NetworkUtils.canonicalize(long_value)
	_check(legacy.success and _bits(legacy.value) == _bits(long_value), "G2 global v1 no longer runs lossy transport orbits")
	for value in [null, true, false, 0, 1, -1, 9007199254740991, -9007199254740991, "", "Русский\n☃", [], {}, {"": [1, 1.0, true, null], "$float64": "user data", "schema": Transport.SCHEMA}]:
		var decoded := _roundtrip(value)
		_check(decoded.success and typeof(decoded.value) == typeof(value) and decoded.value == value, "G2 structural types and safe integers preserved")
	_check(Transport.payload_hash({"a": 1, "b": 2}) == Transport.payload_hash({"b": 2, "a": 1}), "G2 dictionary order canonical")
	_check(Transport.payload_hash(1) != Transport.payload_hash(1.0), "G2 wire type tags do not alias integers and floats")
	_check(Transport.payload_hash(negative_zero) != Transport.payload_hash(0.0), "G2 wire preserves signed zero bits")
	for value in [NAN, INF, -INF, 9007199254740992, float(9007199254740992), Vector3.ONE, {1: "bad key"}]:
		_check(not Transport.encode(value).success, "G2 forbidden or unsafe input fails closed")
	for node in [["x", ""], ["n", "extra"], ["f64le", "00"], ["f64le", "000000000000f07f"], ["f64le", "010000000000f07f"], ["i", "+1"], ["i", "01"], ["i", "-0"], ["i", "9007199254740992"], ["b", 1], ["s", true], ["d", [["a", ["n"]], ["a", ["n"]]]], ["d", [["b", ["n"]], ["a", ["n"]]]]]:
		_check(not Transport.decode(_raw_node(node)).success, "G2 malformed tagged node fails closed", node[0])
	var tampered: Dictionary = Transport.encode({"value": 0.1}).value
	tampered.payload[1][0][1][1] = "000000000000f03f"
	_check(not Transport.decode(tampered).success, "G2 wire tamper fails without checksum repair")
	var extended: Dictionary = Transport.encode({}).value
	extended["extra"] = "bad"
	_check(not Transport.decode(extended).success, "G2 wire unknown fields fail closed")
	var wrong_version: Dictionary = Transport.encode({}).value
	wrong_version.schema = "future.profile"
	_check(not Transport.decode(wrong_version).success, "G2 wire unknown version fails closed")
	var deep: Array = []
	for _index in range(Transport.MAX_DEPTH + 2): deep = [deep]
	_check(not Transport.encode(deep).success, "G2 encode depth bounded")
	var deep_wire: Array = ["n"]
	for _index in range(Transport.MAX_DEPTH + 2): deep_wire = ["a", [deep_wire]]
	_check(not Transport.decode({"schema": Transport.SCHEMA, "payload": deep_wire, "checksum": "0".repeat(64)}).success, "G2 decode depth checked before hash")
	var oversized: Array = []
	oversized.resize(Transport.MAX_NODES + 1)
	_check(not Transport.encode(oversized).success, "G2 encode node budget enforced")
	_check(not Transport.encode("x".repeat(Transport.MAX_TEXT_BYTES + 1)).success, "G2 text budget enforced")
	var canonical := Transport.canonical_json({"a": 0.1})
	_check(Transport.parse_json(canonical).success, "G2 canonical text parsed")
	_check(not Transport.parse_json(canonical.replace('"schema":', '"schema":"duplicate","schema":')).success, "G2 duplicate wire keys rejected")
	_check(not Transport.parse_json(canonical + " ").success, "G2 noncanonical wire rejected")
	print("G2_TRANSPORT_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FABRIC-HOLDOUT-R4-G2-TRANSPORT: PASS")
		quit(0)
	else:
		print("G2_TRANSPORT_FAILURES=", JSON.stringify(failures))
		print("FABRIC-HOLDOUT-R4-G2-TRANSPORT: FAIL")
		quit(1)
