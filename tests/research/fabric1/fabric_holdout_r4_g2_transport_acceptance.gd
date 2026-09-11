extends SceneTree

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions := 0
var failures: Array[String] = []

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)

func _initialize() -> void:
	# Official single-precision Godot needs hundreds of stringify/parse rounds for
	# some finite values before they reach a transport-fixed representation. This
	# value reproduced the B0.4-D ROM regression and needs ~448 rounds there.
	var long_orbit_value := 1.2345678901234567e-169
	var normalized := NetworkUtils.canonicalize(long_orbit_value, "$g2.long_orbit")
	_check(normalized.success, "G2-TRANSPORT long finite orbit normalizes", normalized)
	if normalized.success:
		var wire := JSON.stringify(normalized.value, "", true, true)
		var decoded = JSON.parse_string(wire)
		var replay := NetworkUtils.canonicalize(decoded, "$g2.long_orbit_replay")
		_check(replay.success, "G2-TRANSPORT normalized value replays", replay)
		_check(replay.success and replay.value == normalized.value, "G2-TRANSPORT canonical form is transport fixed", [normalized, replay, wire])
	_check(NetworkUtils.canonical_json(NAN).is_empty() and NetworkUtils.canonical_json(INF).is_empty(), "G2-TRANSPORT nonfinite remains fail-closed")
	print("G2_TRANSPORT_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FABRIC-HOLDOUT-R4-G2-TRANSPORT: PASS")
		quit(0)
	else:
		print("G2_TRANSPORT_FAILURES=", JSON.stringify(failures))
		print("FABRIC-HOLDOUT-R4-G2-TRANSPORT: FAIL")
		quit(1)
