extends SceneTree

## EG3 L0 backend multiplexer: priority ordering under saturation (P0..P5),
## latest-wins coalescing of stale unreliable snapshot/projection streams,
## explicit backpressure rejections (QUEUE_FULL_SESSION / QUEUE_FULL_LINK,
## never silent drops), no starvation of P0/P1 under a P2 flood, per-session
## fair-share caps, bounded queue growth, and slot-reuse state isolation.

const Mux = preload("res://scripts/network/gateway/runtime/eg3_backend_multiplexer.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg3-mux-l0][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _details(result: Dictionary) -> Dictionary:
	return result.get("details", {})


func _spec(channel: String, delivery_mode: String, marker: String) -> Dictionary:
	return {
		"channel": channel,
		"delivery_mode": delivery_mode,
		"payload_schema": "planet_simulator.test_eg3_mux.v1",
		"payload": {"marker": marker},
	}


func _enqueue_ok(mux, gateway_session_id: String, spec: Dictionary) -> void:
	var enqueued: Dictionary = mux.enqueue(gateway_session_id, spec)
	_assert(bool(enqueued.get("success", false)),
			"enqueue(%s %s) failed: %s" % [gateway_session_id, String(spec["channel"]), _err(enqueued)])


func _drain_markers(mux, budget: int) -> Array[String]:
	var drained: Dictionary = mux.drain_link(budget)
	_assert(bool(drained.get("success", false)), "drain_link failed: %s" % _err(drained))
	var markers: Array[String] = []
	for frame_value in _details(drained).get("frames", []):
		markers.append(String(Dictionary(frame_value)["frame_spec"]["payload"]["marker"]))
	return markers


func _init() -> void:
	_run_configure_validation()
	_run_registration_and_slot_reuse_isolation()
	_run_enqueue_validation()
	_run_priority_ordering_under_saturation()
	_run_latest_wins_coalescing()
	_run_backpressure_rejections()
	_run_no_starvation_under_p2_flood()
	_run_fair_share_cap()
	_run_bounded_growth()
	_finish()


func _run_configure_validation() -> void:
	var mux = Mux.new()
	_assert(_err(mux.configure({"max_session_messages": -1})) == "INVALID_OPTION",
			"negative message cap accepted")
	_assert(_err(mux.configure({"no_such_option": 1})) == "UNKNOWN_OPTION",
			"unknown option accepted")
	_assert(bool(mux.configure({
		"max_session_messages": 8,
		"max_session_bytes": 4096,
		"link_max_messages": 16,
		"fair_share_per_drain": 4,
	}).get("success", false)), "valid configure rejected")


func _run_registration_and_slot_reuse_isolation() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({}).get("success", false)), "default configure failed")
	_assert(_err(mux.register_session("player/not-a-session")) == "INVALID_GATEWAY_SESSION_ID",
			"non gateway-session id registered")
	_assert(bool(mux.register_session("gateway-session/eg3/slot-a").get("success", false)),
			"session registration failed")
	_assert(_err(mux.register_session("gateway-session/eg3/slot-a")) == "GATEWAY_SESSION_EXISTS",
			"duplicate registration accepted")
	# Queue frames for identity A, release the slot, re-register as identity B:
	# nothing may survive the slot handover.
	_enqueue_ok(mux, "gateway-session/eg3/slot-a",
			_spec("SESSION_CONTROL", "RELIABLE_ORDERED", "stale-control"))
	_enqueue_ok(mux, "gateway-session/eg3/slot-a",
			_spec("WORLD_OPERATION", "RELIABLE_ORDERED", "stale-op"))
	_assert(int(mux.link_depth()["messages"]) == 2, "link depth wrong before release")
	_assert(bool(mux.release_session("gateway-session/eg3/slot-a").get("success", false)),
			"release failed")
	_assert(int(mux.link_depth()["messages"]) == 0, "released session kept link-buffered frames")
	_assert(bool(mux.register_session("gateway-session/eg3/slot-b").get("success", false)),
			"re-registration of the freed slot failed")
	var drained := _drain_markers(mux, 16)
	_assert(drained.is_empty(), "slot reuse leaked queued frames between identities")
	_assert(_err(mux.release_session("gateway-session/eg3/ghost")) == "UNKNOWN_GATEWAY_SESSION",
			"unknown session released")
	# purge_session drops in-flight state but keeps the registration.
	_enqueue_ok(mux, "gateway-session/eg3/slot-b",
			_spec("INPUT_MOVEMENT", "RELIABLE_UNORDERED", "to-purge"))
	var purged: Dictionary = mux.purge_session("gateway-session/eg3/slot-b")
	_assert(bool(purged.get("success", false)) and int(_details(purged)["purged_frames"]) == 1,
			"purge did not account the dropped frame")
	_assert(int(mux.session_depth("gateway-session/eg3/slot-b")["messages"]) == 0,
			"purged session still reports queued messages")


