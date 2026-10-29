extends SceneTree

# NET-SMOOTH1 R3.1: Godot double JSON parse can alter a numeric last digit.
# Canonical compact + full snapshot checksums MUST survive real frame encoding.
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Compact = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _player(id: String, x: float, z: float, velocity: float, yaw: float, epoch: int) -> Dictionary:
	return {
		"logical_player_id": id, "player_entity_id": "player/" + id,
		"transport_session_id": "transport-session/" + id + "/%d" % epoch,
		"ownership_epoch": epoch, "connected": true,
		"position": {"x": x, "y": 0.0, "z": z},
		"velocity": {"x": velocity, "y": 0.0, "z": -velocity / 11.0},
		"inventory": [], "last_input_sequence": 12, "state_revision": 22,
		"orientation_yaw": yaw, "flashlight_enabled": false,
	}

func _sample(tick: int) -> Dictionary:
	var bases = [0.0, 0.00000000001, -0.0, 10.0, -10.0,
		10.000000000001, -1.0, 0.0000012345678912312345, 12345.12345678, 1.2345678901234567]
	var x: float = bases[tick % bases.size()] + sin(float(tick) * 0.07) * 10.2
	var z: float = bases[(tick + 7) % bases.size()] + cos(float(tick) * 0.13) * 100.4
	var v: float = sin(float(tick) * 0.1415)
	return Full.create("simulation/m3/dedicated", 1, tick + 1, tick, "region/user1/a", [
		_player("a", x, z, v, v, 1),
		_player("b", -x, -z, -v, v / 2.0, tick % 2 + 1),
	], {"item_id": "item/shared/beacon/1", "available": true,
		"owner_player_entity_id": "", "revision": tick})

func _run() -> void:
	for tick in [0, 1, 1954, 1955, 1956, 1957, 1958, 2000, 2016]:
		var source: Dictionary = _sample(tick)
		check(_ok(Full.validate(source)), "source full valid %d" % tick)
		var before: Dictionary = source.duplicate(true)
		var encoded: Dictionary = Compact.encode(source)
		check(_ok(encoded), "compact encoding %d" % tick)
		if not _ok(encoded):
			continue
		var body: Dictionary = Dictionary(encoded.get("details", {}).get("snapshot", {}))
		check(_ok(Compact.validate(body)), "compact hash immediately valid %d" % tick)
		var message: Dictionary = {"type": "COMPACT_GAMEPLAY_SNAPSHOT",
			"reason": "MOVEMENT_NETWORK_TICK", "snapshot": body,
			"server_sent_at_ms": 2345678}
		var frame: Dictionary = Frame.create("frame/netsmooth/r31/%d" % tick,
			"transport-session/netsmooth/b/2", tick+1, "SNAPSHOT",
			"UNRELIABLE_SEQUENCED", "planet_simulator.m3.graphical_multiplayer_message.v1", message)
		check(_ok(Frame.validate(frame)), "outer frame hash valid %d" % tick)
		var packet: Dictionary = Frame.encode(frame)
		check(_ok(packet), "frame bytes encode %d" % tick)
		if not _ok(packet):
			continue
		var decoded_frame: Dictionary = Frame.decode(packet.get("details", {}).get("packet", PackedByteArray()))
		check(_ok(decoded_frame), "outer frame bytes hash valid %d" % tick)
		if not _ok(decoded_frame):
			continue
		var received: Dictionary = Dictionary(decoded_frame.get("details", {}).get("frame", {}).get("payload", {}).get("snapshot", {}))
		var decoded: Dictionary = Compact.decode(received)
		check(_ok(decoded), "nested compact + full checksums valid %d" % tick)
		if _ok(decoded):
			var restored: Dictionary = Dictionary(decoded.get("details", {}).get("snapshot", {}))
			check(_ok(Full.validate(restored)), "restored FullSnapshot valid %d" % tick)
			var p: Dictionary = Dictionary(Array(restored.get("players", []))[0])
			var oldp: Dictionary = Dictionary(Array(before.get("players", []))[0])
			var diff: float = absf(float(Dictionary(p.get("velocity", {})).get("z", 0)) - float(Dictionary(oldp.get("velocity", {})).get("z", 0)))
			check(diff < 0.000000000001, "velocity preserved below picometer per tick %d" % tick)
		check(source == before, "authority source not mutated %d" % tick)
		# Reliable GAMEPLAY_SNAPSHOT uses the same full checksum contract.
		var full_frame: Dictionary = Frame.create("frame/netsmooth/full/%d" % tick,
			"transport-session/netsmooth/b/2", tick + 100, "RESYNC",
			"RELIABLE_ORDERED", "planet_simulator.m3.graphical_multiplayer_message.v1",
			{"type": "GAMEPLAY_SNAPSHOT", "snapshot": source})
		var full_wire: Dictionary = Frame.encode(full_frame)
		check(_ok(full_wire), "full snapshot frame encodes %d" % tick)
		if _ok(full_wire):
			var full_decoded_frame: Dictionary = Frame.decode(full_wire.get("details", {}).get("packet", PackedByteArray()))
			check(_ok(full_decoded_frame), "full snapshot frame checksum %d" % tick)
			if _ok(full_decoded_frame):
				var from_full_frame: Dictionary = Dictionary(full_decoded_frame.get("details", {}).get("frame", {}).get("payload", {}).get("snapshot", {}))
				check(_ok(Full.validate(from_full_frame)), "full snapshot still checksums after JSON frame %d" % tick)

	# Tamper with nested compact values. Valid outer envelope cannot make it OK.
	var good: Dictionary = Dictionary(Compact.encode(_sample(1956)).get("details", {}).get("snapshot", {}))
	var tampered: Dictionary = good.duplicate(true)
	var p0: Dictionary = tampered["p"][0]
	var vel: Array = p0["v"]
	vel[2] = float(vel[2]) + 0.1
	check(not _ok(Compact.validate(tampered)), "tamper to compact numeric detected")
	check(not _ok(Compact.decode(tampered)), "tamper cannot decode even if outer frame is valid")
	var tampered_full: Dictionary = good.duplicate(true)
	tampered_full["c"] = "0000000000000000000000000000000000000000000000000000000000000000"
	var copy: Dictionary = tampered_full.duplicate(true)
	copy.erase("h")
	tampered_full["h"] = Utils.payload_hash(copy)
	check(_ok(Compact.validate(tampered_full)), "re-signed compact h passes direct compact check")
	check(not _ok(Compact.decode(tampered_full)), "invalid nested full checksum is rejected")

	for fail in failures:
		push_error(fail)
	print("NET_SMOOTH1_R31_COMPACT_WIRE: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _ok(v: Dictionary) -> bool:
	return bool(v.get("success", false))

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
