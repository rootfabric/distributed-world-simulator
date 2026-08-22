extends RefCounted

## EG3 backend multiplexer: many logical player sessions over ONE physical
## gateway->sim backend link.
##
## Ownership discipline: this module owns ONLY the outbound backend-leg queue
## topology — per-session bounded queues, the P0..P5 priority scheduler,
## latest-wins coalescing of stale unreliable snapshot/projection/telemetry
## streams, and explicit backpressure rejections. It never interprets domain
## payloads and never touches the route table; the caller keeps wire
## sequencing and physical dispatch (the multiplexer returns drained frame
## specs in send order).
##
## Scheduling contract:
##   P0 session/authority control > P1 reliable world operations >
##   P2 input > P3 authoritative snapshots > P4 projections > P5 telemetry.
##   - Strict priority within a session: P4/P5 backlog can never block P0/P1.
##   - Fair-share cap per session per drain: one client cannot monopolize the
##     tunnel even with high-priority traffic.
##   - Reliable traffic (any class) is NEVER silently dropped: overflow is an
##     explicit QUEUE_FULL_SESSION / QUEUE_FULL_LINK rejection returned to the
##     caller.
##   - Unreliable AUTHORITATIVE_SNAPSHOT / WORLD_PROJECTION / TELEMETRY frames
##     coalesce latest-wins per stream: stale queued revisions are dropped and
##     accounted (never delivered late).
##   - Slot reuse must not leak data between identities: release_session()
##     destroys every trace of the old occupant; register_session() always
##     starts from zero state.

const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.eg3_backend_multiplexer.v1"

const PRIORITY_CONTROL := 0
const PRIORITY_RELIABLE_WORLD := 1
const PRIORITY_INPUT := 2
const PRIORITY_SNAPSHOT := 3
const PRIORITY_PROJECTION := 4
const PRIORITY_TELEMETRY := 5
const PRIORITY_COUNT := 6
const PRIORITY_NAMES: Array[String] = [
	"P0_CONTROL", "P1_RELIABLE_WORLD", "P2_INPUT",
	"P3_SNAPSHOT", "P4_PROJECTION", "P5_TELEMETRY",
]

## Canonical semantic channel -> priority class (fail-closed: unknown channels
## are rejected, never guessed).
const CHANNEL_PRIORITY := {
	"SESSION_CONTROL": PRIORITY_CONTROL,
	"RECOVERY_FULL_STATE": PRIORITY_RELIABLE_WORLD,
	"WORLD_OPERATION": PRIORITY_RELIABLE_WORLD,
	"INPUT_MOVEMENT": PRIORITY_INPUT,
	"AUTHORITATIVE_SNAPSHOT": PRIORITY_SNAPSHOT,
	"WORLD_PROJECTION": PRIORITY_PROJECTION,
	"TELEMETRY": PRIORITY_TELEMETRY,
}

## Streams where only the LATEST unsent revision matters (when carried
## unreliable); reliable deliveries of these channels are never coalesced.
const COALESCING_CHANNELS: Array[String] = [
	"AUTHORITATIVE_SNAPSHOT", "WORLD_PROJECTION", "TELEMETRY",
]

const DELIVERY_MODES: Array[String] = ["RELIABLE_ORDERED", "RELIABLE_UNORDERED", "UNRELIABLE_SEQUENCED"]
const COALESCING_DELIVERY_MODE := "UNRELIABLE_SEQUENCED"

const QUEUE_FULL_SESSION := "QUEUE_FULL_SESSION"
const QUEUE_FULL_LINK := "QUEUE_FULL_LINK"

const DEFAULT_MAX_SESSION_MESSAGES := 128
const DEFAULT_MAX_SESSION_BYTES := 2 * 1024 * 1024
const DEFAULT_LINK_MAX_MESSAGES := 512
const DEFAULT_FAIR_SHARE_PER_DRAIN := 16

