extends RefCounted
## A10 R3: prepare/admit production handoff around the existing A8 state machine.
## This helper owns no authority and performs no ticket transitions itself.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const WorldBinding = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")

static func prepare_ticket(
	cursor: Dictionary,
	source_region: Dictionary,
	target_region: Dictionary,
	created_at_tick: int,
	expires_at_tick: int
) -> Dictionary:
	if not bool(Region.validate(source_region).get("success", false)):
		return _fail("A10_R3_SOURCE_REGION_INVALID")
	if not bool(Region.validate(target_region).get("success", false)):
		return _fail("A10_R3_TARGET_REGION_INVALID")
	var source_admission := WorldBinding.admit_cursor(cursor, source_region)
	if not bool(source_admission.get("success", false)):
		return _fail("A10_R3_SOURCE_CURSOR:" + String(source_admission.get("error", "INVALID")))
	if not _same_spatial_region(source_region, target_region):
		return _fail("A10_R3_SPATIAL_REGION_MISMATCH")
	if String(source_region["owner_node_id"]) == String(target_region["owner_node_id"]):
		return _fail("A10_R3_SAME_OWNER")
	if int(target_region["authority_epoch"]) <= int(source_region["authority_epoch"]):
		return _fail("A10_R3_TARGET_EPOCH_NOT_NEWER")
	if String(target_region["lifecycle_state"]) not in ["WARM", "ACTIVE"]:
		return _fail("A10_R3_TARGET_NOT_PREPARED")
	if not C.integer(created_at_tick, 0, C.MAX_INT) \
	or created_at_tick != int(cursor["clock"]) + 1 \
	or not C.integer(expires_at_tick, created_at_tick + 1, C.MAX_INT):
		return _fail("A10_R3_TICKET_WINDOW")
	var ticket_id := "a10.r3.ticket.%s.%d" % [
		String(cursor["entity_id"]).sha256_text().substr(0, 16),
		int(target_region["authority_epoch"]),
	]
	var ticket := Ticket.create(
		ticket_id,
		String(cursor["entity_id"]),
		String(source_region["owner_node_id"]),
		String(target_region["owner_node_id"]),
		int(source_region["authority_epoch"]),
		int(target_region["authority_epoch"]),
		int(cursor["revision"]),
		String(source_region["region_id"]),
		created_at_tick,
		expires_at_tick
	)
	var checked: Dictionary = Ticket.validate(ticket)
	if not bool(checked.get("success", false)):
		return _fail("A10_R3_TICKET_INVALID:" + String(checked.get("error_code", "")))
	return {"success": true, "ticket": ticket}

static func admit_committed(
	cursor: Dictionary,
	target_region: Dictionary,
	ticket: Dictionary
) -> Dictionary:
	var checked: Dictionary = Ticket.validate(ticket)
	if not bool(checked.get("success", false)):
		return _fail("A10_R3_TICKET_INVALID")
	if String(ticket["state"]) != "COMMITTED":
		return _fail("A10_R3_TICKET_NOT_COMMITTED")
	if String(ticket["entity_id"]) != String(cursor.get("entity_id", "")) \
	or String(ticket["region_id"]) != String(cursor.get("region_id", "")):
		return _fail("A10_R3_TICKET_CURSOR_IDENTITY")
	if String(ticket["target_node_id"]) != String(cursor.get("owner_id", "")) \
	or int(ticket["target_authority_epoch"]) != int(cursor.get("owner_epoch", -1)):
		return _fail("A10_R3_TICKET_CURSOR_OWNER")
	if String(ticket["target_node_id"]) != String(target_region.get("owner_node_id", "")) \
	or int(ticket["target_authority_epoch"]) != int(target_region.get("authority_epoch", -1)):
		return _fail("A10_R3_TICKET_REGION_OWNER")
	var admission := WorldBinding.admit_cursor(cursor, target_region)
	if not bool(admission.get("success", false)):
		return _fail("A10_R3_TARGET_CURSOR:" + String(admission.get("error", "INVALID")))
	return {"success": true}

static func _same_spatial_region(a: Dictionary, b: Dictionary) -> bool:
	var left := Region.normalize(a)
	var right := Region.normalize(b)
	if left.is_empty() or right.is_empty():
		return false
	for field in [
		"region_id", "universe_id", "instance_id", "space_id",
		"partition_scheme", "partition_revision", "selector",
	]:
		if left[field] != right[field]:
			return false
	return true

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
