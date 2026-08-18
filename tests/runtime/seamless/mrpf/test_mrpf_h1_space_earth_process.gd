extends SceneTree

const H0Contract = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_projection_contract.gd")
const H0Composer = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_hierarchical_composer.gd")
const Datagram = preload("res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_projection_datagram.gd")
const Fixture = preload("res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_space_earth_fixture.gd")

const OVERALL_TIMEOUT_MS := 16000
const PHASE_TIMEOUT_MS := 5000
const EXPECTED_ASSERTIONS := 86

var _assertions := 0
var _failures: Array[String] = []
var _state := "INIT"
var _state_entered_ms := 0
var _started_ms := 0
var _space_pid := -1
var _earth_pid := -1
var _client_pid := -1
var _space_port := 0
var _earth_port := 0
var _artifact_dir := ""
var _evidence_path := ""
var _godot_exe := ""
var _project_dir := ""
var _graphical_client := false
var _phase_hold_ms := 100
var _pending_action_ms := 0
var _coarse_view_hash := ""
var _fine_r1_view_hash := ""

func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_godot_exe = OS.get_executable_path()
	_project_dir = ProjectSettings.globalize_path("res://")
	var args := _parse_args(OS.get_cmdline_user_args())
	_graphical_client = String(args.get("graphical-client", "false")).to_lower() == "true"
	_phase_hold_ms = max(0, int(args.get("phase-hold-ms", "100")))
	var seed := int(OS.get_process_id()) % 10000
	_space_port = 32000 + (seed * 2) % 20000
	_earth_port = _space_port + 1
	_artifact_dir = ProjectSettings.globalize_path("res://artifacts/mrpf-h1-process-%d" % OS.get_process_id())
	_evidence_path = _artifact_dir.path_join("client-state.json")
	_prepare_artifacts()
	_run_static_contract_checks()
	if not _failures.is_empty():
		_finish()
		return
	_space_pid = _start_publisher("space", _space_port, 1, "space-r1.log")
	_check(_space_pid > 0, "SPACE publisher process starts")
	_client_pid = _start_client()
	_check(_client_pid > 0, "CLIENT process starts")
	_enter_state("WAIT_COARSE")

func _process(_delta: float) -> bool:
	if not _failures.is_empty():
		_finish()
		return false
	var now := Time.get_ticks_msec()
	if now - _started_ms > OVERALL_TIMEOUT_MS:
		_fail("overall process scenario timed out")
		_finish()
		return false
	if now - _state_entered_ms > PHASE_TIMEOUT_MS and not _state.begins_with("HOLD_"):
		_fail("state %s timed out" % _state)
		_finish()
		return false
	var evidence := _read_evidence()
	match _state:
		"WAIT_COARSE":
			if String(evidence.get("phase", "")) == "COARSE":
				_assert_coarse(evidence)
				_hold_then("START_EARTH_R1")
		"HOLD_START_EARTH_R1":
			if now >= _pending_action_ms:
				_earth_pid = _start_publisher("earth", _space_port * 0 + _earth_port, 1, "earth-r1.log")
				_check(_earth_pid > 0, "EARTH revision 1 publisher starts")
				_enter_state("WAIT_FINE")
		"WAIT_FINE":
			if String(evidence.get("phase", "")) == "FINE":
				_assert_fine(evidence, 1)
				_hold_then("KILL_EARTH_R1")
		"HOLD_KILL_EARTH_R1":
			if now >= _pending_action_ms:
				_kill_pid(_earth_pid)
				_earth_pid = -1
				_enter_state("WAIT_FALLBACK")
		"WAIT_FALLBACK":
			if String(evidence.get("phase", "")) == "FALLBACK":
				_assert_fallback(evidence)
				_hold_then("START_EARTH_R2")
		"HOLD_START_EARTH_R2":
			if now >= _pending_action_ms:
				_earth_pid = _start_publisher("earth", _earth_port, 2, "earth-r2.log")
				_check(_earth_pid > 0, "EARTH revision 2 publisher restarts")
				_enter_state("WAIT_REFINED")
		"WAIT_REFINED":
			if String(evidence.get("phase", "")) == "REFINED":
				_assert_fine(evidence, 2)
				_check(bool(evidence.get("space_route_alive", false)), "SPACE route remains alive through EARTH restart")
				_finish()
	return false