func _run_enqueue_validation() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({}).get("success", false)), "default configure failed (validation)")
	_assert(_err(mux.enqueue("gateway-session/eg3/nobody",
			_spec("SESSION_CONTROL", "RELIABLE_ORDERED", "x"))) == "UNKNOWN_GATEWAY_SESSION",
			"unregistered session accepted frames")
	_assert(bool(mux.register_session("gateway-session/eg3/v").get("success", false)),
			"validation session registration failed")
	_assert(_err(mux.enqueue("gateway-session/eg3/v",
			_spec("NOT_A_CHANNEL", "RELIABLE_ORDERED", "x"))) == "UNKNOWN_CHANNEL",
			"unknown channel accepted (priority mapping must stay fail-closed)")
	_assert(_err(mux.enqueue("gateway-session/eg3/v", {
		"channel": "SESSION_CONTROL",
		"delivery_mode": "CARRIER_PIGEON",
		"payload": {},
	})) == "INVALID_DELIVERY_MODE", "invalid delivery mode accepted")


func _run_priority_ordering_under_saturation() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({"fair_share_per_drain": 64}).get("success", false)),
			"ordering configure failed")
	_assert(bool(mux.register_session("gateway-session/eg3/order").get("success", false)),
			"ordering session registration failed")
	var sid := "gateway-session/eg3/order"
	# Deliberately interleave classes; expected drain order groups P0..P5 with
	# FIFO inside each class.
	_enqueue_ok(mux, sid, _spec("TELEMETRY", "UNRELIABLE_SEQUENCED", "t1"))
	_enqueue_ok(mux, sid, _spec("INPUT_MOVEMENT", "RELIABLE_UNORDERED", "i1"))
	_enqueue_ok(mux, sid, _spec("WORLD_OPERATION", "RELIABLE_ORDERED", "w1"))
	_enqueue_ok(mux, sid, _spec("AUTHORITATIVE_SNAPSHOT", "UNRELIABLE_SEQUENCED", "s1"))
	_enqueue_ok(mux, sid, _spec("SESSION_CONTROL", "RELIABLE_ORDERED", "c1"))
	_enqueue_ok(mux, sid, _spec("INPUT_MOVEMENT", "RELIABLE_UNORDERED", "i2"))
	_enqueue_ok(mux, sid, _spec("WORLD_PROJECTION", "UNRELIABLE_SEQUENCED", "p1"))
	_enqueue_ok(mux, sid, _spec("WORLD_OPERATION", "RELIABLE_ORDERED", "w2"))
	_enqueue_ok(mux, sid, _spec("TELEMETRY", "UNRELIABLE_SEQUENCED", "t2"))
	var order := _drain_markers(mux, 64)
	# t1 was enqueued before t2 on the SAME unreliable telemetry stream and is
	# coalesced away (latest-wins); everything else keeps strict P0..P5 groups.
	var expected: Array[String] = [
		"c1", "w1", "w2", "i1", "i2", "s1", "p1", "t2",
	]
	_assert(order == expected, "priority ordering broken: %s" % str(order))


