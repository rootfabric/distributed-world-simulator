extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const StreamRequest = preload("res://scripts/simulation/representation/network/contracts/representation_stream_request.gd")
const StreamStage = preload("res://scripts/simulation/representation/network/contracts/representation_stream_stage.gd")
const StreamPlan = preload("res://scripts/simulation/representation/network/contracts/representation_stream_plan.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const Descriptor = preload("res://scripts/simulation/representation/contracts/representation_descriptor.gd")
const Selector = preload("res://scripts/simulation/representation/selection/representation_selector.gd")


static func build_plan(request: Dictionary, manifests: Array, created_tick: int, lifetime_ticks: int = 600) -> Dictionary:
	var checked: Dictionary = StreamRequest.validate(request)
	if not bool(checked.get("success", false)):
		return checked
	if created_tick < 0 or lifetime_ticks < 1:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_PLAN_TIME")
	var interest: Dictionary = request["interest_request"]
	var required_source_checksum: String = String(interest["required_source_revision"]["checksum"])
	var usable: Array = []
	var candidates: Array = []
	for index in range(manifests.size()):
		if typeof(manifests[index]) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_REPRESENTATION_STREAM_MANIFEST", {"index": index})
		var manifest: Dictionary = manifests[index]
		checked = ArtifactManifest.validate(manifest)
		if not bool(checked.get("success", false)):
			return Utils.failure(String(checked.get("error_code", "INVALID_REPRESENTATION_STREAM_MANIFEST")), {"index": index})
		if String(manifest["representation_key"]["source_revision"]["checksum"]) != required_source_checksum:
			continue
		if not _scope_matches(request["scope_chain"], manifest["representation_key"]):
			continue
		if not request["supported_encodings"].has(String(manifest["encoding"])):
			continue
		var descriptor: Dictionary = Descriptor.from_manifest(manifest)
		var candidate: Dictionary = Descriptor.to_candidate(descriptor)
		if candidate.is_empty():
			return Utils.failure("REPRESENTATION_STREAM_CANDIDATE_PROJECTION_FAILED", {"index": index})
		usable.append(manifest.duplicate(true))
		candidates.append(candidate)
	if usable.is_empty():
		return Utils.failure("REPRESENTATION_STREAM_NO_SUPPORTED_ARTIFACTS")
	var selected: Dictionary = Selector.select(interest, candidates)
	if not bool(selected.get("success", false)):
		return selected
	var final_hash: String = String(selected["details"]["candidate"]["artifact_hash"])
	var final_manifest: Dictionary = _manifest_by_hash(usable, final_hash)
	if final_manifest.is_empty():
		return Utils.failure("REPRESENTATION_STREAM_SELECTED_MANIFEST_MISSING")
	var selected_manifests: Array = [final_manifest]
	if bool(request["progressive_loading"]):
		selected_manifests = _progressive_chain(request, usable, final_manifest)
	selected_manifests = _trim_to_budget(request, selected_manifests)
	if selected_manifests.is_empty() or String(selected_manifests.back()["artifact_hash"]) != final_hash:
		return Utils.failure("REPRESENTATION_STREAM_FINAL_STAGE_BUDGET_REJECTED")
	var stages: Array = []
	var cached: Array = request["cached_artifact_hashes"]
	for index in range(selected_manifests.size()):
		var manifest: Dictionary = selected_manifests[index]
		var cache_hit: bool = cached.has(String(manifest["artifact_hash"]))
		var stage: Dictionary = StreamStage.create(
			index,
			manifest,
			"CACHE_HIT" if cache_hit else "TRANSFER",
			0 if cache_hit else mini(int(request["maximum_chunk_bytes"]), int(manifest["byte_size"]))
		)
		if stage.is_empty():
			return Utils.failure("REPRESENTATION_STREAM_STAGE_BUILD_FAILED", {"index": index})
		stages.append(stage)
	var total_transfer_bytes: int = 0
	for stage in stages:
		total_transfer_bytes += int(stage["transfer_bytes"])
	if total_transfer_bytes > int(interest["bandwidth_budget_bytes"]):
		return Utils.failure("REPRESENTATION_STREAM_TOTAL_BANDWIDTH_EXCEEDED")
	var identity_payload: Dictionary = {
		"stream_request_id": request["stream_request_id"],
		"request_revision": interest["request_revision"],
		"source_revision_checksum": required_source_checksum,
		"stage_hashes": selected_manifests.map(func(value): return String(value["artifact_hash"])),
	}
	var stream_id: String = "stream/%s" % Utils.payload_hash(identity_payload).substr(0, 32)
	var plan: Dictionary = StreamPlan.create(
		stream_id,
		String(request["stream_request_id"]),
		String(interest["request_id"]),
		int(interest["request_revision"]),
		required_source_checksum,
		stages,
		created_tick,
		created_tick + lifetime_ticks
	)
	if plan.is_empty():
		return Utils.failure("REPRESENTATION_STREAM_PLAN_BUILD_FAILED")
	return Utils.success({"plan": plan})


static func _progressive_chain(request: Dictionary, manifests: Array, final_manifest: Dictionary) -> Array:
	var interest: Dictionary = request["interest_request"]
	var final_lod: int = int(final_manifest["representation_key"]["lod_level"])
	var by_lod: Dictionary = {final_lod: final_manifest}
	for raw_manifest in manifests:
		var manifest: Dictionary = raw_manifest
		var key: Dictionary = manifest["representation_key"]
		var lod: int = int(key["lod_level"])
		if lod <= final_lod:
			continue
		if bool(interest["collision_required"]) and not bool(manifest["collision_capable"]):
			continue
		if bool(interest["interior_required"]) and not bool(manifest["interior_capable"]):
			continue
		var preferred: Array = interest["preferred_artifact_kinds"]
		if not preferred.is_empty() and not preferred.has(String(key["artifact_kind"])):
			continue
		var screen_error: float = Utils.screen_error_px(
			float(manifest["geometric_error_m"]),
			float(interest["distance_m"]),
			float(interest["projection_scale_px"])
		)
		if screen_error > float(request["maximum_bootstrap_screen_error_px"]):
			continue
		if not by_lod.has(lod) or _manifest_is_better(manifest, by_lod[lod]):
			by_lod[lod] = manifest
	var lods: Array = by_lod.keys()
	lods.sort()
	lods.reverse()
	var result: Array = []
	for lod in lods:
		result.append(by_lod[lod].duplicate(true))
	while result.size() > int(request["maximum_stages"]):
		result.remove_at(1 if result.size() > 1 else 0)
	return result


static func _trim_to_budget(request: Dictionary, manifests: Array) -> Array:
	var result: Array = manifests.duplicate(true)
	var cached: Array = request["cached_artifact_hashes"]
	var budget: int = int(request["interest_request"]["bandwidth_budget_bytes"])
	while result.size() > 1 and _transfer_bytes(result, cached) > budget:
		result.pop_front()
	return result


static func _transfer_bytes(manifests: Array, cached: Array) -> int:
	var total: int = 0
	for manifest in manifests:
		if not cached.has(String(manifest["artifact_hash"])):
			total += int(manifest["byte_size"])
	return total


static func _manifest_by_hash(manifests: Array, artifact_hash: String) -> Dictionary:
	for manifest in manifests:
		if String(manifest["artifact_hash"]) == artifact_hash:
			return manifest.duplicate(true)
	return {}


static func _manifest_is_better(left: Dictionary, right: Dictionary) -> bool:
	if int(left["byte_size"]) != int(right["byte_size"]):
		return int(left["byte_size"]) < int(right["byte_size"])
	return String(left["artifact_hash"]) < String(right["artifact_hash"])


static func _scope_matches(scope_chain: Array, key: Dictionary) -> bool:
	for binding in scope_chain:
		if int(binding["lod_level"]) == int(key["lod_level"]) \
			and String(binding["scope_id"]) == String(key["scope_id"]):
			return true
	return false
