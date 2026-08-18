extends SceneTree

const Gameplay = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Resolver = preload("res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd")
const Authority = preload("res://scripts/construction/mvp/v0_p4_mvp_earth_outpost_authority.gd")
const Bridge = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const Server = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Command = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const Grant = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const Replica = preload("res://scripts/construction/multiplayer/construction_multiplayer_replica.gd")
const ItemDelta = preload("res://scripts/runtime/networked_gameplay/contracts/canonical_item_graph_delta.gd")
const NODE := "resource/earth/ore-demo/1"
const A := "alpha"
const B := "beta"
var assertions := 0
var failures: Array[String] = []

class FakeBoundary extends RefCounted:
	var frames: Array[Dictionary] = []
	func get_peer_snapshot(_p: String) -> Dictionary: return {"state":"READY"}
	func mark_peer_handshaking(_p: String) -> Dictionary: return _ok()
	func mark_peer_synchronizing(_p: String) -> Dictionary: return _ok()
	func mark_peer_ready(_p: String) -> Dictionary: return _ok()
	func create_frame_for_peer(peer: String, channel: String, _schema: String, payload: Dictionary, delivery: String) -> Dictionary:
		return _ok({"frame":{"peer_id":peer,"channel":channel,"delivery_mode":delivery,"payload":payload.duplicate(true)}})
	func send_to_peer(peer: String, frame: Dictionary) -> Dictionary:
		var f := frame.duplicate(true); f["peer_id"] = peer; frames.append(f); return _ok()
	func flush_outbound(_n: int, _p: String) -> Dictionary: return _ok()
	func get_snapshot() -> Dictionary: return {"captured_frames":frames.size()}
	func clear() -> void: frames.clear()
	func _ok(details: Dictionary = {}) -> Dictionary: return {"success":true,"error_code":"","details":details}

class SnapshotFaultService extends RefCounted:
	var inner
	var calls := 0
	func _init(v) -> void: inner = v
	func create_canonical_item_graph_snapshot() -> Dictionary:
		calls += 1
		return {"schema":"invalid-for-p4-fallback"} if calls == 1 else inner.create_canonical_item_graph_snapshot()
	func create_targeted_command_result(mid: String, oid: String, result: Dictionary) -> Dictionary: return inner.create_targeted_command_result(mid, oid, result)
	func create_snapshot() -> Dictionary: return inner.create_snapshot()
	func get_report() -> Dictionary: return inner.get_report()

class EventFaultBridge extends RefCounted:
	var inner
	func _init(v) -> void: inner = v
	func submit_player_command(player: String, command: Dictionary) -> Dictionary:
		var out: Dictionary = inner.submit_player_command(player, command)
		if not bool(out.get("success", false)): return out
		var d: Dictionary = out.get("details", {}).duplicate(true)
		d["event_packet"] = {}; d["event_fallback_required"] = true; d["snapshot_packet"] = inner.get_snapshot_packet(); out["details"] = d
		return out
	func get_snapshot_packet() -> Dictionary: return inner.get_snapshot_packet()

func _init() -> void:
	_static_contract(); _normal(); _fallback(); _finish()

func _static_contract() -> void:
	var runtime := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	for needle in ["func _handle_construction_command", "CanonicalItemGraphDelta.create", "V0_P4_CONSTRUCTION_ITEM_DELTA_FALLBACK", "V0_P4_CONSTRUCTION_EVENT_FALLBACK", "replay_publications_suppressed"]: _check(runtime.find(needle) >= 0, "runtime contract: %s" % needle)
	var bridge := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
	_check(bridge.find("event_fallback_required") >= 0 and bridge.find("snapshot_packet") >= 0, "bridge fallback contract")
	_check(bridge.find('return _failure("M3_CONSTRUCTION_GATEWAY_EVENT_REQUIRED")') < 0, "accepted commit can become rejection")

