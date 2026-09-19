extends SceneTree

const Bridge = preload("res://scripts/research/ecology/v2/world_seam_binding_v1.gd")
const WorldBinding = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const Seam = preload("res://scripts/research/ecology/v2/snapshot_seam_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_R3_FAIL " + message)

func _command(seam, op_id: String, kind: String, args: Dictionary, actor: String = "", epoch: int = -1) -> Dictionary:
	var c: Dictionary = seam.cursor()
	return {
		"op_id": op_id,
		"kind": kind,
		"actor": String(c["owner_id"]) if actor.is_empty() else actor,
		"epoch": int(c["owner_epoch"]) if epoch < 0 else epoch,
		"revision": int(c["revision"]),
		"clock": int(c["clock"]) + 1,
		"args": args.duplicate(true),
	}

func _region(owner: String, epoch: int, lifecycle: String, revision: int, region_id: String = "region/a", selector: Dictionary = {}) -> Dictionary:
	var actual_selector := selector
	if actual_selector.is_empty():
		actual_selector = {"kind": "GLOBAL_SPACE", "partition_prefix": "", "chunk_ids": []}
	return Region.create(
		region_id, "universe/main", "instance/main", "space/surface",
		"octree", 7, actual_selector, owner, epoch, lifecycle, revision
	)

