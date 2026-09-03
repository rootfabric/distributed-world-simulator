extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Contract = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_a_fixture.gd")

var _checks := 0
var _failed := false

func _initialize() -> void:
	var subject := Fixture.build()
	_require(bool(subject.get("success", false)), "fixture builds", subject)
	if _failed:
		_finish()
		return
	var contract: Dictionary = subject["contract"]
	var canonical: Dictionary = subject["canonical"]

	_require(bool(Contract.validate(contract).get("success", false)), "mixed ownership contract validates")
	_require(String(contract["canonical_truth_owner"]) == Contract.CANONICAL_TRUTH_OWNER, "Construction/Matter remain canonical truth")
	_require(String(contract["source_revision_policy"]) == Contract.SOURCE_REVISION_POLICY, "derived representations cannot advance canonical revision")
	_require(String(contract["event_commit_policy"]) == Contract.EVENT_COMMIT_POLICY, "event commit is exactly once")
	_require(String(contract["authority_envelope"]["execution_owner"]) == String(canonical["authority"]["execution_owner"]), "existing authority owner is reused")
	_require(String(contract["canonical_source_frontier"]["frontier_hash"]) == String(canonical["frontier"]["frontier_hash"]), "existing canonical frontier is reused")
	_require(contract["representations"].size() == 5, "all five authorized representation kinds are present")

	for representation in contract["representations"]:
		_require(bool(representation["derived_only"]), "%s is derived-only" % representation["representation_id"])
		_require(not bool(representation["canonical_write_authorized"]), "%s has no canonical write authority" % representation["representation_id"])
		_require(String(representation["source_frontier_hash"]) == String(canonical["frontier"]["frontier_hash"]), "%s binds exact frontier" % representation["representation_id"])
		_require(String(representation["authority_epoch_binding"]) == String(canonical["authority"]["authority_epoch_binding"]), "%s binds exact authority epoch" % representation["representation_id"])

	_require(Contract.active_owner_for_region(contract, Fixture.REGION_IMPACT) == Fixture.FULL, "impact region has exactly one FULL active owner")
	_require(Contract.active_owner_for_region(contract, Fixture.REGION_STABLE) == Fixture.STRUCTURAL, "stable region has exactly one structural-bake active owner")
	_require(Contract.active_owner_for_region(contract, Fixture.REGION_CONTACT) == Fixture.CONTACT, "contact region has exactly one contact-bake active owner")
	_require(Contract.active_owner_for_region(contract, Fixture.REGION_DYNAMIC) == Fixture.DYNAMIC, "dynamic region has exactly one dynamic-ROM active owner")
	_require(Contract.active_owner_for_region(contract, Fixture.REGION_HYBRID) == Fixture.HYBRID, "hybrid region has exactly one hybrid-bake active owner")

	var canonical_event := Fixture.canonical_break_event()
	var break_resolution := Contract.resolve_event(contract, canonical_event)
	_require(bool(break_resolution.get("success", false)), "canonical break ownership resolves", break_resolution)
	if bool(break_resolution.get("success", false)):
		var resolved: Dictionary = break_resolution["details"]["resolution"]
		_require(String(resolved["evaluator_representation_id"]) == Fixture.FULL, "FULL evaluates impact-region break")
		_require(String(resolved["evaluator_representation_kind"]) == "FULL", "break evaluator kind is FULL")
		_require(resolved["observer_representation_ids"] == [Fixture.CONTACT, Fixture.STRUCTURAL], "baked representations are observers for impact event")
		_require(String(resolved["commit_owner"]) == String(canonical["authority"]["execution_owner"]), "canonical break commit remains external canonical authority-owned")
		_require(String(resolved["canonical_revision_policy"]) == Contract.SOURCE_REVISION_POLICY, "canonical mutation uses external revision policy")
		_require(not bool(resolved["evaluator_canonical_write_authorized"]), "event evaluator itself still has no canonical write authority")
		_require(bool(Contract.validate_resolution(resolved, contract).get("success", false)), "canonical break resolution validates")

	var derived_event := Fixture.hybrid_jump_event()
	var hybrid_resolution := Contract.resolve_event(contract, derived_event)
	_require(bool(hybrid_resolution.get("success", false)), "derived hybrid event ownership resolves", hybrid_resolution)
	if bool(hybrid_resolution.get("success", false)):
		var resolved: Dictionary = hybrid_resolution["details"]["resolution"]
		_require(String(resolved["evaluator_representation_id"]) == Fixture.HYBRID, "hybrid-bake evaluates hybrid region")
		_require(String(resolved["commit_owner"]) == Contract.DERIVED_EVENT_COMMIT_OWNER, "derived physical event remains FABRIC-owned")
		_require(String(resolved["canonical_revision_policy"]) == "NO_CANONICAL_REVISION", "derived physical event cannot fabricate canonical revision")
		_require(resolved["observer_representation_ids"] == [Fixture.DYNAMIC], "dynamic ROM is observer of hybrid event")

	var duplicate_event := Contract.resolve_event(contract, canonical_event, [String(canonical_event["event_id"])])
	_require(not bool(duplicate_event.get("success", false)), "same physical event cannot resolve for second commit")
	_require(_code(duplicate_event) == "BRIDGE2_A_EVENT_ALREADY_COMMITTED", "duplicate event rejection code exact")

	var missing_owner_event := canonical_event.duplicate(true)
	missing_owner_event["candidate_representation_ids"] = [Fixture.CONTACT, Fixture.STRUCTURAL]
	var missing_owner := Contract.resolve_event(contract, missing_owner_event)
	_require(not bool(missing_owner.get("success", false)), "event candidates cannot omit active evaluator")
	_require(_code(missing_owner) == "BRIDGE2_A_ACTIVE_OWNER_NOT_CANDIDATE", "missing active evaluator code exact")

	var outside_event := canonical_event.duplicate(true)
	outside_event["candidate_representation_ids"] = [Fixture.DYNAMIC, Fixture.FULL]
	var outside := Contract.resolve_event(contract, outside_event)
	_require(not bool(outside.get("success", false)), "event cannot route through representation outside region")
	_require(_code(outside) == "BRIDGE2_A_EVENT_CANDIDATE_OUTSIDE_REGION", "outside-region candidate code exact")

	var double_owner := contract.duplicate(true)
	for binding in double_owner["region_bindings"]:
		if String(binding["region_id"]) == Fixture.REGION_IMPACT and String(binding["representation_id"]) == Fixture.STRUCTURAL:
			binding["ownership_role"] = "ACTIVE_EXECUTION"
			break
	var double_owner_check := Contract.validate(double_owner)
	_require(not bool(double_owner_check.get("success", false)), "two active representations for one region fail closed")
	_require(_code(double_owner_check) == "BRIDGE2_A_MULTIPLE_ACTIVE_REGION_OWNERS", "double-active owner code exact")

	var no_owner := contract.duplicate(true)
	for binding in no_owner["region_bindings"]:
		if String(binding["region_id"]) == Fixture.REGION_DYNAMIC and String(binding["representation_id"]) == Fixture.DYNAMIC:
			binding["ownership_role"] = "OBSERVER"
			break
	var no_owner_check := Contract.validate(no_owner)
	_require(not bool(no_owner_check.get("success", false)), "region without active representation fails closed")
	_require(_code(no_owner_check) == "BRIDGE2_A_REGION_ACTIVE_OWNER_REQUIRED", "missing region owner code exact")

	var canonical_write := contract.duplicate(true)
	canonical_write["representations"][0]["canonical_write_authorized"] = true
	var canonical_write_check := Contract.validate(canonical_write)
	_require(not bool(canonical_write_check.get("success", false)), "derived representation cannot seize canonical write")
	_require(_code(canonical_write_check) == "BRIDGE2_A_DERIVED_CANONICAL_WRITE_FORBIDDEN", "canonical-write seizure code exact")

	var wrong_frontier := contract.duplicate(true)
	wrong_frontier["representations"][0]["source_frontier_hash"] = Utils.canonical_hash({"foreign": "frontier"})
	var wrong_frontier_check := Contract.validate(wrong_frontier)
	_require(not bool(wrong_frontier_check.get("success", false)), "representation bound to foreign frontier fails closed")
	_require(_code(wrong_frontier_check) == "BRIDGE2_A_REPRESENTATION_FRONTIER_MISMATCH", "foreign frontier code exact")

	var wrong_authority := contract.duplicate(true)
	wrong_authority["representations"][0]["authority_epoch_binding"] = Utils.canonical_hash({"foreign": "authority"})
	var wrong_authority_check := Contract.validate(wrong_authority)
	_require(not bool(wrong_authority_check.get("success", false)), "representation bound to foreign authority fails closed")
	_require(_code(wrong_authority_check) == "BRIDGE2_A_REPRESENTATION_AUTHORITY_MISMATCH", "foreign authority code exact")

	var wrong_kind := contract.duplicate(true)
	wrong_kind["representations"][0]["representation_kind"] = "MAGIC_DEVICE_BAKE"
	var wrong_kind_check := Contract.validate(wrong_kind)
	_require(not bool(wrong_kind_check.get("success", false)), "unknown representation kind fails closed")
	_require(_code(wrong_kind_check) == "BRIDGE2_A_UNSUPPORTED_REPRESENTATION_KIND", "unknown representation kind code exact")

	var authority_records: Array = canonical["authority"]["source_authority_frontier"].duplicate(true)
	var unsafe_authority := AuthorityEnvelope.create("server/foreign-executor", authority_records, canonical["authority"]["mutable_source_ids"])
	_require(not unsafe_authority.is_empty(), "syntactically valid foreign executor authority can be constructed for falsifier")
	var cross_authority := Contract.compile(canonical["frontier"], unsafe_authority, subject["representations"], subject["bindings"])
	_require(not bool(cross_authority.get("success", false)), "cross-authority mutable mixed execution fails closed")
	_require(_code(cross_authority) == "AUTHORITY_ENVELOPE_CROSSED", "cross-authority failure reuses existing authority contract")

	var reverse_representations: Array = subject["representations"].duplicate(true)
	reverse_representations.reverse()
	var reverse_bindings: Array = subject["bindings"].duplicate(true)
	reverse_bindings.reverse()
	var deterministic := Contract.compile(canonical["frontier"], canonical["authority"], reverse_representations, reverse_bindings)
	_require(bool(deterministic.get("success", false)), "reverse presentation compiles")
	if bool(deterministic.get("success", false)):
		_require(String(deterministic["details"]["contract"]["contract_hash"]) == String(contract["contract_hash"]), "mixed ownership contract hash deterministic")
		var replay := Contract.resolve_event(deterministic["details"]["contract"], canonical_event)
		_require(bool(replay.get("success", false)), "deterministic event replay resolves")
		if bool(replay.get("success", false)) and bool(break_resolution.get("success", false)):
			_require(String(replay["details"]["resolution"]["resolution_hash"]) == String(break_resolution["details"]["resolution"]["resolution_hash"]), "event ownership resolution hash deterministic")

	_finish(contract)

func _finish(contract: Dictionary = {}) -> void:
	if _failed:
		printerr("FABRIC-BAKE BRIDGE-2-A Mixed Representation Ownership Acceptance: FAIL (%d successful assertions)" % _checks)
		quit(1)
		return
	print("FABRIC-BAKE BRIDGE-2-A Mixed Representation Ownership Acceptance: PASS (%d assertions) contract=%s" % [_checks, String(contract.get("contract_hash", ""))])
	quit(0)

func _require(condition: bool, label: String, details = null) -> bool:
	if condition:
		_checks += 1
		return true
	_failed = true
	printerr("FABRIC-BAKE BRIDGE-2-A FAILURE: %s details=%s" % [label, str(details)])
	return false

func _code(result: Dictionary) -> String:
	return String(result.get("error_code", ""))
