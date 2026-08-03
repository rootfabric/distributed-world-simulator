extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const BusUtils = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const StreamPlan = preload("res://scripts/simulation/representation/network/contracts/representation_stream_plan.gd")
const StreamChunk = preload("res://scripts/simulation/representation/network/contracts/representation_stream_chunk.gd")
const StreamAck = preload("res://scripts/simulation/representation/network/contracts/representation_stream_ack.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")

var _maximum_resident_bytes: int = 67108864
var _resident_bytes: int = 0
var _cache_generation: int = 0
var _cache: Dictionary = {}
var _sessions: Dictionary = {}


func configure(maximum_resident_bytes: int) -> Dictionary:
	if maximum_resident_bytes < 1 or maximum_resident_bytes > 1073741824:
		return Utils.failure("INVALID_REPRESENTATION_CLIENT_CACHE_CAPACITY")
	if maximum_resident_bytes < _resident_bytes:
		return Utils.failure("REPRESENTATION_CLIENT_CACHE_CAPACITY_BELOW_RESIDENT")
	_maximum_resident_bytes = maximum_resident_bytes
	return Utils.success({"maximum_resident_bytes": _maximum_resident_bytes})


func preload_cache(manifest: Dictionary, content: PackedByteArray, last_access_tick: int = 0) -> Dictionary:
	var checked: Dictionary = ArtifactManifest.validate(manifest)
	if not bool(checked.get("success", false)):
		return checked
	if content.size() != int(manifest["byte_size"]) or BusUtils.content_hash_from_bytes(content) != String(manifest["artifact_hash"]):
		return Utils.failure("REPRESENTATION_CLIENT_CACHE_CONTENT_MISMATCH")
	var artifact_hash: String = String(manifest["artifact_hash"])
	if _cache.has(artifact_hash):
		if _cache[artifact_hash]["manifest"] == manifest and _cache[artifact_hash]["content"] == content:
			var existing: Dictionary = _cache[artifact_hash]
			existing["last_access_tick"] = last_access_tick
			_cache[artifact_hash] = existing
			return Utils.success({"duplicate": true})
		return Utils.failure("REPRESENTATION_CLIENT_CACHE_HASH_CONFLICT")
	if _resident_bytes + content.size() > _maximum_resident_bytes:
		return Utils.failure("REPRESENTATION_CLIENT_MEMORY_BUDGET_EXCEEDED")
	_cache[artifact_hash] = {
		"manifest": manifest.duplicate(true),
		"content": content.duplicate(),
		"last_access_tick": last_access_tick,
	}
	_resident_bytes += content.size()
	_cache_generation += 1
	return Utils.success({"duplicate": false, "cache_generation": _cache_generation})


func advertised_hashes() -> Array:
	var result: Array = _cache.keys()
	result.sort()
	return result


func accept_plan(plan: Dictionary, required_source_revision_checksum: String, current_tick: int) -> Dictionary:
	var checked: Dictionary = StreamPlan.validate(plan)
	if not bool(checked.get("success", false)):
		return checked
	if String(plan["source_revision_checksum"]) != required_source_revision_checksum:
		return Utils.failure("REPRESENTATION_CLIENT_PLAN_SOURCE_MISMATCH")
	if current_tick > int(plan["expires_tick"]):
		return Utils.failure("REPRESENTATION_CLIENT_PLAN_EXPIRED")
	var missing_bytes: int = 0
	var stage_states: Array = []
	for stage in plan["stages"]:
		var manifest: Dictionary = stage["artifact_manifest"]
		var artifact_hash: String = String(manifest["artifact_hash"])
		var cache_hit: bool = String(stage["delivery_mode"]) == "CACHE_HIT"
		if cache_hit and not _cache_entry_matches(artifact_hash, manifest):
			return Utils.failure("REPRESENTATION_CLIENT_ADVERTISED_CACHE_MISS", {"artifact_hash": artifact_hash})
		if not cache_hit:
			missing_bytes += int(manifest["byte_size"])
		stage_states.append({
			"buffer": PackedByteArray(),
			"next_chunk_index": 0,
			"next_offset": 0,
			"ready": false,
			"received_chunks": 0,
		})
	if _resident_bytes + missing_bytes > _maximum_resident_bytes:
		return Utils.failure("REPRESENTATION_CLIENT_MEMORY_BUDGET_EXCEEDED", {
			"resident_bytes": _resident_bytes,
			"missing_bytes": missing_bytes,
		})
	var stream_id: String = String(plan["stream_id"])
	var session: Dictionary = {
		"plan": plan.duplicate(true),
		"stage_states": stage_states,
		"status": "ACTIVE",
		"current_stage_index": -1,
	}
	var activated: Dictionary = _activate_available_cache_hits(session)
	session = activated["session"]
	_sessions[stream_id] = session
	return Utils.success({
		"stream_id": stream_id,
		"status": session["status"],
		"initial_acks": activated["acks"],
	})


