extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_authority_process.gd"

# MVP4 adds a single bounded Matter region to the actual MVP3 native process.
# All player movement, identity, fixed clock and authority ingestion are inherited.
const SharedDig4 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_shared_dig_authority.gd")
var _shared_dig4 = null

func create_shared_dig():
	# Composition hook: MVP4 remains the default, with exactly one bridge/owner.
	return SharedDig4.new()

func initialize_owner() -> Dictionary:
	var initialized: Dictionary = super.initialize_owner()
	if not bool(initialized.get("success", false)): return initialized
	if authority != SharedDig4.OWNER: return initialized
	_shared_dig4 = create_shared_dig()
	return _shared_dig4.configure(service, decisions, {"a": Protocol.session(cfg, "a"), "b": Protocol.session(cfg, "b")})

func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP4_"): return super.handle_rpc(body)
	if closing_ms > 0 or _shared_dig4 == null:
		return Protocol.failure("MVP4_MATTER_OWNER_UNAVAILABLE")
	var ingested: Dictionary = ingest_decisions(body)
	if not bool(ingested.get("success", false)): return ingested
	var actor := String(body.get("actor", ""))
	if actor not in ["a", "b"] or body.get("session") != Protocol.session(cfg, actor):
		return Protocol.failure("MVP4_NATIVE_PEER_BINDING_INVALID")
	var session := Protocol.session(cfg, actor)
	var result: Dictionary
	match kind:
		"MVP4_CONNECT":
			if not body.get("sync_request") is Dictionary: return Protocol.failure("MVP4_SYNC_REQUIRED")
			result = _shared_dig4.connect_replica(actor, session, body["sync_request"])
		"MVP4_EQUIP": result = _shared_dig4.equip_tool(actor, session)
		"MVP4_POLL": result = _shared_dig4.poll_replica(actor, session)
		"MVP4_ACK":
			if not body.get("ack") is Dictionary: return Protocol.failure("MVP4_ACK_REQUIRED")
			result = _shared_dig4.acknowledge_replica(actor, session, body["ack"])
		"MVP4_PREPARE":
			if not body.get("direction") is Array: return Protocol.failure("MVP4_DIRECTION_REQUIRED")
			result = _shared_dig4.prepare_dig(actor, session, String(body.get("operation_id", "")), body["direction"])
		"MVP4_EXECUTE":
			if not body.get("plan") is Dictionary: return Protocol.failure("MVP4_PLAN_REQUIRED")
			result = _shared_dig4.execute_prepared(actor, session, body["plan"])
		"MVP4_REPORT": result = Protocol.success(_shared_dig4.report())
		_: result = Protocol.failure("MVP4_UNKNOWN_NATIVE_COMMAND")
	return native_envelope(kind, actor, result)

func report(passed: bool, phase: String) -> Dictionary:
	var value: Dictionary = super.report(passed, phase)
	value["mvp4"] = _shared_dig4.report() if _shared_dig4 != null else {"configured": false, "owns_matter_region": false}
	return value

func finish(passed: bool, code: String) -> void:
	# The inherited finish persists report() before shutting down the native M3.
	super.finish(passed, code)
	if _shared_dig4 != null: _shared_dig4.shutdown()
	_shared_dig4 = null
