extends RefCounted

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p10_view_contract.gd")

const ENTITY_COST_BYTES := 96
const FINE_DISTANCE_M := 30.0

var _active_authority_id := ""
var _default_budget_bytes := 0
var _snapshots: Dictionary = {}
var _source_available: Dictionary = {}
var _artifact_cache: Dictionary = {}

func setup(active_authority_id: String, default_budget_bytes: int) -> Dictionary:
	if active_authority_id not in Contract.AUTHORITIES:
		return _failure("SM0_P10_COMPOSER_AUTHORITY_INVALID")
	if default_budget_bytes < ENTITY_COST_BYTES:
		return _failure("SM0_P10_COMPOSER_BUDGET_INVALID")
	_active_authority_id = active_authority_id
	_default_budget_bytes = default_budget_bytes
	_snapshots.clear()
	_source_available.clear()
	_artifact_cache.clear()
	return _success()

func accept_projection(snapshot: Dictionary) -> Dictionary:
	if _active_authority_id.is_empty():
		return _failure("SM0_P10_COMPOSER_NOT_READY")
	var validation: Dictionary = Contract.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var source_id := String(snapshot.get("source_authority_id", ""))
	var expected_role := "LOCAL" if source_id == _active_authority_id else "FOREIGN"
	if String(snapshot.get("source_role", "")) != expected_role:
		return _failure("SM0_P10_SOURCE_ROLE_MISMATCH", {"source_authority_id": source_id, "expected_role": expected_role})
	if _snapshots.has(source_id):
		var current: Dictionary = Dictionary(_snapshots[source_id])
		var current_epoch := int(current.get("source_authority_epoch", 0))
		var incoming_epoch := int(snapshot.get("source_authority_epoch", 0))
		if incoming_epoch < current_epoch:
			return _failure("SM0_P10_SOURCE_EPOCH_ROLLBACK", {"source_authority_id": source_id})
		if incoming_epoch == current_epoch:
			var current_sequence := int(current.get("projection_sequence", 0))
			var incoming_sequence := int(snapshot.get("projection_sequence", 0))
			if incoming_sequence < current_sequence:
				return _failure("SM0_P10_SOURCE_SEQUENCE_STALE", {"source_authority_id": source_id})
			if incoming_sequence == current_sequence:
				if String(snapshot.get("checksum", "")) == String(current.get("checksum", "")):
					_source_available[source_id] = true
					return _success({"replay": true, "source_authority_id": source_id})
				return _failure("SM0_P10_SOURCE_SAME_SEQUENCE_MUTATION", {"source_authority_id": source_id})
	_snapshots[source_id] = snapshot.duplicate(true)
	_source_available[source_id] = true
	return _success({"replay": false, "source_authority_id": source_id})

func mark_source_unavailable(source_authority_id: String, source_authority_epoch: int) -> Dictionary:
	if not _snapshots.has(source_authority_id):
		return _failure("SM0_P10_SOURCE_UNKNOWN", {"source_authority_id": source_authority_id})
	var current: Dictionary = Dictionary(_snapshots[source_authority_id])
	if source_authority_epoch != int(current.get("source_authority_epoch", 0)):
		return _failure("SM0_P10_SOURCE_DROPOUT_EPOCH_MISMATCH", {"source_authority_id": source_authority_id})
	_source_available[source_authority_id] = false
	return _success({"source_authority_id": source_authority_id})

