extends SceneTree

const Composer = preload("res://scripts/runtime/seamless/sm0/sm0_p10_multi_authority_view_composer.gd")

const A := "authority/sm0/a"
const B := "authority/sm0/b"
const C := "authority/sm0/c"
const EXPECTED_ASSERTIONS := 52

var _ports := {A:26920, B:26921, C:26922}
var _socket: PacketPeerUDP
var _request_counter := 0
var _assertions := 0
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_socket = PacketPeerUDP.new()
	_check(_socket.bind(26930, "127.0.0.1") == OK, "scenario reply socket bind")
	if _failed:
		return _finish()

	var composer = Composer.new()
	_check_success(composer.setup(B, 5000), "composer setup with B active")

	var a1 := await _projection(A)
	var b1 := await _projection(B)
	var c1 := await _projection(C)
	_check(not a1.is_empty(), "A projection received")
	_check(not b1.is_empty(), "B projection received")
	_check(not c1.is_empty(), "C projection received")
	_check(String(a1.get("source_role", "")) == "FOREIGN", "A process advertises FOREIGN")
	_check(String(b1.get("source_role", "")) == "LOCAL", "B process advertises LOCAL")
	_check(String(c1.get("source_role", "")) == "FOREIGN", "C process advertises FOREIGN")
	_check_success(composer.accept_projection(a1), "accept process A")
	_check_success(composer.accept_projection(b1), "accept process B")
	_check_success(composer.accept_projection(c1), "accept process C")
	_check(composer.source_count() == 3, "three real process sources stored")

	var initial := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(initial, "initial process composition")
	var initial_details := Dictionary(initial.get("details", {}))
	_check(Array(initial_details.get("sources_used", [])).size() == 3, "three process sources used")
	_check(Array(initial_details.get("entities", [])).size() == 3, "three process entities composed")
	_check(_has_entity(initial_details, "player/a"), "A player visible")
	_check(_has_entity(initial_details, "ship/01"), "B ship visible")
	_check(_has_entity(initial_details, "player/c"), "C player visible")
	_check(_has_rep(initial_details, "rep/a/terrain/coarse", false), "A starts coarse")
	_check(_has_rep(initial_details, "rep/b/construction/fine", false), "B near representation fine")
	_check(_has_rep(initial_details, "rep/c/terrain/coarse", false), "C far representation coarse")
	_check(not bool(initial_details.get("canonical_state_generated", true)), "process composition noncanonical")
	_check(_all_noncanonical(initial_details), "all process presentation entries read-only")

	var advance := await _command(A, "ADVANCE_FINE")
	_check_success(advance, "A process progressive fine enabled")
	_check(int(Dictionary(advance.get("details", {})).get("projection_sequence", 0)) == 2, "A process sequence advanced")
	var a2 := await _projection(A)
	_check(int(a2.get("projection_sequence", 0)) == 2, "A updated snapshot sequence 2")
	_check_success(composer.accept_projection(a2), "A progressive process update accepted")
	var progressive := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(progressive, "progressive process composition")
	_check(_has_rep(Dictionary(progressive.get("details", {})), "rep/a/terrain/fine", false), "A fine representation loaded progressively")
	_check(composer.cache_size() >= 4, "coarse and fine artifacts retained in cache")

	var replay := composer.accept_projection(a2)
	_check_success(replay, "exact process projection replay accepted")
	_check(bool(Dictionary(replay.get("details", {})).get("replay", false)), "process replay identified")

	var shutdown_a := await _command(A, "SHUTDOWN")
	_check_success(shutdown_a, "A process shutdown request accepted")
	await _wait_frames(3)
	_check_success(composer.mark_source_unavailable(A, 1), "A real source dropout marked")
	_check(not composer.source_available(A), "A source unavailable after process shutdown")
	var degraded := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(degraded, "composition survives real source dropout")
	var degraded_details := Dictionary(degraded.get("details", {}))
	_check(Array(degraded_details.get("degraded_sources", [])).size() == 1, "only one source degraded")
	_check(Array(degraded_details.get("degraded_sources", [])).has(A), "A is degraded source")
	_check(not _has_entity(degraded_details, "player/a"), "A dynamic entity removed after dropout")
	_check(_has_entity(degraded_details, "ship/01"), "B local entity survives A dropout")
	_check(_has_entity(degraded_details, "player/c"), "C foreign entity survives A dropout")
	_check(_has_rep(degraded_details, "rep/a/terrain/coarse", true), "A cached coarse proxy retained as stale presentation")
	_check(_all_noncanonical(degraded_details), "dropout cache remains noncanonical")

	var c_advance := await _command(C, "ADVANCE_ENTITY")
	_check_success(c_advance, "healthy C continues advancing after A dropout")
	var c2 := await _projection(C)
	_check(int(c2.get("projection_sequence", 0)) == 2, "C sequence advances independently")
	_check_success(composer.accept_projection(c2), "healthy C update accepted after A dropout")
	var after_c := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(after_c, "composition continues after independent C update")
	_check(_has_entity(Dictionary(after_c.get("details", {})), "player/c"), "updated C remains visible")

	_check_error(composer.reject_presentation_mutation("rep/a/terrain/coarse", "promote-to-canonical"), "SM0_P10_PRESENTATION_READ_ONLY", "stale presentation cannot become canonical")

	_check_success(await _command(B, "SHUTDOWN"), "B process shutdown")
	_check_success(await _command(C, "SHUTDOWN"), "C process shutdown")
	_finish()

