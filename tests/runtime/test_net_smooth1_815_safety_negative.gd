extends SceneTree

# SAFETY-815 deterministic negative falsifiers (issues #809/#823/#815).
# In-process stub-level tests only: NO real ENet sockets, NO GUI, NO wall
# clock. Every negative path must fail CLOSED with the EXACT historical
# error code documented in work/ns1-815-safety-r1/SAFETY_815_FINDINGS_RU.md.
#
# Native execution required by the exact pinned Windows/Linux CI workflow;
# tests/tools/test_net_smooth1_815_safety_negative_source_contracts.py
# statically pins this file's fail-closed assertions until the deferred run.
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Compact = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Enet = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const SessionScript = preload("res://scripts/network/transports/v2/network_peer_session.gd")
const Wire = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ConditionSimulator = preload("res://scripts/network/conditions/network_condition_simulator_port.gd")
const ConditionProfile = preload("res://scripts/network/conditions/network_condition_profile.gd")
const Stub = preload("res://tests/runtime/r31p23r21_canonical_enet_stub.gd")

const PEER := "peer/815"
const SESSION_OLD := "transport-session/815/a/1"
const SESSION_NEW := "transport-session/815/a/2"

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func _code(value: Dictionary) -> String:
	return String(value.get("error_code", ""))


func _sample(tick: int) -> Dictionary:
	return Full.create("simulation/m3/dedicated", 1, tick + 1, tick,
		"region/user1/a", [_player("a", float(tick) + 0.5, 2.5, 0.25, 1.5, 1)],
		{"item_id": "item/shared/beacon/1", "available": true,
			"owner_player_entity_id": "", "revision": tick})


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


# Historical first-JOIN shape: player + FULL snapshot + item graph snapshot
# on the reliable RESYNC channel, exactly as JOIN_ACK is sent in product.
func _join_frame(session: String, sequence: int) -> Dictionary:
	return Frame.create(
		"frame/815/join/%d" % sequence, session, sequence,
		"RESYNC", "RELIABLE_ORDERED",
		"planet_simulator.m3.graphical_multiplayer_message.v1", {
			"type": "JOIN_ACK",
			"reason": "JOIN_COMPLETE_815_SENTINEL",
			"player": _player("a", 1.5, 2.5, 0.25, 1.5, 1),
			"snapshot": _sample(3),
			"item_graph_snapshot": {"revision": 1, "entries": []},
			"server_sent_at_ms": 1234,
		})


func _snapshot_frame(session: String, sequence: int) -> Dictionary:
	return Frame.create(
		"frame/815/snap/%d" % sequence, session, sequence,
		"SNAPSHOT", "UNRELIABLE_SEQUENCED",
		"planet_simulator.m3.graphical_multiplayer_message.v1", {
			"type": "COMPACT_GAMEPLAY_SNAPSHOT",
			"reason": "MOVEMENT_NETWORK_TICK",
			"server_sent_at_ms": 1000 + sequence,
			"snapshot": _sample(sequence),
		})