func _normal() -> void:
	var f := _fixture("normal"); if f.is_empty(): return
	var graph = f.graph; var bridge = f.bridge; var runtime = f.runtime; var wire: FakeBoundary = f.wire
	var before_item: Dictionary = graph.create_snapshot(); var before_c: Dictionary = bridge.get_snapshot_packet()
	var ra = _replica(before_c, "normal replica A"); var rb = _replica(before_c, "normal replica B")
	var cmd := _command(f.session_a, 0, "normal", before_c.state_bundle)
	runtime._handle_construction_command("peer-a", "wire-a", {"operation_id":"operation/v0-p4/p4-5/wire/normal","command":cmd})
	var after_item: Dictionary = graph.create_snapshot(); _check(_ore(graph, A) == 0, "normal ore debit")
	_check(_count(wire.frames,"COMMAND_RESULT","peer-a") == 1, "normal result")
	_check(_count(wire.frames,"ITEM_GRAPH_DELTA","peer-b") == 1 and _count(wire.frames,"ITEM_GRAPH_DELTA","peer-a") == 0, "delta routing")
	_check(_count(wire.frames,"CONSTRUCTION_EVENT","peer-a") == 1 and _count(wire.frames,"CONSTRUCTION_EVENT","peer-b") == 1, "event routing")
	_check(_count(wire.frames,"ITEM_GRAPH_SNAPSHOT") == 0 and _count(wire.frames,"CONSTRUCTION_SNAPSHOT") == 0, "normal used fallback")
	var da: Dictionary = _payload(wire.frames,"COMMAND_RESULT","peer-a").get("item_graph_delta", {})
	var db: Dictionary = _payload(wire.frames,"ITEM_GRAPH_DELTA","peer-b").get("delta", {})
	var aa := ItemDelta.apply(before_item, da); var ab := ItemDelta.apply(before_item, db); _ok(aa,"delta apply A"); _ok(ab,"delta apply B")
	_check(String(aa.get("details",{}).get("snapshot",{}).get("checksum","")) == String(after_item.get("checksum","")), "A item convergence")
	_check(String(ab.get("details",{}).get("snapshot",{}).get("checksum","")) == String(after_item.get("checksum","")), "B item convergence")
	_ok(ra.apply_event(_payload(wire.frames,"CONSTRUCTION_EVENT","peer-a").get("event",{})), "event apply A")
	_ok(rb.apply_event(_payload(wire.frames,"CONSTRUCTION_EVENT","peer-b").get("event",{})), "event apply B")
	var target: Dictionary = bridge.get_snapshot_packet().state_bundle; _check(ra.converged_with(target) and rb.converged_with(target), "Construction convergence")
	var report: Dictionary = runtime.get_report().v0_p4_post_commit_publication
	_check(int(report.publication_batches) == 1 and int(report.item_snapshot_fallbacks) == 0 and int(report.construction_snapshot_fallbacks) == 0, "normal counters")
	wire.clear(); var ore := _ore(graph,A)
	runtime._handle_construction_command("peer-a","wire-a",{"operation_id":"operation/v0-p4/p4-5/wire/replay","command":cmd})
	_check(_ore(graph,A) == ore, "replay debit")
	_check(_count(wire.frames,"COMMAND_RESULT","peer-a") == 1, "replay result")
	_check(_count(wire.frames,"ITEM_GRAPH_DELTA") + _count(wire.frames,"ITEM_GRAPH_SNAPSHOT") + _count(wire.frames,"CONSTRUCTION_EVENT") + _count(wire.frames,"CONSTRUCTION_SNAPSHOT") == 0, "replay publication")
	_check(int(runtime.get_report().v0_p4_post_commit_publication.replay_publications_suppressed) == 1, "replay counter")
	_shutdown(f)

