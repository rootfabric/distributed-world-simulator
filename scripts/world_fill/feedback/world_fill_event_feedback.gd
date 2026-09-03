class_name WorldFillEventFeedback
extends RefCounted

## WF0.5 Unified Presentation Event Feedback (WORLD FILL train).
##
## One adapter from observed command/result/event notifications to
## presentation feedback channels (audio / VFX / camera / UI).
##
## Guarantees:
## - NON-OWNING: the adapter stores only channel Callables and flags; it owns
##   no scene nodes, no audio players, no VFX pools, no state per event.
## - FAIL-SOFT: unconfigured channels are skipped, never errors; dispatching
##   can never break command execution (dispatch is called after the fact).
## - GLOBALLY DISABLEABLE: set_enabled(false) silences every channel.
## - CLOSED INITIAL EVENT SET with fail-soft unknown handling.

const SCHEMA := "world_fill.feedback_report.v1"

const CHANNELS: Array[String] = ["audio", "vfx", "camera", "ui"]

const INITIAL_EVENT_ROUTES := {
	"DIG_IMPACT": ["vfx", "audio"],
	"DIG_SUCCESS": ["vfx", "audio", "ui"],
	"PICKUP": ["audio", "ui"],
	"DROP": ["audio", "ui"],
	"BUILD_COMMIT": ["vfx", "audio", "ui"],
	"HANDOFF": ["camera", "ui"],
	"COMMAND_REJECTED": ["ui"],
	"ITEM_TRANSFER": ["ui"],
}

var _channels := {}
var _enabled := true


func configure(channel_name: String, handler: Callable) -> void:
	if not CHANNELS.has(channel_name):
		return
	_channels[channel_name] = handler


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func is_enabled() -> bool:
	return _enabled


func dispatch(observed_event: Dictionary) -> Dictionary:
	var event_type := String(observed_event.get("type", ""))
	var report := {
		"schema": SCHEMA,
		"event_type": event_type,
		"enabled": _enabled,
		"known_event": INITIAL_EVENT_ROUTES.has(event_type),
		"invoked": {},
		"skipped": {},
	}
	if not _enabled:
		for channel_name in INITIAL_EVENT_ROUTES.get(event_type, []):
			report["skipped"][channel_name] = "DISABLED"
		return report
	if not INITIAL_EVENT_ROUTES.has(event_type):
		report["skipped"]["all"] = "UNKNOWN_EVENT_TYPE"
		return report

	var presentation_event := {
		"type": event_type,
		"position": observed_event.get("position", Vector3.ZERO),
		"severity": String(observed_event.get("severity", "info")),
	}
	for channel_name in INITIAL_EVENT_ROUTES[event_type]:
		if not _channels.has(channel_name):
			report["skipped"][channel_name] = "CHANNEL_UNCONFIGURED"
			continue
		var handler: Callable = _channels[channel_name]
		if not handler.is_valid():
			report["skipped"][channel_name] = "CHANNEL_INVALID"
			continue
		handler.call(presentation_event)
		report["invoked"][channel_name] = true
	return report