# SAFETY-815 negative test 1: any single-bit payload corruption between the
# server encode and the client decode MUST be detected by the existing
# checksum code as PAYLOAD_CHECKSUM_MISMATCH (fail-closed). Stub-level: the
# real Frame.encode -> bytes -> Frame.decode path is exercised; the real
# boundary maps the decode failure to TRANSPORT_ERROR -> _enter_failed
# (network_transport_boundary_v2.gd:581-583), which is pinned statically in
# tests/tools because the contended host defers the Godot run.
func _join_bit_corruption() -> void:
	var frame: Dictionary = _join_frame(SESSION_OLD, 1)
	check(_ok(Frame.validate(frame)), "815 join frame is checksum valid")
	var encoded: Dictionary = Frame.encode(frame)
	check(_ok(encoded), "815 join frame encodes to canonical bytes")
	if not _ok(encoded):
		return
	var packet: PackedByteArray = Dictionary(encoded["details"])["packet"]
	var marker := String("815_SENTINEL").to_utf8_buffer()
	# PackedByteArray.find accepts ONE integer byte, not an array. Search
	# the exact sentinel byte sequence without false single-byte matches.
	var marker_at: int = -1
	for offset in range(maxi(0, packet.size() - marker.size() + 1)):
		if packet.slice(offset, offset + marker.size()) == marker:
			marker_at = offset
			break
	check(marker_at > 0, "payload sentinel located inside packet bytes")
	if marker_at <= 0:
		return
	var corrupted := packet.duplicate()
	corrupted[marker_at] = corrupted[marker_at] ^ 0x01
	check(corrupted != packet, "exactly one payload byte was flipped")
	var decoded: Dictionary = Frame.decode(corrupted)
	check(not _ok(decoded) and _code(decoded) == "PAYLOAD_CHECKSUM_MISMATCH",
		"corrupted JOIN bytes decode fails CLOSED as PAYLOAD_CHECKSUM_MISMATCH")

	var tampered: Dictionary = frame.duplicate(true)
	tampered["payload"]["reason"] = "JOIN_COMPLETE_815_SENTINELX"
	var validated: Dictionary = Frame.validate(tampered)
	check(not _ok(validated) and _code(validated) == "PAYLOAD_CHECKSUM_MISMATCH",
		"in-memory nested payload tamper keeps EXACT checksum error")

	var enet = Enet.new()
	check(_ok(enet.configure_r31p23r21_single_pass_compact(true)),
		"815 legacy enet parent configured for send-path probe")
	enet.set("_peer", ENetMultiplayerPeer.new())
	enet.set("_mode", "SERVER")
	var refused: Dictionary = enet.send_to_peer(PEER, tampered)
	check(not _ok(refused) and _code(refused) == "PAYLOAD_CHECKSUM_MISMATCH",
		"send path refuses tampered JOIN frame before any packet leaves")
	enet = null


# SAFETY-815 negative test 2: reorder/jitter/duplicate delivery permutations
# MUST NOT mutate frame bytes — every delivered copy decodes checksum-valid;
# a frame actually corrupted between enqueue and dispatch MUST be refused.
func _permutation_unharmed() -> void:
	var stub = Stub.new()
	var sim = ConditionSimulator.new()
	var profile: Dictionary = ConditionProfile.create("REORDER_DUP_815", {
		"outgoing_latency_min_ms": 2, "outgoing_latency_max_ms": 5,
		"jitter_ms": 4, "reorder_percent": 100.0,
		"duplicate_percent": 100.0, "random_seed": 7,
	})
	check(_ok(ConditionProfile.validate(profile)), "815 permutation profile valid")
	check(_ok(sim.setup(stub, profile, null, true, 0)),
		"815 manual-clock simulator configured")
	check(_ok(sim.start_server({})), "815 simulator started without sockets")
	var frame: Dictionary = _snapshot_frame(SESSION_OLD, 1)
	var before: Dictionary = frame.duplicate(true)
	var sent: Dictionary = sim.send_to_peer(PEER, frame)
	check(_ok(sent) and bool(Dictionary(sent.get("details", {})).get("simulated", false)),
		"815 frame queued under reorder/duplicate profile")
	sim.advance_time_ms(10000)
	var drained: Dictionary = sim.drain()
	check(_ok(drained), "815 permutation queue drained deterministically")
	check(stub.accepted.size() >= 2,
		"reorder/duplicate profile delivered the frame plus its duplicate")
	for accepted_value in stub.accepted:
		var accepted: Dictionary = Dictionary(accepted_value)
		var copy: Dictionary = Frame.decode(accepted.get("packet", PackedByteArray()))
		check(_ok(copy),
			"delivered permuted copy decodes checksum-valid: " + _code(copy))
	check(frame == before, "permutation queueing never mutates caller frame")

	# Negative half: corruption introduced BETWEEN enqueue and dispatch is
	# caught by the delegate's mandatory Frame.validate — fail-closed.
	var queued: Dictionary = _snapshot_frame(SESSION_OLD, 2)
	check(_ok(sim.send_to_peer(PEER, queued)), "second 815 frame queued")
	sim.advance_time_ms(10000)
	var queue: Array = sim.get("_outgoing_queue")
	check(not queue.is_empty(), "second frame still held by simulator queue")
	if not queue.is_empty():
		# duplicate_percent is 100% in this profile, so the frame sits in the
		# queue as TWO copies. Every queued copy must be corrupted, otherwise
		# the intact duplicate is legitimately delivered and the fail-closed
		# assertion below would count it as a leak.
		var mutated_queue: Array = queue.duplicate()
		for queue_index in range(mutated_queue.size()):
			var corrupted_item: Dictionary = (
				Dictionary(mutated_queue[queue_index]).duplicate(true)
			)
			var corrupted_held: Dictionary = (
				Dictionary(corrupted_item.get("frame", {})).duplicate(true)
			)
			corrupted_held["payload"]["server_sent_at_ms"] = 999999
			corrupted_item["frame"] = corrupted_held
			mutated_queue[queue_index] = corrupted_item
		var refused_queued: Dictionary = stub.send_to_peer(PEER, mutated_queue[0]["frame"])
		check(not _ok(refused_queued) and
			_code(refused_queued) == "PAYLOAD_CHECKSUM_MISMATCH",
			"delegate validator fails CLOSED on queued-corrupted frame")
		sim.set("_outgoing_queue", mutated_queue)
		var accepted_before: int = stub.accepted.size()
		sim.advance_time_ms(10000)
		sim.drain()
		check(stub.accepted.size() == accepted_before,
			"frame corrupted in queue is refused by delegate validation")
	check(_ok(sim.stop()), "815 permutation simulator stopped")
	stub = null


