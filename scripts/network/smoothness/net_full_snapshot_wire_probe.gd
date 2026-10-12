extends RefCounted

# R4.2-P0 forensic metadata, NOT an alternate validator or a checksum bypass.
# Opt in with DWS_NET_FULL_CHECKSUM_PROBE=1 and existing SmoothTrace output.
# Never records player IDs, sessions, message bodies, raw payload values or
# network packets. Only stage, summary counts and SHA-256 digests are emitted.
const SmoothTrace = preload("res://scripts/network/smoothness/net_smooth_trace.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")


static func capture(stage: String, snapshot: Dictionary) -> void:
	if OS.get_environment("DWS_NET_FULL_CHECKSUM_PROBE") != "1" or not SmoothTrace.enabled():
		return
	var source_validation: Dictionary = Full.validate(snapshot)
	var source_payload: Dictionary = snapshot.duplicate(true)
	source_payload.erase("checksum")
	var source_hash: String = Utils.payload_hash(source_payload)
	var copied: Dictionary = Utils.json_round_trip(snapshot)
	var wire_value = copied.get("value", {})
	var wire_snapshot: Dictionary = Dictionary(wire_value) if wire_value is Dictionary else {}
	var wire_validation: Dictionary = (
		Full.validate(wire_snapshot) if not wire_snapshot.is_empty()
		else {"success": false, "error_code": "PROBE_WIRE_ROUNDTRIP_FAILED"}
	)
	var wire_payload: Dictionary = wire_snapshot.duplicate(true)
	wire_payload.erase("checksum")
	var wire_hash: String = Utils.payload_hash(wire_payload)
	SmoothTrace.emit("full_snapshot_wire_probe", {
		"stage": stage,
		"revision": int(snapshot.get("revision", -1)),
		"server_tick": int(snapshot.get("server_tick", -1)),
		"player_count": Array(snapshot.get("players", [])).size() if snapshot.get("players") is Array else -1,
		"declared_sha256": String(snapshot.get("checksum", "")),
		"source_sha256": source_hash,
		"after_json_sha256": wire_hash,
		"source_valid": bool(source_validation.get("success", false)),
		"source_error": String(source_validation.get("error_code", "")),
		"after_json_valid": bool(wire_validation.get("success", false)),
		"after_json_error": String(wire_validation.get("error_code", "")),
		"json_roundtrip_ok": bool(copied.get("success", false)),
	})
