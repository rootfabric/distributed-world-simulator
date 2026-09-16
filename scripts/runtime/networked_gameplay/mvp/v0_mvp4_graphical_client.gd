extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_live_graphical_client.gd"

# Actual graphical client using the inherited authenticated network/movement
# path. The first MVP4 process gate uses deterministic input, NOT manual input.
const ReplicaSurface4 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_replica_surface.gd")
var _phase4 := "HELLO"
var _matter4: Dictionary = {}
var _snapshot4: Dictionary = {}
var _prepared4: Dictionary = {}
var _captures4: Dictionary = {}
var _capture_busy4 := false
var _hidden_ui4: Array = []

func build_world() -> bool:
	if not super.build_world(): return false
	# Replace only the derived terrain projection before network activation.
	# Body/camera/player identity and all network machinery remain inherited.
	remove_child(surface)
	surface.free()
	surface = ReplicaSurface4.new()
	surface.name = "MVP4CanonicalReplicaSurface"
	add_child(surface)
	var configured: Dictionary = surface.configure_actor(actor, Protocol.session(cfg, actor), true)
	if not bool(configured.get("success", false)): return false
	body_ids["surface"] = surface.get_instance_id()
	return true

func handle_reply(packet: Dictionary) -> void:
	if not Protocol.verify(cfg, packet, "gateway", "client/" + actor, key) or int(packet.get("sequence", 0)) != pending_rpc:
		super.handle_reply(packet)
		return
	var response: Dictionary = packet.get("body", {})
	if bool(response.get("success", false)):
		var details: Dictionary = response.get("details", {})
		_snapshot4 = Dictionary(details.get("snapshot", {})).duplicate(true)
		if pending_kind.begins_with("MVP4_"):
			_matter4 = Dictionary(details.get("matter", {})).duplicate(true)
			if pending_kind == "MVP4_POLL":
				for envelope in _matter4.get("messages", []):
					var accepted: Dictionary = surface.consume(envelope)
					if not bool(accepted.get("success", false)):
						finish(false, "MVP4_FRAME_REJECTED:" + String(accepted.get("error_code", "")))
						return
			if pending_kind == "MVP4_PREPARE": _prepared4 = _matter4.duplicate(true)
	super.handle_reply(packet)

func apply_snapshot(snapshot: Dictionary) -> void:
	super.apply_snapshot(snapshot)
	if hud != null and surface != null:
		var projection: Dictionary = surface.contract_report()
		hud.text += "\nMVP4 shared dig: %s / MW6 cursor %s" % [_phase4, str(projection.get("replica", {}).get("stream_sequence", 0))]

func next_automated(snapshot: Dictionary) -> void:
	if _capture_busy4 or finishing: return
	if not bool(cfg.get("automated", false)):
		finish(false, "MVP4_MANUAL_GATE_NOT_IMPLEMENTED")
		return
	_snapshot4 = snapshot.duplicate(true)
	match _phase4:
		"HELLO":
			if not bool(snapshot.get("both_clients_ready", false)):
				send_request("OBSERVE"); return
			_phase4 = "CONNECT"
			send_request("MVP4_CONNECT", {"sync_request": surface.create_sync_request()})
		"CONNECT":
			_phase4 = "INPUT_NONZERO"
			send_move(1.0 if actor == "a" else -1.0)
		"INPUT_NONZERO":
			_phase4 = "INPUT_STOP"
			send_move(0.0)
		"INPUT_STOP":
			_phase4 = "POLL_BASELINE"
			send_request("MVP4_POLL")
		"POLL_BASELINE":
			if int(_matter4.get("remaining", 0)) > 0:
				send_request("MVP4_POLL"); return
			_phase4 = "CAPTURE_BASELINE"
			_capture4("before", "WAIT_BASELINES", "MVP4_BASELINE")
		"WAIT_BASELINES":
			if not bool(snapshot.get("mvp4", {}).get("both_baselines_ready", false)):
				send_request("OBSERVE"); return
			_phase4 = "EQUIP"
			send_request("MVP4_EQUIP")
		"EQUIP":
			if actor == "a":
				_phase4 = "PREPARE"
				send_request("MVP4_PREPARE", {"operation_id": "operation/mvp4/a/" + String(cfg["run_id"]) + "-dig-1", "direction": [0.0, -1.0, 0.0]})
			else:
				_phase4 = "POLL_DIG"
				send_request("MVP4_POLL")
		"PREPARE":
			_phase4 = "EXECUTE"
			send_request("MVP4_EXECUTE", {"plan": _prepared4})
		"EXECUTE":
			_phase4 = "POLL_DIG"
			send_request("MVP4_POLL")
		"POLL_DIG":
			var projection: Dictionary = surface.contract_report()
			if int(projection.get("replica", {}).get("stream_sequence", 0)) < 1 or int(_matter4.get("remaining", 0)) > 0:
				send_request("MVP4_POLL"); return
			_phase4 = "CAPTURE_AFTER"
			_capture4("after", "WAIT_OBSERVERS", "MVP4_OBSERVED")
		"WAIT_OBSERVERS":
			if not bool(snapshot.get("mvp4", {}).get("both_observed", false)):
				send_request("OBSERVE"); return
			_phase4 = "FINISH"
			send_request("FINISH")
		_:
			finish(false, "MVP4_CLIENT_PHASE_INVALID:" + _phase4)