# SAFETY-815 negative test 3: a stale session can never cross-deliver a
# JOIN_ACK. Port-level SESSION_MISMATCH and boundary-level
# STALE_TRANSPORT_SESSION both fail CLOSED; no "mixed" frame succeeds.
func _session_cross_delivery() -> void:
	var enet = Enet.new()
	check(_ok(enet.configure_r31p23r21_single_pass_compact(true)),
		"815 session probe parent configured")
	enet.set("_peer", ENetMultiplayerPeer.new())
	enet.set("_mode", "SERVER")
	enet.set("_logical_to_numeric", {PEER: 11})
	enet.set("_session_by_peer", {PEER: SESSION_NEW})
	enet.set("_route_generation_by_peer", {PEER: 2})
	var stale_frame: Dictionary = _join_frame(SESSION_OLD, 1)
	check(_ok(Frame.validate(stale_frame)), "stale-session JOIN frame itself valid")
	var refused: Dictionary = enet.send_to_peer(PEER, stale_frame)
	check(not _ok(refused) and _code(refused) == "SESSION_MISMATCH",
		"JOIN_ACK with old session after re-register fails SESSION_MISMATCH")
	enet.set("_logical_to_numeric", {})
	var disconnect_stale: Dictionary = enet.disconnect_peer(PEER, SESSION_OLD)
	check(not _ok(disconnect_stale) and _code(disconnect_stale) == "SESSION_MISMATCH",
		"disconnect with stale session fails SESSION_MISMATCH")
	var disconnect_current: Dictionary = enet.disconnect_peer(PEER, SESSION_NEW)
	check(_ok(disconnect_current), "disconnect with current session succeeds")
	enet = null

	var boundary = Boundary.new()
	var registered: Dictionary = boundary.call("_register_peer",
		PEER, SESSION_OLD, "route/815/a", 1,
		SessionScript.STATE_TRANSPORT_CONNECTED)
	check(_ok(registered), "815 boundary registers first session")
	var stale: Dictionary = boundary.call("_register_peer",
		PEER, SESSION_NEW, "route/815/a", 1,
		SessionScript.STATE_TRANSPORT_CONNECTED)
	check(not _ok(stale) and _code(stale) == "STALE_TRANSPORT_SESSION",
		"same-generation session change fails STALE_TRANSPORT_SESSION")
	var advanced: Dictionary = boundary.call("_register_peer",
		PEER, SESSION_NEW, "route/815/a", 2,
		SessionScript.STATE_TRANSPORT_CONNECTED)
	check(_ok(advanced), "only a strictly newer route generation re-registers")
	boundary = null