func _run_static_contract_checks() -> void:
	var coarse := Fixture.make_space_coarse(1)
	var fine1 := Fixture.make_earth_fine(1)
	var fine2 := Fixture.make_earth_fine(2)
	_check(bool(H0Contract.validate(coarse).get("success", false)), "SPACE coarse fixture is valid H0 DTO")
	_check(bool(H0Contract.validate(fine1).get("success", false)), "EARTH fine rev1 fixture is valid H0 DTO")
	_check(bool(H0Contract.validate(fine2).get("success", false)), "EARTH fine rev2 fixture is valid H0 DTO")
	_check(String(coarse.get("canonical_subject_id", "")) == Fixture.EARTH_SUBJECT_ID, "coarse canonical Earth identity")
	_check(String(fine1.get("canonical_subject_id", "")) == Fixture.EARTH_SUBJECT_ID, "fine canonical Earth identity")
	_check(String(coarse.get("replacement_group_id", "")) == String(fine1.get("replacement_group_id", "")), "coarse/fine share replacement group")
	_check(String(coarse.get("domain_level", "")) == "SPACE", "coarse fixture comes from SPACE level")
	_check(String(fine1.get("domain_level", "")) == "EARTH", "fine fixture comes from EARTH level")
	_check(String(fine1.get("representation_id", "")) == String(fine2.get("representation_id", "")), "fine identity is stable across revisions")
	_check(String(fine1.get("checksum", "")) != String(fine2.get("checksum", "")), "new fine revision changes semantic checksum")
	_check(bool(coarse.get("presentation_only", false)), "coarse is presentation only")
	_check(bool(fine1.get("presentation_only", false)), "fine is presentation only")
	_check(not bool(coarse.get("canonical_write_allowed", true)), "coarse cannot write canonical state")
	_check(not bool(fine1.get("canonical_write_allowed", true)), "fine cannot write canonical state")

	var encoded := Datagram.encode(Fixture.SPACE_ROUTE_ID, "session/test", 7, coarse)
	_check(bool(encoded.get("success", false)), "projection datagram encodes valid representation")
	var decoded := Datagram.decode(PackedByteArray(encoded.get("details", {}).get("packet", PackedByteArray())))
	_check(bool(decoded.get("success", false)), "projection datagram decodes valid representation")
	if bool(decoded.get("success", false)):
		var details: Dictionary = Dictionary(decoded["details"])
		_check(String(details.get("source_route_id", "")) == Fixture.SPACE_ROUTE_ID, "datagram preserves route identity")
		_check(int(details.get("sequence", 0)) == 7, "datagram preserves integer sequence")
		_check(String(Dictionary(details.get("payload", {})).get("checksum", "")) == String(coarse.get("checksum", "")), "datagram preserves semantic payload hash")

	var corrupted: Dictionary = JSON.parse_string(PackedByteArray(encoded["details"]["packet"]).get_string_from_utf8())
	corrupted["payload_hash"] = "forged"
	var corrupted_result := Datagram.decode(JSON.stringify(corrupted).to_utf8_buffer())
	_check(not bool(corrupted_result.get("success", false)), "payload hash mutation fails closed")
	_check(String(corrupted_result.get("error_code", "")) == "MRPF_H1_PAYLOAD_HASH_MISMATCH", "payload hash mutation has deterministic error")

	var unknown := corrupted.duplicate(true)
	unknown["payload_hash"] = String(coarse.get("checksum", ""))
	unknown["earth_magic"] = true
	var unknown_result := Datagram.decode(JSON.stringify(unknown).to_utf8_buffer())
	_check(not bool(unknown_result.get("success", false)), "unknown datagram field fails closed")
	_check(String(unknown_result.get("error_code", "")) == "MRPF_H1_DATAGRAM_FIELD_UNKNOWN", "unknown field has deterministic error")

	var composer := H0Composer.new()
	_check(bool(composer.accept_representation(coarse).get("success", false)), "existing H0 composer accepts coarse fixture")
	_check(bool(composer.accept_representation(fine1).get("success", false)), "existing H0 composer accepts fine fixture")
	var composed := composer.compose_view()
	var selected: Array = Array(composed.get("details", {}).get("representations", []))
	_check(selected.size() == 1, "H0 composer selects one Earth representation")
	if selected.size() == 1:
		_check(String(Dictionary(selected[0]).get("representation_id", "")) == Fixture.EARTH_FINE_ID, "H0 composer prefers EARTH fine over SPACE coarse")

