extends SceneTree

# R4.2-P0 checksum falsifier for the REAL USER1 seam projection.
# The old path re-hashed raw secondary-owned movement/presentation floats;
# the ordinary PlayerSnapshot.create() path had stabilized those floats in r31.
# This test requires real A -> secondary and B reconnect, not a mocked seam.
const Seam = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const A := "net-r42-seam-a"
const B := "net-r42-seam-b"
const A1 := "transport-session/net-r42/seam/a1"
const B1 := "transport-session/net-r42/seam/b1"
const B2 := "transport-session/net-r42/seam/b2"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = Seam.new()
	check(_ok(service.setup("authority/net-r42/seam", 1, 0, {
		"profile": "MULTIPLAYER_CORE", "topology_adapter": "ENET",
		"region_id": "region/m3/single-server",
		"playable_sandbox": true, "fixed_tick_authority": true,
	})), "real USER1 service configured")
	check(_ok(service.join(A, A1, "operation/net-r42/seam/join/a1")), "A joined")
	check(_ok(service.join(B, B1, "operation/net-r42/seam/join/b1")), "B joined")
	var a_epoch: int = int(service.get_player(A).get("ownership_epoch", 0))
	var b_epoch: int = int(service.get_player(B).get("ownership_epoch", 0))
	var crossed := false
	var tick := 0
	for seq in range(1, 801):
		tick += 1
		var advanced: Dictionary = service.advance_fixed_server_tick(tick)
		if not _ok(advanced):
			check(false, "fixed step to secondary")
			break
		var moved: Dictionary = service.simulate_fixed_movement_tick(
			A, A1, a_epoch, seq,
			{"move_x": 1.0, "move_z": 0.0, "look_yaw": 0.4251206143591745,
			 "look_pitch": 0.0, "jump_pressed": false, "sprint": true,
			 "delta_seconds": 1.0 / 60.0}, 1.0 / 60.0
		)
		if not _ok(moved):
			check(false, "authoritative A fixed movement")
			break
		if String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b":
			crossed = true
			break
	check(crossed, "A crossed to real secondary movement owner")
	if not crossed:
		service.shutdown()
		_finish()
		return

	# Build one known wire-sensitive, valid yaw using the real r31 scalar
	# normalization. The numeric source is authority-owned and must not change.
	var sensitive := 0.0
	var found := false
	for n in range(1, 2000):
		var candidate: float = sin(float(n) * 0.1415) / 11.0
		if candidate != Full._wire_number(candidate):
			sensitive = candidate
			found = true
			break
	check(found, "found raw float that differs from JSON wire fixed point")
	if not found:
		service.shutdown()
		_finish()
		return
	var old_source := service.get_player(A)
	var presented: Dictionary = service.set_player_presentation(
		A, A1, a_epoch, sensitive, false, "operation/net-r42/seam/presentation/1"
	)
	check(_ok(presented), "secondary-owned presentation mutation applied")
	check(float(service.get_player(A).get("orientation_yaw", 0.0)) == sensitive,
		"live secondary yaw not numerically changed for checksum")
	check(service.get_player(A).get("position", {}) == old_source.get("position", {}),
		"no accidental authoritative position mutation")
	var remote_snapshot: Dictionary = service.create_snapshot()
	check(_ok(Full.validate(remote_snapshot)), "remote full snapshot valid before transport")
	check(_frame_keeps_full_checksum(remote_snapshot, "remote-presentation"),
		"remote full snapshot checksum survives real Protocol Frame V2")

	# Real transport leave and reconnect while A is still owned by secondary.
	check(_ok(service.leave_transport_session(
		B1, "operation/net-r42/seam/leave/b1")), "B disconnected while A remote")
	var joined: Dictionary = service.join(
		B, B2, "operation/net-r42/seam/join/b2"
	)
	check(_ok(joined), "B rejoined while A secondary")
	var join_snapshot: Dictionary = Dictionary(joined.get("details", {}).get("snapshot", {}))
	check(_ok(Full.validate(join_snapshot)), "actual B join snapshot valid at source")
	check(_frame_keeps_full_checksum(join_snapshot, "b-reconnect-join"),
		"real B reconnect JOIN_ACK snapshot stays checksum-valid on wire")
	check(int(service.get_player(B).get("ownership_epoch", 0)) == b_epoch + 1,
		"B ownership epoch increments once")
	check(String(service.get_product_seam_state(A).get("region_id", "")) == "region/user1/b",
		"A keeps secondary authority through B reconnect")

	# This negative must remain rejected even when a new outer frame checksum
	# authenticates the tampered payload: nested full checksum is independent.
	var tampered: Dictionary = join_snapshot.duplicate(true)
	var player_rows: Array = tampered.get("players", [])
	if not player_rows.is_empty():
		var player: Dictionary = player_rows[0]
		var vel: Dictionary = player.get("velocity", {})
		vel["x"] = float(vel.get("x", 0.0)) + 0.5
		var tamper_frame := _frame_roundtrip(tampered, "tamper")
		check(_ok(tamper_frame), "tampered nested snapshot still has legitimate outer frame")
		if _ok(tamper_frame):
			check(not _ok(Full.validate(Dictionary(tamper_frame.get("details", {}).get("snapshot", {})))),
				"nested tamper cannot bypass full SHA-256 validation")
	else:
		check(false, "two real players required for tamper falsifier")
	service.shutdown()
	_finish()


func _frame_roundtrip(full: Dictionary, label: String) -> Dictionary:
	var encoded_frame: Dictionary = Frame.create(
		"frame/net-r42/seam/" + label, B2, 14, "RESYNC", "RELIABLE_ORDERED",
		"planet_simulator.m3.graphical_multiplayer_message.v1",
		{"type": "JOIN_ACK", "operation_id": "operation/net-r42/seam/join/b2",
		 "snapshot": full}
	)
	var packet: Dictionary = Frame.encode(encoded_frame)
	if not _ok(packet):
		return packet
	var decoded: Dictionary = Frame.decode(packet.get("details", {}).get("packet", PackedByteArray()))
	if not _ok(decoded):
		return decoded
	return {"success": true, "details": {
		"snapshot": Dictionary(decoded.get("details", {}).get("frame", {}).get("payload", {}).get("snapshot", {}))
	}}


func _frame_keeps_full_checksum(full: Dictionary, label: String) -> bool:
	var result: Dictionary = _frame_roundtrip(full, label)
	if not _ok(result):
		return false
	return _ok(Full.validate(Dictionary(result.get("details", {}).get("snapshot", {}))))


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)


func _finish() -> void:
	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH1_R42_SEAM_FULL_WIRE: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)
