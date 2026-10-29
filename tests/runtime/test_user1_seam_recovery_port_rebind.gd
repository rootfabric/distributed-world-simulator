extends SceneTree

# Independent falsifier: after M6 replaces the primary player/ownership
# registries, the already-created USER1 trusted seam port must rebind to those
# new durable rows while retaining the same peer identity. Test both players,
# stale sessions, post-restart ticks and an actual A->B->A transfer.
const Seam = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const PLAYER_A = "a"
const PLAYER_B = "b"
const SESSION_A = "transport-session/independent-m6/a"
const SESSION_B = "transport-session/independent-m6/b"
const REJOIN_A = "transport-session/independent-m6/rejoined-a"
const REJOIN_B = "transport-session/independent-m6/rejoined-b"
var n := 0
var errors: Array[String] = []

func _init():
	call_deferred("_run")

func _assert(ok: bool, detail: String):
	n += 1
	if not ok:
		errors.append(detail)
		printerr("IND_M6_FAIL: ", detail)

func _ok(result: Dictionary, detail: String):
	_assert(bool(result.get("success", false)), detail + " => " + String(result.get("error_code", "")))

func _options() -> Dictionary:
	return {"profile": "MULTIPLAYER_CORE", "topology_adapter": "ENET", "region_id": "region/m3/single-server", "playable_sandbox": true, "fixed_tick_authority": true}

func _intent(move_x: float, move_z: float) -> Dictionary:
	return {"move_x": move_x, "move_z": move_z, "look_yaw": 0.2, "look_pitch": 0.0, "jump_pressed": false, "sprint": false, "delta_seconds": 1.0 / 60.0}

func _movement(svc, pid: String, sess: String, i: int, x: float, z: float):
	var player: Dictionary = svc.get_player(pid)
	_ok(svc.simulate_fixed_movement_tick(pid, sess, int(player.get("ownership_epoch", 0)), i, _intent(x,z), 1.0/60.0),"move %s at %d" % [pid, i])

