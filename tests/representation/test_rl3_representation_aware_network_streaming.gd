extends SceneTree

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const BusUtils = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const InterestRequest = preload("res://scripts/simulation/representation/contracts/representation_interest_request.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const StreamRequest = preload("res://scripts/simulation/representation/network/contracts/representation_stream_request.gd")
const ScopeBinding = preload("res://scripts/simulation/representation/network/contracts/representation_stream_scope_binding.gd")
const StreamStage = preload("res://scripts/simulation/representation/network/contracts/representation_stream_stage.gd")
const StreamPlan = preload("res://scripts/simulation/representation/network/contracts/representation_stream_plan.gd")
const StreamChunk = preload("res://scripts/simulation/representation/network/contracts/representation_stream_chunk.gd")
const StreamAck = preload("res://scripts/simulation/representation/network/contracts/representation_stream_ack.gd")
const Cancellation = preload("res://scripts/simulation/representation/network/contracts/representation_stream_cancellation.gd")
const ArtifactStore = preload("res://scripts/simulation/representation/network/representation_artifact_store.gd")
const Planner = preload("res://scripts/simulation/representation/network/representation_stream_planner.gd")
const StreamServer = preload("res://scripts/simulation/representation/network/representation_stream_server.gd")
const StreamClient = preload("res://scripts/simulation/representation/network/representation_stream_client.gd")
const MatterInterestAdapter = preload("res://scripts/simulation/representation/network/matter_representation_interest_adapter.gd")
const MatterSubscription = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")

var assertions: int = 0
var failures: Array[String] = []
var source: Dictionary = {}
var next_source: Dictionary = {}
var manifests: Array = []
var contents: Dictionary = {}


func _init() -> void:
	_build_fixture()
	_test_config()
	_test_contracts()
	_test_planner()
	_test_progressive_transfer_and_backpressure()
	_test_cache_reconnect()
	_test_cancellation_and_replacement()
	_test_invalidation_fencing()
	_test_budget_and_corruption_fences()
	_finish()


func _build_fixture() -> void:
	source = SourceRevision.create(
		"MATTER", "body/asteroid-rl3", 7, 19,
		_hash("rl3-source-19"), _hash("rl3-dependencies-19")
	)
	next_source = SourceRevision.create(
		"MATTER", "body/asteroid-rl3", 7, 20,
		_hash("rl3-source-20"), _hash("rl3-dependencies-20")
	)
	_assert_ok(SourceRevision.validate(source), "RL3 source rejected")
	_assert_ok(SourceRevision.validate(next_source), "RL3 next source rejected")
	var fixtures: Array = [
		{"scope": "region/rl3-macro", "lod": 2, "kind": "MACRO_PROXY", "error": 1.0, "size": 96, "fill": "M"},
		{"scope": "region/rl3-regional", "lod": 1, "kind": "SIMPLIFIED_MESH", "error": 0.2, "size": 160, "fill": "S"},
		{"scope": "region/rl3-detail", "lod": 0, "kind": "DETAIL", "error": 0.0, "size": 256, "fill": "D"},
	]
	for fixture in fixtures:
		var content: PackedByteArray = String(fixture["fill"]).repeat(int(fixture["size"])).to_utf8_buffer()
		var artifact_hash: String = BusUtils.content_hash_from_bytes(content)
		var key: Dictionary = RepresentationKey.create(
			source, String(fixture["scope"]), int(fixture["lod"]), String(fixture["kind"]), "representation-variant/surface-default"
		)
		var manifest: Dictionary = ArtifactManifest.create(
			key, artifact_hash, content.size(), "RAW", "application/vnd.planet-simulator.matter-mesh",
			float(fixture["error"]), [-64.0, -64.0, -64.0, 64.0, 64.0, 64.0],
			int(fixture["lod"]) == 0, int(fixture["lod"]) <= 1, 4
		)
		_assert_ok(ArtifactManifest.validate(manifest), "RL3 artifact manifest rejected")
		manifests.append(manifest)
		contents[artifact_hash] = content


func _test_config() -> void:
	var path := "res://config/representation/representation-aware-network-streaming.v1.json"
	_assert(FileAccess.file_exists(path), "RL3 config missing")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_assert(typeof(parsed) == TYPE_DICTIONARY, "RL3 config invalid JSON")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_assert(String(parsed.get("checkpoint", "")) == "v17.14.0-simulation-rl3-representation-aware-network-streaming", "RL3 checkpoint changed")
	_assert(String(parsed.get("build_id", "")) == "rl3-representation-aware-network-artifact-streaming", "RL3 build id changed")
	_assert(bool(parsed.get("progressive_coarse_first", false)), "RL3 progressive loading disabled")
	_assert(bool(parsed.get("content_addressed_transfer", false)), "RL3 content addressed transfer disabled")
	_assert(not bool(parsed.get("canonical_matter_changed", true)), "RL3 changes canonical Matter")
	_assert(not bool(parsed.get("production_transport_added", true)), "RL3 unexpectedly adds production transport")


func _test_contracts() -> void:
	var interest: Dictionary = _interest(1, 512)
	var request: Dictionary = _request(interest, [], 0, true)
	_assert_ok(InterestRequest.validate(interest), "RL3 interest request rejected")
	_assert_ok(StreamRequest.validate(request), "RL3 stream request rejected")
	var bad_hashes: Dictionary = request.duplicate(true)
	var unsorted_hashes: Array = [_hash("z"), _hash("a")]
	unsorted_hashes.sort()
	unsorted_hashes.reverse()
	bad_hashes["cached_artifact_hashes"] = unsorted_hashes
	bad_hashes["checksum"] = Utils.compute_checksum(bad_hashes)
	_assert_fail(StreamRequest.validate(bad_hashes), "Unsorted cache hashes accepted")
	var bad_bootstrap: Dictionary = request.duplicate(true)
	bad_bootstrap["maximum_bootstrap_screen_error_px"] = 1.0
	bad_bootstrap["checksum"] = Utils.compute_checksum(bad_bootstrap)
	_assert_fail(StreamRequest.validate(bad_bootstrap), "Bootstrap budget below final accepted")
	var bad_encoding: Dictionary = request.duplicate(true)
	bad_encoding["supported_encodings"] = ["RAW", "PNG"]
	bad_encoding["checksum"] = Utils.compute_checksum(bad_encoding)
	_assert_fail(StreamRequest.validate(bad_encoding), "Unsorted encodings accepted")
	var bad_scope_chain: Dictionary = request.duplicate(true)
	bad_scope_chain["scope_chain"].reverse()
	bad_scope_chain["checksum"] = Utils.compute_checksum(bad_scope_chain)
	_assert_fail(StreamRequest.validate(bad_scope_chain), "Fine-to-coarse scope chain accepted")
	var stage: Dictionary = StreamStage.create(0, manifests[0], "TRANSFER", 64)
	_assert_ok(StreamStage.validate(stage), "RL3 stream stage rejected")
	_assert(int(stage["total_chunks"]) == 2, "RL3 chunk count changed")
	var cache_stage: Dictionary = StreamStage.create(0, manifests[0], "CACHE_HIT", 0)
	_assert_ok(StreamStage.validate(cache_stage), "RL3 cache-hit stage rejected")
	_assert(int(cache_stage["transfer_bytes"]) == 0, "Cache-hit transfer bytes changed")
	var bad_cache_stage: Dictionary = cache_stage.duplicate(true)
	bad_cache_stage["total_chunks"] = 1
	bad_cache_stage["checksum"] = Utils.compute_checksum(bad_cache_stage)
	_assert_fail(StreamStage.validate(bad_cache_stage), "Cache-hit transfer metadata accepted")
	var sample: PackedByteArray = "chunk-data".to_utf8_buffer()
	var chunk: Dictionary = StreamChunk.create(
		"stream/contracts", "stream-request/contracts", 1, 0,
		String(manifests[0]["artifact_hash"]), String(manifests[0]["checksum"]),
		0, 0, sample, true
	)
	_assert_ok(StreamChunk.validate(chunk), "RL3 chunk rejected")
	_assert(StreamChunk.content_bytes(chunk) == sample, "RL3 chunk bytes changed")
	var tampered_chunk: Dictionary = chunk.duplicate(true)
	tampered_chunk["content_hash"] = _hash("tampered")
	tampered_chunk["checksum"] = Utils.compute_checksum(tampered_chunk)
	_assert_fail(StreamChunk.validate(tampered_chunk), "Tampered chunk hash accepted")
	var ack: Dictionary = StreamAck.create(
		"stream/contracts", "stream-request/contracts", 1, 0,
		String(manifests[0]["artifact_hash"]), 10, 1, "RECEIVING", 0
	)
	_assert_ok(StreamAck.validate(ack), "RL3 ack rejected")
	var cancellation: Dictionary = Cancellation.create("stream-request/contracts", 1, 1, "OBSERVER_MOVED", 10)
	_assert_ok(Cancellation.validate(cancellation), "RL3 cancellation rejected")
	var center: Dictionary = CellAddress.create("planet-simulator", "rl3-tests", "asteroid-rl3", "matter-grid-rl3", 1, "asteroid-rl3-root", [0])
	var subscription: Dictionary = MatterSubscription.create(
		"subscription/rl3-adapter", "client/rl3-adapter", 7, 9, 1, center, 1
	)
	_assert_ok(MatterSubscription.validate(subscription), "MW7 subscription fixture rejected")
	var projected: Dictionary = MatterInterestAdapter.project(
		subscription, source, _scope_chain(), 100.0, 1000.0, 3.0, 0.5, false, false, 512,
		["DETAIL", "MACRO_PROXY", "SIMPLIFIED_MESH"], [], ["RAW"], true, 12.0, 3, 64, 128, 128, 0
	)
	_assert_ok(projected, "MW7 representation-aware projection failed")
	var projected_request: Dictionary = projected["details"]["stream_request"]
	_assert(String(projected_request["interest_request"]["observer_id"]) == "client/rl3-adapter", "MW7 client identity projection changed")
	_assert(int(projected_request["interest_request"]["request_revision"]) == 9, "MW7 interest revision projection changed")
	_assert(projected_request["scope_chain"] == _scope_chain(), "MW7 scope projection changed")
	var wrong_epoch: Dictionary = subscription.duplicate(true)
	wrong_epoch["authority_epoch"] = 8
	wrong_epoch["checksum"] = preload("res://scripts/simulation/matter/matter_contract_utils.gd").compute_checksum(wrong_epoch)
	_assert_fail(MatterInterestAdapter.project(
		wrong_epoch, source, _scope_chain(), 100.0, 1000.0, 3.0, 0.5, false, false, 512,
		["DETAIL", "MACRO_PROXY", "SIMPLIFIED_MESH"], [], ["RAW"], true, 12.0, 3, 64, 128, 128, 0
	), "MW7/source authority epoch mismatch accepted")


func _test_planner() -> void:
	var request: Dictionary = _request(_interest(1, 512), [], 0, true)
	var planned: Dictionary = Planner.build_plan(request, manifests, 100, 50)
	_assert_ok(planned, "RL3 planner failed")
	var plan: Dictionary = planned["details"]["plan"]
	_assert_ok(StreamPlan.validate(plan), "RL3 plan rejected")
	_assert(plan["stages"].size() == 2, "Progressive stage count changed")
	_assert(int(plan["stages"][0]["artifact_manifest"]["representation_key"]["lod_level"]) == 2, "Bootstrap stage is not coarse")
	_assert(int(plan["stages"][1]["artifact_manifest"]["representation_key"]["lod_level"]) == 1, "Final stage selection changed")
	_assert(int(plan["total_transfer_bytes"]) == 256, "Progressive transfer total changed")
	_assert(int(plan["expires_tick"]) == 150, "RL3 plan expiry changed")
	var reversed: Array = manifests.duplicate(true)
	reversed.reverse()
	var reordered: Dictionary = Planner.build_plan(request, reversed, 100, 50)
	_assert_ok(reordered, "RL3 reordered planner failed")
	_assert(reordered["details"]["plan"] == plan, "RL3 plan depends on manifest arrival order")
	var final_only_request: Dictionary = _request(_interest(1, 512), [], 0, false)
	var final_only: Dictionary = Planner.build_plan(final_only_request, manifests, 100, 50)
	_assert_ok(final_only, "RL3 final-only planner failed")
	_assert(final_only["details"]["plan"]["stages"].size() == 1, "Final-only request created bootstrap")
	_assert(int(final_only["details"]["plan"]["stages"][0]["artifact_manifest"]["representation_key"]["lod_level"]) == 1, "Final-only LOD changed")
	var unsupported: Dictionary = request.duplicate(true)
	unsupported["supported_encodings"] = ["PNG"]
	unsupported["checksum"] = Utils.compute_checksum(unsupported)
	_assert_fail(Planner.build_plan(unsupported, manifests, 100, 50), "Unsupported encoding produced plan")
	var narrow_budget: Dictionary = _request(_interest(1, 160), [], 0, true)
	var trimmed: Dictionary = Planner.build_plan(narrow_budget, manifests, 100, 50)
	_assert_ok(trimmed, "RL3 budget trimming failed")
	_assert(trimmed["details"]["plan"]["stages"].size() == 1, "Coarse bootstrap not trimmed to total budget")
	_assert(int(trimmed["details"]["plan"]["total_transfer_bytes"]) == 160, "Trimmed transfer budget changed")
	var detail_scope_request: Dictionary = request.duplicate(true)
	detail_scope_request["scope_chain"] = [ScopeBinding.create(0, "region/rl3-detail")]
	detail_scope_request["checksum"] = Utils.compute_checksum(detail_scope_request)
	var detail_only: Dictionary = Planner.build_plan(detail_scope_request, manifests, 100, 50)
	_assert_ok(detail_only, "RL3 exact scope planner failed")
	_assert(detail_only["details"]["plan"]["stages"].size() == 1, "Exact scope planner crossed hierarchy scopes")
	_assert(int(detail_only["details"]["plan"]["stages"][0]["artifact_manifest"]["representation_key"]["lod_level"]) == 0, "Exact scope planner selected wrong artifact")
	var rogue_content: PackedByteArray = "R".repeat(80).to_utf8_buffer()
	var rogue_hash: String = BusUtils.content_hash_from_bytes(rogue_content)
	var rogue_key: Dictionary = RepresentationKey.create(source, "region/rl3-rogue", 1, "SIMPLIFIED_MESH", "representation-variant/surface-default")
	var rogue_manifest: Dictionary = ArtifactManifest.create(
		rogue_key, rogue_hash, rogue_content.size(), "RAW", "application/vnd.planet-simulator.matter-mesh",
		0.1, [-64.0, -64.0, -64.0, 64.0, 64.0, 64.0], false, true, 4
	)
	var polluted_catalog: Array = manifests.duplicate(true)
	polluted_catalog.append(rogue_manifest)
	var isolated: Dictionary = Planner.build_plan(request, polluted_catalog, 100, 50)
	_assert_ok(isolated, "RL3 scope-isolated planner failed")
	_assert(String(isolated["details"]["plan"]["stages"].back()["artifact_manifest"]["artifact_hash"]) == String(manifests[1]["artifact_hash"]), "Planner crossed into unrelated same-LOD scope")


func _test_progressive_transfer_and_backpressure() -> void:
	var store := ArtifactStore.new()
	_assert_ok(store.configure(4096), "RL3 store configure failed")
	for manifest in manifests:
		_assert_ok(store.register(manifest, contents[String(manifest["artifact_hash"])]), "RL3 artifact registration failed")
	_assert(store.total_bytes() == 512, "RL3 store byte accounting changed")
	_assert(bool(store.register(manifests[0], contents[String(manifests[0]["artifact_hash"])])["details"]["duplicate"]), "RL3 duplicate artifact not idempotent")
	var server := StreamServer.new()
	var client := StreamClient.new()
	_assert_ok(server.configure(store), "RL3 server configure failed")
	_assert_ok(client.configure(1024), "RL3 client configure failed")
	var request: Dictionary = _request(_interest(1, 512), [], 0, true, 64, 64)
	var opened: Dictionary = server.open_stream(request, manifests, 100, 100)
	_assert_ok(opened, "RL3 stream open failed")
	var plan: Dictionary = opened["details"]["plan"]
	var stream_id: String = String(plan["stream_id"])
	var accepted: Dictionary = client.accept_plan(plan, String(source["checksum"]), 100)
	_assert_ok(accepted, "RL3 client plan acceptance failed")
	_assert(Array(accepted["details"]["initial_acks"]).is_empty(), "Transfer plan produced cache-hit ack")
	var first_batch: Dictionary = server.next_chunks(stream_id, 10, 101)
	_assert_ok(first_batch, "RL3 first chunk batch failed")
	_assert(first_batch["details"]["chunks"].size() == 1, "In-flight budget did not limit first batch")
	_assert(int(first_batch["details"]["in_flight_bytes"]) == 64, "RL3 in-flight byte accounting changed")
	var blocked: Dictionary = server.next_chunks(stream_id, 10, 102)
	_assert_ok(blocked, "RL3 blocked batch failed")
	_assert(blocked["details"]["chunks"].is_empty(), "Server ignored in-flight backpressure")
	var first_chunk: Dictionary = first_batch["details"]["chunks"][0]
	var received: Dictionary = client.receive_chunk(first_chunk, 103)
	_assert_ok(received, "RL3 client first chunk failed")
	_assert(String(received["details"]["ack"]["status"]) == "RECEIVING", "Partial chunk ack status changed")
	_assert_ok(server.acknowledge(received["details"]["ack"]), "RL3 partial ack failed")
	var duplicate_receive: Dictionary = client.receive_chunk(first_chunk, 104)
	_assert_fail(duplicate_receive, "Duplicate chunk accepted")
	var stage_ready_count: int = 0
	var stream_ready_count: int = 0
	var guard: int = 0
	while String(server.session_snapshot(stream_id)["status"]) != "READY" and guard < 32:
		guard += 1
		var batch: Dictionary = server.next_chunks(stream_id, 10, 110 + guard)
		_assert_ok(batch, "RL3 progressive chunk batch failed")
		for chunk in batch["details"]["chunks"]:
			var result: Dictionary = client.receive_chunk(chunk, 120 + guard)
			_assert_ok(result, "RL3 progressive client receive failed")
			var ack: Dictionary = result["details"]["ack"]
			if String(ack["status"]) == "STAGE_READY":
				stage_ready_count += 1
				_assert(int(client.current_manifest(stream_id)["representation_key"]["lod_level"]) == 2, "Coarse stage was not presented first")
			if String(ack["status"]) == "STREAM_READY":
				stream_ready_count += 1
			for emitted_ack in result["details"]["acks"]:
				_assert_ok(server.acknowledge(emitted_ack), "RL3 progressive ack failed")
	_assert(guard < 32, "RL3 progressive transfer did not converge")
	_assert(stage_ready_count == 1, "RL3 coarse stage ready count changed")
	_assert(stream_ready_count == 1, "RL3 final stage ready count changed")
	_assert(String(server.session_snapshot(stream_id)["status"]) == "READY", "RL3 server stream not ready")
	_assert(String(client.session_snapshot(stream_id)["status"]) == "READY", "RL3 client stream not ready")
	_assert(int(client.current_manifest(stream_id)["representation_key"]["lod_level"]) == 1, "RL3 final presentation LOD changed")
	_assert(client.advertised_hashes().size() == 2, "RL3 client cache artifact count changed")
	_assert(client.resident_bytes() == 256, "RL3 client resident bytes changed")


func _test_cache_reconnect() -> void:
	var store = _store()
	var server := StreamServer.new()
	var client := StreamClient.new()
	_assert_ok(server.configure(store), "RL3 reconnect server configure failed")
	_assert_ok(client.configure(1024), "RL3 reconnect client configure failed")
	_assert_ok(client.preload_cache(manifests[0], contents[String(manifests[0]["artifact_hash"])]), "RL3 coarse cache preload failed")
	_assert_ok(client.preload_cache(manifests[1], contents[String(manifests[1]["artifact_hash"])]), "RL3 final cache preload failed")
	var request: Dictionary = _request(_interest(2, 512), client.advertised_hashes(), 0, true)
	var opened: Dictionary = server.open_stream(request, manifests, 200, 100)
	_assert_ok(opened, "RL3 reconnect stream open failed")
	var plan: Dictionary = opened["details"]["plan"]
	_assert(int(plan["total_transfer_bytes"]) == 0, "RL3 cache reconnect transferred bytes")
	_assert(String(plan["stages"][0]["delivery_mode"]) == "CACHE_HIT", "RL3 coarse cache hit missing")
	_assert(String(plan["stages"][1]["delivery_mode"]) == "CACHE_HIT", "RL3 final cache hit missing")
	_assert(String(server.session_snapshot(String(plan["stream_id"]))["status"]) == "ACTIVE", "Server trusted cache advertisement before client ack")
	var accepted: Dictionary = client.accept_plan(plan, String(source["checksum"]), 200)
	_assert_ok(accepted, "RL3 cache-hit plan rejected")
	var initial_acks: Array = accepted["details"]["initial_acks"]
	_assert(initial_acks.size() == 2, "RL3 cache-hit ack count changed")
	_assert_fail(server.acknowledge(initial_acks[1]), "Later cache-hit stage acknowledged before coarse stage")
	var premature_ready: Dictionary = initial_acks[0].duplicate(true)
	premature_ready["status"] = "STREAM_READY"
	premature_ready["checksum"] = Utils.compute_checksum(premature_ready)
	_assert_fail(server.acknowledge(premature_ready), "Coarse stage accepted STREAM_READY")
	var wrong_final_status: Dictionary = initial_acks[1].duplicate(true)
	wrong_final_status["status"] = "STAGE_READY"
	wrong_final_status["checksum"] = Utils.compute_checksum(wrong_final_status)
	_assert_ok(server.acknowledge(initial_acks[0]), "RL3 coarse cache-hit ack rejected")
	_assert_fail(server.acknowledge(wrong_final_status), "Final stage accepted STAGE_READY")
	_assert_ok(server.acknowledge(initial_acks[1]), "RL3 final cache-hit ack rejected")
	_assert(String(server.session_snapshot(String(plan["stream_id"]))["status"]) == "READY", "RL3 cache-hit server stream not ready")
	_assert(int(client.current_manifest(String(plan["stream_id"]))["representation_key"]["lod_level"]) == 1, "RL3 cache-hit final presentation changed")
	var no_chunks: Dictionary = server.next_chunks(String(plan["stream_id"]), 4, 201)
	_assert_ok(no_chunks, "RL3 ready cache stream query failed")
	_assert(no_chunks["details"]["chunks"].is_empty(), "RL3 cache-hit stream emitted chunks")
	var exported: Array = client.export_cache()
	var restored := StreamClient.new()
	_assert_ok(restored.configure(1024), "RL3 restored client configure failed")
	_assert_ok(restored.import_cache(exported), "RL3 cache import failed")
	_assert(restored.advertised_hashes() == client.advertised_hashes(), "RL3 cache export/import changed hashes")

	var mixed_server := StreamServer.new()
	var mixed_client := StreamClient.new()
	_assert_ok(mixed_server.configure(_store()), "RL3 mixed-cache server configure failed")
	_assert_ok(mixed_client.configure(1024), "RL3 mixed-cache client configure failed")
	_assert_ok(mixed_client.preload_cache(manifests[1], contents[String(manifests[1]["artifact_hash"])]), "RL3 mixed-cache final preload failed")
	var mixed_request: Dictionary = _request(_interest(3, 512, "observer/mixed-cache"), mixed_client.advertised_hashes(), 0, true)
	var mixed_open: Dictionary = mixed_server.open_stream(mixed_request, manifests, 210, 100)
	_assert_ok(mixed_open, "RL3 mixed-cache stream open failed")
	var mixed_plan: Dictionary = mixed_open["details"]["plan"]
	_assert(String(mixed_plan["stages"][0]["delivery_mode"]) == "TRANSFER", "RL3 mixed-cache coarse stage changed")
	_assert(String(mixed_plan["stages"][1]["delivery_mode"]) == "CACHE_HIT", "RL3 mixed-cache final stage changed")
	var mixed_accept: Dictionary = mixed_client.accept_plan(mixed_plan, String(source["checksum"]), 210)
	_assert_ok(mixed_accept, "RL3 mixed-cache plan rejected")
	_assert(Array(mixed_accept["details"]["initial_acks"]).is_empty(), "Trailing cache hit acknowledged before coarse stage")
	var mixed_stream_id: String = String(mixed_plan["stream_id"])
	var mixed_guard: int = 0
	var trailing_cache_ack_seen: bool = false
	while String(mixed_server.session_snapshot(mixed_stream_id)["status"]) != "READY" and mixed_guard < 16:
		mixed_guard += 1
		var mixed_batch: Dictionary = mixed_server.next_chunks(mixed_stream_id, 4, 220 + mixed_guard)
		_assert_ok(mixed_batch, "RL3 mixed-cache batch failed")
		for mixed_chunk in mixed_batch["details"]["chunks"]:
			var mixed_received: Dictionary = mixed_client.receive_chunk(mixed_chunk, 230 + mixed_guard)
			_assert_ok(mixed_received, "RL3 mixed-cache receive failed")
			for mixed_ack in mixed_received["details"]["acks"]:
				if String(mixed_ack["status"]) == "STREAM_READY" and int(mixed_ack["stage_index"]) == 1:
					trailing_cache_ack_seen = true
				_assert_ok(mixed_server.acknowledge(mixed_ack), "RL3 mixed-cache ack failed")
	_assert(mixed_guard < 16, "RL3 mixed-cache transfer did not converge")
	_assert(trailing_cache_ack_seen, "Trailing cache-hit stage was never acknowledged")
	_assert(String(mixed_client.session_snapshot(mixed_stream_id)["status"]) == "READY", "RL3 mixed-cache client not ready")
	_assert(int(mixed_client.current_manifest(mixed_stream_id)["representation_key"]["lod_level"]) == 1, "RL3 mixed-cache final presentation changed")


func _test_cancellation_and_replacement() -> void:
	var server := StreamServer.new()
	_assert_ok(server.configure(_store()), "RL3 cancellation server configure failed")
	var request1: Dictionary = _request(_interest(1, 512, "observer/cancel"), [], 0, true)
	var opened1: Dictionary = server.open_stream(request1, manifests, 300, 100)
	_assert_ok(opened1, "RL3 cancellation stream open failed")
	var stream1: String = String(opened1["details"]["plan"]["stream_id"])
	var request2: Dictionary = _request(_interest(2, 512, "observer/cancel"), [], 0, true)
	var opened2: Dictionary = server.open_stream(request2, manifests, 301, 100)
	_assert_ok(opened2, "RL3 replacement stream open failed")
	_assert(String(server.session_snapshot(stream1)["status"]) == "CANCELLED", "Older observer request not replaced")
	_assert(String(server.session_snapshot(stream1)["cancel_reason"]) == "REPLACED", "Replacement reason changed")
	_assert_fail(server.open_stream(request1, manifests, 302, 100), "Observer request revision rollback accepted")
	var plan2: Dictionary = opened2["details"]["plan"]
	var cancellation: Dictionary = Cancellation.create(String(request2["stream_request_id"]), 2, 1, "OBSERVER_MOVED", 303)
	_assert_ok(server.cancel(cancellation), "RL3 cancellation failed")
	_assert(String(server.session_snapshot(String(plan2["stream_id"]))["status"]) == "CANCELLED", "RL3 cancelled stream remains active")
	_assert_fail(server.cancel(cancellation), "Repeated cancellation generation accepted")
	_assert_fail(server.next_chunks(String(plan2["stream_id"]), 1, 304), "Cancelled stream emitted chunks")
	var conflicting: Dictionary = request2.duplicate(true)
	conflicting["priority"] = 200
	conflicting["checksum"] = Utils.compute_checksum(conflicting)
	_assert_fail(server.open_stream(conflicting, manifests, 305, 100), "Same request revision conflict accepted")


func _test_invalidation_fencing() -> void:
	var server := StreamServer.new()
	var client := StreamClient.new()
	_assert_ok(server.configure(_store()), "RL3 invalidation server configure failed")
	_assert_ok(client.configure(1024), "RL3 invalidation client configure failed")
	var request: Dictionary = _request(_interest(1, 512, "observer/invalidation"), [], 0, true)
	var opened: Dictionary = server.open_stream(request, manifests, 400, 100)
	_assert_ok(opened, "RL3 invalidation stream open failed")
	var plan: Dictionary = opened["details"]["plan"]
	var stream_id: String = String(plan["stream_id"])
	_assert_ok(client.accept_plan(plan, String(source["checksum"]), 400), "RL3 invalidation plan acceptance failed")
	var invalidation: Dictionary = Invalidation.create(
		"invalidation/rl3-stream", source, next_source,
		[-64.0, -64.0, -64.0, 64.0, 64.0, 64.0], "MUTATION",
		["region/rl3-detail", "region/rl3-macro", "region/rl3-regional"], 401
	)
	_assert_ok(Invalidation.validate(invalidation), "RL3 invalidation rejected")
	var server_result: Dictionary = server.apply_invalidation(invalidation)
	var client_result: Dictionary = client.apply_invalidation(invalidation)
	_assert_ok(server_result, "RL3 server invalidation failed")
	_assert_ok(client_result, "RL3 client invalidation failed")
	_assert(server_result["details"]["stale_stream_ids"] == [stream_id], "RL3 server stale stream projection changed")
	_assert(client_result["details"]["stale_stream_ids"] == [stream_id], "RL3 client stale stream projection changed")
	_assert(String(server.session_snapshot(stream_id)["status"]) == "STALE", "RL3 server stale fence missing")
	_assert(String(client.session_snapshot(stream_id)["status"]) == "STALE", "RL3 client stale fence missing")
	_assert(client.current_manifest(stream_id).is_empty(), "Stale client presentation remains active")
	_assert_fail(server.next_chunks(stream_id, 1, 402), "Stale server stream emitted chunks")
	var unrelated := StreamServer.new()
	_assert_ok(unrelated.configure(_store()), "RL3 unrelated server configure failed")
	var other_open: Dictionary = unrelated.open_stream(request, manifests, 400, 100)
	_assert_ok(other_open, "RL3 unrelated stream open failed")
	var partial_invalidation: Dictionary = Invalidation.create(
		"invalidation/rl3-unrelated", source, next_source,
		[100.0, 100.0, 100.0, 101.0, 101.0, 101.0], "MUTATION", ["region/unrelated-scope"], 401
	)
	var unaffected: Dictionary = unrelated.apply_invalidation(partial_invalidation)
	_assert_ok(unaffected, "RL3 unrelated invalidation failed")
	_assert(unaffected["details"]["stale_stream_ids"].is_empty(), "Unrelated invalidation cancelled stream")


func _test_budget_and_corruption_fences() -> void:
	var tiny_client := StreamClient.new()
	_assert_ok(tiny_client.configure(200), "RL3 tiny client configure failed")
	var plan: Dictionary = Planner.build_plan(_request(_interest(1, 512), [], 0, true), manifests, 500, 100)["details"]["plan"]
	_assert_fail(tiny_client.accept_plan(plan, String(source["checksum"]), 500), "Client memory budget overflow accepted")
	var dishonest_client := StreamClient.new()
	_assert_ok(dishonest_client.configure(1024), "RL3 dishonest client configure failed")
	var cached_hashes: Array = [String(manifests[1]["artifact_hash"])]
	cached_hashes.sort()
	var cached_plan: Dictionary = Planner.build_plan(_request(_interest(1, 512), cached_hashes, 0, false), manifests, 500, 100)["details"]["plan"]
	_assert(String(cached_plan["stages"][0]["delivery_mode"]) == "CACHE_HIT", "RL3 dishonest cache fixture changed")
	_assert_fail(dishonest_client.accept_plan(cached_plan, String(source["checksum"]), 500), "Advertised cache miss accepted")
	var wrong_source_client := StreamClient.new()
	_assert_ok(wrong_source_client.configure(1024), "RL3 wrong-source client configure failed")
	_assert_fail(wrong_source_client.accept_plan(plan, String(next_source["checksum"]), 500), "Plan accepted for wrong source revision")
	var store = _store()
	var wrong_content: PackedByteArray = "x".repeat(96).to_utf8_buffer()
	_assert_fail(store.register(manifests[0], wrong_content), "Artifact store accepted wrong bytes")
	var malformed_plan: Dictionary = plan.duplicate(true)
	malformed_plan["stages"].reverse()
	for index in range(malformed_plan["stages"].size()):
		malformed_plan["stages"][index]["stage_index"] = index
		malformed_plan["stages"][index]["checksum"] = Utils.compute_checksum(malformed_plan["stages"][index])
	malformed_plan["checksum"] = Utils.compute_checksum(malformed_plan)
	_assert_fail(StreamPlan.validate(malformed_plan), "Fine-to-coarse plan accepted")


func _interest(revision: int, bandwidth: int, observer_id: String = "observer/rl3-client") -> Dictionary:
	return InterestRequest.create(
		"interest/rl3-%s-%d" % [observer_id.get_file(), revision], observer_id, source,
		100.0, 1000.0, 3.0, 0.5, false, false, bandwidth,
		["DETAIL", "MACRO_PROXY", "SIMPLIFIED_MESH"], revision
	)


func _request(
	interest: Dictionary,
	cached_hashes: Array,
	cancellation_generation: int,
	progressive: bool,
	chunk_bytes: int = 64,
	in_flight_bytes: int = 128
) -> Dictionary:
	var hashes: Array = cached_hashes.duplicate()
	hashes.sort()
	return StreamRequest.create(
		"stream-request/%s-%d" % [String(interest["observer_id"]).get_file(), int(interest["request_revision"])],
		interest, _scope_chain(), hashes, ["RAW"], progressive, 12.0, 3,
		chunk_bytes, in_flight_bytes, 128, cancellation_generation
	)


func _scope_chain() -> Array:
	return [
		ScopeBinding.create(2, "region/rl3-macro"),
		ScopeBinding.create(1, "region/rl3-regional"),
		ScopeBinding.create(0, "region/rl3-detail"),
	]


func _store():
	var store := ArtifactStore.new()
	store.configure(4096)
	for manifest in manifests:
		store.register(manifest, contents[String(manifest["artifact_hash"])])
	return store


func _hash(value: String) -> String:
	return BusUtils.content_hash_from_bytes(value.to_utf8_buffer())


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result.get("error_code", "")])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("RL3 representation-aware network streaming: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("RL3 representation-aware network streaming: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)
