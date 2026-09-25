extends RefCounted

# Bounded loopback composition over the existing transport boundary. It does
# not replace the network kernel. Per-run capabilities never enter artifacts.
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.mvp3_live_process_message.v1"
const SCENE_PATH := "res://scenes/labs/mvp/v0_mvp3_live_shared_world.tscn"
const ENV_CONFIG := "DWS_MVP3_LIVE_CONFIG"
const MAX_CLIENT_COMMANDS := 240
# Interactive clients submit one distinct fixed-tick operation per held tick
# per player. The interactive session envelope is bounded by the gateway
# timeout: 2 players x 60 fixed ticks/s x 120 s = 14400 distinct operations.
# The operation ledger stays fail-closed with no eviction; this bound only
# sizes its capacity so a legitimate full-length manual session cannot be
# rejected by an evidence-budget exhaustion (LEDGER_CAPACITY_EXCEEDED).
const MAX_INTERACTIVE_LEDGER_OPERATIONS := 16384
const MAX_RPC_CALLS := 8192

static func read_config() -> Dictionary:
	var value = JSON.parse_string(OS.get_environment(ENV_CONFIG))
	if not value is Dictionary:
		return {}
	var cfg: Dictionary = value
	for field in ["run_id", "subject_head", "role", "result_file"]:
		if typeof(cfg.get(field)) != TYPE_STRING or String(cfg[field]).is_empty():
			return {}
	if String(cfg["subject_head"]).length() != 40 or not String(cfg["subject_head"]).is_valid_hex_number(false):
		return {}
	if String(cfg["run_id"]).length() != 32 or not String(cfg["run_id"]).is_valid_hex_number(false):
		return {}
	if cfg["role"] not in ["gateway", "authority/a", "authority/b", "client/a", "client/b"]:
		return {}
	return cfg

static func session(cfg: Dictionary, actor: String) -> String:
	return "transport-session/mvp3/" + String(cfg["run_id"]) + "/" + actor

static func valid_key(key: String) -> bool:
	return key.length() == 64 and key.is_valid_hex_number(false)

static func seal(cfg: Dictionary, sender: String, receiver: String, sequence: int, body: Dictionary, key: String) -> Dictionary:
	if not valid_key(key) or sequence < 1:
		return {}
	var packet := {"schema": SCHEMA, "run_id": cfg["run_id"], "subject_head": cfg["subject_head"], "sender": sender, "receiver": receiver, "sequence": sequence, "body": body.duplicate(true)}
	# Sign the exact JSON representation which enters ProtocolFrame. A native
	# double can shorten by one decimal digit on its first JSON round-trip; a MAC
	# over the pre-transport Variant would then reject an otherwise intact frame.
	var round_trip := Utils.json_round_trip(packet)
	if not bool(round_trip.get("success", false)) or not round_trip.get("value") is Dictionary:
		return {}
	packet = Dictionary(round_trip["value"]).duplicate(true)
	packet["mac"] = Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key.to_utf8_buffer(), Utils.payload_hash(packet).to_utf8_buffer()).hex_encode()
	return packet

static func verify(cfg: Dictionary, packet: Dictionary, sender: String, receiver: String, key: String) -> bool:
	return verify_error(cfg, packet, sender, receiver, key).is_empty()


static func verify_error(cfg: Dictionary, packet: Dictionary, sender: String, receiver: String, key: String) -> String:
	if not valid_key(key):
		return "KEY_INVALID"
	if packet.size() != 8:
		return "FIELD_COUNT_INVALID"
	if packet.get("schema") != SCHEMA:
		return "SCHEMA_INVALID"
	if packet.get("run_id") != cfg.get("run_id") or packet.get("subject_head") != cfg.get("subject_head"):
		return "RUN_SUBJECT_INVALID"
	if packet.get("sender") != sender or packet.get("receiver") != receiver:
		return "ROUTE_INVALID"
	var sequence = packet.get("sequence")
	if typeof(sequence) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(sequence)) or float(sequence) != floorf(float(sequence)) or float(sequence) < 1.0 or float(sequence) > MAX_RPC_CALLS:
		return "SEQUENCE_INVALID"
	if not packet.get("body") is Dictionary or typeof(packet.get("mac")) != TYPE_STRING or String(packet["mac"]).length() != 64:
		return "BODY_OR_MAC_INVALID"
	var unsigned := packet.duplicate(true)
	unsigned.erase("mac")
	var expected := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key.to_utf8_buffer(), Utils.payload_hash(unsigned).to_utf8_buffer()).hex_encode()
	return "" if Crypto.new().constant_time_compare(expected.to_utf8_buffer(), String(packet["mac"]).to_utf8_buffer()) else "MAC_MISMATCH"

static func send(boundary, peer: String, packet: Dictionary) -> Dictionary:
	var built: Dictionary = boundary.create_frame_for_peer(peer, "CONTROL", SCHEMA, packet, "RELIABLE_ORDERED")
	if not bool(built.get("success", false)):
		return built
	return boundary.send_to_peer(peer, built["details"]["frame"])

static func payload(event: Dictionary) -> Dictionary:
	var frame: Dictionary = event.get("frame", {})
	return Dictionary(frame["payload"]).duplicate(true) if frame.get("payload_schema") == SCHEMA and frame.get("payload") is Dictionary else {}

static func failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}

static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}
