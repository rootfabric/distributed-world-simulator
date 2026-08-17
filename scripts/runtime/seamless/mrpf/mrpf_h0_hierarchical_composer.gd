extends RefCounted

const Contract = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_projection_contract.gd")

var _representations: Dictionary = {}
var _group_contracts: Dictionary = {}

func accept_representation(value: Dictionary) -> Dictionary:
	var validated := Contract.validate(value)
	if not bool(validated.get("success", false)):
		return validated
	var representation_id := String(value.get("representation_id", ""))
	var group_id := String(value.get("replacement_group_id", ""))
	var group_contract := {
		"canonical_subject_id": String(value.get("canonical_subject_id", "")),
		"coverage_scope": String(value.get("coverage_scope", "")),
		"reference_frame_id": String(value.get("reference_frame_id", "")),
	}
	if _group_contracts.has(group_id) and Dictionary(_group_contracts[group_id]) != group_contract:
		return _failure("MRPF_H0_REPLACEMENT_GROUP_CONTRACT_MISMATCH")
	if _representations.has(representation_id):
		var previous: Dictionary = Dictionary(_representations[representation_id])
		if _identity_binding(previous) != _identity_binding(value):
			return _failure("MRPF_H0_REPRESENTATION_IDENTITY_REBIND")
		var previous_revision := int(previous.get("source_revision", 0))
		var next_revision := int(value.get("source_revision", 0))
		if next_revision < previous_revision:
			return _failure("MRPF_H0_SOURCE_REVISION_STALE")
		if next_revision == previous_revision:
			if String(previous.get("checksum", "")) == String(value.get("checksum", "")):
				return _success({"replay": true})
			return _failure("MRPF_H0_SAME_REVISION_MUTATION")
	_group_contracts[group_id] = group_contract
	_representations[representation_id] = value.duplicate(true)
	return _success({"replay": false})

func remove_representation(representation_id: String, expected_source_revision: int) -> Dictionary:
	if not _representations.has(representation_id):
		return _failure("MRPF_H0_REPRESENTATION_NOT_FOUND")
	var current: Dictionary = Dictionary(_representations[representation_id])
	if int(current.get("source_revision", 0)) != expected_source_revision:
		return _failure("MRPF_H0_REMOVE_REVISION_MISMATCH")
	_representations.erase(representation_id)
	return _success()

func compose_view() -> Dictionary:
	var groups: Dictionary = {}
	for raw in _representations.values():
		var value: Dictionary = Dictionary(raw)
		var group_id := String(value.get("replacement_group_id", ""))
		if not groups.has(group_id):
			groups[group_id] = []
		Array(groups[group_id]).append(value)

	var group_ids: Array = groups.keys()
	group_ids.sort()
	var selected: Array = []
	for group_id in group_ids:
		var candidates: Array = Array(groups[group_id])
		candidates.sort_custom(_candidate_before)
		if not candidates.is_empty():
			var chosen: Dictionary = Dictionary(candidates[0]).duplicate(true)
			chosen["selected_specificity"] = Contract.specificity(chosen)
			selected.append(chosen)

	selected.sort_custom(_selected_before)
	var result := {
		"presentation_only": true,
		"canonical_state_generated": false,
		"representations": selected,
	}
	result["view_hash"] = _view_hash(selected)
	return _success(result)

func reject_presentation_mutation(canonical_subject_id: String, operation: String) -> Dictionary:
	return _failure("MRPF_H0_PRESENTATION_READ_ONLY", {
		"canonical_subject_id": canonical_subject_id,
		"operation": operation,
	})

func representation_count() -> int:
	return _representations.size()

func _identity_binding(value: Dictionary) -> Array:
	return [
		String(value.get("canonical_subject_id", "")),
		String(value.get("source_domain_id", "")),
		String(value.get("source_authority_id", "")),
		String(value.get("publisher_id", "")),
		String(value.get("representation_class", "")),
		int(value.get("lod_level", -1)),
		String(value.get("coverage_scope", "")),
		String(value.get("reference_frame_id", "")),
		String(value.get("replacement_group_id", "")),
		String(value.get("domain_level", "")),
	]

func _candidate_before(a_raw, b_raw) -> bool:
	var a: Dictionary = Dictionary(a_raw)
	var b: Dictionary = Dictionary(b_raw)
	var a_specificity := Contract.specificity(a)
	var b_specificity := Contract.specificity(b)
	if a_specificity != b_specificity:
		return a_specificity > b_specificity
	var a_lod := int(a.get("lod_level", 0))
	var b_lod := int(b.get("lod_level", 0))
	if a_lod != b_lod:
		return a_lod > b_lod
	return String(a.get("representation_id", "")) < String(b.get("representation_id", ""))

func _selected_before(a_raw, b_raw) -> bool:
	var a: Dictionary = Dictionary(a_raw)
	var b: Dictionary = Dictionary(b_raw)
	var a_group := String(a.get("replacement_group_id", ""))
	var b_group := String(b.get("replacement_group_id", ""))
	if a_group != b_group:
		return a_group < b_group
	return String(a.get("representation_id", "")) < String(b.get("representation_id", ""))

func _view_hash(selected: Array) -> String:
	var rows: Array[String] = []
	for raw in selected:
		var value: Dictionary = Dictionary(raw)
		rows.append("|".join([
			String(value.get("replacement_group_id", "")),
			String(value.get("representation_id", "")),
			String(value.get("canonical_subject_id", "")),
			String(value.get("domain_level", "")),
			str(int(value.get("source_revision", 0))),
			String(value.get("content_hash", "")),
			String(value.get("checksum", "")),
		]))
	return "\n".join(rows).sha256_text()

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
