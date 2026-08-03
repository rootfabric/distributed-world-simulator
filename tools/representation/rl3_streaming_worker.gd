extends SceneTree

const ArtifactStore = preload("res://scripts/simulation/representation/network/representation_artifact_store.gd")
const StreamServer = preload("res://scripts/simulation/representation/network/representation_stream_server.gd")
const StreamClient = preload("res://scripts/simulation/representation/network/representation_stream_client.gd")
const StreamAck = preload("res://scripts/simulation/representation/network/contracts/representation_stream_ack.gd")


func _init() -> void:
	var options: Dictionary = _options()
	var mode: String = String(options.get("mode", ""))
	var input_path: String = String(options.get("input", ""))
	var output_path: String = String(options.get("output", ""))
	var input: Dictionary = _read_json(input_path)
	if input.is_empty():
		_write_json(output_path, {"passed": false, "error": "INVALID_INPUT"})
		quit(2)
		return
	var result: Dictionary = {}
	match mode:
		"server":
			result = _run_server(input)
		"client":
			result = _run_client(input)
		_:
			result = {"passed": false, "error": "INVALID_MODE"}
	var written: bool = _write_json(output_path, result)
	quit(0 if written and bool(result.get("passed", false)) else 3)


func _run_server(input: Dictionary) -> Dictionary:
	var store := ArtifactStore.new()
	var configured: Dictionary = store.configure(1048576)
	if not bool(configured.get("success", false)):
		return {"passed": false, "error": configured.get("error_code", "STORE_CONFIGURE")}
	for raw_artifact in Array(input.get("artifacts", [])):
		if typeof(raw_artifact) != TYPE_DICTIONARY:
			return {"passed": false, "error": "INVALID_ARTIFACT"}
		var artifact: Dictionary = raw_artifact
		var registered: Dictionary = store.register(
			Dictionary(artifact.get("manifest", {})),
			Marshalls.base64_to_raw(String(artifact.get("content_base64", "")))
		)
		if not bool(registered.get("success", false)):
			return {"passed": false, "error": registered.get("error_code", "REGISTER_FAILED")}
	var server := StreamServer.new()
	configured = server.configure(store)
	if not bool(configured.get("success", false)):
		return {"passed": false, "error": configured.get("error_code", "SERVER_CONFIGURE")}
	var opened: Dictionary = server.open_stream(
		Dictionary(input.get("request", {})), Array(input.get("manifests", [])), 100, 200
	)
	if not bool(opened.get("success", false)):
		return {"passed": false, "error": opened.get("error_code", "OPEN_FAILED")}
	var plan: Dictionary = opened["details"]["plan"]
	var stream_id: String = String(plan["stream_id"])
	for stage_index in range(plan["stages"].size()):
		var cache_stage: Dictionary = plan["stages"][stage_index]
		if String(cache_stage["delivery_mode"]) != "CACHE_HIT":
			break
		var cache_status: String = "STREAM_READY" if stage_index == int(plan["final_stage_index"]) else "STAGE_READY"
		var cache_ack: Dictionary = StreamAck.create(
			stream_id, String(plan["stream_request_id"]), int(plan["request_revision"]),
			stage_index, String(cache_stage["artifact_manifest"]["artifact_hash"]),
			0, 0, cache_status, 1
		)
		var cache_acknowledged: Dictionary = server.acknowledge(cache_ack)
		if not bool(cache_acknowledged.get("success", false)):
			return {"passed": false, "error": cache_acknowledged.get("error_code", "CACHE_ACK_FAILED")}
	var chunks: Array = []
	var guard: int = 0
	while String(server.session_snapshot(stream_id).get("status", "")) != "READY" and guard < 128:
		guard += 1
		var batch: Dictionary = server.next_chunks(stream_id, 8, 100 + guard)
		if not bool(batch.get("success", false)):
			return {"passed": false, "error": batch.get("error_code", "BATCH_FAILED")}
		var emitted: Array = batch["details"]["chunks"]
		if emitted.is_empty():
			return {"passed": false, "error": "STREAM_STALLED"}
		for chunk in emitted:
			chunks.append(chunk)
			var stage_index: int = int(chunk["stage_index"])
			var stage: Dictionary = plan["stages"][stage_index]
			var end_offset: int = int(chunk["offset_bytes"]) + int(chunk["chunk_size_bytes"])
			var received_chunks: int = int(chunk["chunk_index"]) + 1
			var status: String = "RECEIVING"
			if bool(chunk["final_chunk"]):
				status = "STREAM_READY" if stage_index == int(plan["final_stage_index"]) else "STAGE_READY"
			var ack: Dictionary = StreamAck.create(
				stream_id, String(plan["stream_request_id"]), int(plan["request_revision"]),
				stage_index, String(stage["artifact_manifest"]["artifact_hash"]),
				end_offset, received_chunks, status, 0
			)
			var acknowledged: Dictionary = server.acknowledge(ack)
			if not bool(acknowledged.get("success", false)):
				return {"passed": false, "error": acknowledged.get("error_code", "ACK_FAILED")}
	return {
		"passed": guard < 128 and String(server.session_snapshot(stream_id).get("status", "")) == "READY",
		"plan": plan,
		"chunks": chunks,
		"server_status": String(server.session_snapshot(stream_id).get("status", "")),
		"store_bytes": store.total_bytes(),
	}


func _run_client(input: Dictionary) -> Dictionary:
	var client := StreamClient.new()
	var configured: Dictionary = client.configure(1048576)
	if not bool(configured.get("success", false)):
		return {"passed": false, "error": configured.get("error_code", "CLIENT_CONFIGURE")}
	var imported: Dictionary = client.import_cache(Array(input.get("cache_entries", [])))
	if not bool(imported.get("success", false)):
		return {"passed": false, "error": imported.get("error_code", "CACHE_IMPORT")}
	var plan: Dictionary = Dictionary(input.get("plan", {}))
	var accepted: Dictionary = client.accept_plan(plan, String(input.get("source_checksum", "")), 100)
	if not bool(accepted.get("success", false)):
		return {"passed": false, "error": accepted.get("error_code", "PLAN_ACCEPT")}
	for chunk in Array(input.get("chunks", [])):
		var received: Dictionary = client.receive_chunk(chunk, 101)
		if not bool(received.get("success", false)):
			return {"passed": false, "error": received.get("error_code", "CHUNK_RECEIVE")}
	var stream_id: String = String(plan["stream_id"])
	var session: Dictionary = client.session_snapshot(stream_id)
	var current: Dictionary = client.current_manifest(stream_id)
	return {
		"passed": String(session.get("status", "")) == "READY",
		"client_status": String(session.get("status", "")),
		"current_lod": int(current.get("representation_key", {}).get("lod_level", -1)),
		"advertised_hashes": client.advertised_hashes(),
		"cache_entries": client.export_cache(),
		"cache_generation": client.cache_generation(),
		"resident_bytes": client.resident_bytes(),
		"initial_ack_count": Array(accepted["details"].get("initial_acks", [])).size(),
	}


func _options() -> Dictionary:
	var result: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
		result[parts[0]] = parts[1]
	return result


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_json(path: String, value: Dictionary) -> bool:
	if path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", false, true))
	file.flush()
	var error: int = file.get_error()
	file.close()
	return error == OK