func _run() -> void:
	var protocol := Protocol.manifest()
	_check(not protocol.is_empty(), "A7 protocol is available")
	var treatment := Protocol.treatment()
	_check(Protocol.valid_treatment(treatment, protocol), "A7 treatment fixture is valid")

	var seam = Seam.new()
	_check(seam.start(treatment, "organism/a", "region/a", "node/a", 1), "real A8 seam starts")
	var before_ecology := seam.ecology_text()
	_check(not before_ecology.is_empty(), "A8 ecology payload exists")
	var before_cursor := seam.cursor()
	_check(before_cursor["owner_id"] == "node/a" and before_cursor["owner_epoch"] == 1, "A8 source cursor")

	var source := _region("node/a", 1, "ACTIVE", 10)
	var target_warm := _region("node/b", 2, "WARM", 11)
	var target_active := _region("node/b", 2, "ACTIVE", 12)
	_check(bool(Region.validate(source).get("success", false)), "source production Region valid")
	_check(bool(Region.validate(target_warm).get("success", false)), "target WARM production Region valid")
	_check(bool(WorldBinding.admit_cursor(before_cursor, source).get("success", false)), "R1 admits source A8 cursor")
	var premature_target_cursor := before_cursor.duplicate(true)
	premature_target_cursor["owner_id"] = "node/b"
	premature_target_cursor["owner_epoch"] = 2
	var warm_admission := WorldBinding.admit_cursor(premature_target_cursor, target_warm)
	_check(not bool(warm_admission.get("success", false)) and warm_admission.get("error") == "A10_REGION_NOT_EXECUTABLE", "WARM target cannot execute ecology before commit")

	var prepared := Bridge.prepare_ticket(before_cursor, source, target_warm, int(before_cursor["clock"]) + 1, int(before_cursor["clock"]) + 100)
	_check(bool(prepared.get("success", false)), "R3 prepares production handoff ticket")
	if not bool(prepared.get("success", false)):
		_finish()
		return
	var ticket: Dictionary = prepared["ticket"]
	_check(bool(Ticket.validate(ticket).get("success", false)) and ticket["state"] == "REQUESTED", "prepared ticket is canonical REQUESTED")
	var premature := Bridge.admit_committed(before_cursor, target_active, ticket)
	_check(not bool(premature.get("success", false)) and premature.get("error") == "A10_R3_TICKET_NOT_COMMITTED", "REQUESTED ticket cannot authorize target")

	var begin := _command(seam, "a10.r3.begin", "BEGIN", {"ticket": ticket})
	var result := seam.apply(begin, seam.snapshot_hash())
	_check(bool(result.get("success", false)) and not bool(result.get("replay", false)), "A8 BEGIN accepted")

	for raw_state in ["PREPARING", "FROZEN", "SNAPSHOT_READY", "TARGET_PREPARED", "COMMITTED"]:
		var state: String = String(raw_state)
		var live_ticket: Dictionary = seam.ticket_snapshot()
		var target_ack: bool = state == "TARGET_PREPARED"
		var payload_hash: String = String(live_ticket.get("snapshot_hash", "")) if target_ack else ""
		var actor: String = "node/b" if target_ack else String(seam.cursor()["owner_id"])
		var epoch: int = 2 if target_ack else int(seam.cursor()["owner_epoch"])
		var cmd := _command(
			seam,
			"a10.r3." + state.to_lower(),
			"TRANSITION",
			{"ticket_id": String(live_ticket["ticket_id"]), "state": state, "payload_hash": payload_hash},
			actor,
			epoch
		)
		var received: String = seam.ecology_text() if target_ack else ""
		result = seam.apply(cmd, seam.snapshot_hash(), received)
		_check(bool(result.get("success", false)) and not bool(result.get("replay", false)), "A8 transition " + state)

	var after_cursor := seam.cursor()
	var committed := seam.ticket_snapshot()
	_check(committed["state"] == "COMMITTED" and bool(Ticket.validate(committed).get("success", false)), "real production ticket reaches COMMITTED")
	_check(after_cursor["owner_id"] == "node/b" and after_cursor["owner_epoch"] == 2, "A8 cursor moved to target owner")
	_check(seam.ecology_text() == before_ecology, "handoff preserves exact biology bytes")
	_check(int(after_cursor["ecology_step"]) == int(before_cursor["ecology_step"]), "handoff does not advance biological tick")

	var old_admission := WorldBinding.admit_cursor(after_cursor, source)
	_check(not bool(old_admission.get("success", false)) and old_admission.get("error") == "A10_CURSOR_OWNER_MISMATCH", "old production owner rejected after commit")
	_check(bool(WorldBinding.admit_cursor(after_cursor, target_active).get("success", false)), "new ACTIVE target Region admits committed cursor")
	_check(bool(Bridge.admit_committed(after_cursor, target_active, committed).get("success", false)), "R3 committed ticket and target Region agree")

	var same_owner := _region("node/a", 2, "WARM", 13)
	var same_owner_result := Bridge.prepare_ticket(before_cursor, source, same_owner, 1, 100)
	_check(not bool(same_owner_result.get("success", false)) and same_owner_result.get("error") == "A10_R3_SAME_OWNER", "same-owner target rejected")

	var stale_epoch := _region("node/b", 1, "WARM", 14)
	var stale_epoch_result := Bridge.prepare_ticket(before_cursor, source, stale_epoch, 1, 100)
	_check(not bool(stale_epoch_result.get("success", false)) and stale_epoch_result.get("error") == "A10_R3_TARGET_EPOCH_NOT_NEWER", "non-increasing target epoch rejected")

	var wrong_region := _region("node/b", 2, "WARM", 15, "region/b")
	var wrong_region_result := Bridge.prepare_ticket(before_cursor, source, wrong_region, 1, 100)
	_check(not bool(wrong_region_result.get("success", false)) and wrong_region_result.get("error") == "A10_R3_SPATIAL_REGION_MISMATCH", "different region rejected")

	var dormant := _region("node/b", 2, "DORMANT", 16)
	var dormant_result := Bridge.prepare_ticket(before_cursor, source, dormant, 1, 100)
	_check(not bool(dormant_result.get("success", false)) and dormant_result.get("error") == "A10_R3_TARGET_NOT_PREPARED", "DORMANT target rejected")

	var changed_selector := {"kind": "CHUNK_SET", "partition_prefix": "", "chunk_ids": ["chunk/other"]}
	var other_space := _region("node/b", 2, "WARM", 17, "region/a", changed_selector)
	var selector_result := Bridge.prepare_ticket(before_cursor, source, other_space, 1, 100)
	_check(not bool(selector_result.get("success", false)) and selector_result.get("error") == "A10_R3_SPATIAL_REGION_MISMATCH", "changed partition selector rejected")

	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_R3_SEAM_BINDING checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_R3_SEAM_BINDING PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_R3_FAILURE " + failure)
		quit(1)