func _assert_coarse(evidence: Dictionary) -> void:
	_coarse_view_hash = String(evidence.get("view_hash", ""))
	_check(_coarse_view_hash.length() == 64, "COARSE emits deterministic view hash")
	_check(String(evidence.get("selected_canonical_subject_id", "")) == Fixture.EARTH_SUBJECT_ID, "COARSE keeps Earth canonical identity")
	_check(String(evidence.get("selected_representation_id", "")) == Fixture.SPACE_COARSE_ID, "COARSE selects SPACE representation")
	_check(String(evidence.get("selected_domain_level", "")) == "SPACE", "COARSE selected domain is SPACE")
	_check(int(evidence.get("selected_source_revision", 0)) == 1, "COARSE source revision is 1")
	_check(bool(evidence.get("space_route_alive", false)), "SPACE route is alive in COARSE")
	_check(not bool(evidence.get("earth_route_alive", false)), "EARTH route is absent in COARSE")
	_check(int(evidence.get("representation_count", -1)) == 1, "COARSE composer has one resident representation")
	_check(int(evidence.get("earth_node_count", 0)) == 1, "COARSE renders exactly one Earth node")
	_check(String(evidence.get("visual_mode", "")) == "coarse", "COARSE uses coarse visual mode")
	_check(int(evidence.get("visual_radial_segments", 0)) == 12, "COARSE uses low-detail casual sphere")
	_check(bool(evidence.get("presentation_only", false)), "COARSE composed view is presentation only")
	_check(not bool(evidence.get("canonical_state_generated", true)), "COARSE generates no canonical state")
	_check(int(evidence.get("error_count", -1)) == 0, "COARSE client has no errors")

func _assert_fine(evidence: Dictionary, expected_revision: int) -> void:
	var current_hash := String(evidence.get("view_hash", ""))
	_check(current_hash.length() == 64, "FINE emits deterministic view hash")
	if expected_revision == 1:
		_fine_r1_view_hash = current_hash
	elif expected_revision == 2:
		_check(current_hash != _fine_r1_view_hash, "new fine revision changes composed view hash")
	_check(String(evidence.get("selected_canonical_subject_id", "")) == Fixture.EARTH_SUBJECT_ID, "FINE keeps Earth canonical identity")
	_check(String(evidence.get("selected_representation_id", "")) == Fixture.EARTH_FINE_ID, "FINE selects EARTH representation")
	_check(String(evidence.get("selected_domain_level", "")) == "EARTH", "FINE selected domain is EARTH")
	_check(int(evidence.get("selected_source_revision", 0)) == expected_revision, "FINE uses expected source revision %d" % expected_revision)
	_check(bool(evidence.get("space_route_alive", false)), "SPACE route remains alive while FINE selected")
	_check(bool(evidence.get("earth_route_alive", false)), "EARTH route is alive while FINE selected")
	_check(int(evidence.get("representation_count", -1)) == 2, "FINE composer retains coarse fallback plus fine representation")
	_check(int(evidence.get("earth_node_count", 0)) == 1, "FINE renders exactly one Earth node")
	_check(String(evidence.get("visual_mode", "")) == "fine", "FINE uses fine visual mode")
	_check(int(evidence.get("visual_radial_segments", 0)) == 48, "FINE uses higher-detail casual sphere")
	_check(bool(evidence.get("presentation_only", false)), "FINE composed view is presentation only")
	_check(not bool(evidence.get("canonical_state_generated", true)), "FINE generates no canonical state")
	_check(int(evidence.get("error_count", -1)) == 0, "FINE client has no errors")