func receive_chunk(chunk: Dictionary, current_tick: int) -> Dictionary:
	var checked: Dictionary = StreamChunk.validate(chunk)
	if not bool(checked.get("success", false)):
		return checked
	var stream_id: String = String(chunk["stream_id"])
	if not _sessions.has(stream_id):
		return Utils.failure("REPRESENTATION_CLIENT_STREAM_NOT_FOUND")
	var session: Dictionary = _sessions[stream_id]
	if String(session["status"]) in ["CANCELLED", "STALE", "FAILED"]:
		return Utils.failure("REPRESENTATION_CLIENT_STREAM_NOT_ACTIVE", {"status": session["status"]})
	var plan: Dictionary = session["plan"]
	if String(chunk["stream_request_id"]) != String(plan["stream_request_id"]) or int(chunk["request_revision"]) != int(plan["request_revision"]):
		return Utils.failure("REPRESENTATION_CLIENT_CHUNK_REQUEST_MISMATCH")
	var stage_index: int = int(chunk["stage_index"])
	if stage_index < 0 or stage_index >= plan["stages"].size():
		return Utils.failure("REPRESENTATION_CLIENT_CHUNK_STAGE_OUT_OF_RANGE")
	if stage_index > 0 and not bool(session["stage_states"][stage_index - 1]["ready"]):
		return Utils.failure("REPRESENTATION_CLIENT_CHUNK_BEFORE_PREVIOUS_STAGE")
	var stage: Dictionary = plan["stages"][stage_index]
	if String(stage["delivery_mode"]) != "TRANSFER":
		return Utils.failure("REPRESENTATION_CLIENT_CHUNK_FOR_CACHE_HIT")
	var manifest: Dictionary = stage["artifact_manifest"]
	if String(chunk["artifact_hash"]) != String(manifest["artifact_hash"]) or String(chunk["manifest_checksum"]) != String(manifest["checksum"]):
		return Utils.failure("REPRESENTATION_CLIENT_CHUNK_ARTIFACT_MISMATCH")
	var state: Dictionary = session["stage_states"][stage_index]
	if int(chunk["chunk_index"]) != int(state["next_chunk_index"]) or int(chunk["offset_bytes"]) != int(state["next_offset"]):
		return Utils.failure("REPRESENTATION_CLIENT_CHUNK_SEQUENCE_GAP")
	var bytes: PackedByteArray = StreamChunk.content_bytes(chunk)
	if int(state["next_offset"]) + bytes.size() > int(manifest["byte_size"]):
		return Utils.failure("REPRESENTATION_CLIENT_CHUNK_OVERRUN")
	state["buffer"].append_array(bytes)
	state["next_offset"] = int(state["next_offset"]) + bytes.size()
	state["next_chunk_index"] = int(state["next_chunk_index"]) + 1
	state["received_chunks"] = int(state["received_chunks"]) + 1
	var expected_final: bool = int(state["next_offset"]) == int(manifest["byte_size"])
	if bool(chunk["final_chunk"]) != expected_final:
		return Utils.failure("REPRESENTATION_CLIENT_FINAL_CHUNK_FLAG_MISMATCH")
	var status: String = "RECEIVING"
	if expected_final:
		if BusUtils.content_hash_from_bytes(state["buffer"]) != String(manifest["artifact_hash"]):
			session["status"] = "FAILED"
			_sessions[stream_id] = session
			return Utils.failure("REPRESENTATION_CLIENT_ARTIFACT_HASH_MISMATCH")
		var stored: Dictionary = preload_cache(manifest, state["buffer"], current_tick)
		if not bool(stored.get("success", false)):
			session["status"] = "FAILED"
			_sessions[stream_id] = session
			return stored
		state["ready"] = true
		status = "STREAM_READY" if stage_index == int(plan["final_stage_index"]) else "STAGE_READY"
		session["current_stage_index"] = stage_index
	session["stage_states"][stage_index] = state
	var ack: Dictionary = StreamAck.create(
		stream_id,
		String(plan["stream_request_id"]),
		int(plan["request_revision"]),
		stage_index,
		String(manifest["artifact_hash"]),
		int(state["next_offset"]),
		int(state["received_chunks"]),
		status,
		_cache_generation
	)
	var acknowledgements: Array = [ack]
	if expected_final:
		var activated: Dictionary = _activate_available_cache_hits(session)
		session = activated["session"]
		acknowledgements.append_array(activated["acks"] as Array)
	if _all_stages_ready(session["stage_states"]):
		session["status"] = "READY"
	_sessions[stream_id] = session
	return Utils.success({"ack": ack, "acks": acknowledgements, "status": session["status"], "presentation_manifest": current_manifest(stream_id)})