func compose_view(client_position: Dictionary, max_distance_m: float, budget_bytes: int = -1) -> Dictionary:
	if _active_authority_id.is_empty():
		return _failure("SM0_P10_COMPOSER_NOT_READY")
	if max_distance_m <= 0.0:
		return _failure("SM0_P10_DISTANCE_INVALID")
	var budget := _default_budget_bytes if budget_bytes < 0 else budget_bytes
	if budget < 0:
		return _failure("SM0_P10_BUDGET_INVALID")
	var remaining := budget
	var bandwidth_used := 0
	var cache_hits := 0
	var budget_drops := 0
	var entities_out: Array = []
	var representations_out: Array = []
	var degraded_sources: Array = []
	var sources_used: Array = []

	var entity_candidates: Array = []
	for source_id_raw in _snapshots.keys():
		var source_id := String(source_id_raw)
		if not bool(_source_available.get(source_id, false)):
			degraded_sources.append(source_id)
			continue
		var snapshot: Dictionary = Dictionary(_snapshots[source_id])
		for raw_entity in Array(snapshot.get("entities", [])):
			var entity: Dictionary = Dictionary(raw_entity)
			var distance := Contract.distance_m(client_position, Dictionary(entity.get("world_position", {})))
			if distance <= max_distance_m:
				entity_candidates.append({"source": source_id, "distance": distance, "entity": entity})
	entity_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap := int(Dictionary(a.get("entity", {})).get("priority", 0))
		var bp := int(Dictionary(b.get("entity", {})).get("priority", 0))
		if ap != bp:
			return ap > bp
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)
	for candidate_raw in entity_candidates:
		var candidate: Dictionary = Dictionary(candidate_raw)
		if remaining < ENTITY_COST_BYTES:
			budget_drops += 1
			continue
		remaining -= ENTITY_COST_BYTES
		bandwidth_used += ENTITY_COST_BYTES
		var source_id := String(candidate.get("source", ""))
		var snapshot: Dictionary = Dictionary(_snapshots[source_id])
		var output: Dictionary = Dictionary(candidate.get("entity", {})).duplicate(true)
		output["source_authority_id"] = source_id
		output["source_role"] = String(snapshot.get("source_role", ""))
		output["distance_m"] = float(candidate.get("distance", 0.0))
		output["presentation_only"] = true
		output["canonical_write_allowed"] = false
		entities_out.append(output)
		if not sources_used.has(source_id):
			sources_used.append(source_id)

	var available_rep_groups: Dictionary = {}
	for source_id_raw in _snapshots.keys():
		var source_id := String(source_id_raw)
		var snapshot: Dictionary = Dictionary(_snapshots[source_id])
		if bool(_source_available.get(source_id, false)):
			for raw_rep in Array(snapshot.get("representations", [])):
				var rep: Dictionary = Dictionary(raw_rep)
				var distance := Contract.distance_m(client_position, Dictionary(rep.get("world_position", {})))
				if distance > max_distance_m:
					continue
				var key := "%s|%s" % [source_id, String(rep.get("subject_id", ""))]
				if not available_rep_groups.has(key):
					available_rep_groups[key] = []
				Array(available_rep_groups[key]).append({"source": source_id, "distance": distance, "rep": rep})
		else:
			_append_cached_degraded_representations(source_id, snapshot, client_position, max_distance_m, representations_out)

	var rep_group_candidates: Array = []
	for key_raw in available_rep_groups.keys():
		var group: Array = Array(available_rep_groups[key_raw])
		var selected: Dictionary = _select_representation(group, remaining)
		if selected.is_empty():
			budget_drops += 1
			continue
		rep_group_candidates.append(selected)
	rep_group_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap := int(Dictionary(a.get("rep", {})).get("priority", 0))
		var bp := int(Dictionary(b.get("rep", {})).get("priority", 0))
		if ap != bp:
			return ap > bp
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)
	for selected_raw in rep_group_candidates:
		var selected: Dictionary = Dictionary(selected_raw)
		var rep: Dictionary = Dictionary(selected.get("rep", {}))
		var artifact_hash := String(rep.get("artifact_hash", ""))
		var cache_hit := _artifact_cache.has(artifact_hash)
		var cost := 0 if cache_hit else int(rep.get("byte_size", 0))
		if cost > remaining:
			var fallback: Dictionary = _fallback_coarse(Array(selected.get("group", [])), remaining)
			if fallback.is_empty():
				budget_drops += 1
				continue
			selected = fallback
			rep = Dictionary(selected.get("rep", {}))
			artifact_hash = String(rep.get("artifact_hash", ""))
			cache_hit = _artifact_cache.has(artifact_hash)
			cost = 0 if cache_hit else int(rep.get("byte_size", 0))
		if cost > remaining:
			budget_drops += 1
			continue
		remaining -= cost
		bandwidth_used += cost
		if cache_hit:
			cache_hits += 1
		else:
			_artifact_cache[artifact_hash] = true
		var source_id := String(selected.get("source", ""))
		var snapshot: Dictionary = Dictionary(_snapshots[source_id])
		var output := rep.duplicate(true)
		output["source_authority_id"] = source_id
		output["source_role"] = String(snapshot.get("source_role", ""))
		output["distance_m"] = float(selected.get("distance", 0.0))
		output["cache_hit"] = cache_hit
		output["stale_cached"] = false
		output["canonical_write_allowed"] = false
		representations_out.append(output)
		if not sources_used.has(source_id):
			sources_used.append(source_id)

	sources_used.sort()
	degraded_sources.sort()
	return _success({
		"active_authority_id": _active_authority_id,
		"sources_used": sources_used,
		"degraded_sources": degraded_sources,
		"entities": entities_out,
		"representations": representations_out,
		"bandwidth_budget_bytes": budget,
		"bandwidth_used_bytes": bandwidth_used,
		"cache_hits": cache_hits,
		"budget_drops": budget_drops,
		"presentation_only": true,
		"canonical_state_generated": false,
	})

