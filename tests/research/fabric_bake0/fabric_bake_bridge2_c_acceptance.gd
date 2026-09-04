extends SceneTree

const Router = preload("res://scripts/research/fabric_bake0/mixed_representation_event_router_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const OwnershipFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_a_fixture.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_c_fixture.gd")

var _checks := 0
var _failed := false

func _initialize() -> void:
	var subject := Fixture.build()
	_require(bool(subject.get("success", false)), "B2-C fixture builds", subject)
	if _failed:
		_finish()
		return
	_test_canonical_route(subject)
	_test_derived_route(subject)
	_test_fail_closed(subject)
	_test_determinism(subject)
	_finish()

func _test_canonical_route(subject: Dictionary) -> void:
	var routed := Fixture.canonical_route(subject)
	_require(bool(routed.get("success", false)), "canonical event route prepares", routed)
	if not bool(routed.get("success", false)):
		return
	var route: Dictionary = routed["details"]["route"]
	_require(bool(Router.validate_route(route, subject["mixed"]["subject"], subject["mixed"]["ownership"]).get("success", false)), "canonical route validates")
	_require(String(route["emitter_representation_id"]) == OwnershipFixture.FULL, "FULL emits impact event")
	_require(String(route["evaluator_representation_id"]) == OwnershipFixture.FULL, "FULL remains active evaluator")
	_require(String(route["commit_owner"]) == String(subject["mixed"]["canonical"]["authority"]["execution_owner"]), "canonical event routes to existing authority owner")
	_require(String(route["canonical_revision_policy"]) == Ownership.SOURCE_REVISION_POLICY, "canonical route preserves revision policy")
	_require(route["observer_routes"].size() == 2, "canonical event routes to two observers")
	_require(String(route["observer_routes"][0]["representation_id"]) == OwnershipFixture.CONTACT, "contact bake receives observer route")
	_require(String(route["observer_routes"][1]["representation_id"]) == OwnershipFixture.STRUCTURAL, "structural bake receives observer route")
	for observer in route["observer_routes"]:
		_require(String(observer["delivery_role"]) == "OBSERVER", "observer route cannot become evaluator")
		_require(not bool(observer["canonical_write_authorized"]), "observer route has no canonical write")

	var receipt_result := Fixture.canonical_receipt(subject, route)
	_require(bool(receipt_result.get("success", false)), "real COMPLEX0 canonical commit receipt validates", receipt_result)
	if not bool(receipt_result.get("success", false)):
		return
	var receipt: Dictionary = receipt_result["details"]["receipt"]
	_require(String(receipt["current_source_frontier"]["frontier_hash"]) == String(subject["broken"]["current_frontier"]["frontier_hash"]), "receipt binds exact post-break frontier")
	_require(bool(receipt["canonical_revision_advanced"]), "canonical break advances revision")
	_require(String(receipt["representation_invalidation"]["checksum"]) == String(subject["broken"]["source_invalidation"]["checksum"]), "receipt binds exact RepresentationInvalidation")

	var committed := Router.commit_route(route, receipt, subject["mixed"]["subject"], subject["mixed"]["ownership"])
	_require(bool(committed.get("success", false)), "canonical route commits", committed)
	if not bool(committed.get("success", false)):
		return
	var commit: Dictionary = committed["details"]["commit"]
	_require(String(commit["commit_state"]) == "COMMITTED", "canonical route commit state exact")
	_require(String(commit["ledger_append_event_id"]) == String(route["event_id"]), "router requests one external ledger append")
	_require(String(commit["previous_source_frontier_hash"]) == String(subject["mixed"]["canonical"]["frontier"]["frontier_hash"]), "commit records old frontier")
	_require(String(commit["current_source_frontier_hash"]) == String(subject["broken"]["current_frontier"]["frontier_hash"]), "commit records new frontier")
	_require(commit["observer_deliveries"].size() == 2, "commit delivers event to both observers")
	for delivery in commit["observer_deliveries"]:
		_require(String(delivery["delivery_kind"]) == "CANONICAL_COMMIT_OBSERVATION", "canonical observer delivery kind exact")
		_require(not bool(delivery["canonical_write_authorized"]), "committed observer delivery remains read-only")

	var duplicate_commit := Router.commit_route(route, receipt, subject["mixed"]["subject"], subject["mixed"]["ownership"], [String(route["event_id"])])
	_require(not bool(duplicate_commit.get("success", false)), "canonical event cannot commit twice")
	_require(_code(duplicate_commit) == "BRIDGE2_C_EVENT_ALREADY_COMMITTED", "duplicate commit rejection exact")
	var duplicate_prepare := Fixture.canonical_route(subject, [String(route["event_id"])])
	_require(not bool(duplicate_prepare.get("success", false)), "already committed event cannot be routed again")
	_require(_code(duplicate_prepare) == "BRIDGE2_A_EVENT_ALREADY_COMMITTED", "duplicate route rejected by ownership ledger boundary")