func _collect_ui4(node: Node, out: Array) -> void:
	# Complete actual UI surface: every CanvasLayer/CanvasItem under the client
	# root (the inherited status CanvasLayer + Label today). 3D nodes such as the
	# replica surface, players, seam annotation and camera are never collected.
	for child in node.get_children():
		if child is CanvasLayer:
			out.append(child)
			_collect_ui4(child, out)
		elif child is CanvasItem:
			out.append(child)
			_collect_ui4(child, out)


func _ui_evidence4() -> Dictionary:
	var items: Array = []
	_collect_ui4(self, items)
	var nodes: Array = []
	var region := Rect2()
	for item in items:
		var entry := {"class": item.get_class(), "name": String(item.name), "visible": bool(item.visible)}
		if item is Control:
			var rect: Rect2 = item.get_global_rect()
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				rect.size = item.get_minimum_size()
			entry["rect"] = {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}
			if region.size.x <= 0.0 or region.size.y <= 0.0:
				region = rect
			else:
				region = region.merge(rect)
		nodes.append(entry)
	return {"nodes": nodes, "canvas_items": items.size(),
		"region": {"x": region.position.x, "y": region.position.y, "w": region.size.x, "h": region.size.y} if region.size.x > 0.0 and region.size.y > 0.0 else {}}


func _hide_ui4() -> int:
	# Hide exactly the currently visible UI items and remember them so the
	# restore step cannot change unrelated visibility state.
	var items: Array = []
	_collect_ui4(self, items)
	_hidden_ui4.clear()
	for item in items:
		if bool(item.visible):
			_hidden_ui4.append(item)
			item.visible = false
	return _hidden_ui4.size()


func _restore_ui4() -> void:
	for item in _hidden_ui4:
		if is_instance_valid(item):
			item.visible = true
	_hidden_ui4.clear()


func _capture4(label: String, next_phase: String, command: String) -> void:
	_capture_busy4 = true
	# Terrain-only evidence by construction (review 4001519528): derive the
	# complete UI region from the live UI tree, then hide the whole UI for BOTH
	# the before and the after captures. No HUD/CanvasLayer pixel can exist in
	# either image, so no guessed row cutoff is used anywhere.
	var ui := _ui_evidence4()
	if ui["nodes"].is_empty() or ui["region"].is_empty():
		_capture_busy4 = false
		finish(false, "MVP4_UI_REGION_DERIVATION_FAILED:" + label)
		return
	var hidden := _hide_ui4()
	# Two completed real render frames after replica application and UI hiding,
	# not a desktop screenshot or an image generated from the evidence JSON.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if finishing: return
	var path := String(cfg.get("mvp4_capture_" + label, ""))
	var image := get_viewport().get_texture().get_image()
	_restore_ui4()
	ui["hidden"] = hidden == ui["canvas_items"]
	if image == null or not ui["hidden"]:
		_capture_busy4 = false
		finish(false, "MVP4_UI_HIDE_INCOMPLETE:" + label)
		return
	if path.is_empty() or image.is_empty() or image.save_png(path) != OK:
		_capture_busy4 = false
		finish(false, "MVP4_VIEWPORT_CAPTURE_FAILED:" + label)
		return
	var projection: Dictionary = surface.contract_report()
	_captures4[label] = {"file": path, "width": image.get_width(), "height": image.get_height(), "projection": projection.duplicate(true), "snapshot": _snapshot4.duplicate(true), "frame": Engine.get_process_frames(), "ui": ui}
	_phase4 = next_phase
	_capture_busy4 = false
	send_request(command, {"ack": surface.create_ack(), "projection": projection})

func finish(passed: bool, error_code: String) -> void:
	var valid := passed and _captures4.has("before") and _captures4.has("after")
	var evidence := {"schema": "distributed_world_simulator.mvp4_graphical_capture.v1", "subject_head": cfg.get("subject_head", ""), "run_id": cfg.get("run_id", ""), "actor": actor, "process_id": OS.get_process_id(), "captures": _captures4, "phase": _phase4, "passed": valid and error_code.is_empty(), "manual_input_executed": false, "input_method": "AUTOMATIC_SAME_NATIVE_INPUT_PATH", "mvp4_predicate_verified": false}
	var path := String(cfg.get("mvp4_evidence_file", ""))
	if path.is_empty() or not Support.write_json(path, evidence):
		valid = false
		if error_code.is_empty(): error_code = "MVP4_CAPTURE_EVIDENCE_WRITE_FAILED"
	super.finish(valid, error_code)
