extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_projection_contract.gd")
const Composer = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_hierarchical_composer.gd")

const EXPECTED_ASSERTIONS := 103
var _assertions := 0
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var space := _rep("rep/earth/space", "earth", "space", 1, "CELESTIAL_BODY", 0, "earth/full", "earth/full", "SPACE", "hash-space-r1")
	var earth := _rep("rep/earth/macro", "earth", "earth", 1, "PLANETARY_LAYER", 1, "earth/full", "earth/full", "EARTH", "hash-earth-r1")
	var surface := _rep("rep/earth/surface314", "earth", "surface/314", 1, "TERRAIN_MACRO", 2, "earth/full", "earth/full", "SURFACE", "hash-surface-r1")
	var base := _rep("rep/earth/base17", "earth", "base/17", 1, "REGIONAL_LANDMARK", 3, "earth/full", "earth/full", "BASE", "hash-base-r1")
	for value in [space, earth, surface, base]:
		_check_success(Contract.validate(value), "valid representation")
		_check(value.get("presentation_only") == true, "representation presentation only")
		_check(value.get("canonical_write_allowed") == false, "representation cannot write canonical")

	var bad_level := space.duplicate(true)
	bad_level["domain_level"] = "GALAXY"
	bad_level["checksum"] = Contract.checksum(bad_level)
	_check_error(Contract.validate(bad_level), "MRPF_H0_DOMAIN_LEVEL_INVALID", "unknown level rejected")
	var bad_checksum := space.duplicate(true)
	bad_checksum["content_hash"] = "mutated"
	_check_error(Contract.validate(bad_checksum), "MRPF_H0_CHECKSUM_MISMATCH", "checksum mutation rejected")
	var unknown_field := space.duplicate(true)
	unknown_field["unhashed_payload"] = "must-not-pass"
	_check_error(Contract.validate(unknown_field), "MRPF_H0_FIELD_UNKNOWN", "unknown field rejected")
	var bad_type := space.duplicate(true)
	bad_type["source_revision"] = "1"
	bad_type["checksum"] = Contract.checksum(bad_type)
	_check_error(Contract.validate(bad_type), "MRPF_H0_FIELD_TYPE_INVALID", "wrong scalar type rejected")

	var collision_a := Contract.create_representation("rep/collision", "earth|macro", "domain", "authority/collision", "publisher/collision", 1, "TEST", 0, "collision/full", "frame/solar", "hash-collision", 0, "collision/group", "SPACE")
	var collision_b := Contract.create_representation("rep/collision", "earth", "macro|domain", "authority/collision", "publisher/collision", 1, "TEST", 0, "collision/full", "frame/solar", "hash-collision", 0, "collision/group", "SPACE")
	_check_success(Contract.validate(collision_a), "delimiter collision A validates")
	_check_success(Contract.validate(collision_b), "delimiter collision B validates")
	_check(String(collision_a.get("checksum", "")) != String(collision_b.get("checksum", "")), "typed length-prefixed encoding prevents delimiter collision")
	var unicode_rep := Contract.create_representation("rep/unicode|1", "Земля|A\nB", "domain/µ", "authority/земля", "publisher/earth", 1, "UNICODE", 0, "coverage|α", "frame/solar", "hash|unicode\nvalue", 0, "unicode/group", "SPACE")
	_check_success(Contract.validate(unicode_rep), "unicode delimiter representation validates")
	_check(String(unicode_rep.get("checksum", "")).length() == 64, "unicode canonical checksum emitted")

	var composer = Composer.new()
	_check_error(composer.accept_representation(unknown_field), "MRPF_H0_FIELD_UNKNOWN", "composer rejects open DTO field")
	_check_success(composer.accept_representation(space), "accept space")
	_check(_selected_id(composer) == "rep/earth/space", "SPACE selected initially")
	_check_success(composer.accept_representation(earth), "accept earth")
	_check(_selected_id(composer) == "rep/earth/macro", "EARTH replaces SPACE")
	_check_success(composer.accept_representation(surface), "accept surface")
	_check(_selected_id(composer) == "rep/earth/surface314", "SURFACE replaces EARTH")
	_check_success(composer.accept_representation(base), "accept base")
	_check(_selected_id(composer) == "rep/earth/base17", "BASE replaces SURFACE")
	_check(composer.representation_count() == 4, "coarse candidates retained for fallback")
	_check(composer.identity_ledger_count() == 4, "identity ledger tracks accepted representations")

	var composed := composer.compose_view()
	_check_success(composed, "composition succeeds")
	var details: Dictionary = Dictionary(composed.get("details", {}))
	_check(details.get("presentation_only") == true, "view presentation only")
	_check(details.get("canonical_state_generated") == false, "view generates no canonical state")
	_check(String(details.get("view_hash", "")).length() == 64, "view hash emitted")
	_check(_selected_subject(composer) == "earth", "subject identity stable")
	_check(not composer.has_method("apply_canonical_mutation"), "composer exposes no canonical mutation API")
	_check_error(composer.reject_presentation_mutation("earth", "materialize"), "MRPF_H0_PRESENTATION_READ_ONLY", "mutation rejected")

	var replay := composer.accept_representation(base)
	_check_success(replay, "exact replay accepted")
	_check(bool(Dictionary(replay.get("details", {})).get("replay", false)), "exact replay marked")

	var stale_zero := _rep("rep/earth/base17", "earth", "base/17", 0, "REGIONAL_LANDMARK", 3, "earth/full", "earth/full", "BASE", "hash-base-r0")
	_check_error(Contract.validate(stale_zero), "MRPF_H0_SOURCE_REVISION_INVALID", "zero revision invalid")
	var newer := _rep("rep/earth/base17", "earth", "base/17", 2, "REGIONAL_LANDMARK", 3, "earth/full", "earth/full", "BASE", "hash-base-r2")
	_check_success(composer.accept_representation(newer), "higher revision accepted")
	_check(_selected_id(composer) == "rep/earth/base17", "new base revision selected")
	_check_error(composer.accept_representation(base), "MRPF_H0_SOURCE_REVISION_STALE", "resident stale revision rejected")
	var mutated_same := _rep("rep/earth/base17", "earth", "base/17", 2, "REGIONAL_LANDMARK", 3, "earth/full", "earth/full", "BASE", "hash-base-r2-mutated")
	_check_error(composer.accept_representation(mutated_same), "MRPF_H0_SAME_REVISION_MUTATION", "resident same revision mutation rejected")

	var rebound := Contract.create_representation("rep/earth/base17", "earth", "forged/base", "authority/forged", "publisher/forged", 3, "REGIONAL_LANDMARK", 3, "earth/full", "frame/solar", "hash-forged-r3", 0, "earth/full", "BASE")
	_check_error(composer.accept_representation(rebound), "MRPF_H0_REPRESENTATION_IDENTITY_REBIND", "resident higher revision identity rebind rejected")
	_check(_selected_id(composer) == "rep/earth/base17", "resident rebind rejection preserves current representation")

	_check_error(composer.remove_representation("rep/earth/base17", 1), "MRPF_H0_REMOVE_REVISION_MISMATCH", "remove revision fenced")
	_check_success(composer.remove_representation("rep/earth/base17", 2), "remove base")
	_check(_selected_id(composer) == "rep/earth/surface314", "BASE removal reveals SURFACE")
	_check(composer.identity_ledger_count() == 4, "remove preserves identity ledger")
	_check_error(composer.accept_representation(base), "MRPF_H0_SOURCE_REVISION_STALE", "post-remove stale lower revision rejected")
	_check(_selected_id(composer) == "rep/earth/surface314", "stale post-remove rejection preserves coarse fallback")
	_check_error(composer.accept_representation(newer), "MRPF_H0_TOMBSTONED_REPLAY", "post-remove same revision replay cannot resurrect")
	_check(_selected_id(composer) == "rep/earth/surface314", "tombstoned replay rejection preserves coarse fallback")
	_check_error(composer.accept_representation(rebound), "MRPF_H0_REPRESENTATION_IDENTITY_REBIND", "post-remove higher revision identity rebind rejected")
	_check(_selected_id(composer) == "rep/earth/surface314", "post-remove rebind rejection preserves coarse fallback")
	var legitimate_r3 := _rep("rep/earth/base17", "earth", "base/17", 3, "REGIONAL_LANDMARK", 3, "earth/full", "earth/full", "BASE", "hash-base-r3")
	_check_success(composer.accept_representation(legitimate_r3), "legitimate newer revision reactivates tombstoned identity")
	_check(_selected_id(composer) == "rep/earth/base17", "legitimate reactivation restores BASE")
	_check_success(composer.remove_representation("rep/earth/base17", 3), "remove reactivated base")
	_check(_selected_id(composer) == "rep/earth/surface314", "reactivated BASE removal reveals SURFACE")

	_check_success(composer.remove_representation("rep/earth/surface314", 1), "remove surface")
	_check(_selected_id(composer) == "rep/earth/macro", "SURFACE removal reveals EARTH")
	_check_success(composer.remove_representation("rep/earth/macro", 1), "remove earth")
	_check(_selected_id(composer) == "rep/earth/space", "EARTH removal reveals SPACE")

	var unrelated := _rep("rep/moon/space", "moon", "space", 1, "CELESTIAL_BODY", 0, "moon/full", "moon/full", "SPACE", "hash-moon-r1")
	_check_success(composer.accept_representation(unrelated), "unrelated Moon group accepted")
	var multi := composer.compose_view()
	_check_success(multi, "multi group composition")
	var multi_details: Dictionary = Dictionary(multi.get("details", {}))
	_check(Array(multi_details.get("representations", [])).size() == 2, "unrelated groups compose simultaneously")
	_check(_has_subject(multi_details, "earth"), "Earth remains present")
	_check(_has_subject(multi_details, "moon"), "Moon present independently")

	var mismatch := _rep("rep/earth/bad-coverage", "earth", "earth", 2, "PLANETARY_LAYER", 1, "earth/other", "earth/full", "EARTH", "hash-mismatch")
	_check_error(composer.accept_representation(mismatch), "MRPF_H0_REPLACEMENT_GROUP_CONTRACT_MISMATCH", "sticky replacement group coverage mismatch rejected")

	var order_a = Composer.new()
	var order_b = Composer.new()
	var deterministic_values := [space, earth, surface, base, unrelated]
	for value in deterministic_values:
		_check_success(order_a.accept_representation(value), "order A accepts")
	var reversed := deterministic_values.duplicate()
	reversed.reverse()
	for value in reversed:
		_check_success(order_b.accept_representation(value), "order B accepts")
	var hash_a := String(Dictionary(order_a.compose_view().get("details", {})).get("view_hash", ""))
	var hash_b := String(Dictionary(order_b.compose_view().get("details", {})).get("view_hash", ""))
	_check(hash_a == hash_b, "same inputs produce same view hash regardless insertion order")
	_check(_selected_id(order_a, "earth/full") == "rep/earth/base17", "deterministic Earth winner")
	_check(_selected_id(order_a, "moon/full") == "rep/moon/space", "deterministic Moon winner")

	var semantic_a = Composer.new()
	var semantic_b = Composer.new()
	_check_success(semantic_a.accept_representation(collision_a), "semantic composer A accepts collision tuple A")
	_check_success(semantic_b.accept_representation(collision_b), "semantic composer B accepts collision tuple B")
	var semantic_hash_a := String(Dictionary(semantic_a.compose_view().get("details", {})).get("view_hash", ""))
	var semantic_hash_b := String(Dictionary(semantic_b.compose_view().get("details", {})).get("view_hash", ""))
	_check(semantic_hash_a != semantic_hash_b, "semantic view difference changes view hash")

	_finish()

