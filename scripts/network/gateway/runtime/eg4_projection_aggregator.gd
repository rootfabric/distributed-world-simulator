extends RefCounted

## EG4 projection aggregator: the gateway FAN-IN of projection streams from
## MULTIPLE upstream sources into each client's SINGLE connection.
##
## Data path (client-facing egress):
##   upstream WORLD_PROJECTION frame -> read-only fencing -> per-(session,
##   source) stream slot in a dedicated EG3 backend multiplexer instance ->
##   drain() -> node.send_client_frame_spec_for_session() on the ONE client
##   transport. The multiplexer supplies P4 priority, latest-wins coalescing
##   PER STREAM, bounded queues and explicit backpressure — unchanged EG3
##   machinery.
##
## Read-only fencing (fail closed):
##   - every accepted projection payload carries read_only=true; anything else
##     is rejected PROJECTION_NOT_READ_ONLY;
##   - any non-WORLD_PROJECTION channel arriving from a PROJECTION source is a
##     mutation-shaped payload and is rejected PROJECTION_MUTATION_REJECTED;
##   - frames from an unregistered source are injection and are rejected
##     PROJECTION_SOURCE_NOT_REGISTERED;
##   - stale source revisions are dropped latest-wins (never delivered late).
##
## Upstream subscription lifecycle drives staleness: withdrawing the last
## demand for a (source, world) pair parks it as a STALE upstream subscription;
## bounded maintenance cycles retire up to retire_batch_per_cycle pairs per
## cycle until the stale set is EMPTY.