func _fallback() -> void:
	var f := _fixture("fallback"); if f.is_empty(): return
	var service = f.service; var graph = f.graph; var bridge = f.bridge; var runtime = f.runtime; var wire: FakeBoundary = f.wire
	var before_c: Dictionary = bridge.get_snapshot_packet(); var cmd := _command(f.session_a,0,"fallback",before_c.state_bundle)
	runtime.set("_service", SnapshotFaultService.new(service)); runtime.set("_construction_bridge", EventFaultBridge.new(bridge))
	runtime._handle_construction_command("peer-a","wire-a",{"operation_id":"operation/v0-p4/p4-5/wire/fallback","command":cmd})
	_check(_ore(graph,A) == 0, "fallback commit")
	var result: Dictionary = _payload(wire.frames,"COMMAND_RESULT","peer-a")
	_check(String(result.get("status","")) == "SUCCEEDED" and Dictionary(result.get("item_graph_delta",{})).is_empty(), "fallback result")
	_check(_count(wire.frames,"ITEM_GRAPH_DELTA") == 0 and _count(wire.frames,"CONSTRUCTION_EVENT") == 0, "fallback leaked delta/event")
	_check(_count(wire.frames,"ITEM_GRAPH_SNAPSHOT","peer-a") == 1 and _count(wire.frames,"ITEM_GRAPH_SNAPSHOT","peer-b") == 1, "Item snapshot fallback routing")
	_check(_count(wire.frames,"CONSTRUCTION_SNAPSHOT","peer-a") == 1 and _count(wire.frames,"CONSTRUCTION_SNAPSHOT","peer-b") == 1, "Construction snapshot fallback routing")
	var ai: Dictionary = graph.create_snapshot(); var ac: Dictionary = bridge.get_snapshot_packet()
	_check(String(_payload(wire.frames,"ITEM_GRAPH_SNAPSHOT","peer-a").get("snapshot",{}).get("checksum","")) == String(ai.checksum), "Item fallback stale")
	_check(String(_payload(wire.frames,"CONSTRUCTION_SNAPSHOT","peer-b").get("state_bundle",{}).get("checksum","")) == String(ac.state_bundle.checksum), "Construction fallback stale")
	runtime.set("_service",service); runtime.set("_construction_bridge",bridge)
	var report: Dictionary = runtime.get_report().v0_p4_post_commit_publication
	_check(int(report.publication_batches) == 1 and int(report.item_snapshot_fallbacks) == 1 and int(report.construction_snapshot_fallbacks) == 1, "fallback counters")
	_shutdown(f)

func _fixture(suffix: String) -> Dictionary:
	var service = Gameplay.new(); _ok(service.setup("authority/v0-p4/p4-5/%s"%suffix,1,0,{"profile":Gameplay.PROFILE_MULTIPLAYER_CORE,"topology_adapter":"ENET","region_id":"region/v0-p4/p4-5/%s"%suffix,"fixed_tick_authority":true}),"setup")
	_ok(service.join(A,"transport-session/v0-p4/p4-5/%s/a"%suffix,"operation/v0-p4/p4-5/%s/join-a"%suffix),"join A"); _ok(service.join(B,"transport-session/v0-p4/p4-5/%s/b"%suffix,"operation/v0-p4/p4-5/%s/join-b"%suffix),"join B")
	var graph = service.get_canonical_item_graph_port(); var mining = service.get_resource_mining_port(); var resolver = Resolver.new(); _ok(resolver.setup(),"resolver")
	var resolved: Dictionary = resolver.resolve_planar(mining.get_node(NODE).spatial); _ok(resolved,"resolve"); if not bool(resolved.get("success",false)): service.shutdown(); return {}
	_ok(mining.mine(A,"operation/v0-p4/p4-5/%s/mine"%suffix,{"resource_node_id":NODE,"requested_units":2},resolved.details.planar_position),"mine")
	var auth: Dictionary = Authority.create_gateway(graph,"authority/v0-p4/p4-5/%s"%suffix,1,"user://v0-p4-p4-5/%s/%d-%d"%[suffix,OS.get_process_id(),Time.get_ticks_usec()]); _ok(auth,"authority"); if not bool(auth.get("success",false)): service.shutdown(); return {}
	var bridge = Bridge.new(); _ok(bridge.setup(auth.details.gateway),"bridge"); var ca: Dictionary = bridge.connect_player(A,1); var cb: Dictionary = bridge.connect_player(B,1); _ok(ca,"connect A"); _ok(cb,"connect B")
	var runtime = Server.new(); get_root().add_child(runtime); var wire := FakeBoundary.new(); runtime.set("_service",service); runtime.set("_construction_bridge",bridge); runtime.set("_boundary",wire); runtime.set("_peer_to_player",{"peer-a":A,"peer-b":B}); runtime.set("_peer_to_session",{"peer-a":"wire-a","peer-b":"wire-b"})
	return {"service":service,"graph":graph,"bridge":bridge,"runtime":runtime,"wire":wire,"session_a":ca.details.session}