func apply_invalidation(invalidation: Dictionary) -> Dictionary:
	var checked: Dictionary = Invalidation.validate(invalidation)
	if not bool(checked.get("success", false)):
		return checked
	var previous_checksum: String = String(invalidation["previous_source_revision"]["checksum"])
	var affected_scopes: Array = invalidation["affected_scope_ids"]
	var stale_streams: Array = []
	for stream_id in _sessions.keys():
		var session: Dictionary = _sessions[stream_id]
		if String(session["plan"]["source_revision_checksum"]) != previous_checksum:
			continue
		if not _plan_intersects_scopes(session["plan"], affected_scopes):
			continue
		session["status"] = "STALE"
		session["current_stage_index"] = -1
		_sessions[stream_id] = session
		stale_streams.append(String(stream_id))
	stale_streams.sort()
	return Utils.success({"stale_stream_ids": stale_streams})


func current_manifest(stream_id: String) -> Dictionary:
	if not _sessions.has(stream_id):
		return {}
	var session: Dictionary = _sessions[stream_id]
	var index: int = int(session["current_stage_index"])
	if index < 0:
		return {}
	return session["plan"]["stages"][index]["artifact_manifest"].duplicate(true)


func session_snapshot(stream_id: String) -> Dictionary:
	return _sessions[stream_id].duplicate(true) if _sessions.has(stream_id) else {}


func export_cache() -> Array:
	var hashes: Array = _cache.keys()
	hashes.sort()
	var result: Array = []
	for artifact_hash in hashes:
		var entry: Dictionary = _cache[artifact_hash]
		result.append({
			"manifest": entry["manifest"].duplicate(true),
			"content_base64": Marshalls.raw_to_base64(entry["content"]),
			"last_access_tick": int(entry["last_access_tick"]),
		})
	return result


func import_cache(entries: Array) -> Dictionary:
	for index in range(entries.size()):
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_REPRESENTATION_CLIENT_CACHE_EXPORT", {"index": index})
		var entry: Dictionary = entries[index]
		if typeof(entry.get("manifest")) != TYPE_DICTIONARY or typeof(entry.get("content_base64")) != TYPE_STRING:
			return Utils.failure("INVALID_REPRESENTATION_CLIENT_CACHE_EXPORT", {"index": index})
		var stored: Dictionary = preload_cache(
			entry["manifest"],
			Marshalls.base64_to_raw(String(entry["content_base64"])),
			int(entry.get("last_access_tick", 0))
		)
		if not bool(stored.get("success", false)):
			return stored
	return Utils.success({"cache_generation": _cache_generation})


func cache_generation() -> int:
	return _cache_generation


func resident_bytes() -> int:
	return _resident_bytes


func _cache_entry_matches(artifact_hash: String, manifest: Dictionary) -> bool:
	if not _cache.has(artifact_hash):
		return false
	var entry: Dictionary = _cache[artifact_hash]
	return entry["manifest"] == manifest \
		and entry["content"].size() == int(manifest["byte_size"]) \
		and BusUtils.content_hash_from_bytes(entry["content"]) == artifact_hash


func _activate_available_cache_hits(session: Dictionary) -> Dictionary:
	var result_acks: Array = []
	var plan: Dictionary = session["plan"]
	for index in range(plan["stages"].size()):
		var state: Dictionary = session["stage_states"][index]
		if bool(state["ready"]):
			continue
		if index > 0 and not bool(session["stage_states"][index - 1]["ready"]):
			break
		var stage: Dictionary = plan["stages"][index]
		if String(stage["delivery_mode"]) != "CACHE_HIT":
			break
		state["ready"] = true
		session["stage_states"][index] = state
		session["current_stage_index"] = index
		var status: String = "STREAM_READY" if index == int(plan["final_stage_index"]) else "STAGE_READY"
		result_acks.append(StreamAck.create(
			String(plan["stream_id"]),
			String(plan["stream_request_id"]),
			int(plan["request_revision"]),
			index,
			String(stage["artifact_manifest"]["artifact_hash"]),
			0, 0, status, _cache_generation
		))
	if _all_stages_ready(session["stage_states"]):
		session["status"] = "READY"
	return {"session": session, "acks": result_acks}


func _all_stages_ready(states: Array) -> bool:
	for state in states:
		if not bool(state["ready"]):
			return false
	return true


func _highest_ready_stage(states: Array) -> int:
	var result: int = -1
	for index in range(states.size()):
		if not bool(states[index]["ready"]):
			break
		result = index
	return result


func _plan_intersects_scopes(plan: Dictionary, scopes: Array) -> bool:
	for stage in plan["stages"]:
		if scopes.has(String(stage["artifact_manifest"]["representation_key"]["scope_id"])):
			return true
	return false