func _projection(authority_id: String) -> Dictionary:
	var response := await _command(authority_id, "GET_PROJECTION")
	if not bool(response.get("success", false)):
		return {}
	return Dictionary(Dictionary(response.get("details", {})).get("snapshot", {})).duplicate(true)

func _command(authority_id: String, command: String) -> Dictionary:
	_request_counter += 1
	var request_id := "p10-process-%d" % _request_counter
	var port := int(_ports.get(authority_id, 0))
	if port < 1 or _socket.set_dest_address("127.0.0.1", port) != OK:
		return {"success":false,"error_code":"SM0_P10_SCENARIO_DESTINATION_INVALID","details":{}}
	_socket.put_packet(JSON.stringify({"request_id":request_id,"command":command,"payload":{}}, "", false, true).to_utf8_buffer())
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		while _socket.get_available_packet_count() > 0:
			var decoded = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
			if decoded is Dictionary and String(Dictionary(decoded).get("request_id", "")) == request_id:
				return Dictionary(decoded)
		await process_frame
	return {"success":false,"error_code":"SM0_P10_SCENARIO_TIMEOUT","details":{"authority_id":authority_id,"command":command}}

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _has_entity(details: Dictionary, entity_id: String) -> bool:
	for raw in Array(details.get("entities", [])):
		if String(Dictionary(raw).get("entity_id", "")) == entity_id:
			return true
	return false

func _has_rep(details: Dictionary, representation_id: String, stale_cached: bool) -> bool:
	for raw in Array(details.get("representations", [])):
		var value := Dictionary(raw)
		if String(value.get("representation_id", "")) == representation_id and bool(value.get("stale_cached", false)) == stale_cached:
			return true
	return false

func _all_noncanonical(details: Dictionary) -> bool:
	for raw in Array(details.get("entities", [])):
		var value := Dictionary(raw)
		if value.get("presentation_only") != true or value.get("canonical_write_allowed") != false:
			return false
	for raw in Array(details.get("representations", [])):
		var value := Dictionary(raw)
		if value.get("presentation_only") != true or value.get("canonical_write_allowed") != false:
			return false
	return true

func _v(x: float, y: float, z: float) -> Dictionary:
	return {"x":x,"y":y,"z":z}

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), "%s: %s" % [label, String(result.get("error_code", ""))])

func _check_error(result: Dictionary, error_code: String, label: String) -> void:
	_check(not bool(result.get("success", false)), label + " fails")
	_check(String(result.get("error_code", "")) == error_code, label + " error code")

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("P10 process assertion failed: %s" % label)

func _finish() -> void:
	if _socket != null:
		_socket.close()
	if EXPECTED_ASSERTIONS > 0 and _assertions != EXPECTED_ASSERTIONS:
		_failed = true
		push_error("P10 process assertion count mismatch: expected %d got %d" % [EXPECTED_ASSERTIONS, _assertions])
	print("SM0 P10 process-isolated composition: %s (%d assertions)" % ["FAIL" if _failed else "PASS", _assertions])
	quit(1 if _failed else 0)