func _shutdown(f: Dictionary) -> void:
	var r = f.runtime; r.set("_service",null); r.set("_construction_bridge",null); r.set("_boundary",null); r.queue_free(); f.service.shutdown()
func _replica(packet: Dictionary, label: String):
	var r = Replica.new(); var x := r.initialize(packet.state_bundle,int(packet.last_event_index)); _ok(x,label); return r if bool(x.get("success",false)) else null
func _command(session: Dictionary, seq: int, suffix: String, bundle: Dictionary) -> Dictionary:
	return Command.create("multiplayer-command/v0-p4/p4-5/%s"%suffix,String(session.client_id),String(session.session_id),int(session.session_epoch),seq,Grant.ACTION_BUILD,Authority.CONSTRUCT_ID,_construct_checksum(bundle),int(bundle.server_generation),int(session.permission_epoch),{"build_plan_id":Authority.BUILD_PLAN_ID,"stage_index":0,"operation_id":"operation/v0-p4/p4-5/build/%s"%suffix,"provided_capabilities":["FASTEN"],"options":{}})
func _construct_checksum(bundle: Dictionary) -> String:
	for row in bundle.get("constructs",[]): if row is Dictionary and String(row.get("construct_id","")) == Authority.CONSTRUCT_ID: return String(row.get("checksum",""))
	return ""
func _ore(graph, player: String) -> int:
	var n:=0
	for row in graph.create_snapshot().get("items",[]):
		if row is Dictionary and String(row.get("definition_id","")) == "item/ore":
			var l: Dictionary = row.get("location",{}); if String(l.get("kind","")) == "INVENTORY" and String(l.get("player_id","")) == player: n += int(row.get("quantity",0))
	return n
func _payload(frames: Array[Dictionary], typ: String, peer: String = "") -> Dictionary:
	for f in frames:
		if not peer.is_empty() and String(f.get("peer_id","")) != peer: continue
		var p: Dictionary = f.get("payload",{}); if String(p.get("type","")) == typ: return p.duplicate(true)
	return {}
func _count(frames: Array[Dictionary], typ: String, peer: String = "") -> int:
	var n:=0
	for f in frames:
		if not peer.is_empty() and String(f.get("peer_id","")) != peer: continue
		if String(Dictionary(f.get("payload",{})).get("type","")) == typ: n += 1
	return n
func _ok(r: Dictionary, label: String) -> void: _check(bool(r.get("success",false)),"%s: %s"%[label,r])
func _check(v: bool, label: String) -> void: assertions += 1; failures.append(label) if not v else null; push_error("FAIL: %s"%label) if not v else null
func _finish() -> void:
	if failures.is_empty(): print("V0-P4 post-commit publication/fallback: PASS (%d assertions)"%assertions); quit(0); return
	for f in failures: push_error(f)
	print("V0-P4 post-commit publication/fallback: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]); quit(1)