func _test_derived_route(subject: Dictionary) -> void:
	var routed := Fixture.derived_route(subject)
	_require(bool(routed.get("success", false)), "hybrid derived event route prepares", routed)
	if not bool(routed.get("success", false)):
		return
	var route: Dictionary = routed["details"]["route"]
	_require(String(route["emitter_representation_id"]) == OwnershipFixture.HYBRID, "HYBRID_BAKE emits derived event")
	_require(String(route["commit_owner"]) == Ownership.DERIVED_EVENT_COMMIT_OWNER, "derived event remains FABRIC-owned")
	_require(String(route["canonical_revision_policy"]) == "NO_CANONICAL_REVISION", "derived event cannot advance canonical revision")
	_require(route["observer_routes"].size() == 1 and String(route["observer_routes"][0]["representation_id"]) == OwnershipFixture.DYNAMIC, "DYNAMIC_ROM observes hybrid event")
	var receipt_result := Fixture.derived_receipt(subject, route)
	_require(bool(receipt_result.get("success", false)), "derived receipt validates without source mutation", receipt_result)
	if not bool(receipt_result.get("success", false)):
		return
	var receipt: Dictionary = receipt_result["details"]["receipt"]
	_require(not bool(receipt["canonical_revision_advanced"]), "derived receipt records no canonical revision")
	_require(receipt["representation_invalidation"].is_empty(), "derived receipt emits no source invalidation")
	var committed := Router.commit_route(route, receipt, subject["mixed"]["subject"], subject["mixed"]["ownership"])
	_require(bool(committed.get("success", false)), "derived event commits", committed)
	if bool(committed.get("success", false)):
		var commit: Dictionary = committed["details"]["commit"]
		_require(String(commit["current_source_frontier_hash"]) == String(commit["previous_source_frontier_hash"]), "derived commit preserves canonical frontier")
		_require(commit["source_invalidation_checksum"] == "", "derived commit has no invalidation checksum")
		_require(String(commit["observer_deliveries"][0]["delivery_kind"]) == "DERIVED_EVENT_OBSERVATION", "derived observer delivery kind exact")

func _test_fail_closed(subject: Dictionary) -> void:
	var full_entry: Dictionary = subject["entries"][OwnershipFixture.FULL]
	var event := Fixture.canonical_event(subject)
	var wrong_emitter := Router.prepare_route(
		subject["mixed"]["subject"], subject["mixed"]["ownership"], event,
		OwnershipFixture.STRUCTURAL,
		String(subject["entries"][OwnershipFixture.STRUCTURAL]["execution_identity_hash"]),
		String(subject["entries"][OwnershipFixture.STRUCTURAL]["runtime_state_hash"])
	)
	_require(not bool(wrong_emitter.get("success", false)), "observer cannot emit event owned by FULL")
	_require(_code(wrong_emitter) == "BRIDGE2_C_EMITTER_NOT_ACTIVE_EVALUATOR", "wrong-emitter rejection exact")

	var wrong_execution := Router.prepare_route(
		subject["mixed"]["subject"], subject["mixed"]["ownership"], event,
		OwnershipFixture.FULL,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		String(full_entry["runtime_state_hash"])
	)
	_require(not bool(wrong_execution.get("success", false)), "stale/foreign execution identity cannot emit")
	_require(_code(wrong_execution) == "BRIDGE2_C_EMITTER_EXECUTION_IDENTITY_MISMATCH", "wrong execution identity rejection exact")

	var routed := Fixture.canonical_route(subject)
	if not bool(routed.get("success", false)):
		_require(false, "canonical route prerequisite")
		return
	var route: Dictionary = routed["details"]["route"]
	var tampered_route := route.duplicate(true)
	tampered_route["commit_owner"] = "server/foreign-owner"
	var tampered_route_check := Router.validate_route(tampered_route, subject["mixed"]["subject"], subject["mixed"]["ownership"])
	_require(not bool(tampered_route_check.get("success", false)), "route cannot rewrite ownership-resolved commit owner")
	_require(_code(tampered_route_check) == "BRIDGE2_C_ROUTE_COMMIT_OWNER_OWNERSHIP_MISMATCH", "route commit-owner tamper code exact")
	var tampered_observer := route.duplicate(true)
	tampered_observer["observer_routes"][0]["representation_id"] = OwnershipFixture.DYNAMIC
	var tampered_observer_check := Router.validate_route(tampered_observer, subject["mixed"]["subject"], subject["mixed"]["ownership"])
	_require(not bool(tampered_observer_check.get("success", false)), "route cannot redirect observer delivery outside ownership resolution")
	_require(_code(tampered_observer_check) == "BRIDGE2_C_OBSERVER_ROUTE_OWNERSHIP_MISMATCH", "observer reroute tamper code exact")

	var foreign_owner_route := route.duplicate(true)
	foreign_owner_route["commit_owner"] = "server/foreign-owner"
	var foreign_owner_receipt := Fixture.canonical_receipt(subject, foreign_owner_route)
	_require(not bool(foreign_owner_receipt.get("success", false)), "canonical receipt cannot reroute commit to foreign owner")

	var same_frontier_receipt := Router.create_commit_receipt(
		route,
		subject["mixed"]["ownership"],
		subject["mixed"]["canonical"]["frontier"],
		subject["mixed"]["canonical"]["authority"],
		subject["broken"]["source_invalidation"],
		"CONSTRUCTION_BOND_BREAK"
	)
	_require(not bool(same_frontier_receipt.get("success", false)), "canonical mutation cannot claim unchanged frontier")
	_require(_code(same_frontier_receipt) == "BRIDGE2_C_CANONICAL_RECEIPT_FRONTIER_NOT_ADVANCED", "same-frontier canonical receipt rejection exact")

	var derived_route_result := Fixture.derived_route(subject)
	if bool(derived_route_result.get("success", false)):
		var derived_route: Dictionary = derived_route_result["details"]["route"]
		var illegal_derived_receipt := Router.create_commit_receipt(
			derived_route,
			subject["mixed"]["ownership"],
			subject["broken"]["current_frontier"],
			subject["broken"]["current_authority"],
			subject["broken"]["source_invalidation"],
			"CONSTRUCTION_BOND_BREAK"
		)
		_require(not bool(illegal_derived_receipt.get("success", false)), "derived event cannot smuggle canonical mutation")
		_require(_code(illegal_derived_receipt) == "BRIDGE2_C_DERIVED_RECEIPT_FRONTIER_CHANGED", "derived mutation rejection exact")