# SAFETY-815 negative test 4: an authority epoch change between proof
# preparation and send must fail CLOSED before any JOIN payload leaves, with
# the exact attested error codes; packet tampering keeps the checksum error.
func _authority_epoch_fences() -> void:
	var source = RefCounted.new()
	var enet = Enet.new()
	check(_ok(enet.configure_r31p23r21_single_pass_compact(true)),
		"815 attested parent R2.1 configured")
	check(_ok(enet.configure_r31p23r22_attested_compact(
		true, source, "authority/815", 7)),
		"815 attested R2.2 configured with epoch 7")
	enet.set("_peer", ENetMultiplayerPeer.new())
	enet.set("_mode", "SERVER")
	enet.set("_logical_to_numeric", {PEER: 11})
	enet.set("_session_by_peer", {PEER: SESSION_OLD})
	enet.set("_route_generation_by_peer", {PEER: 3})

	var frame: Dictionary = _snapshot_frame(SESSION_OLD, 10)
	check(_ok(Frame.validate(frame)), "815 attested source frame valid")
	var prepared: Dictionary = enet.r22_prepare_validated_compact(
		source, PEER, frame)
	check(_ok(prepared), "815 proof prepared")
	if not _ok(prepared):
		enet = null
		return
	var ticket: int = int(Dictionary(prepared.get("details", {})).get("ticket", -1))

	# A ticket is consumed BEFORE validating the fence, including failures.
	# Every separate negative must mint a FRESH proof; otherwise a replay
	# error would mask an incorrect epoch/route/session verifier.
	enet.set("_r22_authority_epoch", 8)
	var authority: Dictionary = enet.call("_r22_take_attestation",
		source, PEER, ticket)
	check(not _ok(authority) and _code(authority) == "R31P23R22_AUTHORITY_CHANGED",
		"epoch change fails CLOSED as R31P23R22_AUTHORITY_CHANGED")
	var epoch_replayed: Dictionary = enet.call("_r22_take_attestation", source, PEER, ticket)
	check(not _ok(epoch_replayed) and _code(epoch_replayed) == "R31P23R22_PROOF_MISSING_OR_REPLAYED",
		"failed epoch proof cannot be replayed")
	enet.set("_r22_authority_epoch", 7)

	var p_route: Dictionary = enet.r22_prepare_validated_compact(source, PEER, frame)
	check(_ok(p_route), "fresh proof for route change")
	if _ok(p_route):
		enet.set("_route_generation_by_peer", {PEER: 4})
		var route: Dictionary = enet.call("_r22_take_attestation",
			source, PEER, int(Dictionary(p_route["details"]).get("ticket", 0)))
		check(not _ok(route) and _code(route) == "R31P23R22_ROUTE_CHANGED",
			"route change fails CLOSED as R31P23R22_ROUTE_CHANGED")
		enet.set("_route_generation_by_peer", {PEER: 3})

	var p_session: Dictionary = enet.r22_prepare_validated_compact(source, PEER, frame)
	check(_ok(p_session), "fresh proof for session change")
	if _ok(p_session):
		enet.set("_session_by_peer", {PEER: SESSION_NEW})
		var session: Dictionary = enet.call("_r22_take_attestation",
			source, PEER, int(Dictionary(p_session["details"]).get("ticket", 0)))
		check(not _ok(session) and _code(session) == "SESSION_MISMATCH",
			"session change fails CLOSED as SESSION_MISMATCH")
		enet.set("_session_by_peer", {PEER: SESSION_OLD})

	var p_replay: Dictionary = enet.r22_prepare_validated_compact(source, PEER, frame)
	check(_ok(p_replay), "fresh proof for valid consumption and replay")
	if _ok(p_replay):
		var replay_ticket: int = int(Dictionary(p_replay["details"]).get("ticket", 0))
		var claimed: Dictionary = enet.call("_r22_take_attestation",
			source, PEER, replay_ticket)
		check(_ok(claimed), "valid current authority proof succeeds exactly once")
		var replayed: Dictionary = enet.call("_r22_take_attestation",
			source, PEER, replay_ticket)
		check(not _ok(replayed) and
			_code(replayed) == "R31P23R22_PROOF_MISSING_OR_REPLAYED",
			"proof replay fails CLOSED")

	var damaged: Dictionary = _snapshot_frame(SESSION_OLD, 11)
	var prepared2: Dictionary = enet.r22_prepare_validated_compact(
		source, PEER, damaged)
	check(_ok(prepared2), "second 815 proof prepared")
	if _ok(prepared2):
		var proof: Dictionary = Dictionary(enet.get("_r22_pending")).duplicate(true)
		var packet: PackedByteArray = proof.get("packet", PackedByteArray())
		if not packet.is_empty():
			packet[0] = packet[0] ^ 0x01
			proof["packet"] = packet
			enet.set("_r22_pending", proof)
		var torn: Dictionary = enet.call("_r22_take_attestation",
			source, PEER, int(Dictionary(prepared2["details"]).get("ticket", -1)))
		check(not _ok(torn) and _code(torn) == "PAYLOAD_CHECKSUM_MISMATCH",
			"frozen-packet mutation keeps EXACT PAYLOAD_CHECKSUM_MISMATCH")
	enet = null


