extends SceneTree

const EventStep = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_event_step_v1.gd")

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	var guard := EventStep._parse_transition_id("guard|bond/support|segment|1.0")
	_check(guard.get("ok", false), "G2-BOND-ID guard transition parses", guard)
	_check(str(guard.get("element_id", "")) == "bond/support|segment", "G2-BOND-ID embedded delimiter preserved", guard)
	_check(float(guard.get("sign", 0.0)) == 1.0, "G2-BOND-ID positive sign preserved", guard)
	var polynomials := {"bond/support|segment": {"sentinel": true}}
	_check(polynomials.has(str(guard.get("element_id", ""))), "G2-BOND-ID parsed key reaches polynomial lookup", guard)

	var failure := EventStep._parse_transition_id("failure|bond/a|b|c|-1.0")
	_check(failure.get("ok", false) and str(failure.get("element_id", "")) == "bond/a|b|c" and float(failure.get("sign", 0.0)) == -1.0, "G2-BOND-ID failure transition preserves full id", failure)

	var malformed := EventStep._parse_transition_id("guard||1.0")
	_check(not malformed.get("ok", true) and malformed.get("code") == "R3_GENERAL_EVENT_TRANSITION_SHAPE", "G2-BOND-ID empty element fails closed", malformed)
	malformed = EventStep._parse_transition_id("other|bond/a|1.0")
	_check(not malformed.get("ok", true) and malformed.get("code") == "R3_GENERAL_EVENT_TRANSITION_SHAPE", "G2-BOND-ID unknown transition kind fails closed", malformed)

	print("G2_BOND_ID_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FABRIC-HOLDOUT-R4-G2-BOND-ID: PASS")
		quit(0)
	else:
		print("G2_BOND_ID_FAILURES=", JSON.stringify(failures))
		print("FABRIC-HOLDOUT-R4-G2-BOND-ID: FAIL")
		quit(1)

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)