func _rep(id: String, subject: String, source: String, revision: int, klass: String, lod: int, coverage: String, group: String, level: String, content_hash: String) -> Dictionary:
	return Contract.create_representation(id, subject, source, "authority/%s" % source, "publisher/%s" % source, revision, klass, lod, coverage, "frame/solar", content_hash, 0, group, level)

func _selected_id(composer, group_id: String = "earth/full") -> String:
	var result: Dictionary = composer.compose_view()
	if not bool(result.get("success", false)):
		return ""
	for raw in Array(Dictionary(result.get("details", {})).get("representations", [])):
		var value: Dictionary = Dictionary(raw)
		if String(value.get("replacement_group_id", "")) == group_id:
			return String(value.get("representation_id", ""))
	return ""

func _selected_subject(composer) -> String:
	var result: Dictionary = composer.compose_view()
	for raw in Array(Dictionary(result.get("details", {})).get("representations", [])):
		var value: Dictionary = Dictionary(raw)
		if String(value.get("replacement_group_id", "")) == "earth/full":
			return String(value.get("canonical_subject_id", ""))
	return ""

func _has_subject(details: Dictionary, subject: String) -> bool:
	for raw in Array(details.get("representations", [])):
		if String(Dictionary(raw).get("canonical_subject_id", "")) == subject:
			return true
	return false

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), label + " success")

func _check_error(result: Dictionary, code: String, label: String) -> void:
	_check(not bool(result.get("success", false)), label + " fails")
	_check(String(result.get("error_code", "")) == code, label + " error code")

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failed = true
		push_error("MRPF H0 assertion failed: %s" % label)

func _finish() -> void:
	if EXPECTED_ASSERTIONS >= 0 and _assertions != EXPECTED_ASSERTIONS:
		_failed = true
		push_error("MRPF H0 assertion count mismatch: expected %d got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failed:
		print("MRPF H0 hierarchical projection contracts: FAIL (%d assertions)" % _assertions)
		quit(1)
	else:
		print("MRPF H0 hierarchical projection contracts: PASS (%d assertions)" % _assertions)
		quit(0)