# SAFETY-815 negative test 5: Full-vs-Compact normalization divergence is
# caught by the nested checksum, fail-closed, even inside a valid frame.
func _compact_nested_checksum() -> void:
	var source: Dictionary = _sample(5)
	check(_ok(Full.validate(source)), "815 full snapshot source valid")
	var encoded: Dictionary = Compact.encode(source)
	check(_ok(encoded), "815 compact encoding succeeds")
	if not _ok(encoded):
		return
	var body: Dictionary = Dictionary(encoded["details"])["snapshot"]
	check(_ok(Compact.validate(body)), "815 compact body hash immediately valid")

	var scalar_tampered: Dictionary = body.duplicate(true)
	var first: Dictionary = Dictionary(scalar_tampered["p"][0])
	var velocity: Array = first["v"].duplicate()
	velocity[2] = float(velocity[2]) + 0.5
	first["v"] = velocity
	scalar_tampered["p"][0] = first
	check(not _ok(Compact.validate(scalar_tampered)) and
		_code(Compact.validate(scalar_tampered)) ==
			"COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH",
		"compact scalar tamper keeping h fails CLOSED as COMPACT mismatch")

	var h_tampered: Dictionary = body.duplicate(true)
	var original_h: String = String(h_tampered["h"])
	# A fixed last nibble could already be 0. Always mutate this checksum.
	h_tampered["h"] = original_h.substr(0, 63) + ("1" if original_h.ends_with("0") else "0")
	check(not _ok(Compact.validate(h_tampered)) and
		_code(Compact.validate(h_tampered)) ==
			"COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH",
		"tampered nested h itself fails CLOSED as COMPACT mismatch")

	var resum_ok: Dictionary = body.duplicate(true)
	resum_ok["c"] = "0".repeat(64)
	var resum_copy: Dictionary = resum_ok.duplicate(true)
	resum_copy.erase("h")
	resum_ok["h"] = Wire.payload_hash(resum_copy)
	check(_ok(Compact.validate(resum_ok)),
		"re-signed outer h still passes the compact layer")
	check(not _ok(Compact.decode(resum_ok)),
		"divergent nested FULL checksum is rejected by decode (fail-closed)")

	var frame: Dictionary = Frame.create(
		"frame/815/compact/%d" % 6, SESSION_OLD, 6, "SNAPSHOT",
		"UNRELIABLE_SEQUENCED",
		"planet_simulator.m3.graphical_multiplayer_message.v1",
		{"type": "COMPACT_GAMEPLAY_SNAPSHOT", "snapshot": scalar_tampered})
	var wire: Dictionary = Frame.encode(frame)
	check(_ok(wire), "outer envelope of a tampered compact body still encodes")
	if _ok(wire):
		var decoded: Dictionary = Frame.decode(
			Dictionary(wire["details"])["packet"])
		check(_ok(decoded),
			"outer frame checksum cannot see inside nested body")
		if _ok(decoded):
			var received: Dictionary = Dictionary(
				Dictionary(decoded["details"])["frame"])["payload"]["snapshot"]
			var nested: Dictionary = Compact.decode(received)
			check(not _ok(nested) and
				_code(nested) == "COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH",
				"nested compact checksum catches divergence after full roundtrip")


