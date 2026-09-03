extends RefCounted

const Contract = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const Complex0 = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")

const FULL := "representation/full-impact"
const STRUCTURAL := "representation/structural-bake"
const CONTACT := "representation/contact-bake"
const DYNAMIC := "representation/dynamic-rom"
const HYBRID := "representation/hybrid-bake"

const REGION_IMPACT := "region/impact"
const REGION_STABLE := "region/stable-structure"
const REGION_CONTACT := "region/contact"
const REGION_DYNAMIC := "region/dynamic"
const REGION_HYBRID := "region/hybrid"

static func build() -> Dictionary:
	var canonical := Complex0.build(500)
	if not bool(canonical.get("success", false)):
		return canonical
	var frontier_hash := String(canonical["frontier"]["frontier_hash"])
	var authority_binding := String(canonical["authority"]["authority_epoch_binding"])
	var representations := [
		_representation(FULL, "FULL", frontier_hash, authority_binding),
		_representation(STRUCTURAL, "STRUCTURAL_BAKE", frontier_hash, authority_binding),
		_representation(CONTACT, "CONTACT_BAKE", frontier_hash, authority_binding),
		_representation(DYNAMIC, "DYNAMIC_ROM", frontier_hash, authority_binding),
		_representation(HYBRID, "HYBRID_BAKE", frontier_hash, authority_binding),
	]
	var bindings := [
		_binding(REGION_IMPACT, FULL, "ACTIVE_EXECUTION"),
		_binding(REGION_IMPACT, STRUCTURAL, "OBSERVER"),
		_binding(REGION_IMPACT, CONTACT, "OBSERVER"),
		_binding(REGION_STABLE, STRUCTURAL, "ACTIVE_EXECUTION"),
		_binding(REGION_STABLE, FULL, "OBSERVER"),
		_binding(REGION_CONTACT, CONTACT, "ACTIVE_EXECUTION"),
		_binding(REGION_CONTACT, FULL, "OBSERVER"),
		_binding(REGION_DYNAMIC, DYNAMIC, "ACTIVE_EXECUTION"),
		_binding(REGION_DYNAMIC, FULL, "OBSERVER"),
		_binding(REGION_HYBRID, HYBRID, "ACTIVE_EXECUTION"),
		_binding(REGION_HYBRID, DYNAMIC, "OBSERVER"),
	]
	var compiled := Contract.compile(canonical["frontier"], canonical["authority"], representations, bindings)
	if not bool(compiled.get("success", false)):
		return compiled
	return {
		"success": true,
		"canonical": canonical,
		"representations": representations,
		"bindings": bindings,
		"contract": compiled["details"]["contract"],
	}

static func canonical_break_event() -> Dictionary:
	return {
		"event_id": "event/bridge2-a-break",
		"region_id": REGION_IMPACT,
		"event_kind": "STRUCTURAL_BREAK",
		"canonical_effect": "CANONICAL_MUTATION",
		"candidate_representation_ids": [CONTACT, FULL, STRUCTURAL],
	}

static func hybrid_jump_event() -> Dictionary:
	return {
		"event_id": "event/bridge2-a-hybrid-jump",
		"region_id": REGION_HYBRID,
		"event_kind": "HYBRID_MODE_JUMP",
		"canonical_effect": "DERIVED_PHYSICAL_EVENT",
		"candidate_representation_ids": [DYNAMIC, HYBRID],
	}

static func _representation(id: String, kind: String, frontier_hash: String, authority_binding: String) -> Dictionary:
	return {
		"representation_id": id,
		"representation_kind": kind,
		"derived_only": true,
		"canonical_write_authorized": false,
		"source_frontier_hash": frontier_hash,
		"authority_epoch_binding": authority_binding,
	}

static func _binding(region_id: String, representation_id: String, role: String) -> Dictionary:
	return {
		"region_id": region_id,
		"representation_id": representation_id,
		"ownership_role": role,
	}