func _run_latest_wins_coalescing() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({}).get("success", false)), "coalescing configure failed")
	var sid := "gateway-session/eg3/coalesce"
	_assert(bool(mux.register_session(sid).get("success", false)), "coalesce registration failed")
	for index in range(5):
		_enqueue_ok(mux, sid, _spec("AUTHORITATIVE_SNAPSHOT", "UNRELIABLE_SEQUENCED", "snap-%d" % index))
	_enqueue_ok(mux, sid, _spec("WORLD_PROJECTION", "UNRELIABLE_SEQUENCED", "proj-old"))
	_enqueue_ok(mux, sid, _spec("WORLD_PROJECTION", "UNRELIABLE_SEQUENCED", "proj-new"))
	# Reliable snapshots are NEVER coalesced away.
	for index in range(3):
		_enqueue_ok(mux, sid, _spec("AUTHORITATIVE_SNAPSHOT", "RELIABLE_ORDERED", "rsnap-%d" % index))
	_assert(int(mux.session_depth(sid)["messages"]) == 5,
			"coalescing did not collapse stale unreliable revisions: %s"
					% str(mux.session_depth(sid)))
	var order := _drain_markers(mux, 64)
	# P3 snapshot FIFO keeps insertion order (snap-4 first, then the reliable
	# snapshots); P4 projection follows.
	var expected: Array[String] = [
		"snap-4", "rsnap-0", "rsnap-1", "rsnap-2", "proj-new",
	]
	_assert(order == expected, "latest-wins stream content wrong: %s" % str(order))
	var report: Dictionary = mux.get_report()
	_assert(int(report["counters"]["coalesced_stale"]) == 5,
			"coalesced-stale counter mismatch: %s" % str(report["counters"]["coalesced_stale"]))


func _run_backpressure_rejections() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({
		"max_session_messages": 3,
		"max_session_bytes": 1024,
		"link_max_messages": 5,
	}).get("success", false)), "backpressure configure failed")
	var sid_a := "gateway-session/eg3/bp-a"
	var sid_b := "gateway-session/eg3/bp-b"
	_assert(bool(mux.register_session(sid_a).get("success", false)), "bp-a registration failed")
	_assert(bool(mux.register_session(sid_b).get("success", false)), "bp-b registration failed")
	for index in range(3):
		_enqueue_ok(mux, sid_a, _spec("WORLD_OPERATION", "RELIABLE_ORDERED", "op-%d" % index))
	# Session message cap: RELIABLE world ops are explicitly REJECTED, never dropped.
	var rejected: Dictionary = mux.enqueue(sid_a,
			_spec("WORLD_OPERATION", "RELIABLE_ORDERED", "op-over"))
	_assert(_err(rejected) == Mux.QUEUE_FULL_SESSION,
			"reliable overflow was not an explicit session rejection: %s" % _err(rejected))
	_assert(not bool(rejected.get("success", false)), "overflow reported success")
	# Byte cap rejection.
	var big_payload := {"blob": "x".repeat(2048)}
	var big_rejected: Dictionary = mux.enqueue(sid_b, {
		"channel": "WORLD_OPERATION",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": "planet_simulator.test_eg3_mux.v1",
		"payload": big_payload,
	})
	_assert(_err(big_rejected) == Mux.QUEUE_FULL_SESSION,
			"byte-cap overflow was not rejected: %s" % _err(big_rejected))
	# Link-wide cap: fill b within its session cap until the LINK cap trips.
	var saw_link_rejection := false
	for index in range(3):
		var result: Dictionary = mux.enqueue(sid_b,
				_spec("INPUT_MOVEMENT", "RELIABLE_UNORDERED", "in-%d" % index))
		if not bool(result.get("success", false)):
			saw_link_rejection = _err(result) == Mux.QUEUE_FULL_LINK
			break
	_assert(saw_link_rejection, "link cap never produced QUEUE_FULL_LINK")
	var report: Dictionary = mux.get_report()
	_assert(int(report["counters"]["rejections_queue_full_session"]) == 2,
			"session rejection counter mismatch")
	_assert(int(report["counters"]["rejections_queue_full_link"]) >= 1,
			"link rejection counter mismatch")
	# After draining everything, capacity is restored again.
	_assert(bool(mux.drain_link(64).get("success", false)), "backpressure recovery drain failed")
	var recovered: Dictionary = mux.enqueue(sid_a,
			_spec("WORLD_OPERATION", "RELIABLE_ORDERED", "post-drain"))
	_assert(bool(recovered.get("success", false)), "capacity not restored after drain")


