extends SceneTree

# Full repository native integration: actual USER1/M3 playable-sandbox service,
# two real authoritative player rows, fixed movement, A->B->A, reconnect.
# NO sockets/render/GUI performance claim; the new wire version stays UNROUTED.
const Service = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const Chain = preload("res://tests/runtime/support/r31_815_real_snapshot_chain.gd")
const V2 = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot_v2.gd")

var checks: int = 0
var errors: Array[String] = []
var sample_count: int = 0
var legacy_rejects: int = 0


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		errors.append(label)


func sample(service, tick: int) -> void:
	var source: Dictionary = Chain.Full.Wire.stringify_dictionary_keys(service.create_snapshot())
	var before: String = Chain.Utils.canonical_json(source)
	check(bool(Chain.Full.validate(source).get("success", false)), "native USER1 full snapshot valid %d" % tick)
	var old: Dictionary = Chain.inspect_v1(source, tick + 1)
	check(not old.has("fatal_stage"), "original USER1 compact wire pipeline executed %d" % tick)
	if old.get("first_broken_stage", "NONE") != "NONE":
		legacy_rejects += 1
	var encoded: Dictionary = V2.encode(source)
	check(bool(encoded.get("success", false)), "candidate packs actual USER1 snapshot %d" % tick)
	if not bool(encoded.get("success", false)):
		return
	var body: Dictionary = encoded["details"]["snapshot"]
	var frame: Dictionary = Chain.create_frame(body, tick + 1)
	var wire: Dictionary = Chain.Frame.encode(frame)
	check(bool(wire.get("success", false)), "original Frame.encode accepts USER1-v2 %d" % tick)
	if not bool(wire.get("success", false)):
		return
	var accepted: Dictionary = Chain.Frame.decode(wire["details"]["packet"])
	check(bool(accepted.get("success", false)), "original native frame decoder accepts actual USER1 %d" % tick)
	if not bool(accepted.get("success", false)):
		return
	var expanded: Dictionary = V2.decode(accepted["details"]["frame"]["payload"]["snapshot"])
	check(bool(expanded.get("success", false)), "original USER1 full c retained %d" % tick)
	if bool(expanded.get("success", false)):
		check(Chain.first_numeric_change(source, expanded["details"]["snapshot"]).is_empty(), "USER1 numeric state restored bit-exact %d" % tick)
		check(before == Chain.Utils.canonical_json(expanded["details"]["snapshot"]), "USER1 identity/epoch/session/checksum exact %d" % tick)
	check(before == Chain.Utils.canonical_json(source), "encoding never mutates captured USER1 snapshot %d" % tick)
	check(before == Chain.Utils.canonical_json(Chain.Full.Wire.stringify_dictionary_keys(service.create_snapshot())), "encoding never mutates authoritative USER1 service %d" % tick)
	sample_count += 1


func _run() -> void:
	var service = Service.new()
	var configured: Dictionary = service.setup("authority/product/815-chain", 1, 0, {
		"profile": "MULTIPLAYER_CORE", "topology_adapter": "ENET",
		"region_id": "region/m3/single-server", "playable_sandbox": true,
		"fixed_tick_authority": true,
	})
	check(bool(configured.get("success", false)), "actual playable Earth USER1 service configured")
	if bool(configured.get("success", false)):
		for player in ["a", "b"]:
			var joined: Dictionary = service.join(player, "transport-session/815/" + player,
				"operation/815/chain/join-" + player)
			check(bool(joined.get("success", false)), "actual authoritative player joined: " + player)
		var before_graph: String = String(service.create_canonical_item_graph_snapshot().get("checksum", ""))
		var before_resource: String = String(service.create_resource_mining_snapshot().get("checksum", ""))
		var entity: String = String(service.get_player("a").get("player_entity_id", ""))
		var epoch: int = int(service.get_player("a").get("ownership_epoch", 0))
		var saw_b: bool = false
		var returned: bool = false
		var last_tick: int = 0
		sample(service, 0)
		for tick in range(1, 901):
			last_tick = tick
			var advanced: Dictionary = service.advance_fixed_server_tick(tick)
			check(bool(advanced.get("success", false)), "actual fixed 60Hz authority advances %d" % tick)
			var seam: Dictionary = service.get_product_seam_state("a")
			var dx: float = -1.0 if String(seam.get("region_id", "")) == "region/user1/b" else 1.0
			var moved: Dictionary = service.simulate_fixed_movement_tick("a", "transport-session/815/a", epoch, tick, {
				"move_x": dx, "move_z": 0.0, "look_yaw": 0.4251206143591745,
				"look_pitch": 0.0, "jump_pressed": false, "sprint": true,
				"delta_seconds": 1.0 / 60.0,
			}, 1.0 / 60.0)
			check(bool(moved.get("success", false)), "actual USER1 movement tick %d" % tick)
			seam = service.get_product_seam_state("a")
			if String(seam.get("region_id", "")) == "region/user1/b":
				saw_b = true
			if tick % 3 == 0:
				sample(service, tick)
			if int(seam.get("roundtrips", 0)) >= 1:
				returned = true
				sample(service, tick + 1)
				break
		check(saw_b and returned, "actual A->B->A authority movement completed")
		check(sample_count >= 10, "at least ten real USER1 full/compact/frame snapshots traversed")
		check(before_graph == String(service.create_canonical_item_graph_snapshot().get("checksum", "")), "codec does not mutate primary Item Graph")
		check(before_resource == String(service.create_resource_mining_snapshot().get("checksum", "")), "codec does not mutate ResourceMining authority")
		var left: Dictionary = service.leave("a", "transport-session/815/a", "operation/815/chain/leave-a")
		check(bool(left.get("success", false)), "actual player leaves after seam")
		var rejoined: Dictionary = service.join("a", "transport-session/815/a-rejoined", "operation/815/chain/rejoin-a")
		check(bool(rejoined.get("success", false)), "actual reconnect succeeds")
		var now: Dictionary = service.get_player("a")
		check(String(now.get("player_entity_id", "")) == entity, "player entity preserved on reconnect")
		check(int(now.get("ownership_epoch", 0)) == epoch + 1, "reconnect increments ownership once")
		check(String(now.get("transport_session_id", "")) == "transport-session/815/a-rejoined", "new transport session after reconnect")
		sample(service, last_tick + 2)
		var durable: Dictionary = service.export_durable_state()
		check(not durable.is_empty(), "real product durable projection remains available")
		check(bool(service.validate_durable_state(durable).get("success", false)), "original durable validation not bypassed")
		service.shutdown()
	for error in errors:
		push_error("NS1_815_USER1_CHAIN_FAIL:" + error)
	print("NS1_815_USER1_CHAIN %s assertions=%d failures=%d real_snapshots=%d legacy_rejects=%d" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size(), sample_count, legacy_rejects])
	quit(0 if errors.is_empty() else 1)