const BackendMultiplexerScript = preload("res://scripts/network/gateway/runtime/eg3_backend_multiplexer.gd")
const UpstreamSetScript = preload("res://scripts/network/gateway/runtime/eg4_upstream_set.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.eg4_projection_aggregator.v1"
const PROJECTION_CHANNEL := "WORLD_PROJECTION"
const PROJECTION_PAYLOAD_SCHEMA := "planet_simulator.test_world_projection.v1"
const DEFAULT_RETIRE_BATCH_PER_CYCLE := 2

var _upstream_set
var _egress_multiplexer
var _send_to_client: Callable = Callable()
var _retire_batch_per_cycle: int = DEFAULT_RETIRE_BATCH_PER_CYCLE
var _clients: Dictionary = {}
# synthetic mux slot key ("gateway-session/eg4/fanin-<n>") -> {"gateway_session_id", "source_authority_id"}
var _slot_by_key: Dictionary = {}
# "<gateway_session_id>\u001f<source_authority_id>" -> mux slot key
var _key_by_pair: Dictionary = {}
# "<source>\u001f<world>" -> {"sessions": {gateway_session_id: true}, "stale": bool}
var _subscriptions: Dictionary = {}
# source -> {world_id: true} currently served (non-stale)
var _served_worlds_by_source: Dictionary = {}
var _slot_counter: int = 0
var _frame_counter: int = 0
var _counters := {
	"frames_accepted": 0,
	"frames_delivered": 0,
	"rejected_not_read_only": 0,
	"rejected_mutation_shaped": 0,
	"rejected_injection": 0,
	"rejected_unknown_session": 0,
	"rejected_stale_revision": 0,
	"rejected_backpressure": 0,
	"dropped_latest_wins": 0,
	"subscribe_worlds": 0,
	"unsubscribe_worlds": 0,
	"stale_retired": 0,
}
var _last_source_revision_by_stream: Dictionary = {}


func configure(options: Dictionary) -> Dictionary:
	for key in options.keys():
		var value = options[key]
		match String(key):
			"send_to_client":
				if not value is Callable:
					return _failure("INVALID_OPTION", {"option": "send_to_client"})
				_send_to_client = value
			"max_upstream_sources":
				var upstream := UpstreamSetScript.new()
				var upstream_configured: Dictionary = upstream.configure({"cap": int(value)})
				if not bool(upstream_configured.get("success", false)):
					return _failure("INVALID_OPTION", {"option": "max_upstream_sources"})
				_upstream_set = upstream
			"retire_batch_per_cycle":
				if not GatewayUtilsScript.require_positive_integer(options, "retire_batch_per_cycle").get("success", false):
					return _failure("INVALID_OPTION", {"option": "retire_batch_per_cycle"})
				_retire_batch_per_cycle = int(value)
			_:
				return _failure("UNKNOWN_OPTION", {"option": String(key)})
	if _upstream_set == null:
		_upstream_set = UpstreamSetScript.new()
	_egress_multiplexer = BackendMultiplexerScript.new()
	var mux_configured: Dictionary = _egress_multiplexer.configure({})
	if not bool(mux_configured.get("success", false)):
		return _failure("MULTIPLEXER_CONFIGURE_FAILED", {})
	return _success({})


## ---- clients & sources -------------------------------------------------------


func register_client(gateway_session_id: String) -> Dictionary:
	var check: Dictionary = GatewayUtilsScript.require_id(
			{"gateway_session_id": gateway_session_id}, "gateway_session_id", "gateway-session")
	if not bool(check.get("success", false)):
		return check
	if _clients.has(gateway_session_id):
		return _failure("CLIENT_ALREADY_REGISTERED", {"gateway_session_id": gateway_session_id})
	_clients[gateway_session_id] = {"registered_at_ms": Time.get_ticks_msec()}
	return _success({})


## Release ONE client and EVERY per-client derived record: fan-in slots,
## subscription seats, and latest-wins stream revisions (review R2-A: without
## this cleanup, connect/disconnect churn leaks all three maps). Pairs whose
## last seat disappeared become STALE — they retire through the bounded
## maintenance cycles, never by unbounded silent deletion.
func release_client(gateway_session_id: String) -> Dictionary:
	if not _clients.has(gateway_session_id):
		return _failure("UNKNOWN_CLIENT", {"gateway_session_id": gateway_session_id})
	# _key_by_pair maps "<gateway_session_id>\u001f<source_authority_id>" to the
	# STRING fan-in slot key; the session identity lives in the KEY itself.
	for pair_key_value in _key_by_pair.keys():
		var pair_key := String(pair_key_value)
		var pair_parts := pair_key.split(String.chr(31))
		if pair_parts.size() == 2 and String(pair_parts[0]) == gateway_session_id:
			_release_slot(pair_key)
	var pairs_now_stale := 0
	for sub_key_value in _subscriptions.keys():
		if _detach_session_from_subscription(String(sub_key_value), gateway_session_id):
			pairs_now_stale += 1
	var stream_prefix := "%s%s" % [gateway_session_id, String.chr(31)]
	for stream_key_value in _last_source_revision_by_stream.keys():
		if String(stream_key_value).begins_with(stream_prefix):
			_last_source_revision_by_stream.erase(stream_key_value)
	_clients.erase(gateway_session_id)
	return _success({
		"released": true,
		"gateway_session_id": gateway_session_id,
		"pairs_now_stale": pairs_now_stale,
	})


## Gateway-facing lifecycle hook (review R2-B): called by eg1_gateway_node
## when the client session is dropped/detached so no projection state can
## outlive its session. Idempotent: dropping an already-unknown session is a
## successful no-op.
func on_gateway_session_detached(gateway_session_id: String) -> Dictionary:
	if not _clients.has(gateway_session_id):
		return _success({"released": false, "reason": "UNKNOWN_CLIENT"})
	return release_client(gateway_session_id)


## Register an upstream projection source within the BOUNDED set. When the cap
## is hit, the least-recently-active IDLE source is evicted.
func register_upstream_source(source_authority_id: String, role: String = "PROJECTION") -> Dictionary:
	if role != "PROJECTION":
		return _failure("INVALID_SOURCE_ROLE", {"role": role})
	var registered: Dictionary = _upstream_set.register(source_authority_id)
	if bool(registered.get("success", false)):
		return registered
	return registered


func mark_source_idle(source_authority_id: String) -> Dictionary:
	return _upstream_set.mark_idle(source_authority_id)


## Source loss (link drop / process death): release from the bounded set and
## report which world subscriptions were served by it.
func mark_source_lost(source_authority_id: String) -> Dictionary:
	if not _upstream_set.has(source_authority_id):
		return _failure("UNKNOWN_SOURCE", {"source_authority_id": source_authority_id})
	var affected: Array[String] = []
	for world_value in Dictionary(_served_worlds_by_source.get(source_authority_id, {})).keys():
		affected.append(String(world_value))
	_upstream_set.release(source_authority_id)
	_served_worlds_by_source.erase(source_authority_id)
	return _success({"lost_source": source_authority_id, "affected_worlds": affected})


## ---- subscription lifecycle ---------------------------------------------------


func subscribe_world(gateway_session_id: String, source_authority_id: String, world_id: String) -> Dictionary:
	for check in [
		GatewayUtilsScript.require_id({"gateway_session_id": gateway_session_id}, "gateway_session_id", "gateway-session"),
		GatewayUtilsScript.require_id({"source_authority_id": source_authority_id}, "source_authority_id", "authority"),
		GatewayUtilsScript.require_id({"world_id": world_id}, "world_id", "world"),
	]:
		if not bool(check.get("success", false)):
			return check
	if not _clients.has(gateway_session_id):
		return _failure("UNKNOWN_CLIENT", {"gateway_session_id": gateway_session_id})
	var sub_key := "%s%s%s" % [source_authority_id, String.chr(31), world_id]
	if not _subscriptions.has(sub_key):
		_subscriptions[sub_key] = {"sessions": {}, "stale": false}
	_counters["subscribe_worlds"] = int(_counters["subscribe_worlds"]) + 1
	var entry: Dictionary = _subscriptions[sub_key]
	(entry["sessions"] as Dictionary)[gateway_session_id] = true
	entry["stale"] = false
	if not _served_worlds_by_source.has(source_authority_id):
		_served_worlds_by_source[source_authority_id] = {}
	(Dictionary(_served_worlds_by_source[source_authority_id]))[world_id] = true
	return _success({"subscription": sub_key.replace(String.chr(31), "|")})


func unsubscribe_world(gateway_session_id: String, source_authority_id: String, world_id: String) -> Dictionary:
	var sub_key := "%s%s%s" % [source_authority_id, String.chr(31), world_id]
	if not _subscriptions.has(sub_key):
		return _failure("UNKNOWN_SUBSCRIPTION", {})
	var became_stale := _detach_session_from_subscription(sub_key, gateway_session_id)
	if became_stale:
		_counters["unsubscribe_worlds"] = int(_counters["unsubscribe_worlds"]) + 1
	var entry: Dictionary = _subscriptions[sub_key]
	return _success({"stale": bool(entry["stale"])})


## Remove ONE session seat from a subscription entry. When the last seat is
## gone the upstream subscription turns STALE (bounded retirement path) and
## the world leaves its source's served set immediately — served-set mirrors
## ACTIVE demand only.
func _detach_session_from_subscription(sub_key: String, gateway_session_id: String) -> bool:
	var entry: Dictionary = _subscriptions[sub_key]
	var sessions: Dictionary = entry["sessions"]
	sessions.erase(gateway_session_id)
	if sessions.is_empty() and not bool(entry["stale"]):
		# Last demand gone: the upstream subscription is now STALE until a
		# bounded maintenance cycle retires it (or the source disappears).
		entry["stale"] = true
		var parts := sub_key.split(String.chr(31))
		if parts.size() == 2:
			var source_served: Dictionary = Dictionary(_served_worlds_by_source.get(String(parts[0]), {}))
			source_served.erase(String(parts[1]))
			if source_served.is_empty():
				_served_worlds_by_source.erase(String(parts[0]))
			else:
				_served_worlds_by_source[String(parts[0])] = source_served
		return true
	return false


## Bounded pump-cycle step: retire at most retire_batch_per_cycle stale
## subscriptions, deterministically in sorted order.
func run_maintenance_cycle() -> Dictionary:
	var stale_keys: Array[String] = []
	for sub_key_value in _subscriptions.keys():
		if bool(_subscriptions[sub_key_value]["stale"]):
			stale_keys.append(String(sub_key_value))
	stale_keys.sort()
	var retired: Array[String] = []
	for index in range(mini(stale_keys.size(), _retire_batch_per_cycle)):
		var sub_key := stale_keys[index]
		var sessions: Dictionary = _subscriptions[sub_key]["sessions"]
		if sessions.is_empty():
			_subscriptions.erase(sub_key)
			retired.append(sub_key.replace(String.chr(31), "|"))
			_counters["stale_retired"] = int(_counters["stale_retired"]) + 1
		else:
			_subscriptions[sub_key]["stale"] = false
	return _success({"retired": retired, "remaining_stale": stale_subscription_count()})


func stale_subscription_count() -> int:
	var count := 0
	for sub_key_value in _subscriptions.keys():
		if bool(_subscriptions[sub_key_value]["stale"]):
			count += 1
	return count


## (source, world) pairs currently demanded by at least one live client.
func active_subscription_count() -> int:
	return _active_subscription_count()


func stale_subscriptions() -> Array[String]:
	var output: Array[String] = []
	for sub_key_value in _subscriptions.keys():
		if bool(_subscriptions[sub_key_value]["stale"]):
			output.append(String(sub_key_value).replace(String.chr(31), "|"))
	output.sort()
	return output


## ---- data path ------------------------------------------------------------------


## Accept ONE upstream transport frame from a backend projection leg. The
## transport frame payload must be a GatewayEgressEnvelope whose inner
## ClientWorldFrame rides WORLD_PROJECTION with read_only=true.
##
## Fence ordering: the read-only/MUTATION-shaped semantic fence runs FIRST so
## the stage-named rejection codes (PROJECTION_NOT_READ_ONLY /
## PROJECTION_MUTATION_REJECTED) take precedence over structural envelope
## errors; the full envelope contract still validates before anything is
## scheduled toward the client.
func accept_upstream_frame(source_authority_id: String, transport_frame: Dictionary) -> Dictionary:
	if not _upstream_set.has(source_authority_id):
		_counters["rejected_injection"] = int(_counters["rejected_injection"]) + 1
		return _failure("PROJECTION_SOURCE_NOT_REGISTERED", {"source_authority_id": source_authority_id})
	var raw_payload = transport_frame.get("payload", null)
	if typeof(raw_payload) != TYPE_DICTIONARY \
			or not (raw_payload as Dictionary).has("frame") \
			or not (raw_payload as Dictionary).has("gateway_session_id"):
		_counters["rejected_injection"] = int(_counters["rejected_injection"]) + 1
		return _failure("INVALID_EGRESS_ENVELOPE", {})
	var inner_candidate: Dictionary = Dictionary((raw_payload as Dictionary)["frame"])
	if String(inner_candidate.get("channel", "")) != PROJECTION_CHANNEL:
		# ANY other channel arriving from a projection source is mutation-shaped
		# traffic injected into the read-only stream.
		return _fencing_reject("PROJECTION_MUTATION_REJECTED", String(inner_candidate.get("channel", "")))
	var candidate_payload: Dictionary = Dictionary(inner_candidate.get("payload", {}))
	if typeof(candidate_payload.get("read_only")) != TYPE_BOOL or not bool(candidate_payload["read_only"]):
		return _fencing_reject("PROJECTION_NOT_READ_ONLY", "")
	var envelope_check: Dictionary = EgressEnvelopeScript.validate(raw_payload)
	if not bool(envelope_check.get("success", false)):
		_counters["rejected_injection"] = int(_counters["rejected_injection"]) + 1
		return _failure("INVALID_EGRESS_ENVELOPE", {"error_code": String(envelope_check.get("error_code", ""))})
	var envelope: Dictionary = raw_payload
	var gateway_session_id := String(envelope["gateway_session_id"])
	if not _clients.has(gateway_session_id):
		_counters["rejected_unknown_session"] = int(_counters["rejected_unknown_session"]) + 1
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	var inner: Dictionary = envelope["frame"]
	var frame_check: Dictionary = ClientWorldFrameScript.validate(inner)
	if not bool(frame_check.get("success", false)):
		return _fencing_reject("INVALID_PROJECTION_FRAME", String(frame_check.get("error_code", "")))
	var payload: Dictionary = inner["payload"]
	var source_revision := int(payload.get("source_revision", 0))
	var stream_key := "%s%s%s" % [gateway_session_id, String.chr(31), source_authority_id]
	var last_revision := int(_last_source_revision_by_stream.get(stream_key, 0))
	if source_revision <= last_revision:
		_counters["rejected_stale_revision"] = int(_counters["rejected_stale_revision"]) + 1
		return _failure("STALE_SOURCE_REVISION", {
			"source_revision": source_revision,
			"last_revision": last_revision,
		})
	var slot_key := _ensure_slot(gateway_session_id, source_authority_id)
	if slot_key.is_empty():
		# Review R2-E: a failed fan-in slot registration is fail-closed for
		# THIS frame — no acceptance accounting, no latest-wins revision
		# record, explicit error result instead of an unschedulable accept.
		return _failure("FAN_IN_SLOT_UNAVAILABLE", {
			"gateway_session_id": gateway_session_id,
			"source_authority_id": source_authority_id,
		})
	_last_source_revision_by_stream[stream_key] = source_revision
	_counters["frames_accepted"] = int(_counters["frames_accepted"]) + 1
	_upstream_set.note_activity(source_authority_id)

	_frame_counter += 1
	var client_frame := ClientWorldFrameScript.create(
			"frame/eg4/proj/%06d" % _frame_counter,
			gateway_session_id,
			"WORLD_TO_CLIENT",
			PROJECTION_CHANNEL,
			source_revision,
			PROJECTION_PAYLOAD_SCHEMA,
			payload.duplicate(true))
	var reframe_check: Dictionary = ClientWorldFrameScript.validate(client_frame)
	if not bool(reframe_check.get("success", false)):
		return _fencing_reject("INVALID_EGRESS_REFRAME", String(reframe_check.get("error_code", "")))
	# Physically mapped per the published EG1 channel table: WORLD_PROJECTION
	# rides SNAPSHOT unreliable-sequenced, scheduled at multiplexer priority P4.
	var enqueued: Dictionary = _egress_multiplexer.enqueue(
			slot_key,
			{
				"frame_id": String(client_frame["frame_id"]),
				"channel": GatewayUtilsScript.eg1_physical_channel_for(PROJECTION_CHANNEL),
				"delivery_mode": GatewayUtilsScript.eg1_delivery_mode_for(PROJECTION_CHANNEL),
				"payload_schema": PROJECTION_PAYLOAD_SCHEMA,
				"payload": client_frame,
			},
			PROJECTION_CHANNEL)
	if not bool(enqueued.get("success", false)):
		_counters["rejected_backpressure"] = int(_counters["rejected_backpressure"]) + 1
		return _failure(String(enqueued.get("error_code", "QUEUE_FULL_SESSION")), enqueued.get("details", {}))
	return _success({
		"accepted": true,
		"priority": int(enqueued["details"]["priority"]),
		"priority_name": String(enqueued["details"]["priority_name"]),
		"source_revision": source_revision,
	})


## Drain the fan-in scheduler onto the clients' single transports.
func pump(max_frames: int) -> Dictionary:
	if _egress_multiplexer == null:
		return _failure("NOT_CONFIGURED", {})
	var drained: Dictionary = _egress_multiplexer.drain_link(max_frames)
	if not bool(drained.get("success", false)):
		return drained
	var by_source: Dictionary = {}
	var sent := 0
	for entry_value in drained["details"]["frames"]:
		var entry: Dictionary = entry_value
		var slot_key := String(entry["gateway_session_id"])
		var slot: Dictionary = _slot_by_key.get(slot_key, {})
		if slot.is_empty():
			continue
		var spec: Dictionary = entry["frame_spec"]
		if not _send_to_client.is_null():
			var sent_result: Dictionary = _send_to_client.call(
					String(slot["gateway_session_id"]), spec)
			if not bool(sent_result.get("success", false)):
				continue
		sent += 1
		_counters["frames_delivered"] = int(_counters["frames_delivered"]) + 1
		var source := String(slot["source_authority_id"])
		by_source[source] = int(by_source.get(source, 0)) + 1
	return _success({"sent": sent, "by_source": by_source})


## ---- reporting --------------------------------------------------------------------


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"counters": _counters.duplicate(true),
		"clients": _clients.keys(),
		"upstream_set": _upstream_set.get_report(),
		"fan_in_streams": _slot_by_key.size(),
		"active_subscriptions": _active_subscription_count(),
		"stale_subscription_count": stale_subscription_count(),
		"stale_subscriptions": stale_subscriptions(),
		"last_source_revisions": _public_stream_revisions(),
		"egress_multiplexer": _egress_multiplexer.get_report(),
	}