func _run():
	var first=Seam.new()
	_ok(first.setup("authority/ind-m6",1,0,_options()),"setup pre-recovery")
	_ok(first.join(PLAYER_A, SESSION_A, "operation/ind/a-join"),"join a")
	_ok(first.join(PLAYER_B, SESSION_B, "operation/ind/b-join"),"join b")
	for i in range(1,28):
		_ok(first.advance_fixed_server_tick(i),"pre tick %d" % i)
		_movement(first, PLAYER_A, SESSION_A, i, 0.0, -1.0)
		_movement(first, PLAYER_B, SESSION_B, i, 0.0, 1.0)
	var snap0: Dictionary=first.create_snapshot()
	_assert(Array(snap0.get("players",[])).size()==2,"two players before restart")
	var durable: Dictionary=first.export_durable_state()
	_assert(not durable.is_empty(),"durable export after both players")
	_assert(int(durable.get("server_tick",-1))==27,"durable server tick=27")
	_ok(first.shutdown(),"shutdown original")
	var restarted=Seam.new()
	_ok(restarted.setup("authority/ind-m6",1,0,_options()),"setup restarted at tick=0")
	_ok(restarted.restore_durable_state(durable),"restore ahead-of-0 durable")
	var snap1: Dictionary=restarted.create_snapshot()
	_assert(Array(snap1.get("players",[])).size()==2,"two players present after restore")
	_assert(restarted._primary_port._registry == restarted._players, "recovered transfer port owns restored PlayerRegistry")
	_assert(restarted._primary_port._ownership == restarted._ownership, "recovered transfer port owns restored OwnershipService")
	# Restored sessions are intentionally disconnected; rejoin with new transport sessions.
	_ok(restarted.join(PLAYER_A, REJOIN_A, "operation/ind/a-rejoin"),"rejoin a with new session")
	_ok(restarted.join(PLAYER_B, REJOIN_B, "operation/ind/b-rejoin"),"rejoin b with new session")
	_assert(int(restarted.get_player(PLAYER_A).get("ownership_epoch",0)) == 2, "a owner epoch increments on rejoin")
	_assert(int(restarted.get_player(PLAYER_B).get("ownership_epoch",0)) == 2, "b owner epoch increments on rejoin")
	for i in range(28,50):
		_ok(restarted.advance_fixed_server_tick(i),"recovered tick %d" % i)
		_movement(restarted,PLAYER_A,REJOIN_A,i,0.0,-1.0)
		_movement(restarted,PLAYER_B,REJOIN_B,i,0.0,1.0)
	var snap2: Dictionary=restarted.create_snapshot()
	_assert(Array(snap2.get("players",[])).size()==2,"two players after 22 recovered ticks")
	_assert(int(snap2.get("server_tick", -1))==49,"latest server tick 49")
	var before_positions={}
	for p in snap0.get("players",[]):
		before_positions[String(p.get("logical_player_id", ""))]=Dictionary(p.get("position",{}))
	for p in snap2.get("players",[]):
		var pid=String(p.get("logical_player_id", ""))
		_assert(before_positions.has(pid),"player "+pid+" still present")
		_assert(absf(float(Dictionary(p.get("position", {})).get("z", 0.0))-float(Dictionary(before_positions.get(pid,{})).get("z",0.0)))>0.1,"player "+pid+" movement advances after recovery")
	# A stale pre-recovery transport session must remain blocked.
	var stale_move: Dictionary = restarted.simulate_fixed_movement_tick(PLAYER_A, SESSION_A, 1, 50, _intent(1.0,0.0), 1.0/60.0)
	_assert(not bool(stale_move.get("success", false)), "old transport session still rejected after reconnect")

	# Exercise the full A->B->A after restore while second player remains present.
	var saw_secondary := false
	var roundtrip := false
	for i in range(50,950):
		_ok(restarted.advance_fixed_server_tick(i), "post-recovery seam tick %d" % i)
		var seam: Dictionary = restarted.get_product_seam_state(PLAYER_A)
		var on_secondary := String(seam.get("region_id", "")) == "region/user1/b"
		if on_secondary:
			saw_secondary = true
		var x := -1.0 if on_secondary else 1.0
		var player: Dictionary = restarted.get_player(PLAYER_A)
		var motion: Dictionary = restarted.simulate_fixed_movement_tick(
			PLAYER_A, REJOIN_A, int(player.get("ownership_epoch", 0)), i,
			{"move_x":x,"move_z":0.0,"look_yaw":0.4251206143591745,"look_pitch":0.0,
			 "jump_pressed":false,"sprint":true,"delta_seconds":1.0/60.0}, 1.0/60.0)
		_ok(motion, "post-recovery seam movement %d" % i)
		if not bool(motion.get("success", false)):
			break
		seam=restarted.get_product_seam_state(PLAYER_A)
		if int(seam.get("roundtrips", 0))>=1:
			roundtrip=true
			break
	_assert(saw_secondary, "post-recovery primary->secondary actual transfer")
	_assert(roundtrip, "post-recovery secondary->primary roundtrip")
	var after_seam: Dictionary=restarted.create_snapshot()
	_assert(Array(after_seam.get("players",[])).size()==2, "two players retained through post-recovery seam")
	var report: Dictionary=restarted.get_report()
	var seam_report: Dictionary=Dictionary(report.get("user1_product_seam",{}))
	_assert(int(seam_report.get("transfer_failures",-1))==0, "no transfer failure after durable restore")
	_assert(int(seam_report.get("active_binding_count",-1))==0, "no dangling transfer gates after recovery roundtrip")
	_ok(restarted.shutdown(),"shutdown restart")
	if errors.is_empty():
		print("USER1 POST-RESTORE SEAM PORT REBIND: PASS (%d assertions, 0 failures)" % n)
		quit(0)
	else:
		print("USER1 POST-RESTORE SEAM PORT REBIND: FAIL (%d assertions, %d failures)" % [n,errors.size()])
		quit(1)