var _configured := false
var _max_session_messages: int = DEFAULT_MAX_SESSION_MESSAGES
var _max_session_bytes: int = DEFAULT_MAX_SESSION_BYTES
var _link_max_messages: int = DEFAULT_LINK_MAX_MESSAGES
var _fair_share_per_drain: int = DEFAULT_FAIR_SHARE_PER_DRAIN
## gateway_session_id -> {"queues": Array[Array] x PRIORITY_COUNT, "messages": int,
## "bytes": int, "enqueued": int, "sent": int, "coalesced_stale": int,
## "rejected": int}
var _sessions: Dictionary = {}
var _session_order: Array[String] = []
var _round_robin_cursor: int = 0
var _link_messages: int = 0
var _counters := {
	"registered_sessions": 0,
	"released_sessions": 0,
	"purges": 0,
	"purged_frames": 0,
	"enqueued": 0,
	"sent": 0,
	"rejections_queue_full_session": 0,
	"rejections_queue_full_link": 0,
	"coalesced_stale": 0,
	"drains": 0,
}


func configure(options: Dictionary) -> Dictionary:
	for key in options.keys():
		var value = options[key]
		match String(key):
			"max_session_messages":
				if not _is_positive_int(value):
					return _failure("INVALID_OPTION", {"option": "max_session_messages"})
				_max_session_messages = int(value)
			"max_session_bytes":
				if not _is_positive_int(value):
					return _failure("INVALID_OPTION", {"option": "max_session_bytes"})
				_max_session_bytes = int(value)
			"link_max_messages":
				if not _is_positive_int(value):
					return _failure("INVALID_OPTION", {"option": "link_max_messages"})
				_link_max_messages = int(value)
			"fair_share_per_drain":
				if not _is_positive_int(value):
					return _failure("INVALID_OPTION", {"option": "fair_share_per_drain"})
				_fair_share_per_drain = int(value)
			_:
				return _failure("UNKNOWN_OPTION", {"option": String(key)})
	_configured = true
	return _success({})


func register_session(gateway_session_id: String) -> Dictionary:
	var id_check: Dictionary = GatewayUtilsScript.require_id(
			{"gateway_session_id": gateway_session_id}, "gateway_session_id", "gateway-session")
	if not bool(id_check.get("success", false)):
		return _failure("INVALID_GATEWAY_SESSION_ID", {"gateway_session_id": gateway_session_id})
	if _sessions.has(gateway_session_id):
		return _failure("GATEWAY_SESSION_EXISTS", {"gateway_session_id": gateway_session_id})
	# Fresh state per registration: a reused slot can never inherit queued
	# frames, byte budgets or counters from a previous identity.
	_sessions[gateway_session_id] = _fresh_session_state()
	_session_order.append(gateway_session_id)
	_counters["registered_sessions"] = int(_counters["registered_sessions"]) + 1
	return _success({"gateway_session_id": gateway_session_id})


func release_session(gateway_session_id: String) -> Dictionary:
	if not _sessions.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	_link_messages -= int(_sessions[gateway_session_id]["messages"])
	_sessions.erase(gateway_session_id)
	_session_order.erase(gateway_session_id)
	_round_robin_cursor = 0
	_counters["released_sessions"] = int(_counters["released_sessions"]) + 1
	return _success({})


## Drop every queued frame of one session without releasing the slot
## (e.g. on detach while the row survives for accounting).
func purge_session(gateway_session_id: String) -> Dictionary:
	if not _sessions.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	var state: Dictionary = _sessions[gateway_session_id]
	var purged := int(state["messages"])
	_link_messages -= purged
	_counters["purged_frames"] = int(_counters["purged_frames"]) + purged
	_counters["purges"] = int(_counters["purges"]) + 1
	state["queues"] = _fresh_queues()
	state["messages"] = 0
	state["bytes"] = 0
	return _success({"purged_frames": purged})