## ---- internals ---------------------------------------------------------------


func _fencing_reject(error_code: String, detail: String) -> Dictionary:
	match error_code:
		"PROJECTION_NOT_READ_ONLY":
			_counters["rejected_not_read_only"] = int(_counters["rejected_not_read_only"]) + 1
		"PROJECTION_MUTATION_REJECTED":
			_counters["rejected_mutation_shaped"] = int(_counters["rejected_mutation_shaped"]) + 1
	return _failure(error_code, {"detail": detail})


func _ensure_slot(gateway_session_id: String, source_authority_id: String) -> String:
	var pair_key := "%s%s%s" % [gateway_session_id, String.chr(31), source_authority_id]
	if _key_by_pair.has(pair_key):
		return String(_key_by_pair[pair_key])
	_slot_counter += 1
	var slot_key := "gateway-session/eg4/fanin-%04d" % _slot_counter
	_slot_by_key[slot_key] = {
		"gateway_session_id": gateway_session_id,
		"source_authority_id": source_authority_id,
	}
	_key_by_pair[pair_key] = slot_key
	var registered: Dictionary = _egress_multiplexer.register_session(slot_key)
	if not bool(registered.get("success", false)):
		# Fail closed (review R2-E): roll the slot bookkeeping back and report
		# an empty slot key — the caller must surface FAN_IN_SLOT_UNAVAILABLE.
		_slot_by_key.erase(slot_key)
		_key_by_pair.erase(pair_key)
		push_error("eg4 fan-in slot registration failed: %s" % String(registered.get("error_code", "")))
		return ""
	return slot_key


func _release_slot(pair_key: String) -> void:
	var slot_key := String(_key_by_pair.get(pair_key, ""))
	if slot_key.is_empty():
		return
	if _egress_multiplexer.has_session(slot_key):
		_egress_multiplexer.release_session(slot_key)
	_slot_by_key.erase(slot_key)
	_key_by_pair.erase(pair_key)


func _active_subscription_count() -> int:
	var count := 0
	for sub_key_value in _subscriptions.keys():
		if not bool(_subscriptions[sub_key_value]["stale"]):
			count += 1
	return count


func _public_stream_revisions() -> Dictionary:
	var output: Dictionary = {}
	for stream_key_value in _last_source_revision_by_stream.keys():
		output[String(stream_key_value).replace(String.chr(31), "|")] \
				= int(_last_source_revision_by_stream[stream_key_value])
	return output


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
