extends SceneTree

# #815 genuine policy + live M3 client dispatch hooks; no mocked decoders.
# The full 2048-state real Full/Compact/Frame corpus is a separate exact test.
const Policy = preload("res://scripts/network/contracts/r31_815_compact_codec_negotiation.gd")
const V1 = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const V2 = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot_v2.gd")
const Chain = preload("res://tests/runtime/support/r31_815_real_snapshot_chain.gd")
const Client = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_p2.gd")
const Server = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")

var assertions: int = 0
var failures: Array[String] = []
const ID: String = "handshake/815/real/session-a"
const ID2: String = "handshake/815/real/session-b"
const SESSION: String = "transport-session/m3/a/1/815"
const SESSION2: String = "transport-session/m3/a/2/815"


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures.append(reason)


func result_code(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func clone(value: Dictionary) -> Dictionary:
	return value.duplicate(true)


func _run() -> void:
	for server_mode in Policy.MODES:
		check(bool(Policy.validate_mode(server_mode)["success"]), "server mode accepted " + server_mode)
	for mode in ["bad", "v2", "true", "prefer", "require"]:
		check(not bool(Policy.validate_mode(mode)["success"]), "unknown mode fails closed " + mode)

	var none: Dictionary = {}
	var offer_prefer: Dictionary = Policy.create_offer("prefer_v2", ID)
	var offer_require: Dictionary = Policy.create_offer("require_v2", ID)
	check(offer_prefer.get("formats", []) == [Policy.F64, Policy.LEGACY], "preferred offer explicitly allows v1")
	check(offer_require.get("formats", []) == [Policy.F64], "required offer forbids downgrade")
	check(Policy.create_offer("off", ID).is_empty(), "default sends original HELLO unchanged")
	check(bool(Policy.validate_offer(offer_prefer, ID)["success"]), "preferred offer checksum and schema")
	check(bool(Policy.validate_offer(offer_require, ID)["success"]), "required offer checksum and schema")
	check(result_code(Policy.choose("require_v2", none, ID)) == "COMPACT_CODEC_V2_REQUIRED",
		"required-v2 server refuses legacy client before ACK")
	check(result_code(Policy.choose("require_v2", Policy.create_offer("prefer_v2", ID2), ID)) ==
		"COMPACT_CODEC_OFFER_HANDSHAKE_MISMATCH", "replayed foreign handshake offer rejected")

	for server_mode in Policy.MODES:
		for client_mode in Policy.MODES:
			var offer: Dictionary = Policy.create_offer(client_mode, ID)
			var selected: Dictionary = Policy.choose(server_mode, offer, ID)
			var can_speak: bool = not (server_mode == "require_v2" and client_mode == "off") and not (
				server_mode == "off" and client_mode == "require_v2")
			if not can_speak:
				check(not bool(selected["success"]), "incompatible formats rejected before ACK")
				continue
			check(bool(selected["success"]), "server selected format " + server_mode + "/" + client_mode)
			if not bool(selected["success"]):
				continue
			var format: String = String(selected["details"]["selected"])
			var choice: Dictionary = (
				Policy.create_choice(format, offer, ID)
				if not offer.is_empty() or server_mode != "off" else {}
			)
			var accepted: Dictionary = Policy.client_accept(client_mode, offer, choice, ID)
			check(bool(accepted["success"]) == can_speak,
				"ACK matches client strict mode " + server_mode + "/" + client_mode)
			if can_speak:
				check(String(accepted["details"]["selected"]) == format, "same negotiated format on both ends")
			elif client_mode == "require_v2":
				check(result_code(accepted) == "COMPACT_CODEC_DOWNGRADE_FORBIDDEN",
					"required client never silently falls back to v1")

	var changed: Dictionary = clone(offer_prefer)
	changed["formats"] = [Policy.LEGACY]
	check(result_code(Policy.choose("prefer_v2", changed, ID)) ==
		"COMPACT_CODEC_OFFER_CHECKSUM_MISMATCH", "tampered offer caught")
	changed = clone(offer_prefer)
	changed["formats"] = [Policy.F64, Policy.F64]
	changed["checksum"] = Policy._hash_without_checksum(changed)
	check(result_code(Policy.choose("prefer_v2", changed, ID)) ==
		"COMPACT_CODEC_OFFER_DUPLICATE", "duplicate capabilities denied")
	changed = clone(offer_prefer)
	changed["formats"] = [Policy.F64, "unknown"]
	changed["checksum"] = Policy._hash_without_checksum(changed)
	check(result_code(Policy.choose("prefer_v2", changed, ID)) ==
		"COMPACT_CODEC_OFFER_FORMATS", "unknown capability denied")
	var valid_choice: Dictionary = Policy.create_choice(Policy.F64, offer_prefer, ID)
	changed = clone(valid_choice)
	changed["selected"] = Policy.LEGACY
	check(result_code(Policy.client_accept("prefer_v2", offer_prefer, changed, ID)) ==
		"COMPACT_CODEC_CHOICE_CHECKSUM_MISMATCH", "tampered selected format denied")
	changed = clone(valid_choice)
	changed["offer_checksum"] = "0".repeat(64)
	changed["checksum"] = Policy._hash_without_checksum(changed)
	check(result_code(Policy.client_accept("prefer_v2", offer_prefer, changed, ID)) ==
		"COMPACT_CODEC_CHOICE_OFFER_MISMATCH", "choice bound to exact offer")
	check(result_code(Policy.client_accept("require_v2", offer_require, {}, ID)) ==
		"COMPACT_CODEC_DOWNGRADE_FORBIDDEN", "missing choice forbidden to required v2")

	var full: Dictionary = Chain.make_full(Chain.fixed_witness_players(), 84)
	var v1_encode: Dictionary = V1.encode(full)
	var v2_encode: Dictionary = V2.encode(full)
	check(bool(v1_encode["success"]) and bool(v2_encode["success"]),
		"actual original FullSnapshot accepted by both codecs")
	var wire1: Dictionary = Dictionary(v1_encode["details"]["snapshot"])
	var wire2: Dictionary = Dictionary(v2_encode["details"]["snapshot"])
	var client = Client.new()
	check(bool(client.call("_decode_compact_snapshot", wire1)["success"]),
		"default legacy client still decodes v1 with original validator")
	client.set("_r31_815_client_mode", "require_v2")
	client.set("_handshake_verified", true)
	client.set("_transport_session_id", SESSION)
	client.set("_handshake_id", ID)
	client.set("_r31_815_bound_session", SESSION)
	client.set("_r31_815_bound_handshake", ID)
	client.set("_r31_815_selected", Policy.F64)
	var decoded_v2: Dictionary = client.call("_decode_compact_snapshot", wire2)
	check(bool(decoded_v2["success"]), "M3 product client actually decodes exact v2")
	if bool(decoded_v2["success"]):
		check(Chain.first_numeric_change(full, decoded_v2["details"]["snapshot"]).is_empty(),
			"v2 transport restored every F64 bit and original checksum")
	check(result_code(client.call("_decode_compact_snapshot", wire1)) == "COMPACT_CODEC_VERSION_MISMATCH",
		"no silent v1 fallback for v2 session")
	client.set("_transport_session_id", SESSION2)
	check(result_code(client.call("_decode_compact_snapshot", wire2)) ==
		"COMPACT_CODEC_SESSION_NOT_NEGOTIATED", "old negotiated format never crosses transport reconnect")
	client.set("_transport_session_id", SESSION)
	client.set("_r31_815_selected", Policy.LEGACY)
	check(bool(client.call("_decode_compact_snapshot", wire1)["success"]), "explicit per-session legacy fallback accepted")
	check(result_code(client.call("_decode_compact_snapshot", wire2)) == "COMPACT_CODEC_VERSION_MISMATCH",
		"old session cannot accept unsolicited v2 packet")
	client.free()

	var server = Server.new()
	server.set("_peer_to_session", {"peer/815/a": SESSION})
	server.set("_peer_compatibility", {"peer/815/a": {
		"session_id": SESSION, "handshake_id": ID,
		"compact_codec_format": Policy.F64,
	}})
	check(String(server.call("_r31_815_peer_codec", "peer/815/a")) == Policy.F64,
		"server uses exact bound session for v2 send")
	server.set("_peer_to_session", {"peer/815/a": SESSION2})
	check(String(server.call("_r31_815_peer_codec", "peer/815/a")).is_empty(),
		"server stale-session selection fails closed")
	server.set("_peer_to_session", {"peer/815/a": SESSION})
	server.set("_peer_compatibility", {})
	check(String(server.call("_r31_815_peer_codec", "peer/815/a")).is_empty(),
		"server no handshake cannot send unnegotiated compact")
	server.free()

	for error in failures:
		push_error("NET_SMOOTH_815_NEGOTIATION_FAIL:" + error)
	print("NET_SMOOTH_815_CODEC_NEGOTIATION %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