## Enqueue one backend-leg frame spec for a logical session.
## frame_spec requires: channel, delivery_mode, payload (payload_schema
## optional passthrough). Reliable overflow => explicit rejection, never a
## silent drop.
func enqueue(gateway_session_id: String, frame_spec: Dictionary) -> Dictionary:
	if not _sessions.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	var channel := String(frame_spec.get("channel", ""))
	if not CHANNEL_PRIORITY.has(channel):
		return _failure("UNKNOWN_CHANNEL", {"channel": channel})
	var delivery_mode := String(frame_spec.get("delivery_mode", ""))
	if not DELIVERY_MODES.has(delivery_mode):
		return _failure("INVALID_DELIVERY_MODE", {"delivery_mode": delivery_mode})
	var priority := int(CHANNEL_PRIORITY[channel])
	var byte_size := _estimate_bytes(frame_spec)
	var state: Dictionary = _sessions[gateway_session_id]

	# Latest-wins coalescing for stale unreliable snapshot/projection/
	# telemetry streams: replacing entries never grows the queue, so cap
	# checks are unnecessary by construction here.
	if channel in COALESCING_CHANNELS and delivery_mode == COALESCING_DELIVERY_MODE:
		var stream_queue: Array = state["queues"][priority]
		var stale_count := (stream_queue as Array).size()
		if stale_count > 0:
			var stale_bytes := _queued_stream_bytes(state, priority)
			stream_queue.clear()
			state["messages"] = int(state["messages"]) - stale_count
			state["bytes"] = int(state["bytes"]) - stale_bytes
			_link_messages -= stale_count
			state["coalesced_stale"] = int(state["coalesced_stale"]) + stale_count
			_counters["coalesced_stale"] = int(_counters["coalesced_stale"]) + stale_count

	# Bounded queues: explicit backpressure, never silent drops.
	if int(state["messages"]) + 1 > _max_session_messages:
		state["rejected"] = int(state["rejected"]) + 1
		_counters["rejections_queue_full_session"] = int(_counters["rejections_queue_full_session"]) + 1
		return _failure(QUEUE_FULL_SESSION, {
			"gateway_session_id": gateway_session_id,
			"channel": channel,
			"depth_messages": int(state["messages"]),
			"limit_messages": _max_session_messages,
		})
	if int(state["bytes"]) + byte_size > _max_session_bytes:
		state["rejected"] = int(state["rejected"]) + 1
		_counters["rejections_queue_full_session"] = int(_counters["rejections_queue_full_session"]) + 1
		return _failure(QUEUE_FULL_SESSION, {
			"gateway_session_id": gateway_session_id,
			"channel": channel,
			"depth_bytes": int(state["bytes"]),
			"limit_bytes": _max_session_bytes,
		})
	if _link_messages + 1 > _link_max_messages:
		state["rejected"] = int(state["rejected"]) + 1
		_counters["rejections_queue_full_link"] = int(_counters["rejections_queue_full_link"]) + 1
		return _failure(QUEUE_FULL_LINK, {
			"gateway_session_id": gateway_session_id,
			"channel": channel,
			"link_depth_messages": _link_messages,
			"link_limit_messages": _link_max_messages,
		})

	state["queues"][priority].append({
		"frame_spec": frame_spec.duplicate(true),
		"byte_size": byte_size,
	})
	state["messages"] = int(state["messages"]) + 1
	state["bytes"] = int(state["bytes"]) + byte_size
	state["enqueued"] = int(state["enqueued"]) + 1
	_link_messages += 1
	_counters["enqueued"] = int(_counters["enqueued"]) + 1
	return _success({
		"enqueued": true,
		"priority": priority,
		"priority_name": PRIORITY_NAMES[priority],
		"depth_messages": int(state["messages"]),
	})


## Drain up to max_frames onto the ONE physical backend link.
## Tier-major scheduling: ALL registered P0 frames go out before any P1, all
## P1 before any P2, ... — so a P4/P5 (or P2) backlog anywhere on the link can
## never block anyone's P0/P1. Within one tier, sessions are swept in rotating
## round-robin order, and the per-drain fair-share cap counts across tiers, so
## a single client cannot monopolize the tunnel even inside one class.
func drain_link(max_frames: int) -> Dictionary:
	if max_frames < 1:
		return _failure("INVALID_DRAIN_BUDGET", {"max_frames": max_frames})
	_counters["drains"] = int(_counters["drains"]) + 1
	var drained: Array = []
	var sent_by_session: Dictionary = {}
	var remaining := maxi(max_frames, 0)
	for priority in range(PRIORITY_COUNT):
		if remaining <= 0:
			break
		# Exhaust this tier (rotating round-robin over sessions, respecting the
		# per-session fair-share cap) before any lower tier may send.
		var tier_progressed := true
		while tier_progressed and remaining > 0:
			tier_progressed = false
			for offset in range(_session_order.size()):
				if remaining <= 0:
					break
				var index := (_round_robin_cursor + offset) % _session_order.size()
				var gateway_session_id := String(_session_order[index])
				if int(sent_by_session.get(gateway_session_id, 0)) >= _fair_share_per_drain:
					continue
				var entry: Dictionary = _pop_from_tier(gateway_session_id, priority)
				if entry.is_empty():
					continue
				sent_by_session[gateway_session_id] = int(sent_by_session.get(gateway_session_id, 0)) + 1
				entry["gateway_session_id"] = gateway_session_id
				drained.append(entry)
				remaining -= 1
				tier_progressed = true
	_round_robin_cursor = (_round_robin_cursor + 1) % maxi(_session_order.size(), 1)
	return _success({
		"frames": drained,
		"sent_total": drained.size(),
		"sent_by_session": sent_by_session,
		"link_depth_messages": _link_messages,
	})


