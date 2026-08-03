extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const InterestRequest = preload("res://scripts/simulation/representation/contracts/representation_interest_request.gd")
const Candidate = preload("res://scripts/simulation/representation/contracts/representation_candidate.gd")


static func select(request: Dictionary, candidates: Array) -> Dictionary:
	var checked: Dictionary = InterestRequest.validate(request)
	if not bool(checked.get("success", false)):
		return checked
	var selected: Dictionary = {}
	var selected_screen_error_px: float = 0.0
	var eligible_count: int = 0
	for index in range(candidates.size()):
		if typeof(candidates[index]) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_REPRESENTATION_CANDIDATE", {"index": index})
		var candidate: Dictionary = candidates[index]
		checked = Candidate.validate(candidate)
		if not bool(checked.get("success", false)):
			return Utils.failure(String(checked.get("error_code", "INVALID_REPRESENTATION_CANDIDATE")), {"index": index})
		var key: Dictionary = candidate["representation_key"]
		var required_source: Dictionary = request["required_source_revision"]
		if String(key["source_revision"].get("checksum", "")) != String(required_source.get("checksum", "")):
			continue
		if not bool(candidate["ready"]):
			continue
		if int(candidate["estimated_bytes"]) > int(request["bandwidth_budget_bytes"]):
			continue
		if bool(request["collision_required"]) and not bool(candidate["collision_capable"]):
			continue
		if bool(request["interior_required"]) and not bool(candidate["interior_capable"]):
			continue
		var preferred: Array = request["preferred_artifact_kinds"]
		if not preferred.is_empty() and not preferred.has(String(key["artifact_kind"])):
			continue
		var geometric_error_m: float = float(candidate["geometric_error_m"])
		if geometric_error_m > float(request["maximum_geometric_error_m"]):
			continue
		var screen_error_px: float = Utils.screen_error_px(
			geometric_error_m,
			float(request["distance_m"]),
			float(request["projection_scale_px"])
		)
		if not is_finite(screen_error_px) or screen_error_px > float(request["maximum_screen_error_px"]):
			continue
		eligible_count += 1
		if selected.is_empty() or _is_better(candidate, selected):
			selected = candidate
			selected_screen_error_px = screen_error_px
	if selected.is_empty():
		return Utils.failure("REPRESENTATION_NO_ACCEPTABLE_CANDIDATE")
	return Utils.success({
		"candidate": selected.duplicate(true),
		"screen_error_px": selected_screen_error_px,
		"eligible_count": eligible_count,
	})


static func _is_better(left: Dictionary, right: Dictionary) -> bool:
	var left_key: Dictionary = left["representation_key"]
	var right_key: Dictionary = right["representation_key"]
	var left_lod: int = int(left_key["lod_level"])
	var right_lod: int = int(right_key["lod_level"])
	if left_lod != right_lod:
		return left_lod > right_lod
	var left_bytes: int = int(left["estimated_bytes"])
	var right_bytes: int = int(right["estimated_bytes"])
	if left_bytes != right_bytes:
		return left_bytes < right_bytes
	return String(left_key["checksum"]) < String(right_key["checksum"])
