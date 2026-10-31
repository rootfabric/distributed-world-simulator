extends SceneTree

# NET-SMOOTH1 R3.1: player-local transport operations may not disturb another
# player's active SM1 secondary movement authority binding.
const SeamService = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")

const A := "netsmooth-remote-a"
const B := "netsmooth-reconnect-b"
const C := "netsmooth-late-c"
const A1 := "transport-session/netsmooth/reconnect/a1"
const B1 := "transport-session/netsmooth/reconnect/b1"
const B2 := "transport-session/netsmooth/reconnect/b2"
const C1 := "transport-session/netsmooth/reconnect/c1"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = SeamService.new()
	check_ok(service.setup("authority/netsmooth/reconnect", 1, 0, {
		"profile": "MULTIPLAYER_CORE", "topology_adapter": "ENET",
		"region_id": "region/m3/single-server",
		"playable_sandbox": true, "fixed_tick_authority": true,
	}), "setup")
	check_ok(service.join(A, A1, "operation/netsmooth/join/a1"), "join A")
	check_ok(service.join(B, B1, "operation/netsmooth/join/b1"), "join B")
	var a_before: Dictionary = service.get_player(A)
	var a_entity := String(a_before.get("player_entity_id", ""))
	var a_epoch := int(a_before.get("ownership_epoch", 0))
	var b_before: Dictionary = service.get_player(B)
	var b_entity := String(b_before.get("player_entity_id", ""))
	var b_epoch := int(b_before.get("ownership_epoch", 0))
	var crossed := false
	var tick := 0
	var seq := 0
	for _i in range(800):
		tick += 1
		var advanced: Dictionary = service.advance_fixed_server_tick(tick)
		if not bool(advanced.get("success", false)):
			check_ok(advanced, "advance fixed tick")
			break
		seq += 1
		var moved: Dictionary = service.simulate_fixed_movement_tick(
			A, A1, a_epoch, seq,
			{"move_x":1.0,"move_z":0.0,"look_yaw":0.4251206143591745,
			 "look_pitch":0.0,"jump_pressed":false,"sprint":true,
			 "delta_seconds":1.0/60.0},
			1.0/60.0
		)
		if not bool(moved.get("success", false)):
			check_ok(moved, "A fixed movement")
			break
		if String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b":
			crossed = true
			break
	check(crossed, "A crossed physically to secondary authority")
	check(service.can_persist_product_state(), "remote A ACTIVE persistence stays quiescent")
	var remote_a: Dictionary = service.get_product_seam_state(A)
	var remote_a_epoch := int(remote_a.get("authority_epoch", 0))
	check(String(remote_a.get("region_id", "")) == "region/user1/b", "A remote before other player transport changes")

	# This was globally rejected before R3.1, although C has no transfer row.
	check_ok(service.join(C, C1, "operation/netsmooth/join/c1"), "late C joins while A remains remote")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b", "late JOIN does not return A to primary")
	check_ok(service.leave(C, C1, "operation/netsmooth/leave/c1"), "C direct leave while A remote")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b", "C direct leave does not force-return A")
	check_ok(service.leave_transport_session("transport-session/netsmooth/reconnect/unknown", "operation/netsmooth/leave/unknown"), "stale transport leave replays safely")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b", "unknown leave does not alter A")

	# A disconnect by B must never force-return unrelated remote A.
	check_ok(service.leave_transport_session(B1, "operation/netsmooth/leave/b1"), "B transport-session leave")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b", "B leave does not force-return A")
	check_ok(service.join(B, B2, "operation/netsmooth/join/b2"), "B reconnects while A remote")
	var b_after: Dictionary = service.get_player(B)
	check(String(b_after.get("transport_session_id", "")) == B2, "B reconnect owns new session")
	check(int(b_after.get("ownership_epoch", 0)) == b_epoch+1, "B reconnect increments epoch once")
	check(String(b_after.get("player_entity_id", "")) == b_entity, "B entity identity preserved")
	var a_after: Dictionary = service.get_player(A)
	check(String(a_after.get("player_entity_id", "")) == a_entity, "A entity identity preserved")
	check(int(a_after.get("ownership_epoch", 0)) == a_epoch, "A ownership epoch unaffected by B reconnect")
	check(String(a_after.get("transport_session_id", "")) == A1, "A session unaffected")
	check(int(service.get_product_seam_state(A).get("authority_epoch", 0)) == remote_a_epoch, "A remote authority epoch unaffected")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b", "A stays secondary after B rejoin")
	# Both players must remain simulatable immediately after the transport
	# ownership transition; inspecting snapshots alone is insufficient.
	tick += 1
	check_ok(service.advance_fixed_server_tick(tick), "fixed tick continues after B reconnect")
	seq += 1
	check_ok(service.simulate_fixed_movement_tick(
		A, A1, a_epoch, seq,
		{"move_x":1.0,"move_z":0.0,"look_yaw":0.4251206143591745,
		 "look_pitch":0.0,"jump_pressed":false,"sprint":true,"delta_seconds":1.0/60.0},
		1.0/60.0
	), "A remote fixed movement after B rejoin")
	check_ok(service.simulate_fixed_movement_tick(
		B, B2, b_epoch+1, 1,
		{"move_x":0.0,"move_z":-1.0,"look_yaw":0.0,
		 "look_pitch":0.0,"jump_pressed":false,"sprint":false,"delta_seconds":1.0/60.0},
		1.0/60.0
	), "B fixed movement after reconnect")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b", "A remains remote after both movement updates")
	var snapshot: Dictionary = service.create_snapshot()
	check_ok(service.validate_snapshot(snapshot), "aggregate snapshot validates with A remote and B rejoined")
	var durable: Dictionary = service.export_durable_state()
	check(not durable.is_empty(), "aggregate durable export exists with A remote + B rejoined")
	if not durable.is_empty():
		check_ok(service.validate_durable_state(durable), "aggregate durable snapshot validates")

	# Same remote identity must still be guarded from a new session until
	# its own live movement transfer is quiesced. Avoid stealing an active row.
	var forbidden: Dictionary = service.join(A,"transport-session/netsmooth/reconnect/a2","operation/netsmooth/join/a2")
	check(not bool(forbidden.get("success", false)), "same remote A does not bypass authority transfer gate")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b", "rejected A rejoin does not mutate authority")
	var b_replay: Dictionary = service.join(B,B2,"operation/netsmooth/join/b2")
	check_ok(b_replay, "B retry of same canonical JOIN succeeds as replay")
	check(String(service.get_player(B).get("transport_session_id", "")) == B2, "B retry did not replace session")
	check(int(service.get_player(B).get("ownership_epoch", 0)) == b_epoch+1, "B retry did not increment epoch twice")
	check_ok(service._force_all_primary(), "explicit global quiescence remains possible")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/a", "explicit global quiescence returns A to primary")

	service.shutdown()
	for detail in failures:
		push_error(detail)
	print("NET_SMOOTH1_REMOTE_RECONNECT: %s assertions=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check_ok(result: Dictionary, title: String) -> void:
	check(bool(result.get("success", false)), title + " error=" + String(result.get("error_code", "")))

func check(good: bool, title: String) -> void:
	assertions += 1
	if not good:
		failures.append(title)
