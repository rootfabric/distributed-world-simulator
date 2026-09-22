extends SceneTree

const Guard = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_seam_continuity.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
var assertions := 0
var failures := 0


func _init() -> void:
	var mutations: Array[Dictionary] = [
		{"where": "state", "key": "product_session_id", "value": "wrong"},
		{"where": "state", "key": "logical_player_id", "value": "wrong"},
		{"where": "state", "key": "player_entity_id", "value": "wrong"},
		{"where": "state", "key": "spawn_generation", "value": 2},
		{"where": "payload", "key": "gateway_endpoint_id", "value": "wrong"},
		{"where": "payload", "key": "product_session_id", "value": "wrong"},
		{"where": "payload", "key": "authority_epoch", "value": 0},
		{"where": "payload", "key": "authority_epoch", "value": 1.5},
		{"where": "payload", "key": "authority_epoch", "value": 2},
		{"where": "payload", "key": "active_authority_id", "value": "authority/b"},
		{"where": "state", "key": "world_revision", "value": 0},
		{"where": "state", "key": "last_input_sequence", "value": 0},
		{"where": "state", "key": "position_x", "value": 11.0},
		{"where": "state", "key": "position_x", "value": "NaN"},
		{"where": "payload", "key": "state_checksum", "value": "invalid"},
	]
	for mutation in mutations:
		var guard = fresh_guard()
		var initial := packet(1, 0.0, "authority/a", 1)
		check(guard.accept_state(initial).success, "initial valid state")
		var payload := packet(2, 0.25, "authority/a", 1)
		if mutation.where == "state":
			payload.shared_state[mutation.key] = mutation.value
			payload.state_checksum = Support.checksum(payload.shared_state)
		else:
			payload[mutation.key] = mutation.value
		check(not guard.accept_state(payload).success, "reject " + str(mutation))
		check(guard.report().last_state == initial.shared_state, "invalid state cannot change presentation receipt")
		check(not guard.accept_state(packet(2, 0.25, "authority/a", 1)).success, "failure is latched")
	var guard = fresh_guard()
	check(not guard.report().goal_reached, "no fabricated proof before observations")
	check(guard.note_transport("PEER_CONNECTED").success, "actual connection accepted")
	for data in [[1, 0.0, "authority/a", 1], [2, 0.25, "authority/a", 1], [3, 0.5, "authority/a", 1], [4, 0.75, "authority/b", 2], [5, 1.0, "authority/b", 2], [6, 0.75, "authority/b", 2], [7, 0.5, "authority/a", 3]]:
		check(guard.accept_state(packet(data[0], data[1], data[2], data[3])).success, "valid bounded state sequence")
	check(not guard.report().goal_reached, "route labels alone do not prove post-return control")
	check(guard.accept_state(packet(8, 0.25, "authority/a", 3)).success, "first post-return move")
	check(not guard.report().goal_reached, "require two post-return moves")
	var last := packet(9, 0.0, "authority/a", 3)
	check(guard.accept_state(last).success, "second post-return move")
	check(guard.report().goal_reached, "complete observations reach subgate goal")
	var count: int = guard.report().samples.size()
	check(guard.accept_state(last).duplicate, "identical receipt replay is harmless")
	check(guard.report().samples.size() == count, "duplicate does not inflate evidence")
	check(not guard.note_transport("PEER_DISCONNECTED").success, "disconnect fails closed")
	check(not guard.report().goal_reached, "disconnect invalidates earlier goal")
	var reconnect = fresh_guard()
	reconnect.note_transport("PEER_CONNECTED")
	check(not reconnect.note_transport("PEER_CONNECTED").success, "reconnect cannot hide behind assigned counter")
	print("MVP3_CONTINUITY_CONTRACT assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func fresh_guard():
	var guard = Guard.new()
	var expected := Support.canonical_state()
	expected["gateway_endpoint_id"] = Support.GATEWAY_ENDPOINT_ID
	check(guard.configure(expected).success, "expected identity configured")
	return guard


func packet(revision: int, x: float, owner: String, epoch: int) -> Dictionary:
	var state := Support.canonical_state()
	state.world_revision = revision
	state.last_input_sequence = revision
	state.position_x = x
	return {"type": "STATE", "gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID, "product_session_id": Support.PRODUCT_SESSION_ID, "active_authority_id": owner, "authority_epoch": epoch, "shared_state": state, "state_checksum": Support.checksum(state)}


func check(ok: bool, description: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(description)
