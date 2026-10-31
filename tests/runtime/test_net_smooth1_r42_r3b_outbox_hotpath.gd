extends SceneTree

# R3B: staging must not invoke a full recovery/report export simply to
# retrieve authoritative tick/revision. The external M6 schema and durable
# retry identity remain byte-for-byte compatible with the canonical builder.
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Outbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

class CheapClockFixture:
	extends RefCounted
	var slow_report_calls := 0
	func export_replay_state() -> Dictionary:
		return {}
	func restore_replay_state(_state: Dictionary) -> Dictionary:
		return {"success": true}
	func validate_replay_state(_state: Dictionary) -> Dictionary:
		return {"success": true}
	func has_durable_replay_operation(_id: String) -> bool:
		return true
	func get_report() -> Dictionary:
		slow_report_calls += 1
		return {"server_tick": 9999, "revision": 9999}
	func get_outbox_clock() -> Dictionary:
		return {"server_tick": 123, "revision": 456}

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var cheap = CheapClockFixture.new()
	var lightweight = Outbox.new()
	check(_ok(lightweight.setup(cheap)), "fake service accepted by outbox")
	var staging: Dictionary = lightweight.stage_committed(
		"operation/r3b/outbox/cheap-clock", "ITEM",
		{"payload": {"nested": ["a", 1]}, "result": {"success": true}})
	check(_ok(staging), "outbox stage through cheap clock passes")
	check(cheap.slow_report_calls == 0, "no full service.get_report on ITEM capture")
	var record: Dictionary = Dictionary(staging.get("details", {}).get("record", {}))
	check(int(record.get("committed_at_tick", -1)) == 123, "real tick selected")
	check(int(record.get("service_revision", -1)) == 456, "real revision selected")
	var malformed = lightweight.stage_committed(
		"operation/r3b/outbox/reject-vector", "ITEM", {"invalid": Vector3.ONE})
	check(not _ok(malformed), "invalid non-JSON payload still rejected")

	var service = Service.new()
	check(_ok(service.setup("simulation/r3b/outbox", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/r3b/outbox",
	})), "canonical service configured")
	var join_op := "operation/r3b/outbox/join-a"
	check(_ok(service.join("a", "transport-session/r3b/outbox/a/1", join_op)),
		"canonical JOIN committed in replay")
	var outbox = Outbox.new()
	check(_ok(outbox.setup(service)), "canonical outbox configured")
	var clock: Dictionary = service.get_outbox_clock()
	var full: Dictionary = service.get_report()
	check(int(clock.get("server_tick", -1)) == int(full.get("server_tick", -2)),
		"cheap tick equals full legacy tick")
	check(int(clock.get("revision", -1)) == int(full.get("revision", -2)),
		"cheap revision equals full legacy revision")
	var payload := {
		"logical_player_id": "a",
		"success": true,
		"result": {"details": {"nested": {"value": 42}}},
	}
	check(_ok(outbox.stage_committed(join_op, "JOIN", payload)),
		"real canonical operation staged")
	var detached: Dictionary = outbox.to_dict()
	check(_ok(outbox.validate(detached)), "M6 checksum and full replay validation preserved")
	var expected: Dictionary = Utils.finalize_json_checksum({
		"schema": Outbox.SCHEMA,
		"next_sequence": 2,
		"gameplay_replay": service.export_replay_state(),
		"committed_outbox": outbox.get_records(),
		"checksum": "",
	})
	check(String(expected.get("checksum", "")) == String(detached.get("checksum", "")),
		"optimized to_dict is identical to canonical deep-copy composition")
	var frozen_sha := String(detached.get("checksum", ""))
	payload["result"]["details"]["nested"]["value"] = -10
	detached["committed_outbox"][0]["payload"]["result"]["details"]["nested"]["value"] = 9999
	detached["gameplay_replay"].clear()
	check(String(outbox.to_dict().get("checksum", "")) == frozen_sha,
		"mutating caller/returned DTO cannot corrupt detached M6 outbox")
	check(int(outbox.get_records()[0].get("sequence", -1)) == 1,
		"outbox FIFO sequence and replay identity preserved")
	service.shutdown()
	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH1_R42_R3B_OUTBOX_HOTPATH: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))

func check(success: bool, description: String) -> void:
	assertions += 1
	if not success:
		failures.append(description)