func _test_determinism(subject: Dictionary) -> void:
	var first := Fixture.canonical_route(subject)
	var second := Fixture.canonical_route(subject)
	_require(bool(first.get("success", false)) and bool(second.get("success", false)), "deterministic route prerequisites")
	if not bool(first.get("success", false)) or not bool(second.get("success", false)):
		return
	_require(String(first["details"]["route"]["route_hash"]) == String(second["details"]["route"]["route_hash"]), "route hash deterministic")
	_require(first["details"]["route"]["observer_routes"] == second["details"]["route"]["observer_routes"], "observer routing deterministic")
	var receipt_a := Fixture.canonical_receipt(subject, first["details"]["route"])
	var receipt_b := Fixture.canonical_receipt(subject, second["details"]["route"])
	_require(bool(receipt_a.get("success", false)) and bool(receipt_b.get("success", false)), "deterministic receipt prerequisites")
	if bool(receipt_a.get("success", false)) and bool(receipt_b.get("success", false)):
		_require(String(receipt_a["details"]["receipt"]["receipt_hash"]) == String(receipt_b["details"]["receipt"]["receipt_hash"]), "receipt hash deterministic")
		var commit_a := Router.commit_route(first["details"]["route"], receipt_a["details"]["receipt"], subject["mixed"]["subject"], subject["mixed"]["ownership"])
		var commit_b := Router.commit_route(second["details"]["route"], receipt_b["details"]["receipt"], subject["mixed"]["subject"], subject["mixed"]["ownership"])
		_require(bool(commit_a.get("success", false)) and bool(commit_b.get("success", false)), "deterministic commit prerequisites")
		if bool(commit_a.get("success", false)) and bool(commit_b.get("success", false)):
			_require(String(commit_a["details"]["commit"]["commit_hash"]) == String(commit_b["details"]["commit"]["commit_hash"]), "commit hash deterministic")

func _finish() -> void:
	if _failed:
		printerr("FABRIC-BAKE BRIDGE-2-C Cross-Representation Event Routing Acceptance: FAIL (%d successful assertions)" % _checks)
		quit(1)
		return
	print("FABRIC-BAKE BRIDGE-2-C Cross-Representation Event Routing Acceptance: PASS (%d assertions)" % _checks)
	quit(0)

func _require(condition: bool, label: String, details = null) -> bool:
	if condition:
		_checks += 1
		return true
	_failed = true
	printerr("FABRIC-BAKE BRIDGE-2-C FAILURE: %s details=%s" % [label, str(details)])
	return false

func _code(result: Dictionary) -> String:
	return String(result.get("error_code", ""))