func _run_no_starvation_under_p2_flood() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({
		"max_session_messages": 256,
		"link_max_messages": 1024,
		"fair_share_per_drain": 64,
	}).get("success", false)), "flood configure failed")
	var flooder := "gateway-session/eg3/flood"
	var victim := "gateway-session/eg3/victim"
	_assert(bool(mux.register_session(flooder).get("success", false)), "flooder registration failed")
	_assert(bool(mux.register_session(victim).get("success", false)), "victim registration failed")
	for index in range(200):
		_enqueue_ok(mux, flooder, _spec("INPUT_MOVEMENT", "RELIABLE_UNORDERED", "flood-%d" % index))
	# Control + reliable world op arrive AFTER the flood started.
	_enqueue_ok(mux, victim, _spec("WORLD_OPERATION", "RELIABLE_ORDERED", "victim-op"))
	_enqueue_ok(mux, victim, _spec("SESSION_CONTROL", "RELIABLE_ORDERED", "victim-control"))
	var first_drain := _drain_markers(mux, 2)
	var expected_first: Array[String] = ["victim-control", "victim-op"]
	_assert(first_drain == expected_first,
			"P0/P1 starved behind a P2 flood: %s" % str(first_drain))
	# The flooder's backlog is untouched by those two high-priority sends.
	_assert(int(mux.session_depth(flooder)["messages"]) == 200,
			"flood backlog was disturbed by priority servicing")


func _run_fair_share_cap() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({"fair_share_per_drain": 4}).get("success", false)),
			"fair-share configure failed")
	var loud := "gateway-session/eg3/loud"
	var quiet := "gateway-session/eg3/quiet"
	_assert(bool(mux.register_session(loud).get("success", false)), "loud registration failed")
	_assert(bool(mux.register_session(quiet).get("success", false)), "quiet registration failed")
	for index in range(100):
		_enqueue_ok(mux, loud, _spec("INPUT_MOVEMENT", "RELIABLE_UNORDERED", "loud-%d" % index))
	_enqueue_ok(mux, quiet, _spec("INPUT_MOVEMENT", "RELIABLE_UNORDERED", "quiet-0"))
	var drained: Dictionary = mux.drain_link(100)
	_assert(bool(drained.get("success", false)), "fair-share drain failed")
	var sent_by_session: Dictionary = _details(drained)["sent_by_session"]
	_assert(int(sent_by_session.get(loud, 0)) == 4,
			"loud client exceeded its fair share: %s" % str(sent_by_session))
	_assert(int(sent_by_session.get(quiet, 0)) == 1,
			"quiet client did not get tunnel access under load: %s" % str(sent_by_session))


func _run_bounded_growth() -> void:
	var mux = Mux.new()
	_assert(bool(mux.configure({"max_session_messages": 16, "link_max_messages": 16})
			.get("success", false)), "growth configure failed")
	var sid := "gateway-session/eg3/growth"
	_assert(bool(mux.register_session(sid).get("success", false)), "growth registration failed")
	var accepted := 0
	var rejected := 0
	for index in range(500):
		var result: Dictionary = mux.enqueue(sid,
				_spec("WORLD_OPERATION", "RELIABLE_ORDERED", "grow-%d" % index))
		if bool(result.get("success", false)):
			accepted += 1
		else:
			rejected += 1
			_assert(_err(result) == Mux.QUEUE_FULL_SESSION,
					"growth overflow produced an unexpected code: %s" % _err(result))
	_assert(accepted == 16 and rejected == 484,
			"bounded growth accounting wrong: accepted=%d rejected=%d" % [accepted, rejected])
	_assert(int(mux.session_depth(sid)["messages"]) == 16,
			"queue depth exceeded its hard cap")
	var report: Dictionary = mux.get_report()
	_assert(int(report["counters"]["enqueued"]) == accepted,
			"enqueued counter disagrees with accepted frames")


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg3_backend_multiplexer_l0",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicate": "BOUNDED_PRIORITY_SCHEDULING_PASS" if ok else "PREDICATE_NOT_DEMONSTRATED",
		"unbounded_queue_growth": 0 if ok else 1,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg3-mux-l0] L0 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg3-mux-l0] L0 FAIL")
		quit(1)