func reject_presentation_mutation(entity_or_subject_id: String, operation: String) -> Dictionary:
	return _failure("SM0_P10_PRESENTATION_READ_ONLY", {"id": entity_or_subject_id, "operation": operation})

func cache_size() -> int:
	return _artifact_cache.size()

func source_count() -> int:
	return _snapshots.size()

func source_available(source_authority_id: String) -> bool:
	return bool(_source_available.get(source_authority_id, false))

func _select_representation(group: Array, remaining: int) -> Dictionary:
	if group.is_empty():
		return {}
	var fine: Dictionary = {}
	var coarse: Dictionary = {}
	var min_distance := INF
	for item_raw in group:
		var item: Dictionary = Dictionary(item_raw)
		min_distance = minf(min_distance, float(item.get("distance", INF)))
		var rep: Dictionary = Dictionary(item.get("rep", {}))
		if not bool(rep.get("ready", false)):
			continue
		if String(rep.get("lod", "")) == "FINE":
			fine = item
		elif String(rep.get("lod", "")) == "COARSE":
			coarse = item
	var chosen: Dictionary = fine if min_distance <= FINE_DISTANCE_M and not fine.is_empty() else coarse
	if chosen.is_empty():
		chosen = fine
	if chosen.is_empty():
		return {}
	chosen = chosen.duplicate(true)
	chosen["group"] = group.duplicate(true)
	var rep: Dictionary = Dictionary(chosen.get("rep", {}))
	var hash := String(rep.get("artifact_hash", ""))
	var cost := 0 if _artifact_cache.has(hash) else int(rep.get("byte_size", 0))
	if cost > remaining and not coarse.is_empty():
		var fallback := coarse.duplicate(true)
		fallback["group"] = group.duplicate(true)
		return fallback
	return chosen

func _fallback_coarse(group: Array, remaining: int) -> Dictionary:
	for item_raw in group:
		var item: Dictionary = Dictionary(item_raw)
		var rep: Dictionary = Dictionary(item.get("rep", {}))
		if String(rep.get("lod", "")) != "COARSE" or not bool(rep.get("ready", false)):
			continue
		var hash := String(rep.get("artifact_hash", ""))
		var cost := 0 if _artifact_cache.has(hash) else int(rep.get("byte_size", 0))
		if cost <= remaining:
			var result := item.duplicate(true)
			result["group"] = group.duplicate(true)
			return result
	return {}

func _append_cached_degraded_representations(source_id: String, snapshot: Dictionary, client_position: Dictionary, max_distance_m: float, output: Array) -> void:
	var subjects_done: Dictionary = {}
	for raw_rep in Array(snapshot.get("representations", [])):
		var rep: Dictionary = Dictionary(raw_rep)
		if String(rep.get("lod", "")) != "COARSE" or not bool(rep.get("ready", false)):
			continue
		var hash := String(rep.get("artifact_hash", ""))
		if not _artifact_cache.has(hash):
			continue
		var distance := Contract.distance_m(client_position, Dictionary(rep.get("world_position", {})))
		if distance > max_distance_m:
			continue
		var subject_id := String(rep.get("subject_id", ""))
		if subjects_done.has(subject_id):
			continue
		subjects_done[subject_id] = true
		var degraded := rep.duplicate(true)
		degraded["source_authority_id"] = source_id
		degraded["source_role"] = String(snapshot.get("source_role", ""))
		degraded["distance_m"] = distance
		degraded["cache_hit"] = true
		degraded["stale_cached"] = true
		degraded["canonical_write_allowed"] = false
		output.append(degraded)

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}
static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}