extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const StreamRequest = preload("res://scripts/simulation/representation/network/contracts/representation_stream_request.gd")
const StreamPlan = preload("res://scripts/simulation/representation/network/contracts/representation_stream_plan.gd")
const StreamChunk = preload("res://scripts/simulation/representation/network/contracts/representation_stream_chunk.gd")
const StreamAck = preload("res://scripts/simulation/representation/network/contracts/representation_stream_ack.gd")
const Cancellation = preload("res://scripts/simulation/representation/network/contracts/representation_stream_cancellation.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Planner = preload("res://scripts/simulation/representation/network/representation_stream_planner.gd")

var _store = null
var _sessions: Dictionary = {}
var _request_to_stream: Dictionary = {}
var _observer_revisions: Dictionary = {}


func configure(artifact_store) -> Dictionary:
	if artifact_store == null or not artifact_store.has_method("has") or not artifact_store.has_method("content"):
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_STORE")
	_store = artifact_store
	return Utils.success()


func open_stream(request: Dictionary, manifests: Array, created_tick: int, lifetime_ticks: int = 600) -> Dictionary:
	if _store == null:
		return Utils.failure("REPRESENTATION_STREAM_SERVER_NOT_CONFIGURED")
	var checked: Dictionary = StreamRequest.validate(request)
	if not bool(checked.get("success", false)):
		return checked
	var interest: Dictionary = request["interest_request"]
	var observer_id: String = String(interest["observer_id"])
	var revision: int = int(interest["request_revision"])
	if _observer_revisions.has(observer_id):
		var current: Dictionary = _observer_revisions[observer_id]
		if revision < int(current["revision"]):
			return Utils.failure("REPRESENTATION_STREAM_REQUEST_REVISION_ROLLBACK")
		if revision == int(current["revision"]):
			if String(current["request_checksum"]) == String(request["checksum"]):
				var existing_id: String = String(current["stream_id"])
				return Utils.success({"plan": _sessions[existing_id]["plan"].duplicate(true), "duplicate": true})
			return Utils.failure("REPRESENTATION_STREAM_REQUEST_REVISION_CONFLICT")
		_cancel_stream(String(current["stream_id"]), "REPLACED")
	var planned: Dictionary = Planner.build_plan(request, manifests, created_tick, lifetime_ticks)
	if not bool(planned.get("success", false)):
		return planned
	var plan: Dictionary = planned["details"]["plan"]
	checked = StreamPlan.validate(plan)
	if not bool(checked.get("success", false)):
		return checked
	for stage in plan["stages"]:
		if String(stage["delivery_mode"]) == "TRANSFER":
			var manifest: Dictionary = stage["artifact_manifest"]
			var artifact_hash: String = String(manifest["artifact_hash"])
			if not _store.has(artifact_hash):
				return Utils.failure("REPRESENTATION_STREAM_ARTIFACT_NOT_RESIDENT", {"artifact_hash": artifact_hash})
			if _store.manifest(artifact_hash) != manifest:
				return Utils.failure("REPRESENTATION_STREAM_ARTIFACT_MANIFEST_CONFLICT", {"artifact_hash": artifact_hash})
	var stage_states: Array = []
	for stage in plan["stages"]:
		stage_states.append({
			"sent_bytes": 0,
			"sent_chunks": 0,
			"acked_bytes": 0,
			"acked_chunks": 0,
			"ready": false,
		})
	var stream_id: String = String(plan["stream_id"])
	_sessions[stream_id] = {
		"request": request.duplicate(true),
		"plan": plan.duplicate(true),
		"stage_states": stage_states,
		"status": "READY" if _all_stages_ready(stage_states) else "ACTIVE",
		"cancellation_generation": int(request["cancellation_generation"]),
		"cancel_reason": "",
	}
	_request_to_stream[String(request["stream_request_id"])] = stream_id
	_observer_revisions[observer_id] = {
		"revision": revision,
		"request_checksum": String(request["checksum"]),
		"stream_id": stream_id,
	}
	return Utils.success({"plan": plan.duplicate(true), "duplicate": false})


func next_chunks(stream_id: String, maximum_chunks: int, current_tick: int) -> Dictionary:
	if not _sessions.has(stream_id):
		return Utils.failure("REPRESENTATION_STREAM_NOT_FOUND")
	if maximum_chunks < 1 or maximum_chunks > 256:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_BATCH")
	var session: Dictionary = _sessions[stream_id]
	if String(session["status"]) in ["CANCELLED", "STALE"]:
		return Utils.failure("REPRESENTATION_STREAM_NOT_ACTIVE", {"status": session["status"]})
	var plan: Dictionary = session["plan"]
	if current_tick > int(plan["expires_tick"]):
		session["status"] = "CANCELLED"
		session["cancel_reason"] = "EXPIRED"
		_sessions[stream_id] = session
		return Utils.failure("REPRESENTATION_STREAM_EXPIRED")
	if String(session["status"]) == "READY":
		return Utils.success({"chunks": [], "stream_ready": true, "in_flight_bytes": 0})
	var request: Dictionary = session["request"]
	var in_flight_limit: int = int(request["maximum_in_flight_bytes"])
	var chunks: Array = []
	for stage_index in range(plan["stages"].size()):
		var stage: Dictionary = plan["stages"][stage_index]
		var state: Dictionary = session["stage_states"][stage_index]
		if bool(state["ready"]):
			continue
		if stage_index > 0 and not bool(session["stage_states"][stage_index - 1]["ready"]):
			break
		if String(stage["delivery_mode"]) == "CACHE_HIT":
			break
		var artifact_hash: String = String(stage["artifact_manifest"]["artifact_hash"])
		var content: PackedByteArray = _store.content(artifact_hash)
		while chunks.size() < maximum_chunks and int(state["sent_bytes"]) < content.size():
			var in_flight: int = int(state["sent_bytes"]) - int(state["acked_bytes"])
			var remaining: int = content.size() - int(state["sent_bytes"])
			var chunk_size: int = mini(int(stage["chunk_size_bytes"]), remaining)
			if in_flight + chunk_size > in_flight_limit:
				break
			var offset: int = int(state["sent_bytes"])
			var payload: PackedByteArray = content.slice(offset, offset + chunk_size)
			var chunk: Dictionary = StreamChunk.create(
				stream_id,
				String(plan["stream_request_id"]),
				int(plan["request_revision"]),
				stage_index,
				artifact_hash,
				String(stage["artifact_manifest"]["checksum"]),
				int(state["sent_chunks"]),
				offset,
				payload,
				offset + chunk_size == content.size()
			)
			if chunk.is_empty():
				return Utils.failure("REPRESENTATION_STREAM_CHUNK_BUILD_FAILED")
			chunks.append(chunk)
			state["sent_bytes"] = offset + chunk_size
			state["sent_chunks"] = int(state["sent_chunks"]) + 1
		if chunks.size() >= maximum_chunks or int(state["sent_bytes"]) - int(state["acked_bytes"]) >= in_flight_limit:
			session["stage_states"][stage_index] = state
			break
		session["stage_states"][stage_index] = state
		break
	_sessions[stream_id] = session
	return Utils.success({
		"chunks": chunks,
		"stream_ready": String(session["status"]) == "READY",
		"in_flight_bytes": _session_in_flight(session),
	})


func acknowledge(ack: Dictionary) -> Dictionary:
	var checked: Dictionary = StreamAck.validate(ack)
	if not bool(checked.get("success", false)):
		return checked
	var stream_id: String = String(ack["stream_id"])
	if not _sessions.has(stream_id):
		return Utils.failure("REPRESENTATION_STREAM_NOT_FOUND")
	var session: Dictionary = _sessions[stream_id]
	var plan: Dictionary = session["plan"]
	if String(ack["stream_request_id"]) != String(plan["stream_request_id"]) or int(ack["request_revision"]) != int(plan["request_revision"]):
		return Utils.failure("REPRESENTATION_STREAM_ACK_REQUEST_MISMATCH")
	var stage_index: int = int(ack["stage_index"])
	if stage_index < 0 or stage_index >= plan["stages"].size():
		return Utils.failure("REPRESENTATION_STREAM_ACK_STAGE_OUT_OF_RANGE")
	var stage: Dictionary = plan["stages"][stage_index]
	var manifest: Dictionary = stage["artifact_manifest"]
	if String(ack["artifact_hash"]) != String(manifest["artifact_hash"]):
		return Utils.failure("REPRESENTATION_STREAM_ACK_ARTIFACT_MISMATCH")
	var state: Dictionary = session["stage_states"][stage_index]
	if int(ack["received_contiguous_bytes"]) < int(state["acked_bytes"]) or int(ack["received_chunks"]) < int(state["acked_chunks"]):
		return Utils.failure("REPRESENTATION_STREAM_ACK_ROLLBACK")
	if int(ack["received_contiguous_bytes"]) > int(state["sent_bytes"]) or int(ack["received_chunks"]) > int(state["sent_chunks"]):
		return Utils.failure("REPRESENTATION_STREAM_ACK_AHEAD_OF_SEND")
	var ready_status: bool = String(ack["status"]) in ["STAGE_READY", "STREAM_READY"]
	if String(ack["status"]) == "STREAM_READY" and stage_index != int(plan["final_stage_index"]):
		return Utils.failure("REPRESENTATION_STREAM_ACK_PREMATURE_STREAM_READY")
	if String(ack["status"]) == "STAGE_READY" and stage_index == int(plan["final_stage_index"]):
		return Utils.failure("REPRESENTATION_STREAM_FINAL_ACK_NOT_STREAM_READY")
	if ready_status and stage_index > 0 and not bool(session["stage_states"][stage_index - 1]["ready"]):
		return Utils.failure("REPRESENTATION_STREAM_ACK_BEFORE_PREVIOUS_STAGE")
	if String(stage["delivery_mode"]) == "CACHE_HIT":
		if int(ack["received_contiguous_bytes"]) != 0 or int(ack["received_chunks"]) != 0:
			return Utils.failure("REPRESENTATION_CACHE_HIT_ACK_HAS_TRANSFER")
	else:
		if ready_status and int(ack["received_contiguous_bytes"]) != int(manifest["byte_size"]):
			return Utils.failure("REPRESENTATION_STREAM_READY_ACK_INCOMPLETE")
	state["acked_bytes"] = int(ack["received_contiguous_bytes"])
	state["acked_chunks"] = int(ack["received_chunks"])
	if ready_status:
		state["ready"] = true
	session["stage_states"][stage_index] = state
	if String(ack["status"]) in ["CANCELLED", "STALE", "FAILED"]:
		session["status"] = String(ack["status"])
	elif _all_stages_ready(session["stage_states"]):
		session["status"] = "READY"
	_sessions[stream_id] = session
	return Utils.success({"status": session["status"], "in_flight_bytes": _session_in_flight(session)})


func cancel(cancellation: Dictionary) -> Dictionary:
	var checked: Dictionary = Cancellation.validate(cancellation)
	if not bool(checked.get("success", false)):
		return checked
	var request_id: String = String(cancellation["stream_request_id"])
	if not _request_to_stream.has(request_id):
		return Utils.failure("REPRESENTATION_STREAM_NOT_FOUND")
	var stream_id: String = String(_request_to_stream[request_id])
	var session: Dictionary = _sessions[stream_id]
	if int(cancellation["request_revision"]) != int(session["plan"]["request_revision"]):
		return Utils.failure("REPRESENTATION_STREAM_CANCELLATION_REVISION_MISMATCH")
	if int(cancellation["cancellation_generation"]) <= int(session["cancellation_generation"]):
		return Utils.failure("REPRESENTATION_STREAM_CANCELLATION_NOT_ADVANCED")
	session["cancellation_generation"] = int(cancellation["cancellation_generation"])
	session["status"] = "CANCELLED"
	session["cancel_reason"] = String(cancellation["reason"])
	_sessions[stream_id] = session
	return Utils.success({"stream_id": stream_id})


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
		session["cancel_reason"] = "STALE_SOURCE"
		_sessions[stream_id] = session
		stale_streams.append(String(stream_id))
	stale_streams.sort()
	return Utils.success({"stale_stream_ids": stale_streams})


func session_snapshot(stream_id: String) -> Dictionary:
	return _sessions[stream_id].duplicate(true) if _sessions.has(stream_id) else {}


func _cancel_stream(stream_id: String, reason: String) -> void:
	if not _sessions.has(stream_id):
		return
	var session: Dictionary = _sessions[stream_id]
	session["status"] = "CANCELLED"
	session["cancel_reason"] = reason
	_sessions[stream_id] = session


func _all_stages_ready(states: Array) -> bool:
	for state in states:
		if not bool(state["ready"]):
			return false
	return true


func _session_in_flight(session: Dictionary) -> int:
	var result: int = 0
	for state in session["stage_states"]:
		result += int(state["sent_bytes"]) - int(state["acked_bytes"])
	return result


func _plan_intersects_scopes(plan: Dictionary, scopes: Array) -> bool:
	for stage in plan["stages"]:
		if scopes.has(String(stage["artifact_manifest"]["representation_key"]["scope_id"])):
			return true
	return false
