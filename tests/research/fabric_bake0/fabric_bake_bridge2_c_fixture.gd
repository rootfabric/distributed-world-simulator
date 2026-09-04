extends RefCounted

const Router = preload("res://scripts/research/fabric_bake0/mixed_representation_event_router_v1.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Complex0 = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const OwnershipFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_a_fixture.gd")
const B2BFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_b_fixture.gd")

static func build() -> Dictionary:
	var mixed := B2BFixture.build()
	if not bool(mixed.get("success", false)):
		return mixed
	var structural := Complex0.compile_structural(mixed["canonical"])
	if not bool(structural.get("success", false)):
		return structural
	var broken := Complex0.make_break(mixed["canonical"], structural)
	if not bool(broken.get("success", false)):
		return broken
	var invalidation_check := RepresentationInvalidation.validate(broken["source_invalidation"])
	if not bool(invalidation_check.get("success", false)):
		return invalidation_check
	var entries := {}
	for entry in mixed["subject"]["entries"]:
		entries[String(entry["representation_id"])] = entry
	return {
		"success": true,
		"mixed": mixed,
		"structural": structural,
		"broken": broken,
		"entries": entries,
	}

static func canonical_event(subject: Dictionary) -> Dictionary:
	return {
		"event_id": String(subject["broken"]["event"]["event_id"]),
		"region_id": OwnershipFixture.REGION_IMPACT,
		"event_kind": "STRUCTURAL_BREAK",
		"canonical_effect": "CANONICAL_MUTATION",
		"candidate_representation_ids": [OwnershipFixture.CONTACT, OwnershipFixture.FULL, OwnershipFixture.STRUCTURAL],
	}

static func canonical_route(subject: Dictionary, committed_event_ids: Array = []) -> Dictionary:
	var entry: Dictionary = subject["entries"][OwnershipFixture.FULL]
	return Router.prepare_route(
		subject["mixed"]["subject"], subject["mixed"]["ownership"], canonical_event(subject),
		OwnershipFixture.FULL, String(entry["execution_identity_hash"]), String(entry["runtime_state_hash"]),
		committed_event_ids
	)

static func canonical_receipt(subject: Dictionary, route: Dictionary) -> Dictionary:
	return Router.create_commit_receipt(
		route,
		subject["mixed"]["ownership"],
		subject["broken"]["current_frontier"],
		subject["broken"]["current_authority"],
		subject["broken"]["source_invalidation"],
		"CONSTRUCTION_BOND_BREAK"
	)

static func derived_event() -> Dictionary:
	return {
		"event_id": "event/bridge2-c-hybrid-jump",
		"region_id": OwnershipFixture.REGION_HYBRID,
		"event_kind": "HYBRID_MODE_JUMP",
		"canonical_effect": "DERIVED_PHYSICAL_EVENT",
		"candidate_representation_ids": [OwnershipFixture.DYNAMIC, OwnershipFixture.HYBRID],
	}

static func derived_route(subject: Dictionary, committed_event_ids: Array = []) -> Dictionary:
	var entry: Dictionary = subject["entries"][OwnershipFixture.HYBRID]
	return Router.prepare_route(
		subject["mixed"]["subject"], subject["mixed"]["ownership"], derived_event(),
		OwnershipFixture.HYBRID, String(entry["execution_identity_hash"]), String(entry["runtime_state_hash"]),
		committed_event_ids
	)

static func derived_receipt(subject: Dictionary, route: Dictionary) -> Dictionary:
	return Router.create_commit_receipt(
		route,
		subject["mixed"]["ownership"],
		subject["mixed"]["canonical"]["frontier"],
		subject["mixed"]["canonical"]["authority"],
		{},
		"NONE"
	)