func has_queued_frames() -> bool:
	return _link_messages > 0


func session_depth(gateway_session_id: String) -> Dictionary:
	if not _sessions.has(gateway_session_id):
		return {}
	var state: Dictionary = _sessions[gateway_session_id]
	return {
		"messages": int(state["messages"]),
		"bytes": int(state["bytes"]),
		"by_priority": _depths_by_priority(state),
	}


func link_depth() -> Dictionary:
	return {"messages": _link_messages}


static func priority_for_channel(channel: String) -> int:
	return int(CHANNEL_PRIORITY.get(channel, -1))


## Per-session/per-link metrics for the gateway report.
func get_report() -> Dictionary:
	var sessions: Array = []
	for gateway_session_id in _session_order:
		var state: Dictionary = _sessions[gateway_session_id]
		sessions.append({
			"gateway_session_id": gateway_session_id,
			"depth_messages": int(state["messages"]),
			"depth_bytes": int(state["bytes"]),
			"by_priority": _depths_by_priority(state),
			"enqueued": int(state["enqueued"]),
			"sent": int(state["sent"]),
			"coalesced_stale": int(state["coalesced_stale"]),
			"rejected": int(state["rejected"]),
		})
	return {
		"schema": SCHEMA,
		"options": {
			"max_session_messages": _max_session_messages,
			"max_session_bytes": _max_session_bytes,
			"link_max_messages": _link_max_messages,
			"fair_share_per_drain": _fair_share_per_drain,
		},
		"counters": _counters.duplicate(true),
		"link": {"depth_messages": _link_messages},
		"sessions": sessions,
	}


## ---- internals -------------------------------------------------------------


func _fresh_session_state() -> Dictionary:
	return {
		"queues": _fresh_queues(),
		"messages": 0,
		"bytes": 0,
		"enqueued": 0,
		"sent": 0,
		"coalesced_stale": 0,
		"rejected": 0,
	}


func _fresh_queues() -> Array:
	var queues: Array = []
	for _index in range(PRIORITY_COUNT):
		queues.append([])
	return queues


func _pop_from_tier(gateway_session_id: String, priority: int) -> Dictionary:
	var state: Dictionary = _sessions.get(gateway_session_id, {})
	if state.is_empty():
		return {}
	var stream_queue: Array = state["queues"][priority]
	if (stream_queue as Array).is_empty():
		return {}
	var entry: Dictionary = stream_queue.pop_front()
	state["messages"] = int(state["messages"]) - 1
	state["bytes"] = int(state["bytes"]) - int(entry["byte_size"])
	state["sent"] = int(state["sent"]) + 1
	_link_messages -= 1
	_counters["sent"] = int(_counters["sent"]) + 1
	entry["priority"] = priority
	entry["priority_name"] = PRIORITY_NAMES[priority]
	return entry


## Byte accounting of already-queued entries of one priority stream, used when
## coalescing removes them.
func _queued_stream_bytes(state: Dictionary, priority: int) -> int:
	var total := 0
	for entry_value in state["queues"][priority]:
		total += int(Dictionary(entry_value)["byte_size"])
	return total


func _depths_by_priority(state: Dictionary) -> Dictionary:
	var depths := {}
	var queues: Array = state["queues"]
	for priority in range(PRIORITY_COUNT):
		depths[PRIORITY_NAMES[priority]] = (queues[priority] as Array).size()
	return depths


func _estimate_bytes(frame_spec: Dictionary) -> int:
	var encoded := JSON.stringify(frame_spec.get("payload", {}))
	return encoded.to_utf8_buffer().size()


func _is_positive_int(value) -> bool:
	return NetworkUtilsScript.is_json_integer(value) and int(value) > 0


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