# SAFETY-815 negative test 6: canonical_json byte-identity roundtrip
# falsifier. The GDScript canonical encoder must produce byte-identical
# text for repeated encodes and across encode/parse/encode roundtrips for a
# fixed vector of frames; any divergence would be the reproducible mechanism
# of incident #815. Limitation: the true cross-machine (two Godot process)
# comparison is deferred with the Godot run; this in-process falsifier pins
# double-encode and JSON roundtrip identity on the same frozen binary.
func _canonical_roundtrip_identity() -> void:
	var vector: Array[Dictionary] = [
		_join_frame(SESSION_OLD, 1),
		_join_frame(SESSION_OLD, 2),
		_snapshot_frame(SESSION_OLD, 3),
		_snapshot_frame(SESSION_OLD, 4),
	]
	var index := 0
	for frame_value in vector:
		var frame: Dictionary = Dictionary(frame_value)
		index += 1
		var first: String = Wire.canonical_json(frame)
		var second: String = Wire.canonical_json(frame.duplicate(true))
		check(not first.is_empty() and first == second,
			"815 canonical double-encode byte identity %d" % index)
		var reparsed = JSON.parse_string(first)
		check(reparsed is Dictionary, "815 canonical text reparses %d" % index)
		if reparsed is Dictionary:
			check(Wire.canonical_json(reparsed) == first,
				"815 canonical encode/parse/encode roundtrip identity %d" % index)
		var wire: Dictionary = Frame.encode(frame)
		check(_ok(wire), "815 fixed vector frame encodes %d" % index)
		if _ok(wire):
			var decoded: Dictionary = Frame.decode(
				Dictionary(wire["details"])["packet"])
			check(_ok(decoded), "815 fixed vector frame decodes %d" % index)
			if _ok(decoded):
				var restored: Dictionary = Dictionary(
					Dictionary(decoded["details"])["frame"])
				check(Wire.canonical_json(restored) == first,
					"815 wire bytes are canonical_json byte-identical %d" % index)
		var hash_one: String = Wire.payload_hash(
			Dictionary(frame["payload"]))
		var hash_two: String = Wire.payload_hash(
			Dictionary(JSON.parse_string(Wire.canonical_json(
				Dictionary(frame["payload"])))))
		check(not hash_one.is_empty() and hash_one == hash_two,
			"815 payload_hash stable across roundtrip %d" % index)


func _run() -> void:
	_join_bit_corruption()
	_permutation_unharmed()
	_session_cross_delivery()
	_authority_epoch_fences()
	_compact_nested_checksum()
	_canonical_roundtrip_identity()
	for failure in failures:
		push_error("NET_SMOOTH_815_SAFETY_NEGATIVE_FAIL:" + failure)
	print("NET_SMOOTH_815_SAFETY_NEGATIVE %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
