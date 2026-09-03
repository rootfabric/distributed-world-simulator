extends SceneTree

const Contract = preload("res://scripts/research/fabric_bake0/bridge2_entry_contract_v1.gd")

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var contract := Contract.create()
	_check(not contract.is_empty(), "SYNC4 BRIDGE-2 entry contract creates")
	if contract.is_empty():
		_finish()
		return
	_check(bool(Contract.validate(contract).get("success", false)), "entry contract validates")
	_check(String(contract["authorization"]) == Contract.AUTHORIZATION, "BRIDGE-2 executable research authorized")
	_check(contract["representations"] == Contract.REPRESENTATIONS, "all five representation kinds frozen")
	_check(String(contract["canonical_owner"]) == "PHYSICAL_SOURCE", "canonical ownership remains PhysicalSource")
	_check(String(contract["representation_role"]) == "DERIVED_EXECUTION_ONLY", "mixed representations remain derived only")
	_check(String(contract["physical_event_owner"]) == "FABRIC_PHYSICAL_EVENT", "FABRIC remains event owner")
	_check(String(contract["canonical_revision_policy"]) == "EXTERNAL_AUTHORITY_ONLY", "bridge cannot advance canonical revision")
	_check(String(contract["region_policy"]) == "EXPLICIT_NON_OVERLAPPING_REGION_OWNERSHIP", "region ownership explicit and non-overlapping")
	_check(String(contract["interface_policy"]) == "PHYSICAL_BOUNDARY_CONTRACT_EFFORT_FLOW_ONLY", "mixed interfaces use physical boundary contracts")
	_check(String(contract["invalidation_policy"]) == "CANONICAL_MUTATION_THEN_REPRESENTATION_INVALIDATION_THEN_BAKE_INVALIDATION", "invalidation ordering frozen")
	_check(String(contract["unknown_representation_policy"]) == "FULL_OR_NO_SAFE_BAKE", "unknown representation fails closed")
	_check(not bool(contract["fabric0_19_policy"]["authorized"]), "FABRIC0.19 remains unauthorized")
	_check(String(contract["fabric0_19_policy"]["reason"]) == "NO_MISSING_GENERIC_PHYSICAL_CORE_PRIMITIVE_OBSERVED", "FABRIC0.19 decision reason exact")

	for from_kind in Contract.REPRESENTATIONS:
		for to_kind in Contract.REPRESENTATIONS:
			var result := Contract.permits_transition(String(from_kind), String(to_kind))
			_check(bool(result.get("success", false)), "%s -> %s transition classified" % [from_kind, to_kind])
			if bool(result.get("success", false)) and from_kind != to_kind:
				_check(bool(result["details"]["handoff_required"]), "%s -> %s requires explicit handoff" % [from_kind, to_kind])
				_check(String(result["details"]["state_rule"]) == "RECONSTRUCT_OR_EXACT_FULL_STATE_THEN_PROJECT", "%s -> %s state handoff rule exact" % [from_kind, to_kind])
				_check(String(result["details"]["event_rule"]) == "FABRIC_OWNS_PHYSICAL_EVENT", "%s -> %s event ownership exact" % [from_kind, to_kind])
				_check(String(result["details"]["fallback"]) == "FULL_OR_NO_SAFE_BAKE", "%s -> %s fail-closed fallback exact" % [from_kind, to_kind])

	var unknown := Contract.permits_transition("FULL", "DEVICE_SPECIFIC_MAGIC")
	_check(not bool(unknown.get("success", false)), "unknown representation rejected")
	_check(String(unknown.get("error_code", "")) == "UNKNOWN_BRIDGE2_REPRESENTATION_KIND", "unknown representation rejection exact")

	var tampered := contract.duplicate(true)
	tampered["fabric0_19_policy"]["authorized"] = true
	_check(not bool(Contract.validate(tampered).get("success", false)), "FABRIC0.19 cannot be silently enabled inside SYNC4 contract")

	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC.SYNC4 BRIDGE-2 Authorization Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("FABRIC.SYNC4: %s" % failure)
	print("FABRIC.SYNC4 BRIDGE-2 Authorization Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