func _assert_fallback(evidence: Dictionary) -> void:
	_check(String(evidence.get("view_hash", "")) == _coarse_view_hash, "FALLBACK restores exact coarse composed view hash")
	_check(String(evidence.get("selected_canonical_subject_id", "")) == Fixture.EARTH_SUBJECT_ID, "FALLBACK keeps Earth canonical identity")
	_check(String(evidence.get("selected_representation_id", "")) == Fixture.SPACE_COARSE_ID, "FALLBACK returns to SPACE representation")
	_check(String(evidence.get("selected_domain_level", "")) == "SPACE", "FALLBACK selected domain is SPACE")
	_check(bool(evidence.get("space_route_alive", false)), "SPACE route survives EARTH dropout")
	_check(not bool(evidence.get("earth_route_alive", true)), "EARTH route is down in FALLBACK")
	_check(int(evidence.get("representation_count", -1)) == 1, "FALLBACK tombstones fine and retains one coarse representation")
	_check(int(evidence.get("earth_node_count", 0)) == 1, "FALLBACK still renders exactly one Earth node")
	_check(String(evidence.get("visual_mode", "")) == "coarse", "FALLBACK restores coarse visual mode")
	_check(int(evidence.get("visual_radial_segments", 0)) == 12, "FALLBACK restores low-detail casual sphere")
	_check(int(evidence.get("error_count", -1)) == 0, "FALLBACK client has no errors")

func _start_publisher(role: String, target_port: int, revision: int, log_name: String) -> int:
	var args := PackedStringArray([
		"--headless",
		"--path", _project_dir,
		"--log-file", _artifact_dir.path_join(log_name),
		"--script", "res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_projection_publisher.gd",
		"--",
		"--role=%s" % role,
		"--target-port=%d" % target_port,
		"--revision=%d" % revision,
		"--interval-ms=80",
	])
	return OS.create_process(_godot_exe, args, false)

func _start_client() -> int:
	var args_array: Array[String] = []
	if not _graphical_client:
		args_array.append("--headless")
	args_array.append_array([
		"--path", _project_dir,
		"--log-file", _artifact_dir.path_join("client.log"),
		"--script", "res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_space_earth_client.gd",
		"--",
		"--space-port=%d" % _space_port,
		"--earth-port=%d" % _earth_port,
		"--evidence-path=%s" % _evidence_path,
		"--route-timeout-ms=650",
	])
	return OS.create_process(_godot_exe, PackedStringArray(args_array), false)

func _prepare_artifacts() -> void:
	DirAccess.make_dir_recursive_absolute(_artifact_dir)
	for name in ["client-state.json", "client.log", "space-r1.log", "earth-r1.log", "earth-r2.log"]:
		var path := _artifact_dir.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _read_evidence() -> Dictionary:
	if not FileAccess.file_exists(_evidence_path):
		return {}
	var file := FileAccess.open(_evidence_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return Dictionary(parsed) if typeof(parsed) == TYPE_DICTIONARY else {}

func _hold_then(action: String) -> void:
	_pending_action_ms = Time.get_ticks_msec() + _phase_hold_ms
	_enter_state("HOLD_%s" % action)

func _enter_state(next_state: String) -> void:
	_state = next_state
	_state_entered_ms = Time.get_ticks_msec()

func _kill_pid(pid: int) -> void:
	if pid > 0:
		OS.kill(pid)

func _cleanup() -> void:
	_kill_pid(_earth_pid)
	_kill_pid(_space_pid)
	_kill_pid(_client_pid)
	_earth_pid = -1
	_space_pid = -1
	_client_pid = -1

func _finish() -> void:
	_cleanup()
	if _assertions != EXPECTED_ASSERTIONS and _failures.is_empty():
		_failures.append("assertion count mismatch: expected %d got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failures.is_empty():
		print("MRPF H1 SPACE+EARTH process stand: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		printerr("MRPF H1 SPACE+EARTH process stand: FAIL (%d assertions, %d failures)" % [_assertions, _failures.size()])
		for failure in _failures:
			printerr(" - %s" % failure)
		_dump_child_logs()
		quit(1)

func _dump_child_logs() -> void:
	for name in ["space-r1.log", "earth-r1.log", "earth-r2.log", "client.log"]:
		var path := _artifact_dir.path_join(name)
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			printerr("--- %s ---\n%s" % [name, file.get_as_text()])

func _check(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(message)

func _fail(message: String) -> void:
	_failures.append(message)

func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for raw in raw_args:
		var text := String(raw)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var split := body.split("=", true, 1)
		if split.size() == 2:
			result[String(split[0])] = String(split[1])
	return result
